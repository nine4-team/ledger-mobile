/**
 * Style discipline lint:
 * - Fail CI / checks when inline RN styles are introduced outside `src/ui/**`.
 *
 * Why separate config?
 * - Your main `npm run lint` is intentionally non-blocking (warnings) while the repo stabilizes.
 * - This config is a focused, blocking gate for "styling belongs in the stash".
 */
import tseslint from 'typescript-eslint';
import reactNative from 'eslint-plugin-react-native';

export default [
  {
    ignores: [
      '**/node_modules/**',
      'firebase/**',
      '**/dist/**',
      '**/build/**',
    ],
  },

  {
    files: ['**/*.{ts,tsx,js,jsx}'],
    languageOptions: {
      parser: tseslint.parser,
      ecmaVersion: 'latest',
      sourceType: 'module',
      parserOptions: {
        ecmaFeatures: { jsx: true },
      },
    },
    plugins: {
      'react-native': reactNative,
    },
    rules: {
      // The whole point of this config:
      'react-native/no-inline-styles': 'error',
    },
  },

  // Allow inline styles inside the stash itself.
  {
    files: ['src/ui/**/*.{ts,tsx,js,jsx}'],
    rules: {
      'react-native/no-inline-styles': 'off',
    },
  },
];

