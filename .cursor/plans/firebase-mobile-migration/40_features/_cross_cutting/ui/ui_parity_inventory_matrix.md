# UI parity inventory matrix (web → mobile)

This matrix tracks **shared UI surfaces** that require parity with the web app.
Use it to locate evidence, assign ownership, and identify gaps without guessing.

Status legend: **Not started** | **Partial** | **Done** | **Intentional delta** | **Open question**

| Surface | Parity evidence pointer(s) | Spec owner (canonical) | Mobile target (placeholder) | Status | Notes / deltas |
| --- | --- | --- | --- | --- | --- |
| Empty / loading / error state semantics (lists + detail + forms) | `ledger/src/pages/InventoryList.tsx`; `ledger/src/pages/TransactionsList.tsx`; `ledger/src/pages/BusinessInventory.tsx`; `ledger/src/pages/ProjectSpacesPage.tsx`; `ledger/src/components/TransactionItemForm.tsx` | `shared_ui_contracts.md` → “Empty / loading / error state semantics (lists + detail + forms)” | `src/components/ui/EmptyState.tsx` (new); `src/components/LoadingScreen.tsx` (existing) | Open question | Confirm consistent “no data” vs “no results” copy across mobile lists. |
| Offline prerequisite gating UI | `ledger/src/components/ui/OfflinePrerequisiteBanner.tsx`; `ledger/src/components/TransactionItemForm.tsx`; `ledger/src/pages/AddTransaction.tsx`; `ledger/src/components/ProjectForm.tsx` | `shared_ui_contracts.md` → “Offline prerequisite gating UI (banner placement + retry affordance)” | `src/components/ui/OfflinePrerequisiteBanner.tsx` (new) | Not started | Web banner currently logs + returns `null`; confirm desired mobile UX. |
| Loading spinner / skeleton conventions | `ledger/src/components/ui/LoadingSpinner.tsx`; `ledger/src/App.tsx`; `ledger/src/pages/ImportAmazonInvoice.tsx`; `ledger/src/pages/ImportWayfairInvoice.tsx` | `shared_ui_contracts.md` → “Loading spinner / skeleton conventions (shared)” | `src/components/ui/LoadingSpinner.tsx` (new) | Not started | Identify any web skeleton patterns beyond `BudgetProgress`. |
| Access denied / no access surfaces | `ledger/src/pages/AddItem.tsx`; `ledger/src/pages/EditItem.tsx`; `ledger/src/pages/AddTransaction.tsx`; `ledger/src/pages/ImportAmazonInvoice.tsx`; `ledger/src/pages/ImportWayfairInvoice.tsx`; `ledger/src/components/auth/UserManagement.tsx` | `shared_ui_contracts.md` → “Access denied / no access surfaces (consistent gating UX)” | `src/components/ui/AccessDenied.tsx` (new) | Open question | Decide on mobile-safe navigation action (“Back” vs “Close”). |
| Duplicate grouping UI semantics | `ledger/src/components/ui/CollapsedDuplicateGroup.tsx`; `ledger/src/pages/InventoryList.tsx`; `ledger/src/pages/BusinessInventory.tsx`; `ledger/src/components/TransactionItemsList.tsx` | `shared_ui_contracts.md` → “Duplicate grouping UI semantics (collapsed groups + counts + interactions)” | `src/components/ui/CollapsedDuplicateGroup.tsx` (new) | Not started | Confirm if grouping applies to Transactions in v1 mobile parity. |
| GroupedItemCard (summary + expanded rows) | `ledger/src/components/ui/CollapsedDuplicateGroup.tsx`; `ledger/src/pages/InventoryList.tsx`; `ledger/src/pages/BusinessInventory.tsx` | `shared_ui_contracts.md` → “GroupedItemCard (collapsed + expanded summary)” | `src/components/GroupedItemListCard.tsx` (existing) | Partial | Component started; align usage with grouped list semantics. |
| Global messaging (toast / confirm / banners) | `ledger/src/components/ui/ToastContext.tsx`; `ledger/src/components/ui/Toast.tsx`; `ledger/src/components/ui/BlockingConfirmDialog.tsx`; `ledger/src/components/NetworkStatus.tsx`; `ledger/src/components/SyncStatus.tsx` | `shared_ui_contracts.md` → “Global messaging (toast/confirm/banner)” | `src/components/ui/Toast.tsx` (new); `src/components/ui/ConfirmDialog.tsx` (new) | Partial | Banner placement should align with offline + sync status contracts. |
| Sync health + network status indicators | `ledger/src/components/NetworkStatus.tsx`; `ledger/src/components/SyncStatus.tsx`; `ledger/src/components/BackgroundSyncErrorNotifier.tsx` | `shared_ui_contracts.md` → “Sync health + network status indicators (banner + background errors)” | `src/components/ui/SyncStatus.tsx` (new) | Not started | Determine if mobile should consolidate into a single status surface. |
| Upload activity indicator | `ledger/src/components/ui/UploadActivityIndicator.tsx` | `shared_ui_contracts.md` → “Upload activity indicator (queued uploads + progress)” | `src/components/ui/UploadActivityIndicator.tsx` (new) | Not started | Decide if indicator is global or per-screen. |
| Media UI surfaces (upload / preview / gallery / quota) | `ledger/src/components/ui/ImageUpload.tsx`; `ledger/src/components/ui/ImagePreview.tsx`; `ledger/src/components/ui/ImageGallery.tsx`; `ledger/src/components/ui/StorageQuotaWarning.tsx`; `ledger/src/components/ui/UploadActivityIndicator.tsx` | `shared_ui_contracts.md` → “Media UI surfaces (upload/preview/gallery + quota guardrails)” | `src/components/ui/ImageUpload.tsx` (new); `src/components/ui/ImageGallery.tsx` (new) | Not started | Preserve 80%/90% quota thresholds; confirm platform storage accounting. |
| Pickers (space / transaction / category) conventions | `ledger/src/components/spaces/SpaceSelector.tsx`; `ledger/src/components/CategorySelect.tsx`; `ledger/src/components/transactions/TransactionItemPicker.tsx`; `ledger/src/components/spaces/SpaceItemPicker.tsx` | `shared_ui_contracts.md` → “Pickers (space/transaction/category) conventions” | `src/components/ui/Pickers/` (new) | Open question | **Non-negotiable**: Space + Transaction “add existing items” must reuse the same shared picker component (mode/config), not forked copies. Confirm “create from picker” affordances for mobile. |
| ItemCard semantics | `ledger/src/components/items/ItemPreviewCard.tsx` | `shared_ui_contracts.md` → “ItemCard (shared card semantics)” | `src/components/ItemPreviewCard.tsx` (existing; exports `ItemCard`) | Partial | Component exists; may need polish for parity. |
# UI parity inventory matrix (web → mobile)

