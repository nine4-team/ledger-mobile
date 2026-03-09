# Implement: Reassign Transaction to Project / Inventory

## Overview

Add the ability to reassign a transaction (and all its linked items) to a different project or to business inventory. This is a **correction operation** — no financial records are created, unlike sell operations. It exists in the React Native app (`src/data/reassignService.ts`) but is missing from the SwiftUI implementation.

## What "Reassign Transaction" Means

When a user added a transaction to the wrong project, they can reassign it. This moves the transaction's `projectId` to the target project and updates all linked items' `projectId` to match. Items' `spaceId` is cleared (spaces are project-scoped). A lineage edge with `movementKind: "correction"` is created for each item to record the fix.

This is distinct from "sell to project" which creates canonical sale transactions and financial records.

## Reference Implementation

The React Native implementation is at `src/data/reassignService.ts`:

```typescript
// Reassign transaction + items to a different project
export function reassignTransactionToProject(
  accountId: string,
  transactionId: string,
  targetProjectId: string,
  itemIds: string[]
): void {
  updateTransaction(accountId, transactionId, { projectId: targetProjectId });
  for (const itemId of itemIds) {
    updateItem(accountId, itemId, { projectId: targetProjectId, spaceId: null });
    createLineageEdge(accountId, buildReassignCorrectionEdge({
      accountId, itemId, transactionId,
      note: 'Transaction reassigned to project',
    }));
  }
}

// Reassign transaction + items to business inventory
export function reassignTransactionToInventory(
  accountId: string,
  transactionId: string,
  itemIds: string[]
): void {
  updateTransaction(accountId, transactionId, { projectId: null });
  for (const itemId of itemIds) {
    updateItem(accountId, itemId, { projectId: null, spaceId: null });
    createLineageEdge(accountId, buildReassignCorrectionEdge({
      accountId, itemId, transactionId,
      note: 'Transaction reassigned to inventory',
    }));
  }
}

// Lineage edge builder for corrections
export function buildReassignCorrectionEdge(params: {
  accountId: string; itemId: string;
  transactionId: string | null; note: string;
}): Omit<ItemLineageEdge, 'id' | 'createdAt'> {
  return {
    accountId: params.accountId,
    itemId: params.itemId,
    fromTransactionId: params.transactionId,
    toTransactionId: params.transactionId,  // same tx — item stays in it
    movementKind: 'correction',
    source: 'app',
    note: params.note,
  };
}
```

### Validation rules (from `validateTransactionReassign`):
- **Canonical inventory sales cannot be reassigned** — `isCanonicalInventorySale == true` → reject
- **Already in target** — if transaction's `projectId` matches target → reject
- **Already in inventory** — if reassigning to inventory but transaction has no `projectId` → reject

## What to Build

### 1. Service: `TransactionReassignService`

Create `LedgeriOS/LedgeriOS/Services/TransactionReassignService.swift`.

Use a **Firestore WriteBatch** for atomicity (same pattern as `InventoryOperationsService`).

Two methods:

**`reassignTransactionToProject`:**
- Update transaction's `projectId` to target
- Update each linked item: set `projectId` to target, clear `spaceId`
- Create a lineage edge per item with `movementKind: "correction"`, `note: "Transaction reassigned to project"`, `fromTransactionId` and `toTransactionId` both set to the transaction ID (item stays in the same tx, but the tx moved)
- **Auto-enable budget category:** If the transaction has a `budgetCategoryId`, create a `ProjectBudgetCategory` document in the destination project using `setData(merge: true)` — same pattern as `InventoryOperationsService.sellToProject`. This ensures the transaction's spend appears in the destination project's budget tab. Skip if `budgetCategoryId` is nil or "uncategorized".

**`reassignTransactionToInventory`:**
- Update transaction's `projectId` to `NSNull()`
- Update each linked item: clear `projectId` and `spaceId`
- Create a lineage edge per item with `movementKind: "correction"`, `note: "Transaction reassigned to inventory"`

### 2. Validation: `TransactionReassignValidation`

Create `LedgeriOS/LedgeriOS/Logic/TransactionReassignValidation.swift`.

Pure functions, no Firestore dependency (testable):

```swift
struct TransactionReassignValidation {
    enum ValidationResult {
        case valid
        case invalid(String)
    }

    static func canReassignToProject(
        transaction: Transaction,
        targetProjectId: String
    ) -> ValidationResult

    static func canReassignToInventory(
        transaction: Transaction
    ) -> ValidationResult
}
```

Rules:
- If `transaction.isCanonicalInventorySale == true` → `.invalid("Sale/purchase transactions cannot be reassigned.")`
- If reassigning to project and `transaction.projectId == targetProjectId` → `.invalid("Transaction is already in this project.")`
- If reassigning to inventory and `transaction.projectId == nil` → `.invalid("This transaction is already in inventory.")`
- Otherwise → `.valid`

