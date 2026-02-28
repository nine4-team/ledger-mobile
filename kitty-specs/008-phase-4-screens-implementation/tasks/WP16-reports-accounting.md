---
work_package_id: WP16
title: Session 7c Logic + Screens – Reports + Accounting Tab
lane: "planned"
dependencies:
- WP00
- WP04
base_branch: 008-phase-4-screens-implementation-WP04
base_commit: a7a758408bf79314ea4914afc4e900681ef8906f
created_at: '2026-02-28T23:09:18.327282+00:00'
subtasks:
- T071
- T072
- T073
- T074
- T075
- T076
phase: Phase 7 - Session 7c
assignee: ''
agent: "claude-opus"
shell_pid: "22309"
review_status: "has_feedback"
reviewed_by: "claude-opus"
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP16 – Session 7c Logic + Screens — Reports + Accounting Tab

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

**Reviewer:** claude-opus | **Date:** 2026-02-28

### Issue: PDF content views lost all branded styling from original reports

**Severity:** High — PDFs are the client-facing deliverable.

**What's wrong:** The 3 private `*PDFContent` structs (`InvoiceReportPDFContent`, `ClientSummaryPDFContent`, `PropertyManagementPDFContent`) use generic system fonts and colors instead of matching the branded design from the original RN app's `src/utils/reportHtml.ts` stylesheet. The on-screen report views correctly use theme tokens — only the PDF export content needs rework.

**What's missing vs. the original reports:**

| Element | Original (reportHtml.ts) | Current SwiftUI PDF |
|---------|--------------------------|---------------------|
| Report title | 22px / 700 weight / `#987e55` brand color | System `.title2.bold()` / no brand color |
| Section headers | 16px / 600 / `#987e55` with `#e0d5c5` underline border | System `.caption.weight(.semibold)` / no color |
| Table headers | 11px / 600 / uppercase / `#666` on `#f7f3ee` background | None — no table structure |
| Table rows | Zebra striping (`#faf8f5` alternating), `#f0ebe4` row borders | Plain VStack, no striping |
| Net Due row | 15px / 700 / `#987e55` with 2px brand-color top border | System `.body.bold()` / no brand highlight |
| Overview cards | `#faf8f5` background, `#e0d5c5` border, 8px radius | None — just plain text |
| Card labels | 11px / 600 / uppercase / `#666` | None |
| Card values | 20px / 700 / `#1a1a1a` | None |
| Missing price indicator | Italic / `#c0392b` / 11px | None |
| Receipt badges | 10px / 600 / `#987e55` text on `#f7f3ee` bg / 4px radius | None |
| Header border | 2px solid `#987e55` bottom border | None |
| Footer | 11px / `#999` / centered / `#e0d5c5` top border / generation date | None |
| Page width | 800px with 40px padding (20px for print) | 612pt with 24pt padding |
| Currency format | `Intl.NumberFormat` locale-aware | `String(format: "$%.2f")` — no locale |

**How to fix:**

1. Define PDF-specific color constants matching the original palette: brand `#987e55`, card bg `#faf8f5`, card/table border `#e0d5c5`, body text `#1a1a1a`, secondary text `#666`, error `#c0392b`.
2. Rebuild each `*PDFContent` struct to replicate the original layout: branded header with border, table-style rows with zebra striping, overview cards, section headers with brand color and underline, net due highlight, receipt badges, footer.
3. Use `CurrencyFormatting.formatCentsWithDecimals` (already available) instead of raw `String(format:)`.
4. Reference file: `src/utils/reportHtml.ts` — the `getReportStyles()` function and 3 `generate*Html()` functions define the exact design to match.

---

## Objectives & Success Criteria

- `ReportAggregationCalculations` produces correct data for all 3 report types.
- Invoice net due = charges subtotal − credits subtotal (excluding canceled transactions).
- Client Summary: total saved = sum(marketValue − projectPrice where marketValue > 0).
- Property Management: items grouped by space with "No Space" fallback.
- All 3 report views are native SwiftUI, share as PDF via `ImageRenderer`.
- `AccountingTabView` replaces placeholder with reimbursement summary cards + 3 report navigation buttons.
- All Swift Testing tests pass for aggregation functions.

**To start implementing:** `spec-kitty implement WP16 --base WP04`

---

## Context & Constraints

