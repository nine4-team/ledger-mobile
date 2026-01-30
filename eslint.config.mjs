import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';
import importPlugin from 'eslint-plugin-import';

export default [
  // Keep lint focused on app code; Firebase Functions is its own package.
  {
    ignores: [
      '**/node_modules/**',
      'firebase/**',
      '**/dist/**',
      '**/build/**',
    ],
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  {
    files: ['**/*.{js,jsx,ts,tsx}'],
    plugins: {
      react,
      'react-hooks': reactHooks,
      import: importPlugin,
    },
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      parserOptions: {
        ecmaFeatures: { jsx: true },
      },
    },
    settings: {
      react: { version: 'detect' },
      // Enables resolving TS path aliases like "@/*" from tsconfig.json
      'import/resolver': {
        typescript: {
          project: ['./tsconfig.json'],
        },
      },
    },
    rules: {
      // Expo / React 17+ JSX transform
      'react/react-in-jsx-scope': 'off',

      // Hooks rules
      ...reactHooks.configs.recommended.rules,

      // Small guardrails
      'import/no-duplicates': 'warn',
      'import/order': [
        'warn',
        {
          'newlines-between': 'always',
          alphabetize: { order: 'asc', caseInsensitive: true },
        },
      ],

      // Keep adoption easy: warn on common TS escape hatches in existing code.
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-require-imports': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],

      /**
       * UI kit delta policy:
       * If you’re making app-only tokens/styles/components that should graduate to the kit,
       * tag them with `TODO(ui-kit): ...` and keep them inside `src/ui/**`.
       */
      'no-warning-comments': [
        'error',
        { terms: ['TODO(ui-kit)'], location: 'anywhere' },
      ],

      /**
       * Strict mode:
       * Force all `@nine4/ui-kit` imports to go through the local stash (re-exports) in `src/ui/**`.
       */
      'no-restricted-imports': [
        'error',
        {
          paths: [
            {
              name: '@nine4/ui-kit',
              message: 'Import from `src/ui` (local re-export) so overrides are centralized.',
            },
          ],
        },
      ],
    },
  },

  // Allow TODO(ui-kit) markers inside the stash.
  {
    files: ['src/ui/**/*.{js,jsx,ts,tsx}'],
    rules: {
      'no-warning-comments': 'off',
      'no-restricted-imports': 'off',
    },
  },
];

