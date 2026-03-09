# Transaction Export

## Purpose
Exports project transactions to CSV with user-configurable column selection, respecting active filters and sort order.

## Files

- `Logic/ExportFieldConfig.swift` — `ExportFieldConfig` struct and `ExportFields.all` (20 field definitions with `getValue` closures). `ExportFields.defaultSelectedIds` provides the 8 pre-selected defaults.
- `Logic/TransactionExportCalculations.swift` — Pure CSV generation. Two overloads: configurable (takes `selectedFields`) and legacy (hardcoded 8 columns, kept for backward-compatible tests).
- `Modals/ExportTransactionsModal.swift` — Column selector sheet. `FormSheet` with checkbox list, "Select All"/"Reset to Default" toggle, Export/Cancel buttons.
- `Views/Projects/ProjectDetailView.swift` — Export entry point in project kebab menu. Routes to `TransactionsTabView` (filtered) or presents directly (all transactions) depending on active tab.
- `Views/Projects/TransactionsTabView.swift` — Presents `ExportTransactionsModal` with its `processedTransactions` (filtered + sorted).

## State
No dedicated store. Export state is view-local `@State` in `ExportTransactionsModal`:
- `selectedFieldIds: Set<String>` — which columns are checked
- Resets to `ExportFields.defaultSelectedIds` each time the modal opens (not persisted)

## Data
Read-only. Uses in-memory `ProjectContext.transactions`, `.budgetCategories`, and `.items`. No Firestore writes. Works fully offline.

## Sheets & Navigation

| Trigger | Sheet | Style |
|---------|-------|-------|
| Kebab menu → "Export Transactions" (on Transactions tab) | `ExportTransactionsModal` via `TransactionsTabView` binding | `.selectionMenu` (65%) |
| Kebab menu → "Export Transactions" (other tabs) | `ExportTransactionsModal` directly from `ProjectDetailView` | `.selectionMenu` (65%) |

After export: modal dismisses, then `UIActivityViewController` presents the share sheet with a 0.3s delay (avoids sheet-over-sheet issues).

Filename pattern: `project-{projectId}-{YYYY-MM-DD}.csv`

## Gotchas

- **Filter-aware only on Transactions tab.** When export is triggered from Items/Spaces/Finances tabs, all project transactions are exported (no filters active). This is intentional — those tabs don't have transaction filter state.
- **Share sheet timing.** The modal must dismiss before presenting `UIActivityViewController`. A `DispatchQueue.main.asyncAfter` delay bridges this.
- **Mobile-only fields.** Three fields (`purchasedBy`, `inventorySaleDirection`, `itemCategories`) exist in mobile but not the web app. They're non-default-selected so they don't appear in CSV unless the user opts in.
- **`paymentMethod` added to Transaction model.** This field exists in Firestore but was previously not decoded. Added in this feature for export parity with web.
- **ISO8601DateFormatter is not Sendable.** The shared formatter uses `nonisolated(unsafe)` — safe because it's only read after initialization.
