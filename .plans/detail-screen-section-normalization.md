# Detail Screen Section Normalization

**Status**: ✅ COMPLETE
**Completed**: 2026-02-10
**Work Package**: WP04 (kitty-specs/005-detail-screen-polish)
**Commit**: 0185982

---

## Context

Three detail screens (transaction, item, space) were polished across WP02/03/04 but the section component architecture diverged. Three issues:

1. **Shared `NotesSection` uses `TitledCard`**, creating duplicate titles when inside `CollapsibleSectionHeader` ("NOTES" header + "Notes" card title). Affects item detail + space detail.
2. **Transaction detail created a custom `NotesSection`** (correctly using `Card`) instead of fixing the shared one — duplicated code.
3. **Item detail uses inline `TitledCard` for Details section** inside `CollapsibleSectionHeader` — duplicate title.

## Component Hierarchy (for reference)

```
MediaGallerySection (shared, src/components/)    ← THE shared media component, used by all screens
├── Transaction detail uses via thin wrappers:
│   ├── ReceiptsSection         → passes transaction.receiptImages to MediaGallerySection
│   └── OtherImagesSection      → passes transaction.otherImages to MediaGallerySection
├── Item detail                 → calls MediaGallerySection directly
└── Space detail                → calls MediaGallerySection directly

NotesSection (shared, src/components/)            ← THE shared notes component
├── Item detail                 → uses directly (BUG: has TitledCard)
├── Space detail                → uses directly (BUG: has TitledCard)
└── Transaction detail          → has its OWN custom NotesSection (should use shared)

CollapsibleSectionHeader        → section title header (chevron + uppercase label)
Card                            → plain themed card (no title)
TitledCard                      → card with title header (for standalone use ONLY)
```

**Rule**: Content inside `CollapsibleSectionHeader` must use `Card`, never `TitledCard`. The section title comes from the header — TitledCard creates a duplicate.

## Changes

### 1. Fix shared `NotesSection` — TitledCard → Card
**File:** `src/components/NotesSection.tsx`

NotesSection is ONLY ever used inside `CollapsibleSectionHeader`. No usage outside a collapsible context exists. Just replace TitledCard with Card permanently.

- Replace `import { TitledCard } from './TitledCard'` → `import { Card } from './Card'`
- Replace `<TitledCard title="Notes">` → `<Card>`
- Remove unused `View` import if applicable

Automatically fixes both **item detail** and **space detail** notes sections.

### 2. Delete custom transaction `NotesSection`, use shared
**Delete:** `app/transactions/[id]/sections/NotesSection.tsx`
**Edit:** `app/transactions/[id]/sections/index.ts` — remove `NotesSection` export
**Edit:** `app/transactions/[id]/index.tsx`:
  - Remove `NotesSection` from the `./sections` import
  - Add `import { NotesSection } from '../../../src/components/NotesSection'`
  - Change `<NotesSection transaction={item} />` → `<NotesSection notes={item.notes} expandable={true} />`

### 3. Fix item detail Details section — TitledCard → Card
**File:** `app/items/[id]/index.tsx`

Line 532: `<TitledCard title="Details">` → `<Card>`. Keep `TitledCard` import (still used for footer "Move item").

### 4. Delete dead `MediaSection.tsx`
**Delete:** `app/transactions/[id]/sections/MediaSection.tsx`
**Edit:** `app/transactions/[id]/sections/index.ts` — remove `MediaSection` export

This is the old combined component that rendered both receipts + other images together. It was replaced by the separate `ReceiptsSection` + `OtherImagesSection` (which allow independent collapsibility) but never cleaned up.

## Files Changed

| File | Action |
|------|--------|
| `src/components/NotesSection.tsx` | Edit: TitledCard → Card |
| `app/transactions/[id]/sections/NotesSection.tsx` | Delete |
| `app/transactions/[id]/sections/MediaSection.tsx` | Delete |
| `app/transactions/[id]/sections/index.ts` | Edit: remove NotesSection + MediaSection exports |
| `app/transactions/[id]/index.tsx` | Edit: import shared NotesSection, update call site |
| `app/items/[id]/index.tsx` | Edit: TitledCard → Card for Details section |

## Not Changed (Confirmed Correct)

- **Transaction `ReceiptsSection` + `OtherImagesSection`**: Thin wrappers around shared `MediaGallerySection` with `hideTitle={true}`. No duplicate titles. Correct.
- **Transaction `HeroSection`, `DetailsSection`, `TaxesSection`, `AuditSection`**: All use `Card` inside CollapsibleSectionHeader. Correct.
- **Edit forms** (`transactions/[id]/edit.tsx`, `items/[id]/edit.tsx`): Use `TitledCard` for standalone form sections (not inside CollapsibleSectionHeader). Correct.
- **Item detail footer** (`TitledCard title="Move item"`): Not inside CollapsibleSectionHeader. Correct.
- **Shared `MediaGallerySection`**: Already has `hideTitle` prop and works correctly everywhere.

## Verification

1. `npx tsc --noEmit` — no new type errors
2. Visual check on all three detail screens:
   - Transaction detail: Notes section renders with single title
   - Item detail: Notes and Details sections render with single titles each
   - Space detail: Notes section renders with single title
3. No dead imports after deletions

---

## ✅ Completion Summary

**Completed by**: claude-sonnet-4.5 (WP04 implementation + review)
**Date**: 2026-02-10

All changes implemented and verified:
- ✅ Shared NotesSection now uses Card (line 20, 40 in NotesSection.tsx)
- ✅ Transaction detail uses shared NotesSection (line 36, 1141 in transactions/[id]/index.tsx)
- ✅ Item detail Details section uses Card (line 533, 543 in items/[id]/index.tsx)
- ✅ Dead files deleted (MediaSection.tsx, transaction NotesSection.tsx)
- ✅ Exports cleaned from transactions/[id]/sections/index.ts
- ✅ No new TypeScript errors
- ✅ All three detail screens now have consistent section component architecture

**Result**: Zero duplicate section titles across all detail screens. All sections follow the rule: content inside CollapsibleSectionHeader uses Card, never TitledCard.
