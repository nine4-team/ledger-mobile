/**
 * Shared menu builder for item action menus.
 *
 * Builds AnchoredMenuItem[] arrays for single-item and bulk contexts.
 * All scope-conditional logic lives here so it's tested once, not duplicated
 * across SharedItemsList, SpaceDetailContent, and item detail.
 */

import type { AnchoredMenuItem, AnchoredMenuSubaction } from '../components/AnchoredMenuList';
import type { ScopeConfig } from '../data/scopeConfig';
import { ITEM_STATUSES } from '../constants/itemStatuses';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type MenuContext = 'list' | 'detail' | 'space' | 'transaction';

export type SingleItemCallbacks = {
  onViewItem?: () => void;
  onEditOrOpen: () => void;
  onMakeCopies?: () => void;
  onStatusChange: (status: string) => void;
  onSetTransaction: () => void;
  onClearTransaction: () => void;
  onSetSpace: () => void;
  onClearSpace: () => void;
  onSellToBusiness?: () => void;
  onSellToProject?: () => void;
  onReassignToInventory?: () => void;
  onReassignToProject?: () => void;
  onMoveToReturnTransaction?: () => void;
  onDelete: () => void;
};

export type BulkCallbacks = {
  onStatusChange: (status: string) => void;
  onSetTransaction: () => void;
  onClearTransaction: () => void;
  onSetSpace: () => void;
  onClearSpace: () => void;
  onSellToBusiness?: () => void;
  onSellToProject?: () => void;
  onReassignToInventory?: () => void;
  onReassignToProject?: () => void;
  onDelete: () => void;
};

const SELL_INFO = {
  title: 'About Sell',
  message: 'Moves items between projects and inventory with a financial record so you can track where things went.',
};

const REASSIGN_INFO = {
  title: 'About Reassign',
  message: 'Use when something was added to the wrong place and you need to move it. No financial records are created, as opposed to the Sell action.',
};

// ---------------------------------------------------------------------------
// Single-Item Menu
// ---------------------------------------------------------------------------

/**
 * Build menu items for a single item's action menu.
 *
 * - context 'list': first item is "Edit Details"
 * - context 'detail': first item is "Edit Details", status submenu includes "Clear Status"
 * - context 'space': first item is "Open"
 */
