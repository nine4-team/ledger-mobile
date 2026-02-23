import { useState, useEffect } from 'react';
import { FormBottomSheet } from '../FormBottomSheet';
import { FormField } from '../FormField';

type EditSpaceDetailsModalProps = {
  visible: boolean;
  onRequestClose: () => void;
  initialName: string;
  onSave: (name: string) => void;
};

export function EditSpaceDetailsModal({
  visible,
  onRequestClose,
  initialName,
  onSave,
}: EditSpaceDetailsModalProps) {
  const [name, setName] = useState(initialName);

  useEffect(() => {
    if (visible) {
      setName(initialName);
    }
  }, [visible, initialName]);

  const trimmedName = name.trim();

  const handleSave = () => {
    onSave(trimmedName);
  };

  return (
    <FormBottomSheet
      visible={visible}
      onRequestClose={onRequestClose}
      title="Edit Space Details"
      primaryAction={{ title: 'Save', onPress: handleSave, disabled: !trimmedName }}
    >
      <FormField
        label="Name"
        value={name}
        onChangeText={setName}
        placeholder="Space name"
      />
    </FormBottomSheet>
  );
}
