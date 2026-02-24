import { useState, useEffect, useRef } from 'react';
import { View, Pressable, StyleSheet, TextInput, ScrollView } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { FormBottomSheet } from '../FormBottomSheet';
import { FormField } from '../FormField';
import { AppText } from '../AppText';
import { AppButton } from '../AppButton';
import { useTheme, useUIKitTheme } from '../../theme/ThemeProvider';
import { getTextInputStyle } from '../../ui/styles/forms';
import type { Checklist, ChecklistItem } from '../../data/spacesService';

function randomId(prefix: string) {
  const cryptoApi = globalThis.crypto as { randomUUID?: () => string } | undefined;
  return cryptoApi?.randomUUID ? cryptoApi.randomUUID() : `${prefix}_${Date.now()}_${Math.random()}`;
}

type EditChecklistModalProps = {
  visible: boolean;
  onRequestClose: () => void;
  /** If provided, modal is in edit mode; otherwise it's in create mode. */
  checklist?: Checklist | null;
  onSave: (checklist: Checklist) => void;
};

export function EditChecklistModal({
  visible,
  onRequestClose,
  checklist,
  onSave,
}: EditChecklistModalProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const isEditing = !!checklist;
  const [name, setName] = useState('');
  const [items, setItems] = useState<ChecklistItem[]>([]);

  useEffect(() => {
    if (visible) {
      setName(checklist?.name ?? '');
      setItems(checklist?.items ?? []);
    }
  }, [visible, checklist]);

  const trimmedName = name.trim();

  const handleAddItem = () => {
    setItems((prev) => [
      ...prev,
      { id: randomId('item'), text: '', isChecked: false },
    ]);
  };

  const handleItemTextChange = (id: string, text: string) => {
    setItems((prev) => prev.map((item) => (item.id === id ? { ...item, text } : item)));
  };

  const handleRemoveItem = (id: string) => {
    setItems((prev) => prev.filter((item) => item.id !== id));
  };

  const handleSave = () => {
    const saved: Checklist = {
      id: checklist?.id ?? randomId('checklist'),
      name: trimmedName,
      items: items.filter((i) => i.text.trim().length > 0),
    };
    onSave(saved);
  };

  return (
    <FormBottomSheet
      visible={visible}
      onRequestClose={onRequestClose}
      title={isEditing ? 'Edit Checklist' : 'New Checklist'}
      primaryAction={{
        title: isEditing ? 'Save' : 'Create',
        onPress: handleSave,
        disabled: !trimmedName,
      }}
      containerStyle={styles.container}
    >
      <FormField
        label="Name"
        value={name}
        onChangeText={setName}
        placeholder="Checklist name"
      />

      {items.length > 0 ? (
        <View style={styles.itemsList}>
          {items.map((item) => (
            <View key={item.id} style={styles.itemRow}>
              {/* Circle bullet */}
              <View style={[styles.circle, { borderColor: uiKitTheme.border.primary }]} />
              <TextInput
                value={item.text}
                onChangeText={(text) => handleItemTextChange(item.id, text)}
                placeholder="Item"
                placeholderTextColor={theme.colors.textSecondary}
                style={[
                  getTextInputStyle(uiKitTheme, { padding: 8, radius: 8 }),
                  styles.itemInput,
                ]}
              />
              <Pressable
                onPress={() => handleRemoveItem(item.id)}
                hitSlop={8}
                accessibilityRole="button"
                accessibilityLabel="Remove item"
              >
                <MaterialIcons name="close" size={18} color={theme.colors.textSecondary} />
              </Pressable>
            </View>
          ))}
        </View>
      ) : null}

      <AppButton title="Add Item" variant="secondary" onPress={handleAddItem} />
    </FormBottomSheet>
  );
}

const styles = StyleSheet.create({
  container: {
    maxHeight: '85%',
  },
  itemsList: {
    gap: 8,
  },
  itemRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  circle: {
    width: 18,
    height: 18,
    borderRadius: 9,
    borderWidth: 1.5,
    flexShrink: 0,
  },
  itemInput: {
    flex: 1,
  },
});