export function buildSingleItemMenu(params: {
  context: MenuContext;
  scopeConfig: ScopeConfig;
  callbacks: SingleItemCallbacks;
  selectedStatus?: string | null;
}): AnchoredMenuItem[] {
  const { context, scopeConfig, callbacks, selectedStatus } = params;
  const items: AnchoredMenuItem[] = [];

  // First items: View, Edit/Open, Make Copies
  if (context === 'transaction') {
    if (callbacks.onViewItem) {
      items.push({
        key: 'view',
        label: 'View Item',
        icon: 'open-in-new',
        onPress: callbacks.onViewItem,
      });
    }
    items.push({
      key: 'edit',
      label: 'Edit Details',
      icon: 'edit',
      onPress: callbacks.onEditOrOpen,
    });
    if (callbacks.onMakeCopies) {
      items.push({
        key: 'make-copies',
        label: 'Make Copies',
        icon: 'content-copy',
        onPress: callbacks.onMakeCopies,
      });
    }
  } else if (context === 'space') {
    items.push({
      key: 'open',
      label: 'Open',
      icon: 'open-in-new',
      onPress: callbacks.onEditOrOpen,
    });
  } else {
    items.push({
      key: 'edit',
      label: 'Edit Details',
      icon: 'edit',
      onPress: callbacks.onEditOrOpen,
    });
  }

  // Status submenu
  const statusSubactions: Array<{ key: string; label: string; onPress: () => void }> = ITEM_STATUSES.map((s) => ({
    key: s.key,
    label: s.label,
    onPress: () => callbacks.onStatusChange(s.key),
  }));
  if (context === 'detail' || context === 'transaction') {
    statusSubactions.push({
      key: 'clear-status',
      label: 'Clear Status',
      onPress: () => callbacks.onStatusChange(''),
    });
  }
  items.push({
    key: 'status',
    label: 'Status',
    icon: 'flag',
    actionOnly: true,
    selectedSubactionKey: selectedStatus ?? undefined,
    subactions: statusSubactions,
  });

  // Transaction submenu
  if (context === 'transaction') {
    const txnSubactions: AnchoredMenuSubaction[] = [
      { key: 'clear-transaction', label: 'Clear Transaction', icon: 'link-off', onPress: callbacks.onClearTransaction },
    ];
    if (callbacks.onMoveToReturnTransaction) {
      txnSubactions.push({
        key: 'move-to-return-transaction',
        label: 'Move to Return Transaction',
        icon: 'assignment-return',
        onPress: callbacks.onMoveToReturnTransaction,
      });
    }
    items.push({
      key: 'transaction',
      label: 'Transaction',
      icon: 'link',
      actionOnly: true,
      subactions: txnSubactions,
    });
  } else {
    items.push({
      key: 'transaction',
      label: 'Transaction',
      icon: 'link',
      actionOnly: true,
      subactions: [
        { key: 'set-transaction', label: 'Set Transaction', icon: 'link', onPress: callbacks.onSetTransaction },
        { key: 'clear-transaction', label: 'Clear Transaction', icon: 'link-off', onPress: callbacks.onClearTransaction },
      ],
    });
  }

  // Space submenu
  items.push({
    key: 'space',
    label: 'Space',
    icon: 'place',
    actionOnly: true,
    subactions: [
      { key: 'set-space', label: context === 'space' ? 'Move to Space' : 'Set Space', icon: 'place', onPress: callbacks.onSetSpace },
      { key: 'clear-space', label: context === 'space' ? 'Remove from Space' : 'Clear Space', icon: 'close', onPress: callbacks.onClearSpace },
    ],
  });

  // Sell submenu (scope-dependent)
  const sellSubactions = buildSellSubactions(scopeConfig, {
    onSellToBusiness: callbacks.onSellToBusiness,
    onSellToProject: callbacks.onSellToProject,
  });
  if (sellSubactions.length > 0) {
    items.push({
      key: 'sell',
      label: 'Sell',
      icon: 'sell',
      actionOnly: true,
      info: SELL_INFO,
      subactions: sellSubactions,
    });
  }

  // Reassign submenu (scope-dependent)
  const reassignSubactions = buildReassignSubactions(scopeConfig, {
    onReassignToInventory: callbacks.onReassignToInventory,
    onReassignToProject: callbacks.onReassignToProject,
  });
  if (reassignSubactions.length > 0) {
    items.push({
      key: 'reassign',
      label: 'Reassign',
      icon: 'swap-horiz',
      actionOnly: true,
      info: REASSIGN_INFO,
      subactions: reassignSubactions,
    });
  }

  // Delete (always last)
  items.push({
    key: 'delete',
    label: 'Delete',
    icon: 'delete',
    onPress: callbacks.onDelete,
  });

  return items;
}

// ---------------------------------------------------------------------------
// Bulk Menu
// ---------------------------------------------------------------------------

/**
 * Build menu items for bulk actions.
 */
