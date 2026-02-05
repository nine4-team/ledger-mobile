import React from 'react';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import type { AnchoredMenuItem } from './AnchoredMenuList';

export type SortMenuProps = {
  visible: boolean;
  onRequestClose: () => void;
  items: AnchoredMenuItem[];
  title?: string;
};

export function SortMenu({ visible, onRequestClose, items, title = 'Sort' }: SortMenuProps) {
  return <BottomSheetMenuList visible={visible} onRequestClose={onRequestClose} items={items} title={title} />;
}
