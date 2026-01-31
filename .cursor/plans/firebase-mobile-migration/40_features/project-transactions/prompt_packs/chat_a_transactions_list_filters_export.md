# Prompt Pack — Project Transactions (Chat A: Transactions list + filters + export)

## Goal

You are helping migrate Ledger to **React Native + Firebase** with an **offline-ready** architecture baseline:
- Firestore-native offline persistence (Firestore is canonical)
- Scoped listeners (never unbounded “listen to everything”)
- Request-doc workflows for multi-doc invariants (Cloud Function applies changes atomically)

Your job in this chat:
- Produce parity-grade specs for the **project transactions list** (search/filter/sort/state persistence/scroll restoration + CSV export).

## Outputs (required)

Update or create the following docs:
- `40_features/project-transactions/feature_spec.md`
- `40_features/project-transactions/acceptance_criteria.md`
- `40_features/project-transactions/ui/screens/TransactionsList.md`

If you discover a shared contract that belongs in `_cross_cutting`, put it there and link it:
- `40_features/_cross_cutting/...`

## Source-of-truth code pointers

Primary screens/components:
- `src/pages/ProjectTransactionsPage.tsx`
- `src/pages/TransactionsList.tsx`

Related services/hooks:
- Web parity navigation helpers (evidence only; not the mobile mechanism):
  - `src/hooks/useStackedNavigate.ts`
  - `src/hooks/useNavigationContext.ts`
  - `src/contexts/NavigationStackContext.tsx`
  - `src/utils/navigationReturnTo.ts`
- `src/utils/hydrationHelpers.ts` (transactions cache hydration)
- `src/services/inventoryService.ts` (transaction service + canonical id helpers)

## What to capture (required sections)

For the list contract and acceptance criteria, include:
- Owned routes/entrypoints (project + business inventory scopes; shared Transactions module component configured by scope)
- List controls:
  - search match rules
  - filter modes (including nested submenu behavior)
  - sort modes
  - state persistence + restoration rules (mobile: `ListStateStore[listStateKey]`)
  - scroll restoration rules (mobile: anchor-first restore; optional offset fallback)
- CSV export:
  - columns
  - filename rules
  - mobile share adaptation
- Canonical transaction behaviors:
  - display title mapping
  - computed totals and any self-heal behavior (explicitly call out whether it is retained on mobile)
- Offline behavior:
  - renders from Firestore cache offline (and converges when online)
  - handling stale/partial metadata (category names)
- Collaboration needs:
  - scoped listener expectations; no unbounded listeners
- Error/empty/loading states

## Evidence rule (anti-hallucination)

For each non-obvious behavior:
- Provide parity evidence: “Observed in …” with file + component/function, OR
- Mark as intentional change and justify it (platform/architecture requirement).

## Constraints / non-goals
- Do not prescribe unbounded listeners; realtime must use **scoped** listeners only.
- Do not do pixel-perfect design specs.
- Focus on behaviors where multiple implementations would diverge.

## Mobile navigation note (Expo Router; required)

The new app uses **Expo Router** (React Navigation). Therefore:

- Do not specify a custom global navigation stack as the primary mechanism for Back.
- Do specify that the shared Transactions list module owns list state + scroll restoration, keyed by:
  - `listStateKey = project:${projectId}:transactions` (project scope)
  - `listStateKey = inventory:transactions` (inventory scope)
- Required restoration UX: when opening a transaction from the list, record `anchorId = transactionId` so Back restores to that row best-effort.
