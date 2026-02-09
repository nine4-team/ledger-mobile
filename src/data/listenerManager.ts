/**
 * Scoped Listener Manager
 * 
 * Provides reusable listener lifecycle management for bounded scopes.
 * 
 * Features:
 * - Attaches listeners by scope (e.g., project/account)
 * - Detaches on background and reattaches on resume
 * - Cleans up unsubscribe handlers deterministically
 * 
 * Usage:
 * ```ts
 * const manager = new ScopedListenerManager();
 * 
 * // Register a listener for a scope
 * manager.attach('project:123', () => {
 *   return repo.subscribeList((items) => {
 *     // handle updates
 *   });
 * });
 * 
 * // Detach all listeners for a scope
 * manager.detach('project:123');
 * 
 * // Cleanup all listeners
 * manager.cleanup();
 * ```
 */

import { AppState, AppStateStatus, NativeEventSubscription } from 'react-native';

export type ScopeId = string;
export type UnsubscribeFn = () => void;
export type ListenerFactory = () => UnsubscribeFn;

interface ScopeListenerEntry {
  id: string;
  factory: ListenerFactory;
  unsubscribe: UnsubscribeFn | null;
}

interface ScopeListeners {
  entries: ScopeListenerEntry[];
  isAttached: boolean;
  retryTimeout?: NodeJS.Timeout;
  retryAttempt?: number;
}

/**
 * Manages Firestore listeners by scope with lifecycle awareness.
 * 
 * Scopes are typically:
 * - `project:{projectId}` - listeners for a specific project
 * - `account:{accountId}` - listeners for an account
 * - `user:{userId}` - listeners for a user
 * 
 * Listeners are automatically detached when the app goes to background
 * and reattached when the app resumes.
 */
export class ScopedListenerManager {
  private scopes: Map<ScopeId, ScopeListeners> = new Map();
  private appStateSubscription: NativeEventSubscription | null = null;
  private currentAppState: AppStateStatus = AppState.currentState;

  constructor() {
    // Subscribe to app state changes
    this.appStateSubscription = AppState.addEventListener('change', this.handleAppStateChange);
  }

  /**
   * Attach listeners for a scope.
   * 
   * If the scope is already attached, the factory will be called immediately.
   * If the app is in background, listeners will be queued and attached on resume.
   * Returns a cleanup function to unregister this specific listener.
   * 
   * @param scopeId - Unique identifier for the scope (e.g., 'project:123')
   * @param factory - Function that returns an unsubscribe function
   */
  attach(scopeId: ScopeId, factory: ListenerFactory): () => void {
    let scope = this.scopes.get(scopeId);
    
    if (!scope) {
      scope = {
        entries: [],
        isAttached: false,
      };
      this.scopes.set(scopeId, scope);
    }

    const entry: ScopeListenerEntry = {
      id: `${scopeId}:${Date.now()}:${Math.random().toString(36).slice(2)}`,
      factory,
      unsubscribe: null,
    };

    scope.entries.push(entry);

    if (this.currentAppState === 'active') {
      if (scope.isAttached) {
        entry.unsubscribe = this.safeAttachFactory(scopeId, entry.factory);
      } else {
        this.attachScope(scopeId);
      }
    }

    return () => {
      this.removeEntry(scopeId, entry.id);
    };
  }

  /**
   * Detach all listeners for a scope.
   *
   * This unsubscribes all active listeners and marks the scope as detached.
   * Factories are preserved, so listeners can be reattached later.
   *
   * @param scopeId - Scope identifier
   */
  detach(scopeId: ScopeId): void {
    const scope = this.scopes.get(scopeId);
    if (!scope) return;

    // Clear any pending retry
    if (scope.retryTimeout) {
      clearTimeout(scope.retryTimeout);
      scope.retryTimeout = undefined;
    }

    // Unsubscribe all active listeners
    scope.entries.forEach((entry) => {
      if (!entry.unsubscribe) return;
      try {
        entry.unsubscribe();
      } catch (error) {
        console.error(`[ScopedListenerManager] Error unsubscribing listener for scope ${scopeId}:`, error);
      } finally {
        entry.unsubscribe = null;
      }
    });
    scope.isAttached = false;
  }

  /**
   * Activate a scope's listeners (attach if currently detached).
   *
   * Useful when switching between scopes without re-registering factories.
   *
   * @param scopeId - Scope identifier
   */
  activateScope(scopeId: ScopeId): void {
    const scope = this.scopes.get(scopeId);
    if (!scope) return;
    if (this.currentAppState !== 'active') return;
    this.attachScope(scopeId);
  }

  /**
   * Remove a scope entirely (detach + remove factories).
   * 
   * Use this when a scope is no longer needed (e.g., user switched projects).
   * 
   * @param scopeId - Scope identifier
   */
  remove(scopeId: ScopeId): void {
    this.detach(scopeId);
    this.scopes.delete(scopeId);
  }

