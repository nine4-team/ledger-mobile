import { useCallback, useMemo, useState } from 'react';
import { useRouter } from 'expo-router';
import { moveItemToReturnTransaction } from '../data/returnFlowService';
import { showToast } from '../components/toastStore';
import type { ScopeConfig } from '../data/scopeConfig';

export type ReturnTransactionPickerConfig = {
  accountId: string | null;
  scopeConfig: ScopeConfig | null;
  /**
   * Fixed source transaction ID (when used from transaction detail).
   * Null in non-transaction contexts — use getItemTransactionId instead.
   */
  fromTransactionId?: string | null;
  /**
   * Per-item lookup for the item's current transactionId.
   * Used in non-transaction contexts where items may come from different transactions.
   */
  getItemTransactionId?: (itemId: string) => string | null;
  projectId?: string | null;
  /** Called after items are moved (for clearing selection, etc.) */
  onComplete?: () => void;
};

export type ReturnTransactionPickerState = {
  visible: boolean;
  pendingItemIds: string[];
  subtitle: string | undefined;
  openForItem: (itemId: string) => void;
  openForItems: (itemIds: string[]) => void;
  handleConfirm: (returnTx: { id: string }) => void;
  handleCreateNew: () => void;
  close: () => void;
};

// ---------------------------------------------------------------------------
// Pure helpers — exported for testing
// ---------------------------------------------------------------------------

export function computeSubtitle(count: number): string | undefined {
  if (count === 0) return undefined;
  return `Moving ${count} item${count === 1 ? '' : 's'}`;
}

/**
 * Resolve the source transaction ID for a given item.
 * If a fixed `fromTransactionId` is provided (transaction context), use it.
 * Otherwise, use the per-item lookup function.
 */
export function resolveSourceTransactionId(
  itemId: string,
  fromTransactionId: string | null | undefined,
  getItemTransactionId?: (id: string) => string | null,
): string | null {
  if (fromTransactionId !== undefined) return fromTransactionId;
  return getItemTransactionId?.(itemId) ?? null;
}

/**
 * Build the navigation params for creating a new return transaction.
 */
export function buildCreateNewParams(
  scopeConfig: ScopeConfig,
  itemIds: string[],
  fromTransactionId?: string | null,
): {
  pathname: string;
  params: Record<string, string>;
} {
  return {
    pathname: '/transactions/new',
    params: {
      scope: scopeConfig.scope,
      projectId: scopeConfig.projectId ?? '',
      transactionType: 'return',
      linkItemIds: itemIds.join(','),
      linkItemFromTransactionId: fromTransactionId ?? '',
    },
  };
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export function useReturnTransactionPicker(
  config: ReturnTransactionPickerConfig,
): ReturnTransactionPickerState {
  const {
    accountId,
    scopeConfig,
    fromTransactionId,
    getItemTransactionId,
    projectId,
    onComplete,
  } = config;

  const router = useRouter();
  const [pendingItemIds, setPendingItemIds] = useState<string[]>([]);
  const [visible, setVisible] = useState(false);

  const subtitle = useMemo(
    () => computeSubtitle(pendingItemIds.length),
    [pendingItemIds],
  );

  const openForItem = useCallback((itemId: string) => {
    setPendingItemIds([itemId]);
    setVisible(true);
  }, []);

  const openForItems = useCallback((itemIds: string[]) => {
    if (itemIds.length === 0) return;
    setPendingItemIds(itemIds);
    setVisible(true);
  }, []);

  const close = useCallback(() => {
    setVisible(false);
    setPendingItemIds([]);
    onComplete?.();
  }, [onComplete]);

  const handleConfirm = useCallback(
    (returnTx: { id: string }) => {
      if (!accountId || pendingItemIds.length === 0) return;

      for (const itemId of pendingItemIds) {
        const sourceTxId = resolveSourceTransactionId(
          itemId,
          fromTransactionId,
          getItemTransactionId,
        );

        moveItemToReturnTransaction({
          accountId,
          itemId,
          fromTransactionId: sourceTxId,
          returnTransactionId: returnTx.id,
          fromProjectId: projectId ?? null,
          toProjectId: projectId ?? null,
        });
      }

      const count = pendingItemIds.length;
      showToast(
        count === 1
          ? 'Item moved to return transaction'
          : `${count} items moved to return transaction`,
      );
      setVisible(false);
      setPendingItemIds([]);
      onComplete?.();
    },
    [accountId, pendingItemIds, fromTransactionId, getItemTransactionId, projectId, onComplete],
  );

  const handleCreateNew = useCallback(() => {
    if (!scopeConfig) return;

    const navParams = buildCreateNewParams(scopeConfig, pendingItemIds, fromTransactionId);
    router.push(navParams);

    setVisible(false);
    setPendingItemIds([]);
    onComplete?.();
  }, [scopeConfig, pendingItemIds, fromTransactionId, router, onComplete]);

  return {
    visible,
    pendingItemIds,
    subtitle,
    openForItem,
    openForItems,
    handleConfirm,
    handleCreateNew,
    close,
  };
}
