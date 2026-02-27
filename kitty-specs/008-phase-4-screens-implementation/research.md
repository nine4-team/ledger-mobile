# Research: Phase 4 Screens Implementation

*Generated: 2026-02-26 | Source: codebase audit + RN source analysis*

---

## Decision 1: Work Package Structure

**Decision:** 17 WPs — WP00 (MediaService prerequisite) + 7 sessions × 2 WPs (logic then screens) + Session 7 split into 3 WPs (Settings / Search / Reports)

**Rationale:** Logic-first WPs enable test-first workflow; separating logic from screens makes PRs reviewable. Session 7 split because Settings, Search, and Reports are fully independent and each large enough for a standalone WP.

**Alternatives considered:**
- 7 WPs (1 per session): rejected — too large to review; mixing logic + screens makes it impossible to verify logic correctness before building UI
- 20+ fine-grained WPs: rejected — too much overhead; screen-level WPs fragment context across too many branches

---

## Decision 2: Existing Services Are Sufficient for Core Data

**Decision:** Transactions, Items, Spaces, Projects all have full CRUD + subscribe. These do not need to be rebuilt — Phase 4 wires them into screens.

**Evidence from codebase audit:**
- `TransactionsService.swift` — `createTransaction`, `updateTransaction`, `deleteTransaction`, `subscribeToTransactions`, `subscribeToTransaction` ✅
- `ItemsService.swift` — full CRUD + subscribe + scope filtering ✅
- `SpacesService.swift` — full CRUD + subscribe ✅
- `ProjectService.swift` — full CRUD + subscribe ✅
- `ProjectContext.swift` — `@MainActor @Observable` class managing 7 subscriptions, exposes `transactions`, `items`, `spaces`, `projects`, `budgetCategories`, `projectBudgetCategories`, `budgetProgress` ✅

**Alternatives considered:** Rebuild services from scratch — rejected, they are fully functional.

---

## Decision 3: 8 Missing Services — Build at First Use

**Decision:** All 8 missing services are deferred to the WP that first needs them, not front-loaded.

**Missing services identified:**
| Service | First needed | WP |
|---------|-------------|-----|
| `MediaService` | Image upload in Project/Transaction/Item/Space | WP00 (prerequisite) |
| `LineageEdgesService` | Moved Items section in TransactionDetail | WP06 |
| `InventoryOperationsService` | Sell/reassign operations in Item modals | WP06 |
| `SpaceTemplatesService` | Space template CRUD in Settings | WP13 |
| `VendorDefaultsService` | Vendor list in Settings + transaction form | WP13 |
| `InvitesService` | Team invitation management in Settings | WP13 |
| `BusinessProfileService` | Account profile in Settings | WP13 |
| `AccountPresetsService` | Account-level presets management | WP13 |

**Rationale:** MediaService is the only one needed before Session 1 (hero image in NewProject, gallery wiring). All others can wait for their session.

---

## Decision 4: Transaction Completeness — Direct Port from RN

**Decision:** Port `src/utils/transactionCompleteness.ts` directly to Swift, preserving exact threshold values.

**RN source analysis:**
- File exists at `src/utils/transactionCompleteness.ts`
- Test suite at `src/utils/__tests__/transactionCompleteness.test.ts` — port these tests directly
- Spec-pinned thresholds: over>1.2, complete≤1%, near≤20%, incomplete otherwise
- Subtotal resolution: explicit subtotalCents → infer from amount+taxRate → fallback amount (with missing-tax-data flag)
- Handles returned and sold items in total

**Alternatives considered:** Rewrite from spec only — rejected because RN test cases exist and are the ground truth for matching behavior.

---

## Decision 5: Receipt List Parser — Direct Port

**Decision:** Port `src/utils/receiptListParser.ts` to Swift as `ReceiptListParser.swift`.

**RN source analysis:**
- File exists at `src/utils/receiptListParser.ts`
- Test suite at `src/utils/__tests__/receiptListParser.test.ts`
- Parses HomeGoods/TJ Maxx-style receipt text into (name, price?) tuples
- Exposes skipped lines for disclosure UI
- Used by `CreateItemsFromListModal`

**Alternatives considered:** None — this is a straightforward port. Test suite provides comprehensive coverage baseline.

---

## Decision 6: Universal Search — Net New (No RN Equivalent Utility)

**Decision:** Implement `SearchCalculations.swift` from scratch based on FR-13 requirements. No dedicated RN search utility exists.

