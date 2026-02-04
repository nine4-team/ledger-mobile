import { Alert } from 'react-native';

export type ItemConflictDialogOptions = {
  conflictItemNames: string[];
  onConfirm: () => void;
  onCancel?: () => void;
};

/**
 * Shows a confirmation dialog when items are linked to another transaction/space.
 * Used when adding items that have existing links elsewhere.
 */
export function showItemConflictDialog(options: ItemConflictDialogOptions): void {
  const { conflictItemNames, onConfirm, onCancel } = options;
  const names = conflictItemNames.slice(0, 4);
  const hasMore = conflictItemNames.length > 4;
  const message = `Some items are linked to another transaction. Reassign them?${
    hasMore ? `\n\n${names.join('\n')}\n...and ${conflictItemNames.length - 4} more` : `\n\n${names.join('\n')}`
  }`;

  Alert.alert('Reassign items?', message, [
    { text: 'Cancel', style: 'cancel', onPress: onCancel },
    { text: 'Reassign', style: 'destructive', onPress: onConfirm },
  ]);
}
