import { useEffect, useState } from 'react';
import { subscribeToSpace, type Space } from '../data/spacesService';

type UseSpaceByIdOptions = {
  mode?: 'online' | 'offline';
};

export function useSpaceById(
  accountId: string | null | undefined,
  spaceId: string | null | undefined,
  options: UseSpaceByIdOptions = {}
): { data: Space | null; loading: boolean } {
  const [data, setData] = useState<Space | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!accountId || !spaceId) {
      setData(null);
      setLoading(false);
      return;
    }

    setLoading(true);

    // Subscribe to real-time updates (includes cache-first behavior from React Native Firebase)
    const unsubscribe = subscribeToSpace(accountId, spaceId, (space) => {
      setData(space);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [accountId, spaceId]);

  return { data, loading };
}