export function buildBulkMenu(params: {
  context: 'list' | 'space';
  scopeConfig: ScopeConfig;
  callbacks: BulkCallbacks;
}): AnchoredMenuItem[] {
  const { context, scopeConfig, callbacks } = params;
  const items: AnchoredMenuItem[] = [];

  // Status submenu
  items.push({
    key: 'status',
    label: 'Status',
    icon: 'flag',
    actionOnly: true,
    subactions: ITEM_STATUSES.map((s) => ({
      key: s.key,
      label: s.label,
      onPress: () => callbacks.onStatusChange(s.key),
    })),
  });

  // Transaction submenu
  items.push({
    key: 'transaction',
    label: 'Transaction',
    icon: 'link',
    actionOnly: true,
    subactions: [
      { key: 'set-transaction', label: 'Set Transaction', icon: 'link', onPress: callbacks.onSetTransaction },
      { key: 'clear-transaction', label: 'Clear Transaction', icon: 'link-off', onPress: callbacks.onClearTransaction },
    ],
  });

  // Space submenu
  items.push({
    key: 'space',
    label: 'Space',
    icon: 'place',
    actionOnly: true,
    subactions: [
      { key: 'set-space', label: context === 'space' ? 'Move to Another Space' : 'Set Space', icon: 'place', onPress: callbacks.onSetSpace },
      { key: 'clear-space', label: context === 'space' ? 'Remove from Space' : 'Clear Space', icon: 'close', onPress: callbacks.onClearSpace },
    ],
  });

  // Sell submenu (scope-dependent)
  const sellSubactions = buildSellSubactions(scopeConfig, {
    onSellToBusiness: callbacks.onSellToBusiness,
    onSellToProject: callbacks.onSellToProject,
  });
  if (sellSubactions.length > 0) {
    items.push({
      key: 'sell',
      label: 'Sell',
      icon: 'sell',
      actionOnly: true,
      info: SELL_INFO,
      subactions: sellSubactions,
    });
  }

  // Reassign submenu (scope-dependent)
  const reassignSubactions = buildReassignSubactions(scopeConfig, {
    onReassignToInventory: callbacks.onReassignToInventory,
    onReassignToProject: callbacks.onReassignToProject,
  });
  if (reassignSubactions.length > 0) {
    items.push({
      key: 'reassign',
      label: 'Reassign',
      icon: 'swap-horiz',
      actionOnly: true,
      info: REASSIGN_INFO,
      subactions: reassignSubactions,
    });
  }

  // Delete (always last)
  items.push({
    key: 'delete',
    label: 'Delete',
    icon: 'delete',
    onPress: callbacks.onDelete,
  });

  return items;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildSellSubactions(
  scopeConfig: ScopeConfig,
  callbacks: { onSellToBusiness?: () => void; onSellToProject?: () => void },
) {
  const subactions: Array<{ key: string; label: string; icon: 'inventory' | 'assignment'; onPress: () => void }> = [];

  if (scopeConfig.scope === 'project') {
    if (callbacks.onSellToBusiness) {
      subactions.push({
        key: 'sell-to-business',
        label: 'Sell to Business',
        icon: 'inventory',
        onPress: callbacks.onSellToBusiness,
      });
    }
    if (callbacks.onSellToProject) {
      subactions.push({
        key: 'sell-to-project',
        label: 'Sell to Project',
        icon: 'assignment',
        onPress: callbacks.onSellToProject,
      });
    }
  } else if (scopeConfig.scope === 'inventory') {
    if (callbacks.onSellToProject) {
      subactions.push({
        key: 'sell-to-project',
        label: 'Sell to Project',
        icon: 'assignment',
        onPress: callbacks.onSellToProject,
      });
    }
  }

  return subactions;
}

function buildReassignSubactions(
  scopeConfig: ScopeConfig,
  callbacks: { onReassignToInventory?: () => void; onReassignToProject?: () => void },
) {
  const subactions: Array<{ key: string; label: string; icon: 'inventory' | 'assignment'; onPress: () => void }> = [];

  if (scopeConfig.scope === 'project') {
    if (callbacks.onReassignToInventory) {
      subactions.push({
        key: 'reassign-to-inventory',
        label: 'Reassign to Inventory',
        icon: 'inventory',
        onPress: callbacks.onReassignToInventory,
      });
    }
    if (callbacks.onReassignToProject) {
      subactions.push({
        key: 'reassign-to-project',
        label: 'Reassign to Project',
        icon: 'assignment',
        onPress: callbacks.onReassignToProject,
      });
    }
  } else if (scopeConfig.scope === 'inventory') {
    if (callbacks.onReassignToProject) {
      subactions.push({
        key: 'reassign-to-project',
        label: 'Reassign to Project',
        icon: 'assignment',
        onPress: callbacks.onReassignToProject,
      });
    }
  }

  return subactions;
}
