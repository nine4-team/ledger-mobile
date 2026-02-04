import React from 'react';
import { StyleSheet, View } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { AppButton } from './AppButton';
import { ListStateControls } from './ListStateControls';
import { useUIKitTheme } from '../theme/ThemeProvider';

type ControlAction = {
  title: string;
  onPress: () => void;
  variant: 'primary' | 'secondary';
  iconName?: React.ComponentProps<typeof MaterialIcons>['name'];
  disabled?: boolean;
};

type ListControlBarProps = {
  search: string;
  onChangeSearch: (value: string) => void;
  actions: ControlAction[];
};

export function ListControlBar({ search, onChangeSearch, actions }: ListControlBarProps) {
  const uiKitTheme = useUIKitTheme();

  return (
    <View style={styles.controlBar}>
      <ListStateControls search={search} onChangeSearch={onChangeSearch} />
      <View style={styles.controlButtons}>
        {actions.map((action) => (
          <AppButton
            key={action.title}
            title={action.title}
            variant={action.variant}
            onPress={action.onPress}
            style={styles.controlButton}
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
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  controlBar: {
    flexDirection: 'column',
    alignItems: 'stretch',
    gap: 12,
    paddingTop: 8,
    borderRadius: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  controlButtons: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    width: '100%',
  },
  controlButton: {
    flex: 1,
    minHeight: 40,
    paddingVertical: 10,
    paddingHorizontal: 16,
  },
});
