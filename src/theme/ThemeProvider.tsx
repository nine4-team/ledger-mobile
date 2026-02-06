import React, { createContext, useContext, useMemo } from 'react';
import { useColorScheme } from 'react-native';
import { darkTheme, lightTheme, type ColorTheme } from '../ui';
import { createThemeFromUIKit, type Theme } from './theme';
import { appThemeOverrides } from '../ui/tokens';
import { useAppearanceStore, type AppearanceMode } from './appearanceStore';

type ResolvedScheme = 'light' | 'dark';

type ThemeContextValue = {
  uiKitTheme: ColorTheme;
  theme: Theme;
  appearanceMode: AppearanceMode;
  setAppearanceMode: (mode: AppearanceMode) => void;
  resolvedColorScheme: ResolvedScheme;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const systemScheme = useColorScheme();
  const appearanceMode = useAppearanceStore((s) => s.mode);
  const setAppearanceMode = useAppearanceStore((s) => s.setMode);

  const resolvedColorScheme: ResolvedScheme =
    appearanceMode === 'system' ? (systemScheme ?? 'light') : appearanceMode;

  const uiKitTheme = useMemo<ColorTheme>(() => {
    const baseTheme = resolvedColorScheme === 'dark' ? darkTheme : lightTheme;
    // `appThemeOverrides` is intentionally partial; treat it as overrides, not a full theme.
    const overrides = (resolvedColorScheme === 'dark'
      ? appThemeOverrides.dark
      : appThemeOverrides.light) as Partial<ColorTheme>;

    return {
      ...baseTheme,
      primary: {
        ...baseTheme.primary,
        ...(overrides.primary ?? {}),
      },
      neutral: {
        ...baseTheme.neutral,
        ...(overrides.neutral ?? {}),
      },
      text: {
        ...baseTheme.text,
        ...(overrides.text ?? {}),
      },
      border: {
        ...baseTheme.border,
        ...(overrides.border ?? {}),
      },
      background: {
        ...baseTheme.background,
        ...overrides.background,
      },
      tabBar: {
        ...baseTheme.tabBar,
        ...overrides.tabBar,
      },
      button: {
        ...baseTheme.button,
        primary: {
          ...baseTheme.button.primary,
          ...(overrides.button?.primary ?? {}),
        },
        secondary: {
          ...baseTheme.button.secondary,
          ...(overrides.button?.secondary ?? {}),
        },
        disabled: {
          ...baseTheme.button.disabled,
          ...(overrides.button?.disabled ?? {}),
        },
        destructive: {
          ...baseTheme.button.destructive,
          ...(overrides.button?.destructive ?? {}),
        },
        icon: {
          ...baseTheme.button.icon,
          ...(overrides.button?.icon ?? {}),
        },
      },
      input: {
        ...baseTheme.input,
        ...(overrides.input ?? {}),
      },
      status: {
        ...baseTheme.status,
        ...(overrides.status ?? {}),
        met: {
          ...baseTheme.status.met,
          ...(overrides.status?.met ?? {}),
        },
        inProgress: {
          ...baseTheme.status.inProgress,
          ...(overrides.status?.inProgress ?? {}),
        },
        missed: {
          ...baseTheme.status.missed,
          ...(overrides.status?.missed ?? {}),
        },
      },
      archive: {
        ...baseTheme.archive,
        ...(overrides.archive ?? {}),
      },
      shadow: overrides.shadow ?? baseTheme.shadow,
      divider: overrides.divider ?? baseTheme.divider,
      activityIndicator: overrides.activityIndicator ?? baseTheme.activityIndicator,
      link: overrides.link ?? baseTheme.link,
    };
  }, [resolvedColorScheme]);

  const theme = useMemo(() => createThemeFromUIKit(uiKitTheme), [uiKitTheme]);

  const value = useMemo<ThemeContextValue>(
    () => ({
      uiKitTheme,
      theme,
      appearanceMode,
      setAppearanceMode,
      resolvedColorScheme,
    }),
    [appearanceMode, resolvedColorScheme, setAppearanceMode, theme, uiKitTheme]
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useThemeContext() {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    throw new Error('useThemeContext must be used within <ThemeProvider />');
  }
  return ctx;
}

export function useTheme() {
  return useThemeContext().theme;
}

export function useUIKitTheme() {
  return useThemeContext().uiKitTheme;
}

export function useAppearance() {
  const { appearanceMode, setAppearanceMode, resolvedColorScheme } = useThemeContext();
  return { appearanceMode, setAppearanceMode, resolvedColorScheme };
}

