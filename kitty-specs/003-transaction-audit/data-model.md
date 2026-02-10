# Data Model (Discovery Draft)

## Entities

### Entity: Transaction
- **Description**: A financial transaction record linked to a project. Contains the total amount, optional tax info, and references to linked items.
- **Attributes**:
  - `id` (string) – Firestore document ID
  - `amountCents` (number | null) – Total transaction amount including tax, in cents
  - `subtotalCents` (number | null) – Pre-tax amount in cents (explicitly set by user)
  - `taxRatePct` (number | null) – Tax rate percentage, e.g., 8.25
  - `budgetCategoryId` (string | null) – FK to BudgetCategory; controls itemization check
  - `itemIds` (string[] | null) – Array of linked Item IDs
  - `needsReview` (boolean | null) – Denormalized flag: true if audit completeness is below threshold
  - `projectId` (string | null) – FK to project
  - `status` (string | null) – 'pending' | 'completed' | 'canceled'
- **Identifiers**: `id` (primary key)
- **Lifecycle Notes**: Created via transaction form. Updated on item link/unlink. `needsReview` auto-computed.
- **Source**: `src/data/transactionsService.ts:16-43`

### Entity: Item
- **Description**: An inventory item that can be linked to a transaction. Purchase price is the key field for audit calculations.
- **Attributes**:
  - `id` (string) – Firestore document ID
  - `name` (string) – Item description/name
  - `sku` (string | null) – Stock keeping unit
  - `purchasePriceCents` (number | null) – What was paid for the item, in cents. **Key audit field.**
  - `projectPriceCents` (number | null) – What the item is sold for (not used in audit)
  - `transactionId` (string | null) – FK to currently associated transaction
  - `budgetCategoryId` (string | null) – FK to budget category
  - `images` (AttachmentRef[] | null) – Item images
- **Identifiers**: `id` (primary key)
- **Lifecycle Notes**: Created during transaction entry or standalone. Linked/unlinked to transactions. Purchase price may be set later.
- **Source**: `src/data/itemsService.ts:20-41`

### Entity: BudgetCategory
- **Description**: A budget grouping for transactions. Controls whether itemization (and thus audit) is enabled.
- **Attributes**:
  - `id` (string) – Firestore document ID
  - `name` (string) – Display name (e.g., "Furnishings", "Design Fee")
  - `metadata.categoryType` (BudgetCategoryType | null) – `'general' | 'itemized' | 'fee'`. **Audit only shown when `'itemized'`.**
  - `metadata.excludeFromOverallBudget` (boolean | null) – Whether excluded from budget totals
  - `projectId` (string | null) – FK to project
- **Identifiers**: `id` (primary key)
- **Lifecycle Notes**: Created per-project. Metadata controls audit behavior.
- **Source**: `src/data/budgetCategoriesService.ts:15-35`

### Entity: TransactionCompleteness (Computed — not persisted)
- **Description**: Computed audit metrics for a transaction. Calculated client-side from Transaction + Items data. This matches the legacy `TransactionCompleteness` interface.
- **Attributes**:
  - `itemsNetTotal` (number) – Sum of `item.purchasePriceCents` for all linked items, in cents
  - `itemsCount` (number) – Total count of linked items
  - `itemsMissingPriceCount` (number) – Count of items where `purchasePriceCents` is null/0
  - `transactionSubtotal` (number) – Pre-tax subtotal in cents (resolved via D5 priority)
  - `completenessRatio` (number) – `itemsNetTotal / transactionSubtotal` (0-N, where 1.0 = 100%)
  - `completenessStatus` (CompletenessStatus) – `'complete' | 'near' | 'incomplete' | 'over'`
  - `missingTaxData` (boolean) – True if no subtotal and no tax rate available
  - `inferredTax` (number | undefined) – Tax amount calculated from taxRatePct (cents)
  - `taxAmount` (number | undefined) – Explicit tax amount if available (cents)
  - `varianceCents` (number) – `itemsNetTotal - transactionSubtotal` (positive = over, negative = under)
  - `variancePercent` (number) – `(varianceCents / transactionSubtotal) * 100`
- **Identifiers**: N/A (derived per-transaction)
- **Lifecycle Notes**: Recomputed whenever transaction or item data changes. Memoized in component.
- **Source**: Legacy type at `/Users/benjaminmackenzie/Dev/ledger/src/types/index.ts:446-458`

## Relationships

| Source | Relation | Target | Cardinality | Notes |
|--------|----------|--------|-------------|-------|
| Transaction | has many | Item | 1:N | Via `transaction.itemIds[]` and `item.transactionId` (bidirectional FK) |
| Transaction | belongs to | BudgetCategory | N:1 | Via `transaction.budgetCategoryId` |
| Item | belongs to | BudgetCategory | N:1 | Via `item.budgetCategoryId` |
| Transaction | computes | TransactionCompleteness | 1:1 | Derived client-side from Transaction + Items |

## Validation & Governance

- **Data quality requirements**:
  - `amountCents` should be a positive integer (but handle null/0 gracefully)
  - `subtotalCents` when set should be <= `amountCents` (pre-tax <= total)
  - `taxRatePct` when set should be 0-100
  - `purchasePriceCents` should be non-negative when set (null = missing)
  - Division by zero: when `transactionSubtotal === 0`, completeness is N/A
- **Compliance considerations**: No PII in audit data. Financial data stays within account scope.
- **Source of truth**:
  - Transaction data: Firestore `accounts/{accountId}/transactions/{transactionId}`
  - Item data: Firestore `accounts/{accountId}/items/{itemId}`
  - Budget categories: Firestore `accounts/{accountId}/budget_categories/{categoryId}`

> Treat this as a working model. When research uncovers new flows or systems, update the entities and relationships immediately so the implementation team inherits up-to-date context.
