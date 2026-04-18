# Field Tooltips
Status: new
Last updated: 2026-04-17

## Summary
An info-tooltip system for non-obvious fields and options across the app. Any field whose purpose isn't immediately clear from its label gets a small `(i)` icon next to the label. Tapping it opens a bottom sheet with a plain-language explanation.

Goal: users should never feel lost or confused about what a field means or why it matters.

## How It Works

### Trigger
A small `info.circle` SF Symbol icon appears inline next to the field label. Tapping it opens a tooltip sheet. The icon uses `BrandColors.textTertiary` so it's visible but doesn't compete with the label.

### Presentation
A bottom sheet (`.small` detent via `SheetStyle`) containing:
- **Field name** as the title
- **Explanation** — 1–3 sentences in plain language. No jargon. Written as if explaining to someone using the app for the first time.
- **Example** (optional) — a concrete scenario that makes the explanation click.

The sheet is dismissible by drag or tapping outside.

### Content Registry
All tooltip text lives in a single centralized file — a dictionary mapping field keys to tooltip content. This keeps copy out of views, makes it easy to audit, update, and eventually localize.

```swift
// TooltipContent.swift
struct TooltipEntry {
    let title: String
    let explanation: String
    let example: String?  // optional concrete scenario
}

enum TooltipKey: String {
    case payable
    case budgetCategory
    case emailReceipt
    case purchasedBy
    case source
    case subtotal
    case taxRate
    // ... add as needed
}

enum TooltipContent {
    static let entries: [TooltipKey: TooltipEntry] = [
        .payable: TooltipEntry(
            title: "Payable",
            explanation: "Tracks whether this purchase created a debt between you and the client. 'To Client' means the client paid but you need to pay them back. 'To Business' means you paid but the client needs to pay you back.",
            example: "You bought a lamp with the client's card that was actually for a different project — that's payable to the client."
        ),
        .budgetCategory: TooltipEntry(
            title: "Budget Category",
            explanation: "The budget line item this transaction counts toward. Each project has its own set of categories (e.g., Furniture, Lighting, Textiles). The transaction amount rolls into this category's spent total.",
            example: nil
        ),
        .emailReceipt: TooltipEntry(
            title: "Email Receipt",
            explanation: "Whether the receipt for this purchase was sent via email rather than a physical copy. Helps the team know where to find the receipt if needed later.",
            example: nil
        ),
        // ...
    ]
}
```

### View Integration
A reusable modifier or small component that any field label can adopt:

```swift
// Usage in a form:
FieldLabel("Reimbursement", tooltip: .reimbursement)

// Usage on a DetailRow:
DetailRow(label: "Budget Category", value: "Furniture", tooltip: .budgetCategory)
```

The component handles the icon rendering and sheet presentation internally. Views don't need to know about tooltip text — they just pass the key.

## Initial Tooltip Candidates

Fields that are non-obvious and should ship with tooltips in the first pass:

### Transaction Fields
| Field | Why it needs a tooltip |
|-------|----------------------|
| Payable | Renamed from "Reimbursement". Options: "None" / "To Client" / "To Business". Still needs a tooltip to explain when/why money would be owed. |
| Budget Category | New users don't know what categories are or that this controls budget tracking. |
| Email Receipt | Not clear why this matters or what it's used for. |
| Purchased By | "Client Card" vs "Design Business" — users need to know this affects reimbursement logic. |
| Source | Where the item was bought. Distinction between `source` (original vendor) and `currentSource` (immediate source) is invisible to users but affects reports. |

### Item Fields
| Field | Why it needs a tooltip |
|-------|----------------------|
| Status (workflow) | Multiple statuses with specific meanings (ordered, received, installed, etc.). |
| Billing Status | Unbilled → Invoiced → Paid pipeline isn't obvious. |
| Current Source | Why this might differ from where the item was originally purchased. |

### Project Fields
| Field | Why it needs a tooltip |
|-------|----------------------|
| Budget Allocation | How category-level budgets relate to the overall project budget. |
| Markup | What percentage is applied and how it affects the client-facing price. |

### Budget Fields
| Field | Why it needs a tooltip |
|-------|----------------------|
| Allocated vs Spent | What counts as "spent" (committed transactions) vs what's allocated (planned). |
| Variance | Over/under budget and what the colors mean. |

This list isn't exhaustive — add tooltips to any field where user testing or support questions reveal confusion.

## What's Changing

### Adding
- `TooltipContent.swift` — centralized tooltip text registry
- `TooltipSheet` — small bottom sheet view for displaying tooltip content
- `FieldLabel` component (or modifier) — label + optional `(i)` icon + sheet trigger
- Tooltip support on `DetailRow`, `FormField`, `FormToggle`, and other shared form components
- Initial tooltip text for ~12 fields listed above

### Renaming
- **"Reimbursement" → "Payable"** — label, filter menu, detail rows, and export headers. Option values change: "None" stays "None", "Owed to Client" → "To Client", "Owed to Company" → "To Business". Firestore `reimbursementType` field values stay the same — mapping happens at the display layer.

### Staying the Same
- Field behavior, layout, and data flow — tooltips are purely informational overlay
- Existing label styling — the `(i)` icon is additive, not a replacement

## Decisions
- **Always available.** No "don't show again" dismiss. Tooltips require a deliberate tap, so they're unobtrusive — and if dismissed permanently, users lose access to help they might need later.
- **Both read-only and edit views.** Tooltip icons appear on `DetailRow` (read) and form fields (edit). Confusion happens when reading too, not just when entering data.
- **"Reimbursement" renamed to "Payable".** One word, widely understood, not accounting jargon. Options: "None" / "To Client" / "To Business". Firestore `reimbursementType` field values unchanged — mapping at display layer only.

## Open Questions
- None currently.
