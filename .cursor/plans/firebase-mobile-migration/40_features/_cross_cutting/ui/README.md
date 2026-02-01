# Cross-cutting UI: style lanes + starter surfaces

This folder exists to keep **UI contracts and conventions** centralized as we build the Ledger Mobile app in this repo.

## Style lane (non-negotiable)

- **All UI-kit imports go through `src/ui`**.
  - Do **not** import `@nine4/ui-kit` directly in app code.
  - The repo enforces this via `no-restricted-imports` in `eslint.config.mjs`.
- **App-owned tokens/styles intended to “graduate” into the shared UI kit live in `src/ui/**`.**
  - Tag anything intended for graduation with **`TODO(ui-kit): ...`**.
  - Run `npm run ui:check` to ensure those markers exist **only** in `src/ui/**`.
- **Avoid ad-hoc inline styles outside `src/ui/**`.**
  - The repo includes a strict style discipline lint: `npm run lint:styles` (blocks inline RN styles outside `src/ui/**`).

### Where to put what (quick map)

- **Published UI kit re-export (single import surface)**: `src/ui/kit.ts`
- **App-only tokens / overrides**: `src/ui/tokens.ts` (e.g. `appTokens.screen.*`)
- **App-only style primitives**: `src/ui/styles/*`
  - `layout` (row helpers, shared spacing wrappers)
  - `surface` (card helpers, overflow helpers)
  - `textEmphasis` (section labels, value emphasis, etc.)

## Starter surfaces you can build on

These are intentionally small but give the team stable lanes to slot into:

- **Screen shell + header**: `src/components/Screen.tsx`, `src/components/TopHeader.tsx`
- **Tabbed navigation surface**: `src/components/ScreenTabs.tsx`
- **Settings baseline**: `app/(tabs)/settings.tsx`
- **Card primitives**:
  - Item preview card: `src/components/ItemPreviewCard.tsx` (exports `ItemCard`)
  - Grouped item list card: `src/components/GroupedItemListCard.tsx` (exports `GroupedItemCard`)
- **Components playground / template screens (overwrite content freely)**:
  - `app/(tabs)/index.tsx` (currently a components playground)
  - `app/(tabs)/screen-two.tsx`
  - `app/(tabs)/screen-three.tsx`

## Web parity references (Ledger web app)

When a behavior/UI contract is “parity-critical”, feature specs should cite the web source as evidence (example: `shared_items_and_transactions_modules.md`).

- **Do**: link to the relevant web file/function in the spec as “parity evidence”.
- **Don’t**: copy/paste web implementation details into mobile specs when a short reference will do.

## Related cross-cutting specs

- Shared Items + Transactions modules: `shared_items_and_transactions_modules.md`
- Shared UI contracts (single canonical doc): `shared_ui_contracts.md`
- UI parity inventory matrix (track gaps): `ui_parity_inventory_matrix.md`

## Cross-cutting UI contracts (index)

The web app we’re migrating from has a dedicated reusable UI layer:

- `ledger/src/components/ui/*`

We do **not** need to spec every component up front, but we do need a grounded backlog so this folder doesn’t feel arbitrary.

### Where shared UI behavior is specified (canonical)

- **All shared UI behavior contracts live in one place**:
  - `shared_ui_contracts.md`
- Use the **UI parity inventory matrix** to track what’s missing / in-progress:
  - `ui_parity_inventory_matrix.md`

### High-value contracts (already present)

All shared UI contract content is centralized in:

- `shared_ui_contracts.md`

### Validation rule (so we don’t write fake docs)

Treat every contract section in `shared_ui_contracts.md` as **tentative until a feature spec references it**.

- When you first reference a contract from a feature spec, sanity-check it against parity behavior (web) and add missing edge cases.
- If something turns out not to be reused (or not worth sharing), move the contract back into the owning feature spec and leave a short redirect note.

