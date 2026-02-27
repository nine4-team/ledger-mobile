# Data Model: Phase 4 Screens Implementation

*Generated: 2026-02-26*

---

## Existing Models (Complete — No Changes Needed)

### Transaction
All required fields confirmed present in `LedgeriOS/LedgeriOS/Models/Transaction.swift`:
- `id: String` (@DocumentID)
- `projectId: String?`, `accountId: String?`
- `source: String?` — vendor name (UI label: "Vendor/Source")
- `transactionType: String?` — canonical values: `purchase`, `sale`, `return`, `to-inventory`
- `reimbursementType: String?` — canonical values: `none`, `owed-to-client`, `owed-to-company`
- `amountCents: Int?`
- `subtotalCents: Int?`
- `taxRatePct: Double?`
- `status: String?` — `pending`, `completed`, `canceled`, `inventory-only`
- `budgetCategoryId: String?`
- `purchasedBy: String?`
- `hasEmailReceipt: Bool?`
- `notes: String?`
- `receiptImages: [AttachmentRef]?`
- `otherImages: [AttachmentRef]?`
- `transactionImages: [AttachmentRef]?` (legacy field)
- `itemIds: [String]?`
- `needsReview: Bool?`
- `isCanceled: Bool?`
- `isCanonicalInventorySale: Bool?`
- `inventorySaleDirection: InventorySaleDirection?`
- `transactionDate: Timestamp?`
- `createdAt: Timestamp?`, `updatedAt: Timestamp?`

**Display name priority:** `source` → canonical inventory sale label → ID prefix (6 chars) → "Untitled Transaction"

**Completeness thresholds (pinned business rules):**
- `over`: ratio > 1.2
- `complete`: |variance%| ≤ 1%
- `near`: |variance%| ≤ 20%
- `incomplete`: otherwise
- `null`: no valid subtotal

---

### Item
Present in `LedgeriOS/LedgeriOS/Models/Item.swift`. **One field to add (WP00):**

- `id: String` (@DocumentID)
- `accountId: String?`, `projectId: String?`
- `name: String?`
- `source: String?`
- `sku: String?`
- `status: String?` — canonical: `to-purchase`, `purchased`, `to-return`, `returned`
- `purchasePriceCents: Int?`
- `projectPriceCents: Int?`
- `marketValueCents: Int?`
- **`quantity: Int?`** ← **ADD THIS FIELD (WP00)**
- `budgetCategoryId: String?` — inherited from linked transaction, not set directly
- `spaceId: String?`
- `transactionId: String?`
- `bookmark: Bool?` — UI label: "bookmarked"
- `images: [AttachmentRef]?`
- `notes: String?`
- `createdAt: Timestamp?`, `updatedAt: Timestamp?`

**Display price priority:** `projectPriceCents` if set, otherwise `purchasePriceCents`

---

### Space
All fields confirmed present in `LedgeriOS/LedgeriOS/Models/Space.swift`:
- `id: String` (@DocumentID)
- `accountId: String?`, `projectId: String?`
- `name: String?`
- `notes: String?`
- `images: [AttachmentRef]?`
- `checklists: [Checklist]?`
- `isArchived: Bool?`
- `createdAt: Timestamp?`, `updatedAt: Timestamp?`

```swift
struct Checklist: Codable, Identifiable {
    var id: String
    var name: String           // UI: checklist title
    var items: [ChecklistItem]
}

struct ChecklistItem: Codable, Identifiable {
    var id: String
    var text: String
    var isChecked: Bool        // Note: spec says isCompleted; use isChecked (existing field name)
}
```

---

### Project
All fields present in `LedgeriOS/LedgeriOS/Models/Project.swift` (verified by audit).

---

### BudgetCategory
All fields present in `LedgeriOS/LedgeriOS/Models/BudgetCategory.swift`.

Key fields:
- `type: String?` — `general`, `itemized`, `fee` (mutually exclusive)
- `excludeFromOverallBudget: Bool?`
- `isArchived: Bool?`
- Validation: name max 100 chars; isItemized and isFee mutually exclusive

