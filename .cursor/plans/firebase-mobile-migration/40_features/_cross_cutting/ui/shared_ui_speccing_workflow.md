## Shared UI speccing workflow (runnable playbook)

Goal: make updates to the single canonical shared UI spec (`shared_ui_contracts.md`) **reliably** across many independent AI chats.

Canonical spec (edit target): `/Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md`

Parity evidence source (read-only): `/Users/benjaminmackenzie/Dev/ledger` (the web app)

Hard rules (must follow in every chat):

- **One canonical file**: all shared UI contracts live in `shared_ui_contracts.md`.
- **Append-only headings**: do not reorder headings in `shared_ui_contracts.md` (add content under the correct existing heading).
- **Evidence rule**: for any non-obvious behavior, include a concrete file path in `/Users/benjaminmackenzie/Dev/ledger/...` OR label it **Intentional delta**.
- **Anti-fork rule**: if unsure, add an **Open question** (don’t invent a second behavior).

---

## How to run this (10 minutes to start)

Checklist:

- [ ] Pick **one** surface from “Work queue (one chat per surface)”.
- [ ] Start a **new chat** dedicated to that one surface (no mixing).
- [ ] Paste the matching prompt from “Copy/paste prompts”.
- [ ] In that chat:
  - [ ] Read the target heading in `shared_ui_contracts.md` (do not move headings).
  - [ ] Inspect the listed parity evidence files in `/Users/benjaminmackenzie/Dev/ledger/...`.
  - [ ] Update the target heading by **adding** (not rewriting) these subsections if missing:
    - **Intent**
    - **Contract**
    - **Parity evidence pointers**
    - **Open questions**
  - [ ] Every non-obvious rule has either:
    - [ ] a cited web path, or
    - [ ] “Intentional delta” with a reason.
- [ ] Produce output as a **ready-to-apply patch** or a clearly delimited “paste into this exact heading” block.

What the chat should NOT do:

- Do not create new files.
- Do not add per-component docs.
- Do not “solve” uncertainties by guessing—add an Open question.

---

## Work queue (one chat per surface)

One row = one chat. The “Surface/section name” and “Output location” must match headings in `shared_ui_contracts.md` exactly.

