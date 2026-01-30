# Cross-cutting UI: style lanes + starter surfaces

This folder exists to keep **UI contracts and conventions** centralized as we build the Ledger mobile app on top of the skeleton app in this repo.

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

## Skeleton “starter surfaces” you can build on

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
- Image gallery / lightbox contract: `components/image_gallery_lightbox.md`
- Offline media storage guardrails: `components/storage_quota_warning.md`