  /**
   * Attach all listeners for a scope.
   *
   * Called internally when app resumes or when a scope is first attached.
   *
   * @param scopeId - Scope identifier
   */
  private attachScope(scopeId: ScopeId): void {
    const scope = this.scopes.get(scopeId);
    if (!scope || scope.isAttached) return;

    // Clear any pending retry
    if (scope.retryTimeout) {
      clearTimeout(scope.retryTimeout);
      scope.retryTimeout = undefined;
    }

    let anySucceeded = false;

    scope.entries.forEach((entry) => {
      entry.unsubscribe = this.safeAttachFactory(scopeId, entry.factory);
      if (entry.unsubscribe) {
        anySucceeded = true;
      }
    });

    // Only mark as attached if at least one listener succeeded
    if (anySucceeded) {
      scope.isAttached = true;
      scope.retryAttempt = 0;
    } else {
      // All listeners failed - schedule retry with exponential backoff
      const attempt = (scope.retryAttempt ?? 0) + 1;
      const maxAttempts = 3;

      if (attempt <= maxAttempts) {
        const delay = Math.pow(2, attempt - 1) * 1000; // 1s, 2s, 4s
        console.warn(`[ScopedListenerManager] All listeners failed for scope ${scopeId}. Retrying in ${delay}ms (attempt ${attempt}/${maxAttempts})`);

        scope.retryAttempt = attempt;
        scope.retryTimeout = setTimeout(() => {
          scope.retryTimeout = undefined;
          this.attachScope(scopeId);
        }, delay);
      } else {
        console.error(`[ScopedListenerManager] All listeners failed for scope ${scopeId} after ${maxAttempts} attempts. Giving up.`);
        scope.retryAttempt = 0;
      }
    }
  }

  /**
   * Detach all listeners for a scope.
   * 
   * Called internally when app goes to background.
   * 
   * @param scopeId - Scope identifier
   */
  private detachScope(scopeId: ScopeId): void {
    this.detach(scopeId);
  }

  private safeAttachFactory(scopeId: ScopeId, factory: ListenerFactory): UnsubscribeFn | null {
    try {
      return factory();
    } catch (error) {
      console.error(`[ScopedListenerManager] Error creating listener for scope ${scopeId}:`, error);
      return null;
    }
  }

  private removeEntry(scopeId: ScopeId, entryId: string): void {
    const scope = this.scopes.get(scopeId);
    if (!scope) return;

    const nextEntries: ScopeListenerEntry[] = [];
    scope.entries.forEach((entry) => {
      if (entry.id !== entryId) {
        nextEntries.push(entry);
        return;
      }

      if (entry.unsubscribe) {
        try {
          entry.unsubscribe();
        } catch (error) {
          console.error(`[ScopedListenerManager] Error unsubscribing listener for scope ${scopeId}:`, error);
        }
      }
    });

    scope.entries = nextEntries;

    if (scope.entries.length === 0) {
      this.scopes.delete(scopeId);
    }
  }

  /**
   * Handle app state changes (active/background/inactive).
   */
  private handleAppStateChange = (nextAppState: AppStateStatus): void => {
    const wasActive = this.currentAppState === 'active';
    const isActive = nextAppState === 'active';
    
    this.currentAppState = nextAppState;

    if (wasActive && !isActive) {
      // App went to background - detach all listeners
      this.scopes.forEach((_, scopeId) => {
        this.detachScope(scopeId);
      });
    } else if (!wasActive && isActive) {
      // App resumed - reattach all listeners
      this.scopes.forEach((_, scopeId) => {
        this.attachScope(scopeId);
      });
    }
  };

  /**
   * Cleanup all listeners and remove all scopes.
   *
   * Call this when the manager is no longer needed (e.g., app unmount).
   */
  cleanup(): void {
    // Detach all scopes (this also clears retry timeouts)
    this.scopes.forEach((_, scopeId) => {
      this.detach(scopeId);
    });

    // Remove all scopes
    this.scopes.clear();

    // Remove app state listener
    if (this.appStateSubscription) {
      this.appStateSubscription.remove();
      this.appStateSubscription = null;
    }
  }

  /**
   * Get the number of active listeners for a scope.
   * 
   * @param scopeId - Scope identifier
   * @returns Number of active listeners
   */
  getListenerCount(scopeId: ScopeId): number {
    const scope = this.scopes.get(scopeId);
    if (!scope) return 0;
    return scope.entries.filter((entry) => entry.unsubscribe).length;
  }

  /**
   * Check if a scope is currently attached.
   * 
   * @param scopeId - Scope identifier
   * @returns True if scope has active listeners
   */
  isAttached(scopeId: ScopeId): boolean {
    const scope = this.scopes.get(scopeId);
    return scope?.isAttached ?? false;
  }

  /**
   * Get all active scope IDs.
   * 
   * @returns Array of scope IDs
   */
  getActiveScopes(): ScopeId[] {
    return Array.from(this.scopes.keys());
  }

  /**
   * Detach and reattach all scopes (best-effort refresh).
   */
  refreshAllScopes(): void {
    this.scopes.forEach((_, scopeId) => {
      this.detach(scopeId);
    });
    if (this.currentAppState === 'active') {
      this.scopes.forEach((_, scopeId) => {
        this.attachScope(scopeId);
      });
    }
  }
}

/**
 * Singleton instance for app-wide listener management.
 * 
 * Apps can use this directly or create their own instances for specific contexts.
 */
export const globalListenerManager = new ScopedListenerManager();
