import { useEffect, useRef, useState } from 'react';
import { subscribeToItem } from '../data/itemsService';
import type { Item } from '../data/itemsService';

/**
 * Subscribe to multiple items by ID for realtime updates.
 * Each item gets its own subscription; subscriptions are cleaned up on unmount or ID changes.
 */
export function useItemsByIds(
  accountId: string | null | undefined,
  itemIds: string[],
): { items: Item[]; loading: boolean } {
  const [itemsMap, setItemsMap] = useState<Record<string, Item>>({});
  const [loading, setLoading] = useState(itemIds.length > 0);
  const pendingRef = useRef(new Set<string>());

  useEffect(() => {
    if (!accountId || itemIds.length === 0) {
      setItemsMap({});
      setLoading(false);
      return;
    }

    // Deduplicate
    const uniqueIds = [...new Set(itemIds)];
    const pending = new Set(uniqueIds);
    pendingRef.current = pending;
    setLoading(true);

    const unsubscribes = uniqueIds.map((itemId) =>
      subscribeToItem(accountId, itemId, (item) => {
        if (item) {
          setItemsMap((prev) => ({ ...prev, [itemId]: item }));
        } else {
          setItemsMap((prev) => {
            const next = { ...prev };
            delete next[itemId];
            return next;
          });
        }
        pending.delete(itemId);
        if (pending.size === 0) {
          setLoading(false);
        }
      }),
    );

    return () => {
      unsubscribes.forEach((unsub) => unsub());
    };
  }, [accountId, itemIds.join(',')]); // eslint-disable-line react-hooks/exhaustive-deps

  const items = Object.values(itemsMap);
  return { items, loading };
}
