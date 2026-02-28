---
work_package_id: WP13
title: Session 7a Screens – Settings
lane: "for_review"
dependencies:
- WP00
base_branch: 008-phase-4-screens-implementation-WP00
base_commit: 5635cf5479637c42d5d31eb9ce1911b40ef3f438
created_at: '2026-02-28T23:10:06.401426+00:00'
subtasks:
- T060
- T061
- T062
- T063
- T064
- T065
phase: Phase 7 - Session 7a
assignee: ''
agent: "claude-opus"
shell_pid: "49033"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP13 – Session 7a Screens — Settings

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- 4 new models and 5 new services created and working.
- `SettingsView` replaces placeholder with 4-tab interface.
- Budget category CRUD works with drag-reorder and archive/unarchive.
- `CategoryFormModal` shows exact validation error messages.
- Space templates and vendor defaults management works.
- Users tab shows team members + pending invitations.
- Account tab: business profile editable, sign out clears state and returns to sign-in.

**To start implementing:** `spec-kitty implement WP13 --base WP00`

---

## Context & Constraints

- **Refs**: `plan.md` (WP13), `spec.md` FR-12, `data-model.md` (new models section).
- **New models** (see data-model.md for full struct definitions): `SpaceTemplate`, `VendorDefault`, `Invite`, `BusinessProfile`.
- **Firestore paths**:
  - `SpaceTemplate`: `accounts/{accountId}/presets/default/spaceTemplates/{templateId}`
  - `VendorDefault`: `accounts/{accountId}/presets/default/vendors/{vendorId}` (verify path in RN source)
  - `Invite`: `accounts/{accountId}/invites/{inviteId}`
  - `BusinessProfile`: part of `accounts/{accountId}` document (check RN source)
- **Exact validation errors** (FR-12.8):
  - `"Category name must be 100 characters or less"` (when name > 100 chars)
  - `"A category cannot be both Itemized and Fee"` (when both isItemized and isFee are true)
- **Vendor pre-populated list**: Home Depot, Wayfair, West Elm, Pottery Barn — check `src/data/accountPresetsService.ts` for full list of default vendors.
- **Theme selection** (General tab): store in `UserDefaults("colorSchemePreference")` with values `"light"`, `"dark"`, `"system"` (default "system"). Apply via `@AppStorage` + `.preferredColorScheme()` modifier on root view.
- **Sign out**: clear all `@Observable` state managers + Firebase `Auth.auth().signOut()` → navigate back to sign-in screen. Coordinate with `AuthManager` sign-out flow.
- **`DraggableCardList`**: check if this component exists in Phase 5 library. If not, use SwiftUI `List` with `.onMove` modifier.

---

## Subtasks & Detailed Guidance

### Subtask T060 – Create 4 new models

**Purpose**: Swift model structs for new Settings domain entities.

**Steps**:
1. Create `Models/SpaceTemplate.swift`:
   ```swift
   struct SpaceTemplate: Codable, Identifiable {
       @DocumentID var id: String?
       var name: String
       var notes: String?
       var checklists: [Checklist]
       var isArchived: Bool?
       var order: Int?
       @ServerTimestamp var createdAt: Timestamp?
       @ServerTimestamp var updatedAt: Timestamp?
   }
   ```
2. Create `Models/VendorDefault.swift`:
   ```swift
   struct VendorDefault: Codable, Identifiable {
       @DocumentID var id: String?
       var name: String
       var order: Int?
       @ServerTimestamp var createdAt: Timestamp?
   }
   ```
3. Create `Models/Invite.swift`:
   ```swift
   struct Invite: Codable, Identifiable {
       @DocumentID var id: String?
       var email: String
       var role: String
       var status: String?
       @ServerTimestamp var createdAt: Timestamp?
       @ServerTimestamp var expiresAt: Timestamp?
   }
   ```
4. Create `Models/BusinessProfile.swift`:
   ```swift
   struct BusinessProfile: Codable {
       var name: String?
       var logoUrl: String?
       @ServerTimestamp var updatedAt: Timestamp?
   }
   ```

**Files**:
- `Models/SpaceTemplate.swift` (create)
- `Models/VendorDefault.swift` (create)
- `Models/Invite.swift` (create)
- `Models/BusinessProfile.swift` (create)

