import React, { useMemo } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import type { TextInputProps, ViewStyle } from 'react-native';

import { useTheme, useUIKitTheme } from '@/theme/ThemeProvider';
import { getTextInputStyle } from '../ui/styles/forms';
import { layout } from '../ui/styles/layout';
import { getCardStyle, surface } from '../ui/styles/surfaces';
import { getTextSecondaryStyle, textEmphasis } from '../ui/styles/typography';

import { AppButton } from './AppButton';
import { AppText } from './AppText';

export type InfoCardStatus = 'idle' | 'saving' | 'success' | 'error';

export type InfoCardProps = {
  title: string;
  description?: string;
  /**
   * Optional element rendered next to the title label (outside the card surface).
   * Useful for small actions like Edit.
   */
  titleRight?: React.ReactNode;
  status?: InfoCardStatus;
  error?: string;
  successText?: string;
  footer?: React.ReactNode;
  children: React.ReactNode;
  style?: ViewStyle;
};

export type InfoCardFieldProps = {
  label: string;
  value: string;
  right?: React.ReactNode;
  helperText?: string;
};

export type InfoCardEditableFieldProps = {
  label: string;
  value: string;
  onChangeText: (next: string) => void;
  placeholder?: string;
  disabled?: boolean;
  inputProps?: Omit<TextInputProps, 'value' | 'onChangeText' | 'editable' | 'placeholder'>;
  errorText?: string;
};

export type InfoCardActionsProps = {
  primary?: React.ComponentProps<typeof AppButton>;
  secondary?: React.ComponentProps<typeof AppButton>;
};

type InfoCardComponent = React.FC<InfoCardProps> & {
  Field: React.FC<InfoCardFieldProps>;
  EditableField: React.FC<InfoCardEditableFieldProps>;
  Actions: React.FC<InfoCardActionsProps>;
};

export const InfoCard = (({
  title,
  description,
  titleRight,
  status = 'idle',
  error,
  successText = 'Saved.',
  footer,
  children,
  style,
}: InfoCardProps) => {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const showError = status === 'error' && Boolean(error);
  const showSuccess = status === 'success' && Boolean(successText);

  return (
    <View style={style}>
      <View style={styles.titleRow}>
        <AppText variant="caption" style={[textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}>
          {title}
        </AppText>
        {titleRight ? <View style={styles.titleRight}>{titleRight}</View> : null}
      </View>

      <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
        {description ? (
          <AppText variant="caption" style={[styles.description, getTextSecondaryStyle(uiKitTheme)]}>
            {description}
          </AppText>
        ) : null}

        {showError ? (
          <View style={[styles.banner, { borderColor: theme.colors.error }]}>
            <AppText variant="body" style={{ color: theme.colors.error }}>
              {error}
            </AppText>
          </View>
        ) : null}

        <View style={styles.content}>{children}</View>

        {showSuccess ? (
          <AppText variant="caption" style={[styles.successText, getTextSecondaryStyle(uiKitTheme)]}>
            {successText}
          </AppText>
        ) : null}

        {footer ? <View style={styles.footer}>{footer}</View> : null}
      </View>
    </View>
  );
}) as InfoCardComponent;

InfoCard.Field = function InfoCardField({ label, value, right, helperText }: InfoCardFieldProps) {
  const uiKitTheme = useUIKitTheme();

  return (
    <View>
      <View style={layout.rowBetween}>
        <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
          {label}
        </AppText>
        <View style={styles.fieldRight}>
          <AppText variant="body" style={[styles.value, textEmphasis.value]}>
            {value}
          </AppText>
          {right ? <View style={styles.fieldRightAccessory}>{right}</View> : null}
        </View>
      </View>
      {helperText ? (
        <AppText variant="caption" style={[styles.helperText, getTextSecondaryStyle(uiKitTheme)]}>
          {helperText}
        </AppText>
      ) : null}
    </View>
  );
};

InfoCard.EditableField = function InfoCardEditableField({
  label,
  value,
  onChangeText,
  placeholder,
  disabled,
  inputProps,
  errorText,
}: InfoCardEditableFieldProps) {
  const uiKitTheme = useUIKitTheme();

  const inputStyle = useMemo(
    () =>
      getTextInputStyle(uiKitTheme, {
        radius: 10,
        paddingVertical: 10,
        paddingHorizontal: 12,
      }),
    [uiKitTheme]
  );

  return (
    <View style={styles.editableField}>
      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
        {label}
      </AppText>
      <TextInput
        placeholder={placeholder}
        value={value}
        onChangeText={onChangeText}
        editable={!disabled}
        style={[inputStyle, disabled ? styles.disabledInput : null]}
        placeholderTextColor={uiKitTheme.input.placeholder}
        autoCorrect={false}
        {...inputProps}
      />
      {errorText ? (
        <AppText variant="caption" style={[styles.helperText, { color: uiKitTheme.status.missed.text }]}>
          {errorText}
        </AppText>
      ) : null}
    </View>
  );
};

InfoCard.Actions = function InfoCardActions({ primary, secondary }: InfoCardActionsProps) {
  if (!primary && !secondary) return null;

  return (
    <View style={styles.actions}>
      {secondary ? <AppButton {...secondary} variant={secondary.variant ?? 'secondary'} /> : null}
      {primary ? <AppButton {...primary} /> : null}
    </View>
  );
};

const styles = StyleSheet.create({
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 8,
  },
  titleRight: {
    marginTop: -1,
  },
  description: {
    marginBottom: 12,
  },
  banner: {
    borderWidth: 1,
    borderRadius: 10,
    padding: 10,
    marginBottom: 12,
  },
  fieldRight: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    flexShrink: 1,
    minWidth: 0,
  },
  fieldRightAccessory: {
    marginLeft: 8,
  },
  value: {
    textAlign: 'right',
  },
  helperText: {
    marginTop: 6,
  },
  editableField: {
    gap: 6,
  },
  disabledInput: {
    opacity: 0.6,
  },
  content: {
    gap: 12,
  },
  actions: {
    flexDirection: 'row',
    gap: 8,
  },
  successText: {
    marginTop: 10,
  },
  footer: {
    marginTop: 10,
  },
});