---

## New Models (Phase 4 Additions)

### SpaceTemplate
**Firestore path:** `accounts/{accountId}/presets/default/spaceTemplates/{templateId}`

```swift
struct SpaceTemplate: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var notes: String?
    var checklists: [Checklist]
    var isArchived: Bool?
    var order: Int?            // numeric, used for drag-reorder persistence
    @ServerTimestamp var createdAt: Timestamp?
    @ServerTimestamp var updatedAt: Timestamp?
}
```

**Validation:** name required. Templates with `isArchived=true` hidden from pickers but preserved.

---

### VendorDefault
**Firestore path:** `accounts/{accountId}/presets/default/vendors/{vendorId}` (or flat array in account presets doc — check RN implementation during WP13)

```swift
struct VendorDefault: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var order: Int?
    @ServerTimestamp var createdAt: Timestamp?
}
```

**Pre-populated names:** Home Depot, Wayfair, West Elm, Pottery Barn, (and others from RN `src/data/accountPresetsService.ts`)

---

### Invite
**Firestore path:** `accounts/{accountId}/invites/{inviteId}`

```swift
struct Invite: Codable, Identifiable {
    @DocumentID var id: String?
    var email: String
    var role: String           // owner, admin, member
    var status: String?        // pending, accepted, expired
    @ServerTimestamp var createdAt: Timestamp?
    @ServerTimestamp var expiresAt: Timestamp?
}
```

---

### BusinessProfile
**Firestore path:** `accounts/{accountId}` (subset of account document) or `accounts/{accountId}/profile/default`

```swift
struct BusinessProfile: Codable {
    var name: String?
    var logoUrl: String?       // Firebase Storage URL
    @ServerTimestamp var updatedAt: Timestamp?
}
```

---

## Firestore Subscription Architecture

### ProjectContext (existing — `State/ProjectContext.swift`)
Manages 7 subscriptions when a project is active:
1. Single project detail
2. All projects (sidebar nav)
3. Project-scoped transactions
4. Project-scoped items
5. Project-scoped spaces
6. Account budget categories
7. Project budget categories

Lifecycle: `activate(accountId:projectId:)` / `deactivate()`

### InventoryContext (new — WP09)
New `@MainActor @Observable` class for inventory-scoped data:
1. Inventory-scoped items (`scope: .inventory`)
2. Inventory-scoped transactions (`scope: .inventory`)
3. Inventory-scoped spaces (`scope: .inventory`)
4. Persists last-selected tab to `UserDefaults` key `"inventorySelectedTab"`

---

## Pure Logic Modules Summary

| Module | Inputs | Key Outputs |
|--------|--------|-------------|
| `TransactionDisplayCalculations` | `Transaction`, `[BudgetCategory]` | displayName, badgeConfig, formattedAmount, formattedDate |
| `TransactionNextStepsCalculations` | `Transaction`, `BudgetCategory?` | `[NextStep]`, isComplete, visibleStepCount |
| `TransactionCompletenessCalculations` | `Transaction`, `[Item]` | ratio, status, variancePct, itemsNetTotal, subtotal |
| `TransactionListCalculations` | `[Transaction]`, filters, sort, query | `[Transaction]` filtered+sorted |
| `ReceiptListParser` | `String` (raw text) | `[(name: String, priceCents: Int?)]`, skippedLines |
| `ItemListCalculations` | `[Item]`, `ItemListMode`, sort, query, `[Space]`, `[BudgetCategory]` | `[ItemRow]` (items + group rows) |
| `ItemDetailCalculations` | `Item`, `[Space]`, `[BudgetCategory]`, userRole | actionMenuItems, displayFields |
| `BulkSaleResolutionCalculations` | `[Item]`, `[BudgetCategory]`, destination | categoryResolutionMap, eligibleItems |
| `SpaceListCalculations` | `[Space]`, `[Item]` | sorted spaces with itemCount + checklistProgress |
| `SpaceDetailCalculations` | `Space`, `[Item]`, userRole | checklistProgress, canSaveAsTemplate |
| `SearchCalculations` | query: `String`, `[Item]`, `[Transaction]`, `[Space]`, `[BudgetCategory]` | `SearchResults` (items, transactions, spaces) |
| `ReportAggregationCalculations` | `[Transaction]`, `[Item]`, `[Space]`, `[BudgetCategory]` | `InvoiceReportData`, `ClientSummaryData`, `PropertyManagementData` |
| `ProjectFormValidation` | name, clientName, budgetAllocations | `[ValidationError]` |
| `TransactionFormValidation` | transactionType, destination, detailFields | `[ValidationError]` |
| `ItemFormValidation` | name, prices | `[ValidationError]` |
| `SpaceFormValidation` | name | `[ValidationError]` |

