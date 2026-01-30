import React, { createContext, useContext, useMemo } from 'react';
import { useColorScheme } from 'react-native';
import { darkTheme, lightTheme, type ColorTheme } from '../ui';
import { createThemeFromUIKit, type Theme } from './theme';
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
    return resolvedColorScheme === 'dark' ? darkTheme : lightTheme;
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

