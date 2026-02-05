# Style lane rule violations (what’s *actually* breaking existing rules)

Date: 2026-02-05

This doc answers a narrow question:

> Where are components/screens **violating style rules that already exist in this repo** (the ones we can point to in docs + eslint/scripts)?

Anything that’s merely “ugly / inconsistent” but **not an existing rule today** is moved into an appendix so it doesn’t dilute the report.

## Existing style-lane rules in this repo

These are the rules currently defined in-repo:

1) **UI-kit import lane (eslint enforced)**  
   - Rule: do **not** import `@nine4/ui-kit` directly; import via `src/ui` re-exports.  
   - Enforced by: `no-restricted-imports` in `eslint.config.mjs`.

2) **UI-kit delta lane (script enforced)**  
   - Rule: `TODO(ui-kit): ...` markers must exist **only inside `src/ui/**`**.  
   - Enforced by: `npm run ui:check` (`scripts/check-ui-kit-deltas.mjs`).

3) **Inline-style discipline (eslint enforced, but currently noisy)**  
   - Rule: no inline RN styles outside `src/ui/**`.  
   - Enforced by: `npm run lint:styles` (`eslint.styles.config.mjs` → `react-native/no-inline-styles`).

## Rule compliance summary (PASS/FAIL)

- **Rule 1 (UI-kit imports must go through `src/ui`)**: **PASS**
  - Evidence: searching for `@nine4/ui-kit` only hits `src/ui/kit.ts` plus config/docs (no app-code direct imports found).

- **Rule 2 (`TODO(ui-kit):` only in `src/ui/**`)**: **PASS**
  - Evidence: `TODO(ui-kit):` occurrences are in `src/ui/**`, config/docs, and this doc; none found in app/source code outside `src/ui/**`.

- **Rule 3 (no inline styles outside `src/ui/**`)**: **PASS**
  - Evidence: inline-style offenders removed and `npm run lint:styles` runs without `react-native/no-inline-styles` errors.

### Rule 3 cleanup notes (current state)

- The inline-style instances previously flagged by `lint:styles` were moved into StyleSheet or memoized style helpers.
- The style-only lint config now loads the React Hooks and TypeScript ESLint plugins so inline `eslint-disable` comments no longer cause “rule not found” noise.

## Appendix A — drift / inconsistency inventory (useful, but not “existing rule violations”)

These items can absolutely contribute to ugly UI, but **they are not explicitly forbidden by current eslint/scripts**.

### A1) Hard-coded hex colors outside `src/ui/**` (counts by file)

#### `app/**`

```text
app/(tabs)/settings.tsx:12
app/(auth)/sign-in.tsx:1
app/project/[projectId]/spaces/[spaceId].tsx:1
```

#### `src/**`

```text
src/screens/ComponentsGallery.tsx:1
src/components/ListControlBar.tsx:1
src/components/SelectorCircle.tsx:1
src/features/dictation/DictationWidget.tsx:1
```

### A2) Grep signals for additional inline style usage (not the canonical enforcement source)

These are “how much is out there” signals, not authoritative rule violations.

- `style={{ ... }}` appears in:
  - `app/**` (12 files): `app/(tabs)/index.tsx`, `app/paywall.tsx`, `app/account-select.tsx`, etc.
  - `src/**` (9 files): `src/components/SharedItemsList.tsx`, `src/components/SharedItemPicker.tsx`, etc.

- `style={[ ..., { ... } ]}` on the same line appears in:
  - `app/(tabs)/settings.tsx`
  - many `src/components/*` files including `GroupedItemCard`, `ItemCard`, `ExpandableCard`, `AnchoredMenuList`, etc.