### 3. UI: Add "Reassign" submenu to transaction kebab menu

Modify `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift`.

In the `actionMenuItems` computed property, add a **Reassign** action group (only for non-canonical transactions). The RN app uses a submenu with two options:

1. **"Reassign to Inventory"** — only shown if transaction is in a project (`projectId != nil`). Shows a confirmation dialog before executing.
2. **"Reassign to Project"** — shows `ProjectPickerList` in a sheet, then a confirmation dialog before executing.

Pattern to follow: see how `ReassignToProjectModal` works for items. For transactions, the flow is:

1. User taps kebab → "Reassign" → shows submenu
2. "Reassign to Inventory" → confirmation alert → execute `reassignTransactionToInventory` → dismiss/pop
3. "Reassign to Project" → `ProjectPickerList` sheet → user picks project → confirmation alert → execute `reassignTransactionToProject` → dismiss/pop

After reassignment, dismiss the transaction detail view (the transaction is no longer in this project).

**Confirmation dialog text** (from RN):
- To project: "This transaction and all its items will be moved to the selected project. No sale or purchase records will be created."
- To inventory: "This transaction and all its items will be moved to business inventory. No sale or purchase records will be created."

**Info text for Reassign submenu** (from RN): "Use when something was added to the wrong place and you need to move it. No financial records are created, as opposed to the Sell action."

### 4. Tests

Create `LedgeriOS/LedgeriOSTests/TransactionReassignValidationTests.swift`.

Test the validation logic using Swift Testing (`@Test`, `#expect`, `@Suite`):
- Canonical sales cannot be reassigned (to project or inventory)
- Cannot reassign to the same project it's already in
- Cannot reassign to inventory when already in inventory
- Valid cases pass

## Existing Code to Reuse

| Component | Location | Purpose |
|-----------|----------|---------|
| `ProjectPickerList` | `Modals/ProjectPickerList.swift` | Project selection sheet — reuse as-is |
| `ActionMenuSheet` | Used in TransactionDetailView already | Kebab menu — add Reassign items |
| `ActionMenuItem` | Shared component | Menu item model — supports subactions |
| `LineageEdgesService.createEdge()` | `Services/LineageEdgesService.swift` | Creates lineage edge docs |
| `TransactionsService.updateTransaction()` | `Services/TransactionsService.swift` | Updates transaction fields |
| `ItemsService` | `Services/ItemsService.swift` | For individual item updates (or use batch) |
| `InventoryOperationsService` | `Services/InventoryOperationsService.swift` | Reference for batch write + auto-enable pattern |

## Auto-Enable Budget Category (Important)

When reassigning a transaction to a project, the transaction's `budgetCategoryId` may reference a category that isn't enabled in the destination project. Per the budget management spec (`docs/specs/budget-management.md`, "Auto-enable on transfer" section), the system must automatically create a `ProjectBudgetCategory` document in the destination so the spend appears in the budget tab.

The pattern is already implemented in `InventoryOperationsService.sellToProject` — look at lines 222-230 for reference:

```swift
// Auto-enable: ensure ProjectBudgetCategory docs exist for all destination categories.
for catId in destinationCategoryIds where catId != "uncategorized" {
    var fields: [String: Any] = ["updatedAt": FieldValue.serverTimestamp()]
    if let userId { fields["updatedBy"] = userId }
    batch.setData(fields, forDocument: pbcRef.document(catId), merge: true)
}
```

## File Checklist

| File | Action |
|------|--------|
| `LedgeriOS/LedgeriOS/Services/TransactionReassignService.swift` | **Create** — batch Firestore operations |
| `LedgeriOS/LedgeriOS/Logic/TransactionReassignValidation.swift` | **Create** — pure validation functions |
| `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift` | **Modify** — add Reassign menu items + sheets |
| `LedgeriOS/LedgeriOSTests/TransactionReassignValidationTests.swift` | **Create** — validation tests |
| `LedgeriOS/LedgeriOS.xcodeproj/project.pbxproj` | **Modify** — add new files to Xcode project |

## Verification

1. Build: `cd LedgeriOS && xcodebuild build -scheme "LedgeriOS (Emulator)" -destination 'platform=iOS Simulator,name=iPhone 16e' -derivedDataPath DerivedData -quiet 2>&1 | tail -5`
2. Tests: `xcodebuild test -scheme "LedgeriOS (Emulator)" -destination 'platform=iOS Simulator,name=iPhone 16e' -derivedDataPath DerivedData -only-testing:LedgeriOSTests/TransactionReassignValidationTests 2>&1 | grep -E "(Test|passed|failed|SUCCEEDED|FAILED)"`
3. Full test suite: `xcodebuild test -scheme "LedgeriOS (Emulator)" -destination 'platform=iOS Simulator,name=iPhone 16e' -derivedDataPath DerivedData 2>&1 | grep -E "(Test run|SUCCEEDED|FAILED)"`