**Parallel?**: Yes — all 4 independent.

---

### Subtask T061 – Create 5 new services

**Purpose**: Firestore CRUD services for all Settings domain entities.

**Steps**:
1. Create `Services/SpaceTemplatesService.swift`:
   - `subscribe(accountId:)` → real-time listener for space templates.
   - `create(_ template: SpaceTemplate)`, `update(_ template: SpaceTemplate)`, `delete(id:)`.
   - `create(from space: Space)` — creates template from a space's name/notes/checklists (called from Space Detail "Save as Template").
2. Create `Services/VendorDefaultsService.swift`:
   - `subscribe(accountId:)` → real-time listener.
   - `create(_ vendor: VendorDefault)`, `delete(id:)`.
   - `prePopulateDefaults(accountId:)` — write the default vendor list if empty: ["Home Depot", "Wayfair", "West Elm", "Pottery Barn", ...others from RN source].
3. Create `Services/InvitesService.swift`:
   - `subscribe(accountId:)` → real-time listener for pending invites.
   - `create(email:, role:)` — creates invite document.
   - `delete(id:)` — revoke invite.
4. Create `Services/BusinessProfileService.swift`:
   - `fetch(accountId:) async throws -> BusinessProfile` — one-time read.
   - `update(_ profile: BusinessProfile)`.
5. Create `Services/AccountPresetsService.swift`:
   - `initializeDefaults(accountId:)` — checks if vendors collection is empty; if so, calls `VendorDefaultsService.prePopulateDefaults()`.
   - Can be called on first account setup.

**Files**:
- 5 service files in `Services/` (create, ~60-80 lines each)

**Parallel?**: No — services can be written in parallel with each other but must exist before the views in T062–T065.

---

### Subtask T062 – Create `Views/Settings/SettingsView.swift`

**Purpose**: Replace `SettingsPlaceholderView.swift` with a 4-tab settings root view.

**Steps**:
1. Create `Views/Settings/SettingsView.swift`.
2. `ScrollableTabBar` with 4 tabs: General, Presets, Users, Account.
3. Tab content:
   - General (index 0): theme selection + account info display.
   - Presets (index 1): sub-tabs (Budget Categories, Space Templates, Vendors) — use another `ScrollableTabBar` or a `Picker` with segment style.
   - Users (index 2): `UsersView()`.
   - Account (index 3): `AccountView()`.
4. Update `MainTabView` to use `SettingsView()` instead of `SettingsPlaceholderView()`.

**Files**:
- `Views/Settings/SettingsView.swift` (create, ~60 lines)

---

### Subtask T063 – Create `Views/Settings/BudgetCategoryManagementView.swift` + `CategoryFormModal`

**Purpose**: Full CRUD for budget categories with drag-reorder and archive management.

**Steps**:
1. Create `Views/Settings/BudgetCategoryManagementView.swift`:
   - Subscribe to `ProjectBudgetCategoriesService` (or `AccountBudgetCategoriesService`) — read all categories for the account.
   - Show list of non-archived categories with drag handles (`.onMove`).
   - Each row: category name + type pill (general/itemized/fee) + archive button.
   - Archive button: show `.confirmationDialog("Archive this category? Transactions using it will still show it in reports.")` → call `service.archive(id:)`.
   - Unarchive: show archived categories in a "Archived" section; tap to unarchive.
   - "Add Category" button → present `CategoryFormModal(mode: .create)`.
   - Tap category → present `CategoryFormModal(mode: .edit(category))`.
2. Create `Modals/CategoryFormModal.swift`:
   - Present as `.sheet()` `.presentationDetents([.medium, .large])`.
   - Fields: Name (required `TextField`, max 100 chars), isItemized `Toggle`, isFee `Toggle` (mutually exclusive), excludeFromOverallBudget `Toggle`.
   - Validation (inline, shown on submit attempt):
     - Name > 100 chars → "Category name must be 100 characters or less" (exact).
     - isItemized AND isFee both true → "A category cannot be both Itemized and Fee" (exact).
     - Name empty → "Name is required".
   - Mutual exclusivity: if isItemized toggled on → set isFee to false (and vice versa).
   - Save/Create button: calls `service.create()` or `service.update()` → dismiss.
   - Button label: "Create" (new) or "Save" (edit) per FR-12.8.

