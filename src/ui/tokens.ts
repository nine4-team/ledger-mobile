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

