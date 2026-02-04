import { useEffect, useMemo } from 'react';
import { globalListenerManager } from './listenerManager';
import { getScopeId, ScopeConfig } from './scopeConfig';

type ScopeSwitchOptions = {
  isActive: boolean;
  keepScopePrefixes?: string[];
};

const DEFAULT_KEEP_PREFIXES = ['account:', 'user:'];

export function useScopeSwitching(scopeConfig: ScopeConfig | null, options: ScopeSwitchOptions): string | null {
  const scopeId = useMemo(() => (scopeConfig ? getScopeId(scopeConfig) : null), [scopeConfig]);
  const keepScopePrefixes = options.keepScopePrefixes ?? DEFAULT_KEEP_PREFIXES;

  useEffect(() => {
    if (!options.isActive || !scopeId) return;

    const activeScopes = globalListenerManager.getActiveScopes();
    activeScopes.forEach((id) => {
      if (id === scopeId) return;
      if (keepScopePrefixes.some((prefix) => id.startsWith(prefix))) return;
      globalListenerManager.detach(id);
    });

    globalListenerManager.activateScope(scopeId);

    return () => {
      globalListenerManager.detach(scopeId);
    };
  }, [keepScopePrefixes, options.isActive, scopeId]);

  return scopeId;
}
