import { useState, useRef, useCallback, useMemo } from 'react';

/**
 * Hook for managing edit form state with change tracking.
 *
 * Provides partial write capability by tracking which fields have been modified
 * and protecting against subscription overwrites during active editing.
 *
 * @param initialData - Initial form data (can be null during loading)
 * @returns Form state management object with change tracking
 */
export function useEditForm<T extends Record<string, any>>(initialData: T | null) {
  // Snapshot of initial data for change comparison
  const [snapshot, setSnapshot] = useState<T | null>(initialData);

  // Current form values
  const [values, setValues] = useState<T>(() =>
    initialData || {} as T
  );

  // Track if user has made any edits
  const [hasEdited, setHasEdited] = useState(false);

  /**
   * shouldAcceptSubscriptionData is true until the first setField call.
   * This prevents subscription updates from overwriting user edits.
   */
  const shouldAcceptSubscriptionData = !hasEdited;

  /**
   * Update a single field and mark form as edited
   */
  const setField = useCallback(<K extends keyof T>(key: K, value: T[K]) => {
    setHasEdited(true);
    setValues(prev => ({
      ...prev,
      [key]: value
    }));
  }, []);

  /**
   * Update multiple fields at once
   * Useful for accepting subscription data or bulk updates
   */
  const setFields = useCallback((updates: Partial<T>) => {
    setValues(prev => ({
      ...prev,
      ...updates
    }));
    // Update snapshot to reflect new baseline
    setSnapshot(prev => ({
      ...(prev || {} as T),
      ...updates
    }));
  }, []);

  /**
   * Get only the fields that have changed from the initial snapshot
   */
  const getChangedFields = useCallback((): Partial<T> => {
    if (!snapshot) {
      return values; // No snapshot means everything is new
    }

    const changed: Partial<T> = {};

    for (const key in values) {
      if (values[key] !== snapshot[key]) {
        changed[key] = values[key];
      }
    }

    return changed;
  }, [values, snapshot]);

  /**
   * Check if there are any changes from the initial snapshot
   */
  const hasChanges = useMemo(() => {
    const changed = getChangedFields();
    return Object.keys(changed).length > 0;
  }, [getChangedFields]);

  /**
   * Reset the form to accept subscription data again
   * Call this after accepting new subscription data
   */
  const reset = useCallback(() => {
    setHasEdited(false);
  }, []);

  return {
    values,
    setField,
    setFields,
    hasEdited,
    getChangedFields,
    hasChanges,
    shouldAcceptSubscriptionData,
    reset
  };
}
