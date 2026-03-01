import React from 'react';
import { ListControlBar } from './ListControlBar';

type ItemsListControlBarProps = {
  search: string;
  onChangeSearch: (value: string) => void;
  showSearch: boolean;
  onToggleSearch: () => void;
  onSort: () => void;
  isSortActive: boolean;
  onFilter: () => void;
  isFilterActive: boolean;
  onAdd?: () => void;
  onAiSearch?: () => void;
  leftElement?: React.ReactNode;
};

export function ItemsListControlBar({
  search,
  onChangeSearch,
  showSearch,
  onToggleSearch,
  onSort,
  isSortActive,
  onFilter,
  isFilterActive,
  onAdd,
  onAiSearch,
  leftElement,
}: ItemsListControlBarProps) {
  return (
    <ListControlBar
      search={search}
      onChangeSearch={onChangeSearch}
      showSearch={showSearch}
      leftElement={leftElement}
      actions={[
        {
          title: '',
          variant: 'secondary',
          onPress: onToggleSearch,
          iconName: 'search',
          active: showSearch,
          accessibilityLabel: 'Toggle search',
        },
        {
          title: 'Sort',
          variant: 'secondary',
          onPress: onSort,
          iconName: 'sort',
          active: isSortActive,
          accessibilityLabel: 'Sort items',
        },
        {
          title: 'Filter',
          variant: 'secondary',
          onPress: onFilter,
          iconName: 'filter-list',
          active: isFilterActive,
          accessibilityLabel: 'Filter items',
        },
        ...(onAiSearch ? [{
          title: 'AI Search',
          variant: 'secondary' as const,
          onPress: onAiSearch,
          iconName: 'auto-awesome' as const,
          accessibilityLabel: 'AI Search',
        }] : []),
        ...(onAdd ? [{
          title: 'Add',
          variant: 'primary' as const,
          onPress: onAdd,
          iconName: 'add' as const,
          accessibilityLabel: 'Add item',
        }] : []),
      ]}
    />
  );
}
