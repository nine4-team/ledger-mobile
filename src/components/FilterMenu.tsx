import React from 'react';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import type { AnchoredMenuItem } from './AnchoredMenuList';

export type FilterMenuProps = {
  visible: boolean;
  onRequestClose: () => void;
  items: AnchoredMenuItem[];
  title?: string;
};

export function FilterMenu({ visible, onRequestClose, items, title = 'Filters' }: FilterMenuProps) {
  return (
    <BottomSheetMenuList
      visible={visible}
      onRequestClose={onRequestClose}
      items={items}
      title={title}
      closeOnSubactionPress={false}
      closeOnItemPress={false}
    />
  );
}