- **Refs**: `plan.md` (WP16), `spec.md` FR-14 (Accounting tab), FR-15 (Reports), `data-model.md`.
- **Invoice Report** (FR-15.1): Charge Lines = `reimbursementType=="owed-to-company"`; Credit Lines = `reimbursementType=="owed-to-client"`. Exclude canceled transactions. Per-line: displayName, date, notes, amount, category, linked items with project prices. Net due = charges − credits.
- **Client Summary** (FR-15.2): total spent = sum of `item.projectPriceCents` across all items (where non-nil). Total market value = sum of `item.marketValueCents`. Total saved = sum of `(marketValue − projectPrice)` where `marketValue > 0`. Category resolution: from `item.budgetCategoryId` OR from `item's transaction.budgetCategoryId`. Receipt link 3 states: `{type:'invoice'}`, `{type:'receipt-url', url:String}`, `nil`.
- **Property Management** (FR-15.3): group items by `item.spaceId`. Map to space name from spaces array. Items with `spaceId==nil` → "No Space" group. Per-item: name, source, SKU, market value.
- **Reimbursement summary in AccountingTabView** (FR-14.1): skip `isCanceled=true` transactions. Sum `amountCents` where `reimbursementType=="owed-to-company"` → "Owed to Design Business". Sum where `reimbursementType=="owed-to-client"` → "Owed to Client".
- **PDF generation**: use `ImageRenderer` (iOS 16+). Render the SwiftUI view → PDF data → share via `UIActivityViewController`.
- **No WebView**: pure SwiftUI native views for all reports.

---

## Subtasks & Detailed Guidance

### Subtask T071 – Create `Logic/ReportAggregationCalculations.swift`

**Purpose**: Three aggregation functions — one per report type.

**Steps**:
1. Create `Logic/ReportAggregationCalculations.swift`.
2. Define output types:
   ```swift
   struct InvoiceLineItem {
       let transaction: Transaction
       let displayName: String
       let formattedDate: String
       let notes: String?
       let amountCents: Int
       let categoryName: String?
       let linkedItems: [InvoiceItem]
       let isMissingProjectPrices: Bool
   }
   struct InvoiceItem {
       let name: String?
       let projectPriceCents: Int?
       let isMissingPrice: Bool
   }
   struct InvoiceReportData {
       let chargeLines: [InvoiceLineItem]
       let creditLines: [InvoiceLineItem]
       var chargesSubtotalCents: Int { chargeLines.reduce(0) { $0 + $1.amountCents } }
       var creditsSubtotalCents: Int { creditLines.reduce(0) { $0 + $1.amountCents } }
       var netDueCents: Int { chargesSubtotalCents - creditsSubtotalCents }
   }
   struct ClientSummaryData {
       let totalSpentCents: Int
       let totalMarketValueCents: Int
       let totalSavedCents: Int
       let categoryBreakdowns: [CategoryBreakdown]
       let items: [ClientSummaryItem]
   }
   struct CategoryBreakdown {
       let categoryName: String
       let spentCents: Int
   }
   struct ClientSummaryItem {
       let item: Item
       let spaceName: String?
       let receiptLink: ReceiptLink
   }
   enum ReceiptLink {
       case invoice
       case receiptURL(String)
       case none
   }
   struct PropertyManagementData {
       let spaceGroups: [SpaceGroup]
       let noSpaceItems: [Item]
       let totalItemCount: Int
       let totalMarketValueCents: Int
   }
   struct SpaceGroup {
       let space: Space
       let items: [Item]
       var marketValueCents: Int { items.reduce(0) { $0 + ($1.marketValueCents ?? 0) } }
   }
   ```

3. Implement `func computeInvoiceReport(transactions: [Transaction], items: [Item], categories: [BudgetCategory]) -> InvoiceReportData`:
   - Filter: `!transaction.isCanceled`.
   - Charge lines: `reimbursementType == "owed-to-company"`.
   - Credit lines: `reimbursementType == "owed-to-client"`.
   - For each transaction: get linked items (from `items` by `transaction.itemIds`); build `InvoiceLineItem`.
   - Flag `isMissingProjectPrices` if any linked item has `projectPriceCents == nil`.

4. Implement `func computeClientSummary(items: [Item], transactions: [Transaction], spaces: [Space], categories: [BudgetCategory]) -> ClientSummaryData`:
   - Total spent = sum of non-nil `projectPriceCents` (or `purchasePriceCents` fallback?—check RN source).
   - Total market value = sum of non-nil `marketValueCents`.
   - Total saved = sum of `(mV − pP)` where `mV > 0`.
   - Category breakdown: group items by resolved category; sort alphabetically by category name.
   - Category resolution: `item.budgetCategoryId` first, else look up item's transaction's `budgetCategoryId`.
   - Receipt link per item:
     - Transaction `isCanonicalInventorySale` or is invoiceable reimbursement → `.invoice`.
     - Transaction has `receiptImages` → `.receiptURL(firstReceiptUrl)`.
     - Otherwise → `.none`.

