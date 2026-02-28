---
work_package_id: WP12
title: Session 6 Screens – Creation Flows
lane: "doing"
dependencies:
- WP11
base_branch: 008-phase-4-screens-implementation-WP11
base_commit: 1ebc6c75a33486632d7c44764aeca3bac590a22f
created_at: '2026-02-28T23:25:41.585474+00:00'
subtasks:
- T055
- T056
- T057
- T058
- T059
phase: Phase 6 - Session 6
assignee: ''
agent: ''
shell_pid: "98337"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP12 – Session 6 Screens — Creation Flows

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- All 4 creation forms present as bottom sheets and validate correctly before submission.
- After submission, forms dismiss immediately (optimistic UI) and new entities appear in their lists.
- `NewTransactionView` progressive disclosure shows/hides fields based on transaction type selection.
- `NewItemView` supports image upload via `MediaService` and space/transaction association.
- All "Add" buttons throughout the app route to the correct creation form.

**To start implementing:** `spec-kitty implement WP12 --base WP11`

---

## Context & Constraints

- **Refs**: `plan.md` (WP12), `spec.md` FR-11.
- **Architecture**: Views in `Views/Creation/`. All present as `.sheet()` `.presentationDetents([.large])` with `.presentationDragIndicator(.visible)`.
- **Optimistic UI rule**: call `dismiss()` immediately after initiating the Firestore write. Never block UI on server acknowledgment.
- **Required field validation**: disable the Submit/Create button OR show an inline error banner when required fields are empty (don't silently prevent submission).
- **`ProjectBudgetCategoriesService`**: for new project creation, need to write per-category budget allocations. Check if `ProjectBudgetCategoriesService` has a `create()` or `set()` method — add if missing.
- **Vendor suggestions in NewTransactionView**: requires `VendorDefaultsService` (built in WP13). Stub: if service unavailable, show empty suggestions list.
- **`SpaceTemplatesService` in NewSpaceView**: stub if WP13 not landed.
- **Budget category inheritance**: items don't set `budgetCategoryId` directly — it's inherited server-side from the linked transaction.

---

## Subtasks & Detailed Guidance

### Subtask T055 – Create `Views/Creation/NewProjectView.swift`

**Purpose**: Bottom-sheet form for creating a new project with all required and optional fields.

**Steps**:
1. Create `Views/Creation/NewProjectView.swift`.
2. `@Environment` dependencies: `ProjectContext`, `AuthManager`, `MediaService`.
3. `@State` fields: `name: String = ""`, `clientName: String = ""`, `description: String = ""`, `heroImageData: Data? = nil`, `budgetAllocations: [String: Int] = [:]`.
4. Form layout:
   - Name field (required — show asterisk or inline "required" label).
   - Client Name field (required).
   - Description field (optional `TextEditor`).
   - Hero Image: `PhotosPicker` → load `Data` → show thumbnail preview. On upload: `MediaService.uploadImage(...)`.
   - Budget Allocation section: for each enabled `BudgetCategory` in the account, show: category name label + dollar amount `TextField` (numeric). Allow zero.
5. Create/Save button: disabled if `!ProjectFormValidation.isValidProject(name:clientName:)`. On tap: `ProjectsService.create(name:clientName:description:heroImageUrl:)` → upload image if selected → set budget allocations via `ProjectBudgetCategoriesService.set(allocations:)` → `dismiss()`.
6. Cancel button: `dismiss()`.
7. Present from: project list "Add" button.

**Files**:
- `Views/Creation/NewProjectView.swift` (create, ~120 lines)

**Parallel?**: Yes — independent of T056–T058.

**Notes**:
- Budget allocation section may be long — wrap in `ScrollView`.
- Image upload: get `PhotosPickerItem` → `loadTransferable(type: Data.self)` → upload async after creation if project creation succeeds.
- Project creation + budget allocation should succeed as a unit — use `async let` or sequential awaits.

---

### Subtask T056 – Create `Views/Creation/NewTransactionView.swift`

**Purpose**: Multi-step bottom sheet form with progressive disclosure for transaction creation.

**Steps**:
1. Create `Views/Creation/NewTransactionView.swift`.
2. `@State var transactionType: String? = nil`.
3. `@State var currentStep: Int = 1` (1=type, 2=destination, 3=details).
4. **Step 1 — Type selection**:
   - 4 large tappable cards: Purchase, Sale, Return, To Inventory.
   - On tap → `transactionType = selectedType` → advance to Step 2.
5. **Step 2 — Destination/Channel** (type-specific):
   - Purchase: "Where?" (vendor/source input with vendor suggestions from `VendorDefaultsService`).
   - Sale/Return/To Inventory: may skip or have different destination fields — check RN source.
   - Back button → Step 1.
   - Next → Step 3.
6. **Step 3 — Detail fields**:
   - Source/Vendor (text input, autocomplete from `VendorDefaultsService`).
   - Date (date picker, default today).
   - Amount (currency input).
   - Status (picker: pending/completed/canceled/inventory-only, default pending).
   - Purchased By (picker: client-card/design-business, default design-business).
   - Reimbursement Type (picker: none/owed-to-client/owed-to-company, default none).
   - Notes (text area, optional).
   - Budget Category (CategoryPickerList, optional).
   - Email Receipt toggle (default false).
   - Conditional: if `budgetCategory?.type == "itemized"`: Subtotal + Tax Rate fields.
7. Create button: validate via `TransactionFormValidation.isTransactionReadyToSubmit()`. On tap → `TransactionsService.create(...)` → `dismiss()`.

**Files**:
- `Views/Creation/NewTransactionView.swift` (create, ~150 lines)

**Parallel?**: Yes.

---

### Subtask T057 – Create `Views/Creation/NewItemView.swift`

**Purpose**: Bottom-sheet form for creating a new item.

**Steps**:
1. Create `Views/Creation/NewItemView.swift`.
2. `@State` fields: name, source, sku, status (default "to-purchase"), purchasePriceCents, projectPriceCents, marketValueCents, quantity, spaceId, transactionId, imageData.
3. Form fields (in order matching RN):
   - Name (required `TextField`).
   - Source (optional vendor text input).
   - SKU (optional).
   - Status picker (StatusPickerModal or inline picker): to-purchase/purchased/to-return/returned.
   - Purchase Price (currency input, optional).
   - Project Price (currency input, optional).
   - Market Value (currency input, optional).
   - Quantity (stepper or numeric input, optional, min 1).
   - Space: "Select Space" button → present `SpacePickerList`.
   - Transaction: "Link Transaction" button → present `TransactionPickerModal`.
   - Image: `PhotosPicker` → show thumbnail.
4. Create button: disabled if `!ItemFormValidation.isValidItem(name:)`. On tap → `ItemsService.create(...)` → upload image via `MediaService` if selected → `dismiss()`.

**Files**:
- `Views/Creation/NewItemView.swift` (create, ~130 lines)

**Parallel?**: Yes.

---

### Subtask T058 – Create `Views/Creation/NewSpaceView.swift`

**Purpose**: Bottom-sheet form for creating a new space with optional template selection.

**Steps**:
1. Create `Views/Creation/NewSpaceView.swift`.
2. `@State` fields: name, notes, selectedTemplateId.
3. Form fields:
   - Name (required `TextField`).
   - Notes (optional `TextEditor`).
   - Template: "Apply Template" button → show list of `SpaceTemplate`s (from `SpaceTemplatesService` — stub if WP13 not yet done; show empty list).
4. Create button: disabled if `!SpaceFormValidation.isValidSpace(name:)`. On tap → `SpacesService.create(name:notes:checklists:)` — if template selected, copy its `checklists` to the new space → `dismiss()`.

**Files**:
- `Views/Creation/NewSpaceView.swift` (create, ~80 lines)

**Parallel?**: Yes.

---

### Subtask T059 – Wire entry points (Add buttons)

**Purpose**: Connect "Add" buttons throughout the app to the correct creation forms.

**Steps**:
1. **Projects list** (WP02): "Add Project" + button → `NewProjectView()`.
2. **Transactions tab** (WP04): Add pill in toolbar → `NewTransactionView(defaultContext: .project(projectId))`.
3. **Items tab** (WP06): Add button → `NewItemView(defaultContext: .project(projectId, spaceId: nil))`.
4. **Spaces tab** (WP08): Add button → `NewSpaceView(defaultContext: .project(projectId))`.
5. **Inventory Items sub-tab** (WP10): Add button → `NewItemView(defaultContext: .inventory)`.
6. **Inventory Spaces sub-tab** (WP10): Add button → `NewSpaceView(defaultContext: .inventory)`.
7. Review if a center FAB "+" button exists in `MainTabView` — wire it to present a type picker → route to the correct creation form.

**Files**:
- Various views updated to wire `isPresenting*` sheet states to creation form views.

**Parallel?**: No — depends on T055–T058 existing.

**Notes**:
- Pass context (project ID vs inventory) to creation forms so they write to the correct Firestore paths.
- After dismissal, lists should update immediately because Firestore listeners are already active.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `NewProjectView` budget allocation section too complex | Implement plain `ForEach` with `TextField` per category — no custom component needed |
| `NewTransactionView` 3-step state management | Use `@State var step: Int = 1`; all 3 steps in one `NavigationStack` with `NavigationLink` or conditional `@ViewBuilder` |
| `NewItemView` image upload before or after item creation? | Create item first (optimistic), then upload image, then update item's `images` array |
| `VendorDefaultsService` not yet available | Stub: show empty suggestions array |

---

## Review Guidance

- [ ] All 4 forms present as bottom sheets with `.presentationDetents([.large])`.
- [ ] Required field validation: submit button disabled OR inline error shown when fields are empty.
- [ ] Optimistic UI: forms dismiss immediately after Create tap (no waiting).
- [ ] `NewTransactionView`: type selection → detail fields progressive disclosure.
- [ ] `NewItemView`: space + transaction pickers work.
- [ ] `NewSpaceView`: template selection works (or gracefully stubs).
- [ ] All Add buttons throughout the app open the correct creation form.
- [ ] Light + dark mode correct.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