| Surface/section name | What the chat must add | Parity evidence targets to inspect (web, read-only) | Output location (exact heading) | Definition of done |
| --- | --- | --- | --- | --- |
| List controls + control bar (search/filter/sort/group + state restore) | - Canonical control bar responsibilities + boundaries<br>- State persistence + restore contract (what’s persisted; keying)<br>- Empty/loading/“no results” semantics for controls<br>- Intentional deltas for mobile (if any) | - `/Users/benjaminmackenzie/Dev/ledger/src/pages/InventoryList.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/pages/TransactionsList.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/pages/BusinessInventory.tsx` | `## List controls + control bar (search/filter/sort/group + state restore)` | - [ ] Intent/Contract/Parity/Open questions present<br>- [ ] Non-obvious rules cite web paths or “Intentional delta”<br>- [ ] No new headings/reorders |
| Selection + bulk actions | - Selection model (single vs multi; clear vs persist)<br>- Bulk actions lifecycle + error semantics<br>- “Select all” semantics (or Open question)<br>- Disable/tooltip patterns for unavailable actions | - `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/BulkItemControls.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/TransactionItemsList.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/pages/InventoryList.tsx` | `## Selection + bulk actions` | - [ ] Contract describes lifecycle + failure behavior<br>- [ ] Parity pointers added for each key behavior<br>- [ ] Open questions captured (no guessing) |
| Action menus + action registry | - Canonical “…” menu behaviors (open/close, outside click, Escape)<br>- Disabled reasons + gating semantics (scope/state)<br>- Define “registry” contract (Intentional delta if web is per-entity menus)<br>- Alignment with bulk actions (shared action definitions) | - `/Users/benjaminmackenzie/Dev/ledger/src/components/items/ItemActionsMenu.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/transactions/TransactionActionsMenu.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/BulkItemControls.tsx` | `## Action menus + action registry` | - [ ] Contract includes close semantics + disabled reasons<br>- [ ] “Registry” described as contract + where it lives (or Open question)<br>- [ ] Any “registry” claim labeled Intentional delta if not in web |
| Pickers (space/transaction/category) conventions | - Search fields + matching behavior conventions<br>- Empty state conventions (no results vs no data)<br>- “Create new” affordance rules (or Intentional delta)<br>- Disabled/offline gating semantics | - `/Users/benjaminmackenzie/Dev/ledger/src/components/spaces/SpaceSelector.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/CategorySelect.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/transactions/TransactionItemPicker.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/spaces/SpaceItemPicker.tsx` | `## Pickers (space/transaction/category) conventions` | - [ ] Contract specifies consistent picker UX primitives<br>- [ ] Evidence pointers cover each picker type<br>- [ ] Any missing behavior is an Open question |
| Global messaging (toast/confirm/banner) | - Toast API surface (show/hide, stacking, durations)<br>- Confirm dialog contract incl “Working…” state + a11y minimums<br>- Banner conventions (when banner vs toast) | - `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/ToastContext.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/Toast.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/BlockingConfirmDialog.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/StorageQuotaWarning.tsx` | `## Global messaging (toast/confirm/banner)` | - [ ] Contract includes API + defaults (with evidence)<br>- [ ] A11y expectations listed (or Intentional delta)<br>- [ ] No feature-specific copy/one-offs |
| Offline + pending + error UI semantics | - Canonical state machine for mutation UI (ready/pending/offline/failed)<br>- Retry affordances and error copy conventions<br>- Where to show status (row badge? banner? toast?) | - `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/RetrySyncButton.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/BackgroundSyncErrorNotifier.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/hooks/useNetworkState.ts`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/utils/offlineUxFeedback.ts` | `## Offline + pending + error UI semantics` | - [ ] Contract is explicit about failure + retry<br>- [ ] Evidence pointers for each non-obvious claim<br>- [ ] Clear guidance on when toast vs banner vs inline |
| Media UI surfaces (upload/preview/gallery + quota guardrails) | - Upload/preview/gallery contracts + key interactions<br>- Quota thresholds + cadence + gating rules<br>- Offline preview resolution rules | - `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/ImageUpload.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/ImagePreview.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/ImageGallery.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/StorageQuotaWarning.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/services/offlineAwareImageService.ts` | `## Media UI surfaces (upload/preview/gallery + quota guardrails)` | - [ ] Non-obvious gestures/keys listed with evidence<br>- [ ] Quota semantics documented + labeled deltas if mobile differs<br>- [ ] Open questions added for RN-specific gaps |
| Navigation + “return to list” + scroll restoration (UI-owned parts) | - Contract for list-owned persistence vs nav-owned history<br>- Restore hint contract (anchorId/offset; clearing behavior)<br>- Intentional deltas (Expo Router differences) | - `/Users/benjaminmackenzie/Dev/ledger/src/contexts/NavigationStackContext.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/hooks/useStackedNavigate.ts`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/hooks/useNavigationContext.ts`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/pages/InventoryList.tsx` | `## Navigation + “return to list” + scroll restoration (UI-owned parts)` | - [ ] Restore contract is precise and testable<br>- [ ] Explicit “who owns what” (UI vs navigation)<br>- [ ] Evidence pointers included |
| Performance + large-list constraints (UI-visible implications) | - Define UI-visible constraints (virtualization assumptions, “select all” limits)<br>- Define “large N” targets (or Open question) | - `/Users/benjaminmackenzie/Dev/ledger/src/pages/InventoryList.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/pages/TransactionsList.tsx` | `## Performance + large-list constraints (UI-visible implications)` | - [ ] Constraints are user-visible and actionable<br>- [ ] Any numbers are evidenced or an Open question |
| Accessibility + keyboard rules (cross-cutting minimums) | - Dialog/menu keyboard rules (Escape, focus)<br>- Minimum aria semantics parity (or Intentional delta for RN) | - `/Users/benjaminmackenzie/Dev/ledger/src/components/ui/BlockingConfirmDialog.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/items/ItemActionsMenu.tsx`<br>- `/Users/benjaminmackenzie/Dev/ledger/src/components/transactions/TransactionActionsMenu.tsx` | `## Accessibility + keyboard rules (cross-cutting minimums)` | - [ ] Minimums are explicit and small<br>- [ ] Any web-only a11y is labeled Intentional delta for RN |

