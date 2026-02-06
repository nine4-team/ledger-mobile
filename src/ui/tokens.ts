/**
 * App-only UI tokens and overrides.
 *
 * Rule:
 * - If it doesn't exist in `@nine4/ui-kit` yet, define it here.
 * - Mark anything intended for graduation with `TODO(ui-kit): ...` so it’s easy to locate later.
 */
export const appTokens = {
  screen: {
    // TODO(ui-kit): Add vertical padding params to `getScreenContentStyle` (or a first-class ScreenContent token)
    contentPaddingTop: 18,
    contentPaddingBottom: 0,
  },
} as const;

export const appThemeOverrides = {
  light: {
    /**
     * Light mode should feel clean and "bright":
     * - soft off-white page background
     * - pure-white surfaces
     * - subtle borders
     * - one crisp accent color (used sparingly)
     */
    primary: {
      // Restore brand primary (matches ui-kit default).
      main: '#987e55',
      light: '#987e55',
      dark: '#987e55',
    },
    text: {
      // Slightly richer than ui-kit defaults.
      primary: '#111827',
      secondary: '#6B7280',
      tertiary: '#9CA3AF',
    },
    border: {
      // Softer + less "dirty" than #ddd/#e0e0e0.
      // Slightly stronger so edges are readable on white.
      primary: '#C7CBD4',
      secondary: '#E5E7EB',
    },
    background: {
      // Keep page backgrounds subtle, and let cards carry the "white".
      screen: '#F7F8FA',
      // Use "chrome" (headers/toolbars) as a clear visual layer.
      chrome: '#FFFFFF',
      surface: '#FFFFFF',
      tertiary: '#F3F4F6',
    },
    tabBar: {
      background: '#FFFFFF',
      border: '#E5E7EB',
      activeTint: '#987e55',
      inactiveTint: '#9CA3AF',
    },
    button: {
      primary: {
        background: '#987e55',
      },
      secondary: {
        background: '#FFFFFF',
        text: '#111827',
      },
      icon: {
        // Keep header / "more" icons neutral (accent is too loud everywhere).
        background: '#F3F4F6',
        icon: '#6B7280',
      },
    },
    status: {
      met: {
        // Warm neutral so it doesn't fight the brand accent.
        background: '#F5F3EF',
        text: '#987e55',
        bar: '#987e55',
      },
    },
    link: '#987e55',
    activityIndicator: '#987e55',
  },
  dark: {
    // Base darkTheme from @nine4/ui-kit already has correct neutral grays.
    // Only override here if we need app-specific dark mode customizations.
    // Currently empty - base theme colors are used as-is.
  },
} as const;

// TODO(ui-kit): Promote card padding token when UI kit supports it.
export const CARD_PADDING = 20;

// App-level card border width (used by ItemCard to match list views).
// TODO(ui-kit): Promote when kit supports border width tokens.
export const CARD_BORDER_WIDTH = 1;