5. Implement `func computePropertyManagement(items: [Item], spaces: [Space]) -> PropertyManagementData`:
   - Group items by `item.spaceId`.
   - Look up space for each group → build `SpaceGroup`.
   - Items with nil `spaceId` → `noSpaceItems`.
   - Compute totals.

**Files**:
- `Logic/ReportAggregationCalculations.swift` (create, ~200 lines)

**Parallel?**: No — sequential.

---

### Subtask T072 – Write Swift Testing suite for ReportAggregationCalculations

**Purpose**: Verify all 3 report aggregations are correct.

**Steps**:
1. Create `LedgeriOSTests/Logic/ReportAggregationCalculationsTests.swift`.
2. Invoice tests:
   - `@Test func canceledTransactionExcluded()`: canceled transaction → not in charge lines.
   - `@Test func chargesVsCredits()`: owed-to-company → charge line; owed-to-client → credit line.
   - `@Test func netDueCalculation()`: charges=$100, credits=$30 → net due=$70.
   - `@Test func missingProjectPricesFlagged()`: item with nil projectPriceCents → isMissingProjectPrices=true.
3. Client Summary tests:
   - `@Test func totalSpentSumsProjectPrices()`.
   - `@Test func totalSavedOnlyWhereMarketValuePositive()`: item with marketValue=0 → not included in savings.
   - `@Test func categoryFromTransaction()`: item has nil budgetCategoryId; transaction has budgetCategoryId → uses transaction's category.
4. Property Management tests:
   - `@Test func groupsBySpace()`: 3 items, 2 spaces → 2 groups.
   - `@Test func noSpaceGroup()`: items with nil spaceId → in noSpaceItems.
   - `@Test func totalMarketValue()`.

**Files**:
- `LedgeriOSTests/Logic/ReportAggregationCalculationsTests.swift` (create, ~120 lines)

---

### Subtask T073 – Create `Views/Projects/AccountingTabView.swift`

**Purpose**: Replace `AccountingTabPlaceholder.swift` with real reimbursement summary + report navigation.

**Steps**:
1. Create `Views/Projects/AccountingTabView.swift`.
2. Compute reimbursement totals from `projectContext.transactions`:
   - Filter out `isCanceled=true`.
   - Sum `amountCents` where `reimbursementType=="owed-to-company"` → "Owed to Design Business".
   - Sum where `reimbursementType=="owed-to-client"` → "Owed to Client".
3. Show 2 summary cards (using `Card` component from Phase 5 library):
   - Card 1: "Owed to Design Business" + formatted total amount.
   - Card 2: "Owed to Client" + formatted total amount.
4. Show 3 report navigation buttons:
   - "Property Management Summary" → navigate to `PropertyManagementReportView`.
   - "Client Summary" → navigate to `ClientSummaryReportView`.
   - "Invoice" → navigate to `InvoiceReportView`.
5. Navigation: use `NavigationLink(value:)` for report destination types (define `enum ReportType { case invoice, clientSummary, propertyManagement }`) + `.navigationDestination(for: ReportType.self)`.

**Files**:
- `Views/Projects/AccountingTabView.swift` (create, ~80 lines)

---

### Subtask T074 – Create `Views/Reports/InvoiceReportView.swift`

**Purpose**: Native SwiftUI invoice report view with PDF sharing.

**Steps**:
1. Create `Views/Reports/InvoiceReportView.swift` with `init(data: InvoiceReportData)`.
2. Compute `InvoiceReportData` in parent (AccountingTabView or passed from it) using `projectContext` data.
3. Report layout (scrollable `ScrollView`):
   - Header: project name, client name, date.
   - "Charges" section: list of `InvoiceLineItem` where type=charge. Each line: date | display name | amount. Sub-item rows (indented): linked item name | project price.
   - "Credits" section: same structure.
   - Summary section: Charges subtotal | Credits subtotal | **Net Due** (bold).
   - Warning banner if any items have missing project prices.
4. Share button (toolbar): generate PDF via `ImageRenderer`:
   ```swift
   let renderer = ImageRenderer(content: InvoiceReportPDFView(data: data))
   renderer.scale = UIScreen.main.scale
   if let pdfData = renderer.pdf(actions: { pageContext in
       // render page
   }) {
       // write to temp URL, present UIActivityViewController
   }
   ```
   Note: `ImageRenderer.pdf` is the correct API for PDF generation. Implement multi-page if content overflows.