---

## Copy/paste prompts

Use **one prompt per chat**. Each prompt tells the chat exactly what to update and exactly which web files to inspect.

### List controls + control bar (search/filter/sort/group + state restore)

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in the canonical shared UI spec:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## List controls + control bar (search/filter/sort/group + state restore)"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect (read-only web app):
- /Users/benjaminmackenzie/Dev/ledger/src/pages/InventoryList.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/pages/TransactionsList.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/pages/BusinessInventory.tsx

In the target heading, ensure these subsections exist and are populated:
- Intent
- Contract (make it testable: persistence keys, restore behavior, control visibility, empty/loading semantics)
- Parity evidence pointers (bullet list of the above files + what they prove)
- Open questions (anything uncertain)

Output: provide a patch or a clearly delimited block that can be pasted under the exact heading.
```

### Selection + bulk actions

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## Selection + bulk actions"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect:
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/BulkItemControls.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/TransactionItemsList.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/pages/InventoryList.tsx

Required subsections to add/populate under the heading:
- Intent
- Contract (visibility, placement, lifecycle, failure handling, selection clearing rules, “select all” semantics or Open question)
- Parity evidence pointers
- Open questions

Output: a patch or paste-ready block targeting ONLY that heading.
```

### Action menus + action registry

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## Action menus + action registry"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect:
- /Users/benjaminmackenzie/Dev/ledger/src/components/items/ItemActionsMenu.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/transactions/TransactionActionsMenu.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/BulkItemControls.tsx

Required subsections under the heading:
- Intent
- Contract (menu open/close triggers, outside click, Escape, disabled reasons tooltips/titles, submenu behavior, alignment with bulk actions)
- Parity evidence pointers (cite exact functions/handlers if relevant)
- Open questions

Also: if you define an “action registry” concept that is NOT present in the web code, label it explicitly as:
- Intentional delta: unify actions into a single registry in mobile to prevent drift.

Output: a patch or paste-ready block targeting ONLY that heading.
```

### Pickers (space/transaction/category) conventions

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## Pickers (space/transaction/category) conventions"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect:
- /Users/benjaminmackenzie/Dev/ledger/src/components/spaces/SpaceSelector.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/spaces/SpaceItemPicker.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/CategorySelect.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/transactions/TransactionItemPicker.tsx

Required subsections:
- Intent
- Contract (search fields, matching, empty states, create-from-picker rules, disabled/offline gating)
- Parity evidence pointers
- Open questions

Output: patch or paste-ready block under ONLY that heading.
```

### Global messaging (toast/confirm/banner)

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## Global messaging (toast/confirm/banner)"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect:
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/ToastContext.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/Toast.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/BlockingConfirmDialog.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/StorageQuotaWarning.tsx

Required subsections:
- Intent
- Contract (toast API + defaults; confirm dialog lifecycle + “Working…”; banner usage conventions)
- Parity evidence pointers
- Open questions (including RN placement/a11y deltas if uncertain)

Output: patch or paste-ready block under ONLY that heading.
```

### Offline + pending + error UI semantics

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## Offline + pending + error UI semantics"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect:
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/RetrySyncButton.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/BackgroundSyncErrorNotifier.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/hooks/useNetworkState.ts
- /Users/benjaminmackenzie/Dev/ledger/src/utils/offlineUxFeedback.ts

Required subsections:
- Intent
- Contract (explicit UI states; retry surfaces; where to show error vs status; copy conventions if present)
- Parity evidence pointers
- Open questions

Output: patch or paste-ready block under ONLY that heading.
```

### Media UI surfaces (upload/preview/gallery + quota guardrails)

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## Media UI surfaces (upload/preview/gallery + quota guardrails)"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect:
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/ImageUpload.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/ImagePreview.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/ImageGallery.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/StorageQuotaWarning.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/services/offlineAwareImageService.ts

