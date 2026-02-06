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
    background: {
      screen: '#F6F6F6',
      surface: '#FFFFFF',
    },
    tabBar: {
      background: '#F6F6F6',
      border: '#E3E3E3',
    },
    button: {
      secondary: {
        background: '#FFFFFF',
      },
    },
  },
  dark: {
    background: {
      screen: '#0F1115',
      surface: '#151922',
    },
    tabBar: {
      background: '#0F1115',
      border: '#23272F',
    },
    button: {
      secondary: {
        background: '#1B2029',
      },
    },
  },
} as const;

// TODO(ui-kit): Promote card padding token when UI kit supports it.
export const CARD_PADDING = 20;

// App-level card border width (used by ItemCard to match list views).
// TODO(ui-kit): Promote when kit supports border width tokens.
export const CARD_BORDER_WIDTH = 1;