Goal: reduce “UI parity anxiety” by making **shared UI surfaces** explicit and trackable:

- what exists in the web app
- where it is specified *now* (canonical owner)
- where it should live in the mobile app (target placeholder)
- what’s missing / intentionally different

**Rules**

- **Do not invent parity evidence pointers**. Only use pointers already cited in existing migration docs; otherwise mark **Open question**.
- **Canonical shared UI contracts live in**: `shared_ui_contracts.md`.
- If a surface is screen-specific (not shared), its canonical owner is the **screen contract** or **feature acceptance criteria**, not `shared_ui_contracts.md`.

---

## Inventory matrix (checklist)

Status values: **Not started** / **Partial** / **Done** / **Intentional delta** / **Open question**

| Surface | Parity evidence pointer(s) (web, as available) | Spec owner (canonical) | Mobile target (placeholder) | Status | Notes / deltas |
|---|---|---|---|---|---|
| Toast system | `ledger/src/components/ui/ToastContext.tsx`, `ledger/src/components/ui/Toast.tsx` | `shared_ui_contracts.md` → “Global messaging (toast/confirm/banner)” | `src/ui/feedback/Toast*` | Not started | Placement differs on mobile; behavior contract should still be consistent. |
| Blocking confirm dialog | `ledger/src/components/ui/BlockingConfirmDialog.tsx` | `shared_ui_contracts.md` → “Global messaging (toast/confirm/banner)” | `src/ui/feedback/BlockingConfirmDialog*` | Not started | Ensure “Working…” disabled state parity. |
| Retry sync affordance | `ledger/src/components/ui/RetrySyncButton.tsx` | `shared_ui_contracts.md` → “Offline + pending + error UI semantics” | `src/ui/sync/RetrySyncButton*` | Not started | Needs consistent placement rules (see also Offline prerequisite gating). |
| Offline prerequisite banner (gating) | `ledger/src/components/ui/OfflinePrerequisiteBanner.tsx` | `shared_ui_contracts.md` → “Offline prerequisite gating UI (banner placement + retry affordance)” | `src/ui/offline/OfflinePrerequisiteBanner*` | Open question | Web component currently returns `null` (logs only); parity behavior + copy are Open question. |
| Loading spinner (shared) | `ledger/src/components/ui/LoadingSpinner.tsx` | `shared_ui_contracts.md` → “Loading spinner / skeleton conventions (shared)” | `src/ui/loading/LoadingSpinner*` | Not started | Must avoid jank on large lists; define delay + skeleton vs spinner rules. |
| Skeletons (lists, cards) | `ledger/src/components/ui/BudgetProgress.tsx` (animate-pulse skeleton) | `shared_ui_contracts.md` → “Loading spinner / skeleton conventions (shared)” | `src/ui/loading/*Skeleton*` | Open question | Web has at least one skeleton pattern; decide whether to standardize for lists. |
| Empty state: “no data yet” vs “no results” | `ledger/src/pages/InventoryList.tsx`, `ledger/src/pages/TransactionsList.tsx`, `ledger/src/pages/BusinessInventory.tsx`, `ledger/src/pages/ProjectSpacesPage.tsx` | `shared_ui_contracts.md` → “Empty / loading / error state semantics (lists + detail + forms)” + screen contracts where copy differs | `src/ui/states/EmptyState*` + screen-owned copy | Open question | Contract defines semantics + CTA affordances (clear filters / create new) without hardcoding copy. |
| Error state (list fetch / detail load) | `ledger/src/components/BudgetCategoriesManager.tsx`, `ledger/src/components/TransactionItemsList.tsx` | `shared_ui_contracts.md` → “Empty / loading / error state semantics (lists + detail + forms)” | `src/ui/states/ErrorState*` | Open question | Needs retry rules, offline-aware messaging alignment with sync UX. |
| Inline form error semantics (validation vs server) | `ledger/src/components/TransactionItemForm.tsx` | `shared_ui_contracts.md` → “Empty / loading / error state semantics (lists + detail + forms)” + feature acceptance criteria | `src/ui/forms/FormError*` | Open question | Don’t guess copy; define where errors appear + when to block submit. |
| Access denied / no access gate | `ledger/src/pages/EditItem.tsx`, `ledger/src/pages/AddItem.tsx`, `ledger/src/pages/ImportAmazonInvoice.tsx`, `ledger/src/pages/ImportWayfairInvoice.tsx` | `shared_ui_contracts.md` → “Access denied / no access surfaces (consistent gating UX)” + permissions specs | `src/ui/states/AccessDenied*` | Open question | Needs consistent “why / what next” UX and navigation affordance. |
| Collapsed duplicate group (grouping UI) | `ledger/src/components/ui/CollapsedDuplicateGroup.tsx` | `shared_ui_contracts.md` → “Duplicate grouping UI semantics (collapsed groups + counts + interactions)” | `src/ui/lists/CollapsedDuplicateGroup*` | Not started | Decide whether this is truly shared (Items + Transactions) or owned by one module. |
| ItemCard | `ledger/src/components/items/ItemPreviewCard.tsx` | `shared_ui_contracts.md` → “ItemCard (shared card semantics)” | `src/components/ItemPreviewCard.tsx` | Partial | Implemented in RN; component may need polish for parity. |
| GroupedItemCard (summary + expanded rows) | `ledger/src/components/ui/CollapsedDuplicateGroup.tsx`, `ledger/src/pages/InventoryList.tsx`, `ledger/src/pages/BusinessInventory.tsx` | `shared_ui_contracts.md` → “GroupedItemCard (collapsed + expanded summary)” | `src/components/GroupedItemListCard.tsx` | Partial | Component started; align usage with grouped list semantics. |
| Duplicate quantity controls | `ledger/src/components/ui/DuplicateQuantityMenu.tsx`, `ledger/src/components/ui/QuantityPill.tsx` | Feature-owned unless reused across multiple modules | `src/ui/lists/DuplicateQuantityMenu*`, `src/ui/lists/QuantityPill*` | Open question | Might become shared if multiple modules need it; otherwise leave in owning feature spec. |
| Image upload | `ledger/src/components/ui/ImageUpload.tsx`, `ledger/src/services/offlineAwareImageService.ts` | `shared_ui_contracts.md` → “Media UI surfaces (upload/preview/gallery + quota guardrails)” | `src/ui/media/ImageUpload*` | Not started | Contract already exists; ensure RN implementation matches offline gating + quota semantics. |
| Image preview | `ledger/src/components/ui/ImagePreview.tsx` | `shared_ui_contracts.md` → “Media UI surfaces (upload/preview/gallery + quota guardrails)” | `src/ui/media/ImagePreview*` | Not started | Offline `offline://` resolution parity cited in contracts. |
| Image gallery / lightbox | `ledger/src/components/ui/ImageGallery.tsx` | `shared_ui_contracts.md` → “Media UI surfaces (upload/preview/gallery + quota guardrails)” | `src/ui/media/ImageGallery*` | Not started | Web keyboard semantics will need mobile-friendly equivalents (intentional deltas). |
| Storage quota warning banner | `ledger/src/components/ui/StorageQuotaWarning.tsx` | `shared_ui_contracts.md` → “Media UI surfaces (upload/preview/gallery + quota guardrails)” | `src/ui/media/StorageQuotaWarning*` | Not started | Dismissal + thresholds are already specified. |
| Upload activity indicator | `ledger/src/components/ui/UploadActivityIndicator.tsx` | Open question (shared vs feature-owned) | `src/ui/media/UploadActivityIndicator*` | Open question | If used only inside media module, don’t make it cross-cutting. |
| Button (UI kit) | `ledger/src/components/ui/Button.tsx` | UI kit (`src/ui/kit.ts`), not a contract unless semantics are shared | `src/ui/kit.ts` re-export | Intentional delta | Prefer RN-native button patterns; shared behavior should be minimal and design-token driven. |
| Select (UI kit) | `ledger/src/components/ui/Select.tsx` | UI kit (`src/ui/kit.ts`), not a contract unless semantics are shared | `src/ui/kit.ts` re-export | Intentional delta | Web control semantics may not map 1:1 to RN; avoid contract unless parity-critical. |
| Combobox (UI kit) | `ledger/src/components/ui/Combobox.tsx` (empty-result copy: “Nothing found.”) | UI kit (`src/ui/kit.ts`), not a contract unless semantics are shared | `src/ui/kit.ts` re-export | Open question | Decide if “no results” copy should be standardized across pickers. |
| Budget progress | `ledger/src/components/ui/BudgetProgress.tsx` | Feature acceptance criteria (billing/entitlements) | `src/features/billing/BudgetProgress*` | Open question | Feature-owned unless reused across multiple modules. |
| Transaction audit | `ledger/src/components/ui/TransactionAudit.tsx` | Transactions feature spec | `src/features/transactions/TransactionAudit*` | Open question | Likely feature-owned; include in shared UI only if reused. |
| Transaction item outside search | `ledger/src/components/ui/TransactionItemOutsideSearch.tsx` | Transactions + Items module spec | `src/features/transactions/TransactionItemOutsideSearch*` | Open question | Clarify if this is shared across modules or list-owned. |
| Item lineage breadcrumb | `ledger/src/components/ui/ItemLineageBreadcrumb.tsx` | Inventory operations / lineage spec | `src/features/inventory/ItemLineageBreadcrumb*` | Open question | Feature-owned unless reused across multiple modules. |
| Speech mic button (dictation) | `ledger/src/components/ui/SpeechMicButton.tsx` | Dictation feature spec | `src/features/dictation/SpeechMicButton*` | Open question | Feature-owned unless reused across multiple modules. |
| Network status banner | `ledger/src/components/NetworkStatus.tsx` | Connectivity/sync status spec | `src/features/sync/NetworkStatus*` | Open question | Related to global messaging but owned by sync feature. |
| Sync status banner | `ledger/src/components/SyncStatus.tsx` | Connectivity/sync status spec | `src/features/sync/SyncStatus*` | Open question | Related to global messaging but owned by sync feature. |
| Background sync error notifier | `ledger/src/components/BackgroundSyncErrorNotifier.tsx` | Connectivity/sync status spec | `src/features/sync/BackgroundSyncErrorNotifier*` | Open question | Confirm whether mobile needs equivalent surface or toast-only. |
| Conflict modal | `ledger/src/components/ConflictModal.tsx` | Conflicts feature spec | `src/features/conflicts/ConflictModal*` | Open question | Determine if mobile uses a full-screen flow vs modal. |
| Conflict resolution view | `ledger/src/components/ConflictResolutionView.tsx` | Conflicts feature spec | `src/features/conflicts/ConflictResolutionView*` | Open question | Parity-critical for offline conflict UX. |
| Context link | `ledger/src/components/ContextLink.tsx` | Navigation stack / context links spec | `src/features/navigation/ContextLink*` | Open question | Likely RN navigation affordance; map to deep-link UX. |
| Context back link | `ledger/src/components/ContextBackLink.tsx` | Navigation stack / context links spec | `src/features/navigation/ContextBackLink*` | Open question | RN back affordance likely replaces; confirm required parity. |

---

## Open questions (explicit backlog)

- What is the canonical web parity evidence for **skeletons** (if any) that we want to replicate, vs using a mobile-native convention?
- Do we need a shared, explicit **ErrorState** component (with retry/offline detection), or can screens own this while adhering to contract semantics?
- What are the web sources of truth for **AccessDenied / NoAccess** UX (copy + actions)? (Not yet cited in current migration docs.)
- Is **duplicate grouping** a shared surface across multiple modules in v1 mobile parity, or only for one list?

