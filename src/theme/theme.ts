import {
  typography,
  spacing,
  SCREEN_PADDING,
  getCardBaseStyle,
  getCardBorderStyle,
  type ColorTheme,
} from '../ui';

/**
 * Recommended guardrail:
 * Keep a single adapter from UI kit tokens → app theme shape to avoid drift.
 */
export function createThemeFromUIKit(baseTheme: ColorTheme) {
  return {
    colors: {
      // As of ui-kit 0.2.0+, `primary` is the brand accent color.
      primary: baseTheme.primary.main,
      background: baseTheme.background.screen,
      text: baseTheme.text.primary,
      textSecondary: baseTheme.text.secondary,
      inputPlaceholder: baseTheme.input.placeholder,
      border: baseTheme.border.primary,
      error: baseTheme.status.missed.text,
      success: baseTheme.status.met.barComplete,
    },
    typography: {
      h1: typography.header.large,
      h2: typography.header.medium,
      body: typography.text.body,
      caption: typography.text.small,
    },
    spacing: {
      screenPadding: SCREEN_PADDING,
      ...spacing,
    },
    card: {
      backgroundColor: baseTheme.background.surface,
      ...getCardBaseStyle({ radius: 12 }),
      ...getCardBorderStyle(baseTheme),
    },
    tabBar: {
      activeTint: baseTheme.tabBar.activeTint,
      inactiveTint: baseTheme.tabBar.inactiveTint,
      background: baseTheme.tabBar.background,
      border: baseTheme.tabBar.border,
    },
  };
}

export type Theme = ReturnType<typeof createThemeFromUIKit>;