5. Present share sheet via `UIActivityViewController`.

**Files**:
- `Views/Reports/InvoiceReportView.swift` (create, ~120 lines)

---

### Subtask T075 – Create `Views/Reports/ClientSummaryReportView.swift`

**Purpose**: Native SwiftUI client summary report with PDF sharing.

**Steps**:
1. Create `Views/Reports/ClientSummaryReportView.swift` with `init(data: ClientSummaryData)`.
2. Report layout:
   - Summary section: Total Spent | Total Market Value | Total Saved (all formatted as currency).
   - Category Breakdown section: sorted alphabetically; each row: category name | spent amount.
   - Items section: each `ClientSummaryItem` row: item name | space | project price | receipt link indicator (icon: invoice/receipt/none).
3. Share button → PDF via `ImageRenderer` (same pattern as T074).

**Files**:
- `Views/Reports/ClientSummaryReportView.swift` (create, ~100 lines)

**Parallel?**: Yes — independent of T074 pattern.

---

### Subtask T076 – Create `Views/Reports/PropertyManagementReportView.swift`

**Purpose**: Native SwiftUI property management report grouped by space.

**Steps**:
1. Create `Views/Reports/PropertyManagementReportView.swift` with `init(data: PropertyManagementData)`.
2. Report layout:
   - For each `SpaceGroup`: section header with space name; rows: item name | source | SKU | market value.
   - "No Space" section (if `noSpaceItems` non-empty): same row structure.
   - Summary footer: total items | total market value.
3. Share button → PDF via `ImageRenderer` (same pattern as T074).

**Files**:
- `Views/Reports/PropertyManagementReportView.swift` (create, ~80 lines)

**Parallel?**: Yes.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `ImageRenderer.pdf` API details unknown | Check Apple docs for `ImageRenderer` PDF rendering; may need `UIGraphicsBeginPDFContextToData` for multi-page |
| Client Summary category resolution across items → transactions | Build a lookup map `itemId → transaction` once before iterating items |
| Total saved when marketValue == projectPrice | `(mV - pP) > 0` check ensures only positive savings counted |
| Invoice with many line items overflows single PDF page | Research `ImageRenderer` multi-page PDF rendering; simplest: render single long scroll as one wide page |

---

## Review Guidance

- [ ] Accounting tab: 2 reimbursement cards (correct totals) + 3 report buttons.
- [ ] Canceled transactions excluded from reimbursement totals.
- [ ] Invoice report: charges vs credits correctly split; net due = charges − credits.
- [ ] Client Summary: total saved only counts items where marketValue > 0.
- [ ] Property Management: "No Space" section appears for items without spaceId.
- [ ] PDF share sheet opens with valid PDF content.
- [ ] All 3 reports are native SwiftUI (no WebView).
- [ ] All aggregation tests pass ⌘U.
- [ ] Light + dark mode correct.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-28T23:09:18Z – claude-opus – shell_pid=46281 – lane=doing – Assigned agent via workflow command
- 2026-02-28T23:24:55Z – claude-opus – shell_pid=46281 – lane=for_review – Ready for review: ReportAggregationCalculations with 3 report types (Invoice, Client Summary, Property Management), AccountingTabView with reimbursement summary cards, 3 native SwiftUI report views with PDF sharing via ImageRenderer, 16 passing Swift Testing tests covering all aggregation functions
- 2026-02-28T23:34:38Z – claude-opus – shell_pid=22309 – lane=doing – Started review via workflow command
- 2026-02-28T23:36:22Z – claude-opus – shell_pid=22309 – lane=done – Review passed: All 3 report aggregation functions correctly compute invoice (charges/credits/net due), client summary (spent/saved/category breakdown), and property management (space grouping). AccountingTabView properly excludes canceled transactions from reimbursement totals. 3 native SwiftUI report views with PDF sharing via ImageRenderer. 16 Swift Testing tests with comprehensive coverage. Clean logic/view separation, proper theme token usage, correct NavigationLink(value:) pattern.
- 2026-02-28T23:51:42Z – claude-opus – shell_pid=22309 – lane=planned – Changes requested: PDF content views lost all branded styling from original RN/web reports. The 3 *PDFContent structs use generic system fonts/colors instead of brand color #987e55, branded card backgrounds, table layouts with zebra striping, receipt badges, header logos, footers, etc. On-screen report views are fine — only the PDF export views need rework to match the original reportHtml.ts stylesheet.
