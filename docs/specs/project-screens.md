# Project Screens Specification

**Version**: 1.0
**Date**: 2026-02-06
**Status**: Draft

---

## Table of Contents

1. [Overview](#overview)
2. [Data Model](#data-model)
3. [Add Project Screen](#add-project-screen)
4. [Edit Project Screen](#edit-project-screen)
5. [Project Detail Screen](#project-detail-screen)
6. [Accounting Tab (Future)](#accounting-tab-future)
7. [Component Reuse Map](#component-reuse-map)
8. [Validation Rules](#validation-rules)
9. [Implementation Targets](#implementation-targets)

---

## Overview

The app has three project-related screens:

- **Add Project** (`/project/new`) — Form for creating a new project with metadata and budget allocation
- **Edit Project** (`/project/:projectId/edit`) — Same form, pre-populated from existing project data
- **Project Detail** (`/project/:projectId`) — Tabbed view of project data (budget, items, transactions, spaces)

Add and Edit share the same form layout. The form captures basic info, description, a main image, and per-category budget allocations — all in a single scrollable screen.

The Project Detail screen has been revised from the legacy layout. It uses the `Screen` component's built-in tab system instead of the legacy's separate budget/accounting and section tab groups. The Accounting tab from legacy is not yet implemented and is documented here as a future feature.

### Legacy Reference

The legacy web app implements these screens in:
- `~/Dev/ledger/src/components/ProjectForm.tsx` — shared add/edit modal form
- `~/Dev/ledger/src/pages/ProjectLayout.tsx` — project detail with budget/accounting tabs and section tabs

---

## Data Model

### Project

**Path**: `src/data/projectService.ts`

```typescript
type Project = {
  id: string;
  accountId: string;
  name: string;
  clientName: string;
  description?: string | null;
  mainImageUrl?: string | null;
  isArchived?: boolean | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};
```

### CreateProjectPayload

**Path**: `src/data/projectService.ts`

```typescript
// Current (minimal)
type CreateProjectPayload = {
  accountId: string;
  name: string;
  clientName: string;
};
```

> **Note**: The payload will need to be expanded to include `description` when the form is updated. The `mainImageUrl` is set via a separate update call after project creation (requires `projectId`). Budget categories are stored in a subcollection, not on the project document.

### ProjectBudgetCategory

**Path**: `src/data/projectBudgetCategoriesService.ts`

```typescript
type ProjectBudgetCategory = {
  id: string;                    // matches BudgetCategory.id
  budgetCents: number | null;
  createdAt?: unknown;
  updatedAt?: unknown;
  createdBy?: string;
  updatedBy?: string;
};
```

**Firestore path**: `accounts/{accountId}/projects/{projectId}/budgetCategories/{categoryId}`

### BudgetCategory (Account-Scoped)

**Path**: `src/data/budgetCategoriesService.ts`

```typescript
type BudgetCategory = {
  id: string;
  accountId: string;
  name: string;
  slug: string;
  isArchived: boolean;
  sortOrder?: number;
  metadata?: {
    categoryType?: "general" | "itemized" | "fee";
    excludeFromOverallBudget?: boolean;
  } | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};
```

---

## Add Project Screen

**Route**: `/project/new`
**File**: `app/project/new.tsx`
**Current state**: Minimal — only `name` and `clientName` fields

### Screen Layout

Uses `Screen` component with title "New Project" and back navigation.

Content is a scrollable form with the following sections, in order:

### Section 1: Basic Information

Two text fields stacked vertically.

| Field | Type | Required | Placeholder | Component |
|-------|------|----------|-------------|-----------|
| Project Name | single-line text | Yes | "Enter project name" | `FormField` |
| Client Name | single-line text | Yes | "Enter client name" | `FormField` |

**Component**: `FormField` from `src/components/FormField.tsx`
**Props**: `label`, `value`, `onChangeText`, `placeholder`, `errorText`

### Section 2: Description

| Field | Type | Required | Placeholder | Component |
|-------|------|----------|-------------|-----------|
| Description | multiline text (3 lines) | No | "Enter project description" | `FormField` |

**Component**: `FormField` with `inputProps={{ multiline: true, numberOfLines: 3, textAlignVertical: 'top' }}`

### Section 3: Main Project Image

A single-image picker for the project's hero/banner image.

| Field | Type | Required | Constraints | Component |
|-------|------|----------|-------------|-----------|
| Main Project Image | image picker | No | JPEG/PNG/GIF/WebP, max 10MB | `MediaGallerySection` |

**Component**: `MediaGallerySection` from `src/components/MediaGallerySection.tsx`
**Props**:
- `title`: "Main Project Image"
- `attachments`: current image (empty for new projects)
- `maxAttachments`: 1
- `allowedKinds`: `['image']`
- `onAddAttachment`: handler to store picked image locally
- `onRemoveAttachment`: handler to clear picked image
- `emptyStateMessage`: "Add a project image"

**Behavior**:
- For new projects, the image is stored locally during form fill
- After successful project creation (which returns a `projectId`), the image is uploaded and the project is updated with `mainImageUrl` via `updateProject()`

### Section 4: Budget Categories

A section for allocating dollar amounts to each active budget category.

#### Total Budget Display

A prominent read-only card at the top of this section showing the auto-calculated total.

- **Label**: "Total Budget"
- **Value**: Sum of all category budget amounts, formatted as currency (e.g., "$12,500.00")
- **Helper text**: "Sum of all category budgets"
- **Styling**: Uses `TitledCard` or a styled card with `getCardBaseStyle`

#### Per-Category Budget Inputs

One `CategoryBudgetInput` per active (non-archived) budget category loaded from the account.

**Component**: `CategoryBudgetInput` from `src/components/budget/CategoryBudgetInput.tsx`
**Props**: `categoryName`, `budgetCents`, `onChange`, `disabled`

**Data source**: Subscribe to account-wide budget categories via `subscribeToBudgetCategories(accountId, callback)` from `src/data/budgetCategoriesService.ts`. Filter out archived categories.

**Layout**: Single-column stack on mobile. Each input shows the category name as its label with a currency input below.

**Loading state**: Show "Loading budget categories..." while categories are being fetched.

**Empty state**: If no budget categories exist, show: "No budget categories created yet. Create categories in Budget Category Management."

### Section 5: Actions

Two buttons in a horizontal row.

| Button | Variant | Behavior |
|--------|---------|----------|
| Cancel | secondary | Navigate back |
| Create Project | primary | Validate and submit |

**Submit button states**:
- Default: "Create Project"
- Submitting: "Creating..." with loading spinner
- Disabled when: submitting, or name/clientName empty, or offline

### Submit Flow

1. Validate required fields (name, clientName)
2. Check online connectivity (create requires Cloud Function)
3. Call `createProject({ accountId, name, clientName })` — returns `{ projectId }`
4. If image was picked: upload image, then call `updateProject(accountId, projectId, { mainImageUrl })`
5. If budget amounts were set: call `setProjectBudgetCategory()` for each category
6. Navigate to `/project/${projectId}?tab=items`

---

## Edit Project Screen

**Route**: `/project/:projectId/edit`
**File**: `app/project/[projectId]/edit.tsx`
**Current state**: Minimal — only `name` and `clientName` fields

### Differences from Add Project

The edit screen uses the **same form layout** as Add Project with these differences:

| Aspect | Add Project | Edit Project |
|--------|------------|--------------|
| Screen title | "New Project" | "Edit Project" |
| Form pre-population | All fields empty | Fields loaded from existing project via `subscribeToProject()` |
| Submit button text | "Create Project" / "Creating..." | "Save" / "Saving..." |
| Image upload timing | After project creation | Immediate (projectId already exists) |
| Budget pre-population | All categories at $0.00 | Categories pre-populated from `subscribeToProjectBudgetCategories()` |
| Online requirement | Required (Cloud Function) | Not required (direct Firestore write) |
| Back target | `/(tabs)/index` | `/project/${projectId}` |
| Submit action | `createProject()` + `updateProject()` | `updateProject()` + `setProjectBudgetCategory()` |

### Data Loading

On mount, subscribe to:
1. `subscribeToProject(accountId, projectId)` — populates name, clientName, description, mainImageUrl
2. `subscribeToBudgetCategories(accountId)` — loads account-wide category list
3. `subscribeToProjectBudgetCategories(accountId, projectId)` — loads existing budget amounts

### Submit Flow

1. Validate required fields
2. Call `updateProject(accountId, projectId, { name, clientName, description })` for metadata changes
3. Handle image changes (upload new / remove existing)
4. Call `setProjectBudgetCategory()` for each modified category budget
5. Navigate to `/project/${projectId}`

---

## Project Detail Screen

**Route**: `/project/:projectId`
**File**: `src/screens/ProjectShell.tsx`
**Route wrapper**: `app/project/[projectId]/index.tsx`
**Current state**: Mostly complete — revised layout from legacy

### Screen Structure

```
┌─────────────────────────────────┐
│ Screen                          │
│  title: project.name            │
│  subtitle: project.clientName   │
│  menu: kebab → BottomSheet      │
│  pull-to-refresh: handleRefresh │
├─────────────────────────────────┤
│ Tabs: Budget│Items│Txns│Spaces  │
├─────────────────────────────────┤
│                                 │
│ [Banner Image - if exists]      │
│  140px height, 12px radius      │
│                                 │
├─────────────────────────────────┤
│                                 │
│ [Tab Content Area]              │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### Header

**Component**: `Screen` from `src/components/Screen.tsx`

- **Title**: `project.name` (trimmed, fallback "Project")
- **Subtitle**: `project.clientName` (trimmed)
- **Menu**: Kebab menu via `onPressMenu`, opens `BottomSheetMenuList`
- **Pull-to-refresh**: Refreshes project, items, transactions, spaces, budget categories

### Banner Image

Displayed at top of content area when `project.mainImageUrl` exists. Uses React Native `Image` component.

- Width: 100%
- Height: 140px
- Border radius: 12px

### Tabs

Four tabs rendered via `Screen.tabs`:

| Tab Key | Label | Content Component | Source File |
|---------|-------|-------------------|-------------|
| `budget` | Budget | `BudgetProgressDisplay` | `src/components/budget/BudgetProgressDisplay.tsx` |
| `items` | Items | `SharedItemsList` | `src/components/SharedItemsList.tsx` |
| `transactions` | Transactions | `SharedTransactionsList` | `src/components/SharedTransactionsList.tsx` |
| `spaces` | Spaces | `ProjectSpacesList` | `src/screens/ProjectSpacesList.tsx` |

Default tab: `budget` (or passed via `initialTabKey` prop)

### Budget Tab Content

**Component**: `BudgetProgressDisplay`

Shows per-category budget progress with:
- Category name, spent/budget amounts, percentage, color-coded progress bar
- Pin/unpin categories (persisted per user per project via `projectPreferencesService`)
- "Set Budget" button → navigates to `/project/${projectId}/budget` (ProjectBudgetForm)
- Category press → navigates to transactions filtered by that category

### Items Tab Content

**Component**: `SharedItemsList`

Full item list with sort, filter, search, and bulk selection. Scoped to this project.

### Transactions Tab Content

**Component**: `SharedTransactionsList`

Full transaction list with sort, filter, search. Scoped to this project.

### Spaces Tab Content

**Component**: `ProjectSpacesList` from `src/screens/ProjectSpacesList.tsx`

Grid of `SpaceCard` components showing space name, image, item count, and checklist progress.

### Kebab Menu Actions

Rendered via `BottomSheetMenuList`:

| Action | Behavior |
|--------|----------|
| Edit Project | Navigate to `/project/${projectId}/edit` |
| Export Transactions | Share CSV of project transactions |
| Delete Project | Confirmation alert → `deleteProject()` → navigate to home |

### Data Subscriptions

ProjectShell subscribes to the following real-time data sources:

| Data | Service | Hook/Function |
|------|---------|---------------|
| Project | `projectService` | `subscribeToProject()` |
| Budget categories | `budgetCategoriesService` | `subscribeToBudgetCategories()` |
| Project budget categories | `projectBudgetCategoriesService` | `subscribeToProjectBudgetCategories()` |
| Budget progress | `budgetProgressService` | `subscribeToProjectBudgetProgress()` |
| Project preferences (pins) | `projectPreferencesService` | `subscribeToProjectPreferences()` |
| Account presets | `accountPresetsService` | `subscribeToAccountPresets()` |
| Scoped items | `scopedListData` | `subscribeToScopedItems()` |
| Scoped transactions | `scopedListData` | `subscribeToScopedTransactions()` |

---

## Accounting Tab (Future)

**Status**: Not yet implemented
**Legacy reference**: `~/Dev/ledger/src/pages/ProjectLayout.tsx` (lines 409-457)

The legacy web app includes an "Accounting" tab alongside the "Budget" tab in the project header. This section documents the legacy feature for future implementation.

### Summary Cards

Two side-by-side summary cards:

| Card | Calculation | Description |
|------|-------------|-------------|
| Owed to Design Business | Sum of `amount` for non-canceled transactions where `reimbursementType === 'CLIENT_OWES_COMPANY'` | Total amount clients owe the business |
| Owed to Client | Sum of `amount` for non-canceled transactions where `reimbursementType === 'COMPANY_OWES_CLIENT'` | Total amount the business owes clients |

### Report Generation

Three action buttons for generating reports:

| Report | Icon | Route (Legacy) | Description |
|--------|------|-----------------|-------------|
| Property Management Summary | Building2 | `/project/:projectId/property-management-summary` | Summary for property managers |
| Client Summary | User | `/project/:projectId/client-summary` | Summary for clients |
| Invoice | Receipt | `/project/:projectId/invoice` | Detailed invoice with charges and credits |

### Mobile Implementation Notes

When implemented, the accounting tab could be added as a fifth tab on the `Screen` component or as a sub-tab within the budget tab. The reimbursement type fields would need to be part of the transaction data model in the mobile app.

---

## Component Reuse Map

### Add/Edit Project Form

| UI Element | Existing Component | File Path |
|-----------|-------------------|-----------|
| Page wrapper with back nav | `Screen` | `src/components/Screen.tsx` |
| Text input with label | `FormField` | `src/components/FormField.tsx` |
| Primary/secondary buttons | `AppButton` | `src/components/AppButton.tsx` |
| Image picker with preview | `MediaGallerySection` | `src/components/MediaGallerySection.tsx` |
| Currency input per category | `CategoryBudgetInput` | `src/components/budget/CategoryBudgetInput.tsx` |
| Section card wrapper | `TitledCard` | `src/components/TitledCard.tsx` |
| Themed text | `AppText` | `src/components/AppText.tsx` |
| Scroll container | `AppScrollView` | `src/components/AppScrollView.tsx` |
| Text input styling | `getTextInputStyle` | `src/ui/styles/forms.ts` |
| Card styling | `getCardBaseStyle` | `src/ui/index.ts` |

### Project Detail Screen

| UI Element | Existing Component | File Path |
|-----------|-------------------|-----------|
| Page with tabs + refresh + menu | `Screen` | `src/components/Screen.tsx` |
| Budget progress with categories | `BudgetProgressDisplay` | `src/components/budget/BudgetProgressDisplay.tsx` |
| Individual category trackers | `BudgetCategoryTracker` | `src/components/budget/BudgetCategoryTracker.tsx` |
| Items list (sort/filter/search) | `SharedItemsList` | `src/components/SharedItemsList.tsx` |
| Transactions list | `SharedTransactionsList` | `src/components/SharedTransactionsList.tsx` |
| Spaces list with cards | `ProjectSpacesList` | `src/screens/ProjectSpacesList.tsx` |
| Space card with image | `SpaceCard` | `src/components/SpaceCard.tsx` |
| Kebab menu | `BottomSheetMenuList` | `src/components/BottomSheetMenuList.tsx` |
| Compact budget on project card | `BudgetProgressPreview` | `src/components/budget/BudgetProgressPreview.tsx` |
| Loading state | `LoadingScreen` | `src/components/LoadingScreen.tsx` |
| Error state | `ErrorRetryView` | `src/components/ErrorRetryView.tsx` |

---

## Validation Rules

### Required Fields

| Field | Rule | Error Message |
|-------|------|---------------|
| Project Name | Non-empty after trim | "Project name is required" |
| Client Name | Non-empty after trim | "Client name is required" |

### Optional Fields

| Field | Constraints |
|-------|-------------|
| Description | No validation (free text) |
| Main Image | File type: JPEG, PNG, GIF, WebP. Max size: 10MB |
| Budget amounts | Non-negative. Max: $21,474,836.47 (2^31 - 1 cents). Handled by `CategoryBudgetInput` |

### Connectivity

| Screen | Requirement |
|--------|-------------|
| Add Project | Online required (uses Cloud Function via `createProject()`) |
| Edit Project | Works offline (direct Firestore write via `updateProject()`) |
| Project Detail | Works offline (all data from Firestore cache) |

---

## Implementation Targets

Files that will need to be created or modified when implementing this spec.

### Files to Modify

| File | Changes Needed |
|------|----------------|
| `app/project/new.tsx` | Expand form to include description, image, budget categories |
| `app/project/[projectId]/edit.tsx` | Expand form to include description, image, budget categories |
| `src/data/projectService.ts` | Expand `CreateProjectPayload` to include `description` |

### Potential New Files

| File | Purpose |
|------|---------|
| `src/components/ProjectForm.tsx` | Optional shared form component for add/edit (to avoid duplicating the expanded form logic) |

### Existing Files (No Changes Needed)

These files are used as-is by the screens:

| File | Used For |
|------|----------|
| `src/components/FormField.tsx` | Text inputs |
| `src/components/MediaGallerySection.tsx` | Image picker |
| `src/components/budget/CategoryBudgetInput.tsx` | Budget amount inputs |
| `src/components/AppButton.tsx` | Action buttons |
| `src/components/Screen.tsx` | Page wrapper |
| `src/components/TitledCard.tsx` | Section cards |
| `src/components/AppText.tsx` | Text display |
| `src/data/budgetCategoriesService.ts` | Load account budget categories |
| `src/data/projectBudgetCategoriesService.ts` | Load/save project budget allocations |
| `src/screens/ProjectShell.tsx` | Project detail (already implemented) |
| `src/screens/ProjectBudgetForm.tsx` | Standalone budget form (accessible from detail budget tab) |
