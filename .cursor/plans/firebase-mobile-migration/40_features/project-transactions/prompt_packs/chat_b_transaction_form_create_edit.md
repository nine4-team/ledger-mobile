# Prompt Pack — Project Transactions (Chat B: Transaction form — create + edit)

## Goal

You are helping migrate Ledger to **React Native + Firebase** with an **offline-ready** architecture baseline:
- Firestore-native offline persistence (Firestore is canonical)
- Scoped listeners (never unbounded “listen to everything”)
- Request-doc workflows for multi-doc invariants (Cloud Function applies changes atomically)

Your job in this chat:
- Produce parity specs for **creating and editing** a transaction, including metadata gating, validation, itemization enablement, and offline-aware media attachment.

## Outputs (required)

Update or create the following docs:
- `40_features/project-transactions/feature_spec.md`
- `40_features/project-transactions/acceptance_criteria.md`
- `40_features/project-transactions/ui/screens/TransactionForm.md`

If you discover a shared contract that belongs in `_cross_cutting`, put it there and link it:
- `40_features/_cross_cutting/...`

## Source-of-truth code pointers

Primary screens/components:
- `src/pages/AddTransaction.tsx`
- `src/pages/EditTransaction.tsx`
- `src/components/TransactionItemsList.tsx` (transaction itemization UI surface)
- `src/components/ui/ImageUpload.tsx`
- `src/components/ui/UploadActivityIndicator.tsx`
- `src/components/CategorySelect.tsx`
- `src/components/ui/OfflinePrerequisiteBanner.tsx`

Related services/hooks:
- `src/services/offlineMetadataService.ts` (cached vendor defaults)
- `src/services/accountPresetsService.ts` (default category online/cached)
- `src/services/offlineAwareImageService.ts`
- `src/services/offlineMediaService.ts`
- `src/hooks/useOfflineMediaTracker.ts`
- `src/utils/offlineUxFeedback.ts`
- `src/utils/hydrationHelpers.ts` (transaction + items hydration)

## What to capture (required sections)

For the form contract and acceptance criteria, include:
- Field-level validation and defaults
- Offline prerequisites gate:
  - what’s required
  - what happens when offline and prerequisites are missing
- Source/vendor selection rules and offline behavior
- Tax rules (simplified; no presets):
  - default None
  - tax rate entry and derived values
  - “calculate from subtotal” mode + validation
  - optional tax amount entry and rate back-calculation
  - hide tax inputs for non-itemized categories (no `itemize`/`itemizationEnabled` metadata)
- Itemization enablement rules (category-dependent, and “disabled but existing items” case)
- Media attachment rules:
  - receipts include PDFs; other images are images only
  - max image counts
  - placeholder behavior (`offline://`)
  - delete semantics and cleanup expectations
- Status ↔ reimbursement coupling rules on edit
- Pending/saved-offline feedback expectations

## Evidence rule (anti-hallucination)

For each non-obvious behavior:
- Provide parity evidence: “Observed in …” with file + component/function, OR
- Mark as intentional change and justify it (platform/architecture requirement).

## Constraints / non-goals
- Do not prescribe unbounded listeners; realtime uses **scoped** listeners only.
- Do not do pixel-perfect design specs.
- Focus on contracts that prevent divergence (offline gating, media, itemization).
