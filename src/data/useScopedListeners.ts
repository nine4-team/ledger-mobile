/**
 * React hook for managing scoped listeners
 * 
 * Provides a convenient way to attach listeners to a scope with automatic cleanup.
 * 
 * Usage:
 * ```tsx
 * function ProjectScreen({ projectId }: { projectId: string }) {
 *   const scopeId = `project:${projectId}`;
 *   
 *   useScopedListeners(scopeId, () => {
 *     const repo = createRepository(`projects/${projectId}/items`, 'offline');
 *     return repo.subscribeList((items) => {
 *       // update state
 *     });
 *   });
 *   
 *   return <View>...</View>;
 * }
 * ```
 */

import { useEffect } from 'react';
import { ScopedListenerManager, ScopeId, ListenerFactory } from './listenerManager';
import { globalListenerManager } from './listenerManager';

/**
 * Hook to manage listeners for a scope.
 * 
 * Listeners are automatically:
 * - Attached when the component mounts or scope changes
 * - Detached when the component unmounts or scope changes
 * - Detached when app goes to background
 * - Reattached when app resumes
 * 
 * @param scopeId - Unique identifier for the scope (e.g., 'project:123')
 * @param factory - Function that returns an unsubscribe function
 * @param manager - Optional listener manager instance (defaults to global)
 */
export function useScopedListeners(
  scopeId: ScopeId,
  factory: ListenerFactory,
  manager: ScopedListenerManager = globalListenerManager
): void {
  useEffect(() => {
    const removeListener = manager.attach(scopeId, factory);
    return () => {
      removeListener();
    };
  }, [scopeId, factory, manager]);
}

/**
 * Hook to manage multiple listeners for a scope.
 * 
 * Useful when you need to attach multiple listeners to the same scope.
 * 
 * @param scopeId - Unique identifier for the scope
 * @param factories - Array of factory functions
 * @param manager - Optional listener manager instance
 */
export function useScopedListenersMultiple(
  scopeId: ScopeId,
  factories: ListenerFactory[],
  manager: ScopedListenerManager = globalListenerManager
): void {
  useEffect(() => {
    const removers = factories.map((factory) => manager.attach(scopeId, factory));
    return () => {
      removers.forEach((removeListener) => {
        removeListener();
      });
    };
  }, [scopeId, factories, manager]);
}