Required subsections:
- Intent
- Contract (upload/preview/gallery behaviors; gestures/keys; quota thresholds + gating; offline preview resolution)
- Parity evidence pointers (cite the exact file(s) and what they prove)
- Open questions (RN-specific unknowns, platform deltas)

Output: patch or paste-ready block under ONLY that heading.
```

### Navigation + “return to list” + scroll restoration (UI-owned parts)

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## Navigation + “return to list” + scroll restoration (UI-owned parts)"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect:
- /Users/benjaminmackenzie/Dev/ledger/src/contexts/NavigationStackContext.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/hooks/useStackedNavigate.ts
- /Users/benjaminmackenzie/Dev/ledger/src/hooks/useNavigationContext.ts
- /Users/benjaminmackenzie/Dev/ledger/src/pages/InventoryList.tsx

Required subsections:
- Intent
- Contract (what UI owns vs nav owns; restore hint contract; clearing semantics; Expo Router deltas if needed)
- Parity evidence pointers
- Open questions

Output: patch or paste-ready block under ONLY that heading.
```

### Performance + large-list constraints (UI-visible implications)

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## Performance + large-list constraints (UI-visible implications)"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect:
- /Users/benjaminmackenzie/Dev/ledger/src/pages/InventoryList.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/pages/TransactionsList.tsx

Required subsections:
- Intent
- Contract (only user-visible implications; any “large N” numbers must be evidenced or an Open question)
- Parity evidence pointers
- Open questions

Output: patch or paste-ready block under ONLY that heading.
```

### Accessibility + keyboard rules (cross-cutting minimums)

```text
You are an AI dev working in /Users/benjaminmackenzie/Dev/ledger_mobile.

Task: Update ONLY this exact heading in:
- /Users/benjaminmackenzie/Dev/ledger_mobile/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/shared_ui_contracts.md
- Heading: "## Accessibility + keyboard rules (cross-cutting minimums)"

Hard rules:
- Append-only under that heading (do not reorder headings).
- Non-obvious behavior must cite an exact web parity file path in /Users/benjaminmackenzie/Dev/ledger/... OR be labeled "Intentional delta".

Parity evidence files to inspect:
- /Users/benjaminmackenzie/Dev/ledger/src/components/ui/BlockingConfirmDialog.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/items/ItemActionsMenu.tsx
- /Users/benjaminmackenzie/Dev/ledger/src/components/transactions/TransactionActionsMenu.tsx

Required subsections:
- Intent
- Contract (minimums only: keyboard close, focus expectations, parity vs RN deltas labeled)
- Parity evidence pointers
- Open questions

Output: patch or paste-ready block under ONLY that heading.
```

---

## Anti-drift rules (enforcement)

Review rules (apply in PR review and spec review):

- **No redefinition in feature specs**:
  - Feature specs under `40_features/**` must reference `shared_ui_contracts.md` for shared UI surfaces.
  - If a feature spec needs to describe shared UI behavior, it must instead:
    - link to the exact heading in `shared_ui_contracts.md`, and
    - specify only feature wiring (data fields, routes, permissions), not UI semantics.
- **Disagreements don’t fork**:
  - If two chats/specs disagree on behavior, do not invent two variants.
  - Add an **Open question** under the relevant heading, with:
    - the conflicting interpretations,
    - parity evidence pointers (or “Intentional delta” options),
    - and what decision is required.
- **What counts as “shared enough” to belong here**:
  - Belongs in `shared_ui_contracts.md` if it is:
    - used across 2+ features, OR
    - a cross-cutting trust surface (offline/pending/error), OR
    - a consistency surface users notice (menus, pickers, global messaging), OR
    - a behavior that must remain aligned across scopes (project vs inventory).
  - Does NOT belong here if it is:
    - a single-screen layout choice,
    - purely visual styling already covered by `src/ui/**`,
    - feature-specific copy that doesn’t generalize.

Enforcement checklist for reviewers:

- [ ] New/updated feature specs reference the correct shared UI heading(s) instead of restating behavior.
- [ ] Any new shared UI behavior is added to `shared_ui_contracts.md` (not in feature specs).
- [ ] Any non-obvious shared UI behavior includes parity evidence pointers or is labeled “Intentional delta”.