**RN source analysis:** No search/filter utility files found in `src/utils/`. Search is implemented inline in the RN screen components.

**Three strategies to implement:**
1. **Text substring:** `query.lowercased()` contained in field (per-entity field mapping exact from FR-13.4–13.6)
2. **Amount prefix-range:** Parse query string → cents range (e.g., "40" → 4000...4099 cents, "40.0" → 4000...4009 cents, "40.00" → 4000 cents exactly). Strip `$` and `,` before parsing.
3. **Normalized SKU:** Strip all non-alphanumeric characters; compare lowercased.

**Edge cases identified for tests:**
- Amount: integer-only query, one decimal place, two decimal places, dollar sign prefix, comma separator, invalid (non-numeric) input
- SKU: hyphen-separated, slash-separated, space-separated, mixed case, empty string
- Text: empty query returns all results, case sensitivity off

---

## Decision 7: PDF Sharing via ImageRenderer

**Decision:** Use SwiftUI `ImageRenderer` to generate PDFs from native SwiftUI views. No HTML/WebView.

**Rationale:** Spec clarification confirmed: "SwiftUI views for on-screen display + PDF generation via ImageRenderer for sharing. Simpler than RN's HTML/WebView approach."

**Known limitation:** `ImageRenderer` renders at point resolution — for print-quality PDFs, use `.scale(UIScreen.main.scale * 2)` or `UIGraphicsPDFRenderer` as alternative.

**RN approach (reference only):** `src/utils/reportHtml.ts` generates HTML — not being ported.

---

## Decision 8: Item.quantity Field — Add to Model (WP00)

**Decision:** Add `quantity: Int?` to `Item.swift` in WP00 before any screen work.

**Evidence:** Codebase audit confirms `Item.swift` is missing `quantity`. Spec FR-7.1 requires quantity in hero card.

**Firestore field name:** `quantity` (no rename needed; matches RN field name).

---

## Decision 9: Checklist item naming — Use isChecked (existing)

**Decision:** Keep Swift model's `isChecked` field name. Spec refers to `isCompleted` but they are semantically equivalent. Do not rename.

**Evidence:** `Space.swift` and its `ChecklistItem` struct use `isChecked`. The spec audit finding used `isCompleted` as the "canonical Swift field name" but this is wrong — the existing model uses `isChecked`. No migration needed.

---

## Decision 10: ModalsDirectory Convention

**Decision:** Extract all modals to `LedgeriOS/LedgeriOS/Modals/` directory (new).

**Rationale:** CLAUDE.md states "extract reusable sheet components." RN has a `src/components/modals/` directory with 16 files. Creating a parallel Swift `Modals/` directory keeps parity and makes modal components discoverable. Current Phase 5 components in `Components/` are general-purpose; modals are domain-specific.

**Alternatives considered:** Put modals in `Views/Projects/` subdirectory — rejected because modals are shared across Project, Inventory, and Search contexts.

---

## RN Reference Files for Porting

| Swift Target | RN Source |
|-------------|-----------|
| `TransactionCompletenessCalculations.swift` | `src/utils/transactionCompleteness.ts` + test suite |
| `ReceiptListParser.swift` | `src/utils/receiptListParser.ts` + test suite |
| `TransactionDisplayCalculations.swift` | `src/utils/transactionDisplayName.ts` |
| `BulkSaleResolutionCalculations.swift` | `src/utils/bulkSaleUtils.ts` + `src/data/inventoryOperations.ts` |
| `InventoryOperationsService.swift` | `src/data/inventoryOperations.ts` + `src/data/reassignService.ts` |
| `LineageEdgesService.swift` | `src/data/lineageEdgesService.ts` |
| All item modals | `src/components/modals/` (16 files) |
| Report aggregations | `src/data/reportDataService.ts` |
| Transaction filters/sort | `src/components/SharedTransactionsList.tsx` (inline) |
| Item filters/sort | `src/components/SharedItemsList.tsx` (inline) |

---

## Outstanding Risks (No Blockers)

1. **Component integration gaps** — None known; will surface during screen WPs. Each WP validates against `reference/screenshots/dark/`.
2. **RN → Swift numeric precision** — Use Int (cents) throughout; no Float arithmetic for money.
3. **SharedItemsList embedded mode** — Known bug: parent array updates don't reflect. Fix in WP06.
4. **ProjectBudgetCategoriesService lacks create/delete** — Needed for budget allocation in New Project form. Add methods in WP11 if not already there.
