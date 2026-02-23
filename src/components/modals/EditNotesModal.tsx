import React, { useEffect, useState } from 'react';

import { FormBottomSheet } from '../FormBottomSheet';
import { FormField } from '../FormField';

export type EditNotesModalProps = {
  visible: boolean;
  onRequestClose: () => void;
  initialNotes: string;
  onSave: (notes: string) => void;
  title?: string;
};

export function EditNotesModal({
  visible,
  onRequestClose,
  initialNotes,
  onSave,
  title = 'Edit Notes',
}: EditNotesModalProps) {
  const [notes, setNotes] = useState(initialNotes);

  useEffect(() => {
    if (visible) {
      setNotes(initialNotes);
    }
  }, [visible]);

  const handleSave = () => {
    onSave(notes);
    onRequestClose();
  };

  return (
    <FormBottomSheet
      visible={visible}
      onRequestClose={onRequestClose}
      title={title}
      primaryAction={{
        title: 'Save',
        onPress: handleSave,
        disabled: notes === initialNotes,
      }}
    >
      <FormField
        label="Notes"
        value={notes}
        onChangeText={setNotes}
        placeholder="Add notes..."
        inputProps={{
          multiline: true,
          numberOfLines: 8,
          textAlignVertical: 'top',
        }}
        inputStyle={{ minHeight: 160 }}
      />
    </FormBottomSheet>
  );
}
