import { useRef, useState, useCallback, useEffect } from 'react';

/**
 * Form hook that tracks which fields changed relative to an initial snapshot.
 *
 * @example
 * const { values, setField, hasEdited, getChangedFields, hasChanges } = useEditForm(project);
 *
 * // Update a single field
 * setField('name', 'New Name');
 *
 * // Update multiple fields
 * setFields({ name: 'New Name', description: 'New Desc' });
 *
 * // Get only the fields that changed
 * const changes = getChangedFields(); // { name: 'New Name' }
 *
 * // Check if there are any changes
 * if (hasChanges) {
 *   updateProject(projectId, getChangedFields());
 * }
 */
export function useEditForm<T extends Record<string, any>>(initialData: T | null) {
  // Snapshot of the original data - captured from first non-null initialData
  const snapshotRef = useRef<T | null>(null);

  // Current form values
  const [values, setValues] = useState<T | null>(initialData);

  // Track whether user has touched the form
  const [hasEdited, setHasEdited] = useState(false);

  // Capture snapshot from first non-null initialData
  // Update snapshot from subscription data until user edits
  useEffect(() => {
    if (initialData === null) {
      return;
    }

    // First time receiving data - capture snapshot
    if (snapshotRef.current === null) {
      snapshotRef.current = initialData;
      setValues(initialData);
      return;
    }

    // If user hasn't edited yet, accept subscription updates
    if (!hasEdited) {
      snapshotRef.current = initialData;
      setValues(initialData);
    }
  }, [initialData, hasEdited]);

  /**
   * Update a single field and mark form as edited
   */
  const setField = useCallback(<K extends keyof T>(key: K, value: T[K]) => {
    setHasEdited(true);
    setValues((prev) => {
      if (prev === null) return null;
      return { ...prev, [key]: value };
    });
  }, []);

  /**
   * Update multiple fields at once and mark form as edited
   */
  const setFields = useCallback((updates: Partial<T>) => {
    setHasEdited(true);
    setValues((prev) => {
      if (prev === null) return null;
      return { ...prev, ...updates };
    });
  }, []);

  /**
   * Compare two values, treating null and undefined as equivalent
   * (Firestore doesn't store undefined)
   */
  const isEqual = useCallback((a: any, b: any): boolean => {
    // Normalize null/undefined
    const normalizedA = a ?? null;
    const normalizedB = b ?? null;

    return normalizedA === normalizedB;
  }, []);

  /**
   * Get only the fields that differ from the snapshot
   * Returns empty object if no changes
   */
  const getChangedFields = useCallback((): Partial<T> => {
    if (snapshotRef.current === null || values === null) {
      return {};
    }

    const changes: Partial<T> = {};
    const snapshot = snapshotRef.current;

    for (const key in values) {
      if (!isEqual(values[key], snapshot[key])) {
        changes[key] = values[key];
      }
    }

    return changes;
  }, [values, isEqual]);

  /**
   * Check if there are any changes (getChangedFields() is non-empty)
   */
  const hasChanges = useCallback((): boolean => {
    const changes = getChangedFields();
    return Object.keys(changes).length > 0;
  }, [getChangedFields]);

  /**
   * Whether subscription data should be accepted
   * True until first setField call
   */
  const shouldAcceptSubscriptionData = !hasEdited;

  /**
   * Reset the form to re-accept subscription data
   * Clears hasEdited flag and resets to snapshot
   */
  const reset = useCallback(() => {
    setHasEdited(false);
    if (snapshotRef.current !== null) {
      setValues(snapshotRef.current);
    }
  }, []);

  return {
    values: values ?? ({} as T), // Return empty object if null for easier consumption
    setField,
    setFields,
    hasEdited,
    getChangedFields,
    hasChanges: hasChanges(),
    shouldAcceptSubscriptionData,
    reset,
  };
}
