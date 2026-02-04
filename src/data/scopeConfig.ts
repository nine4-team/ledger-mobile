export type Scope = 'project' | 'inventory';

export type ScopeConfig = {
  scope: Scope;
  /**
   * Required when scope === 'project'. Must be absent for inventory.
   */
  projectId?: string;
  capabilities?: {
    // Transactions
    canExportCsv?: boolean;
    supportsInventoryOnlyStatusFilter?: boolean;

    // Items
    canAllocateToProject?: boolean;
  };
  fields?: {
    showBusinessInventoryLocation?: boolean;
  };
};

export type SharedListKind = 'items' | 'transactions';

export function createProjectScopeConfig(projectId: string): ScopeConfig {
  return {
    scope: 'project',
    projectId,
    capabilities: {
      canExportCsv: true,
      supportsInventoryOnlyStatusFilter: false,
      canAllocateToProject: false,
    },
  };
}

export function createInventoryScopeConfig(): ScopeConfig {
  return {
    scope: 'inventory',
    capabilities: {
      canExportCsv: false,
      canAllocateToProject: true,
    },
    fields: {
      showBusinessInventoryLocation: true,
    },
  };
}

export function getScopeId(scopeConfig: ScopeConfig): string | null {
  if (scopeConfig.scope === 'project') {
    return scopeConfig.projectId ? `project:${scopeConfig.projectId}` : null;
  }
  return 'inventory';
}

export function getListStateKey(scopeConfig: ScopeConfig, kind: SharedListKind): string | null {
  if (scopeConfig.scope === 'project') {
    return scopeConfig.projectId ? `project:${scopeConfig.projectId}:${kind}` : null;
  }
  return `inventory:${kind}`;
}