**Files**:
- `Views/Settings/BudgetCategoryManagementView.swift` (create, ~120 lines)
- `Modals/CategoryFormModal.swift` (create, ~100 lines)

---

### Subtask T064 – Create `Views/Settings/SpaceTemplateManagementView.swift`

**Purpose**: Full CRUD for space templates with drag-reorder.

**Steps**:
1. Create `Views/Settings/SpaceTemplateManagementView.swift`.
2. Subscribe to `SpaceTemplatesService`.
3. List of non-archived templates with drag handles + delete button.
4. "Add Template" → sheet with name + notes fields + checklist editor (similar to `EditChecklistModal`).
5. Tap template → edit sheet with same fields.
6. Reorder → update `order` field on each template via `SpaceTemplatesService.update()`.
7. Delete → `SpaceTemplatesService.delete(id:)`.

**Files**:
- `Views/Settings/SpaceTemplateManagementView.swift` (create, ~100 lines)

**Parallel?**: Yes — independent of T065.

---

### Subtask T065 – Create Vendor/Users/Account views

**Purpose**: Three remaining settings sub-views.

**Steps**:

**`VendorDefaultsView.swift`**:
1. Subscribe to `VendorDefaultsService`.
2. List of vendors with drag handles (for reorder) and delete buttons.
3. "Add Vendor" → text field sheet → `VendorDefaultsService.create()`.
4. On first load: call `AccountPresetsService.initializeDefaults()` if vendors list is empty.

**`UsersView.swift`**:
1. Read `AccountContext.members` (existing) + subscribe to `InvitesService` for pending invites.
2. Members section: list of `AccountMember` with name + role pill.
3. Pending Invitations section: list of `Invite` with email + role + "Revoke" button.
4. "Invite User" button → sheet with: email `TextField` + role picker (owner/admin/member) → `InvitesService.create(email:role:)`.

**`AccountView.swift`**:
1. Show current `BusinessProfile` (name + logo).
2. "Edit Profile": `BusinessProfileService.update()` — name field + logo `PhotosPicker` → upload via `MediaService`.
3. "Create New Account": show sheet with account name field → `AccountsService.create()` (if exists).
4. "Sign Out": call `AuthManager.signOut()` → clears all contexts → navigates to sign-in.

**Files**:
- `Views/Settings/VendorDefaultsView.swift` (create, ~80 lines)
- `Views/Settings/UsersView.swift` (create, ~100 lines)
- `Views/Settings/AccountView.swift` (create, ~80 lines)

**Parallel?**: Yes — all 3 independent.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Firestore path for VendorDefault unclear | Check `src/services/vendorDefaultsService.ts` for exact collection path |
| `DraggableCardList` not in Phase 5 library | Use `List` with `.onMove` + `.environment(\.editMode, .constant(.active))` |
| Mutual exclusivity of isItemized/isFee toggles | Implement as computed `@State`: toggling one automatically clears the other |
| Sign out coordination | Coordinate with existing `AuthManager.signOut()` — don't duplicate sign-out logic |

---

## Review Guidance

- [ ] `CategoryFormModal` shows exact error strings: "Category name must be 100 characters or less" and "A category cannot be both Itemized and Fee".
- [ ] Category CRUD: create, edit, archive, unarchive, drag-reorder all work.
- [ ] Space templates: CRUD + reorder working.
- [ ] Vendors: CRUD + reorder + pre-populated defaults on empty list.
- [ ] Users: team members visible + pending invites + create invite.
- [ ] Sign out: returns to sign-in screen, all contexts cleared.
- [ ] All modals as bottom sheets with drag indicator.
- [ ] Light + dark mode correct.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-28T23:10:06Z – claude-opus – shell_pid=49033 – lane=doing – Assigned agent via workflow command
- 2026-02-28T23:24:50Z – claude-opus – shell_pid=49033 – lane=for_review – Ready for review: Settings screens with 4-tab interface (General/Presets/Users/Account), 4 models, 5 services, CategoryFormModal with validation, theme selection, sign out flow. Build succeeds.