---

## Badge Color Mapping (FR-4.3)

| Badge Type | Color Token |
|-----------|-------------|
| Purchase | `StatusColors.budgetMet` (green) |
| Sale | `.blue` |
| Return | `StatusColors.budgetMissed` (red) |
| To Inventory | `BrandColors.primary` (brand taupe) |
| Owed to Client / Business | `.amber` (orange/amber) |
| Receipt | `BrandColors.primary` |
| Needs Review | rust/orange (per RN `StatusColors.needsReview`) |
| Budget Category | `BrandColors.primary` |

---

## Transaction Type & Reimbursement Type Canonical Values

| Field | Value | UI Label |
|-------|-------|----------|
| transactionType | `purchase` | "Purchase" |
| transactionType | `sale` | "Sale" |
| transactionType | `return` | "Return" |
| transactionType | `to-inventory` | "To Inventory" |
| reimbursementType | `none` | "None" |
| reimbursementType | `owed-to-client` | "Owed to Client" |
| reimbursementType | `owed-to-company` | "Owed to Business" |

---

## Item Status Canonical Values

| Value | UI Label |
|-------|----------|
| `to-purchase` | "To Purchase" |
| `purchased` | "Purchased" |
| `to-return` | "To Return" |
| `returned` | "Returned" |

---

## Amount Representation Convention

All monetary values stored and computed in **integer cents** (`Int`). Never use `Double` for money arithmetic. Display formatting via existing `CurrencyFormatting.swift`.

```swift
// Correct
let amountCents: Int = 4999  // $49.99

// Wrong
let amount: Double = 49.99   // floating point errors
```

---

## Search Amount Prefix-Range Algorithm

```
Input: "40"    → range: 4000...4099 cents  ($40.00–$40.99)
Input: "40.0"  → range: 4000...4009 cents  ($40.00–$40.09)
Input: "40.00" → range: 4000...4000 cents  ($40.00 exactly)
Input: "$40"   → strip $ → same as "40"
Input: "1,200" → strip , → "1200" → range: 120000...120099 cents

Algorithm:
1. Strip leading $ and commas
2. Split on "." to get integer and decimal parts
3. Integer part only → multiply by 100, range is [result, result + 99]
4. One decimal digit → multiply by 10, range is [result * 10, result * 10 + 9]
5. Two decimal digits → exact cents match
6. Invalid (non-numeric after stripping) → no amount matching
```

---

## Validation Error Messages (Exact Text from Spec)

| Context | Error |
|---------|-------|
| Budget category name too long | "Category name must be 100 characters or less" |
| Category isItemized AND isFee | "A category cannot be both Itemized and Fee" |
| Project name empty | "Name is required" |
| Project clientName empty | "Client name is required" |
| Item name empty | "Name is required" |
| Space name empty | "Name is required" |

---

## Empty State Text (Exact from Spec)

| Context | Text |
|---------|------|
| Projects list — active tab empty | "No active projects yet." |
| Projects list — archived tab empty | "No archived projects yet." |
| Search initial state | "Start typing to search" (with centered search icon) |
| Search — no items | "No items found" |
| Search — no transactions | "No transactions found" |
| Search — no spaces | "No spaces found" |
