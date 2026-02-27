# Firestore Field Contracts

*Phase 4 Screens Implementation — new fields and new collections only*

---

## Item — New Field

**Collection:** `accounts/{accountId}/items/{itemId}` (and project-scoped path)

| Field | Type | Description |
|-------|------|-------------|
| `quantity` | `number \| null` | Item count. Null means 1 (treat as 1 in display). No negative values. |

---

## SpaceTemplate — New Collection

**Collection:** `accounts/{accountId}/presets/default/spaceTemplates/{templateId}`

| Field | Type | Constraints |
|-------|------|------------|
| `name` | `string` | Required, max 200 chars |
| `notes` | `string \| null` | Optional |
| `checklists` | `array<Checklist>` | Can be empty array |
| `isArchived` | `boolean \| null` | Null = false |
| `order` | `number \| null` | Numeric sort key for drag-reorder; null = append |
| `createdAt` | `timestamp` | Server-set |
| `updatedAt` | `timestamp` | Server-set |

**Checklist (embedded):**
| Field | Type |
|-------|------|
| `id` | `string` |
| `name` | `string` |
| `items` | `array<ChecklistItem>` |

**ChecklistItem (embedded):**
| Field | Type |
|-------|------|
| `id` | `string` |
| `text` | `string` |
| `isChecked` | `boolean` |

---

## VendorDefault — New Collection

**Collection:** `accounts/{accountId}/presets/default/vendors/{vendorId}` *(verify path against RN `accountPresetsService.ts` in WP13)*

| Field | Type | Constraints |
|-------|------|------------|
| `name` | `string` | Required |
| `order` | `number \| null` | Sort order for reordering |
| `createdAt` | `timestamp` | Server-set |

---

## Invite — New Collection

**Collection:** `accounts/{accountId}/invites/{inviteId}`

| Field | Type | Constraints |
|-------|------|------------|
| `email` | `string` | Required, valid email |
| `role` | `string` | One of: `owner`, `admin`, `member` |
| `status` | `string` | One of: `pending`, `accepted`, `expired` |
| `createdAt` | `timestamp` | Server-set |
| `expiresAt` | `timestamp \| null` | Optional expiry |

---

## BusinessProfile — Existing Collection Update

**Collection:** `accounts/{accountId}` *(verify: may be embedded in account doc or separate path — check RN `businessProfileService.ts` in WP13)*

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string \| null` | Business/firm name |
| `logoUrl` | `string \| null` | Firebase Storage download URL for logo image |
| `updatedAt` | `timestamp` | Server-set |

---

## Existing Fields — Read-Only Reference (No Changes)

These Firestore fields are read by Phase 4 screens but were defined in prior phases. Listed for implementation reference only.

### Transaction
```
amountCents: number
source: string | null
transactionType: "purchase" | "sale" | "return" | "to-inventory"
reimbursementType: "none" | "owed-to-client" | "owed-to-company"
status: "pending" | "completed" | "canceled" | "inventory-only"
budgetCategoryId: string | null
purchasedBy: string | null
hasEmailReceipt: boolean | null
notes: string | null
subtotalCents: number | null
taxRatePct: number | null
receiptImages: AttachmentRef[]
otherImages: AttachmentRef[]
itemIds: string[]
needsReview: boolean | null
isCanceled: boolean | null
isCanonicalInventorySale: boolean | null
inventorySaleDirection: "project_to_business" | "business_to_project" | null
transactionDate: timestamp | null
```

### Item
```
name: string | null
source: string | null
sku: string | null
status: "to-purchase" | "purchased" | "to-return" | "returned"
purchasePriceCents: number | null
projectPriceCents: number | null
marketValueCents: number | null
budgetCategoryId: string | null
spaceId: string | null
transactionId: string | null
bookmark: boolean | null
images: AttachmentRef[]
notes: string | null
```

### AttachmentRef (shared embedded type)
```
url: string
storagePath: string | null
isPrimary: boolean | null
```
