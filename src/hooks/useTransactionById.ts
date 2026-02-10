import { useEffect, useState } from 'react';
import { subscribeToTransaction, type Transaction, getTransaction } from '../data/transactionsService';

type UseTransactionByIdOptions = {
  mode?: 'online' | 'offline';
};

export function useTransactionById(
  accountId: string | null | undefined,
  transactionId: string | null | undefined,
  options: UseTransactionByIdOptions = {}
): { data: Transaction | null; loading: boolean } {
  const { mode = 'offline' } = options;
  const [data, setData] = useState<Transaction | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!accountId || !transactionId) {
      setData(null);
      setLoading(false);
      return;
    }

    setLoading(true);

    // Cache-first preload for instant display (offline-first pattern)
    if (mode === 'offline') {
      getTransaction(accountId, transactionId, 'offline')
        .then((transaction) => {
          setData(transaction);
          setLoading(false);
        })
        .catch((err) => {
          console.warn('[useTransactionById] cache preload failed:', err);
          setLoading(false);
        });
    }

    // Subscribe to real-time updates
    const unsubscribe = subscribeToTransaction(accountId, transactionId, (transaction) => {
      setData(transaction);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [accountId, transactionId, mode]);

  return { data, loading };
}
