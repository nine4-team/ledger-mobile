import React, { useMemo } from 'react';
import { StyleSheet, View, TouchableOpacity } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { AppButton } from './AppButton';
import { ListStateControls } from './ListStateControls';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { BUTTON_BORDER_RADIUS } from '../ui';

type ControlAction = {
  title: string;
  onPress: () => void;
  variant: 'primary' | 'secondary';
  iconName?: React.ComponentProps<typeof MaterialIcons>['name'];
  disabled?: boolean;
  active?: boolean;
  appearance?: 'default' | 'tile';
  accessibilityLabel?: string;
};

type ListControlBarProps = {
  search: string;
  onChangeSearch: (value: string) => void;
  actions: ControlAction[];
  leftElement?: React.ReactNode;
  showSearch?: boolean;
};

export function ListControlBar({ search, onChangeSearch, actions, leftElement, showSearch = true }: ListControlBarProps) {
  const uiKitTheme = useUIKitTheme();
  const themed = useMemo(
    () =>
      StyleSheet.create({
        container: {
          backgroundColor: uiKitTheme.background.chrome,
          borderColor: uiKitTheme.border.secondary,
        },
      }),
    [uiKitTheme]
  );

  return (
    <View style={[styles.controlBar, themed.container]}>
      <View style={styles.controlButtons}>
        {leftElement}
        {actions.map((action, index) => {
          if (action.appearance === 'tile') {
            return (
              <TouchableOpacity
                key={`${action.accessibilityLabel ?? action.title ?? 'tile'}-${action.iconName ?? 'action'}-${index}`}
                onPress={action.onPress}
                disabled={action.disabled}
                style={[
                  styles.tileButton,
                  {
                    borderColor: action.active ? uiKitTheme.primary.main : uiKitTheme.border.secondary,
                    backgroundColor: 'transparent',
                  },
                  action.disabled && styles.disabled,
                ]}
                accessibilityRole="button"
                accessibilityLabel={
                  action.accessibilityLabel ??
                  (action.title?.trim() ? action.title : undefined) ??
                  'Action'
                }
              >
                <MaterialIcons
                  name={action.iconName ?? 'add'}
                  size={20}
                  color={uiKitTheme.text.secondary}
                />
              </TouchableOpacity>
            );
          }
          const isIconOnly = !action.title || action.title.trim() === '';
          if (isIconOnly && action.iconName) {
            return (
              <TouchableOpacity
                key={`${action.iconName || 'action'}-${index}`}
                onPress={action.onPress}
                disabled={action.disabled}
                style={[
                  styles.iconOnlyButton,
                  action.variant === 'primary'
                    ? { backgroundColor: uiKitTheme.button.primary.background }
                    : {
                        backgroundColor: uiKitTheme.button.secondary.background,
                        borderWidth: 1,
                        borderColor: action.active
                          ? uiKitTheme.primary.main
                          : uiKitTheme.border.primary,
                      },
                  action.disabled && styles.disabled,
                ]}
                accessibilityRole="button"
                accessibilityLabel={action.title || 'Toggle search'}
              >
                <MaterialIcons
                  name={action.iconName}
                  size={18}
                  color={
                    action.variant === 'primary'
                      ? uiKitTheme.button.primary.text
                      : uiKitTheme.button.secondary.text
                  }
                />
              </TouchableOpacity>
            );
          }
          return (
            <AppButton
              key={`${action.title || action.iconName || 'action'}-${index}`}
              title={action.title}
              variant={action.variant}
              onPress={action.onPress}
              style={[
                styles.controlButton,
                action.active ? { borderColor: uiKitTheme.primary.main } : null,
              ]}
              disabled={action.disabled}
              leftIcon={
                action.iconName ? (
                  <MaterialIcons
                    name={action.iconName}
                    size={18}
                    color={
                      action.variant === 'primary'
                        ? uiKitTheme.button.primary.text
                        : uiKitTheme.button.secondary.text
                    }
                  />
                ) : undefined
              }
            />
          );
        })}
      </View>
      {showSearch && <ListStateControls search={search} onChangeSearch={onChangeSearch} />}
    </View>
  );
}

const styles = StyleSheet.create({
  controlBar: {
    flexDirection: 'column',
    alignItems: 'stretch',
    gap: 12,
    padding: 8,
    borderRadius: 16,
    borderWidth: 1,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  controlButtons: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    width: '100%',
  },
  controlButton: {
    flex: 1,
    minHeight: 40,
    paddingVertical: 10,
    paddingHorizontal: 16,
  },
  iconOnlyButton: {
    borderRadius: BUTTON_BORDER_RADIUS,
    alignItems: 'center',
    justifyContent: 'center',
    width: 40,
    height: 40,
  },
  tileButton: {
    borderRadius: 12,
    borderWidth: 2,
    borderStyle: 'dashed',
    alignItems: 'center',
    justifyContent: 'center',
    width: 40,
    height: 40,
  },
  disabled: {
    opacity: 0.5,
  },
});
