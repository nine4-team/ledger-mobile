# Prompt Pack Template (Multi‑Chat AI Dev Workflow)

Copy/paste this at the start of any AI dev chat so the dev can work **without prior conversation context**.

---

## Goal

You are helping migrate Ledger to **React Native + Firebase** with the **Offline Data v2** architecture (see `OFFLINE_FIRST_V2_SPEC.md`):
- Firestore-native offline persistence is the baseline (Firestore is canonical)
- Scoped listeners are allowed (no unbounded “listen to everything”)
- Multi-doc correctness uses **request-doc workflows** (Cloud Function applies changes in a transaction)
- SQLite is allowed only as an **optional derived search index** (index-only), if robust offline item search is required

Your job in this chat:
- **Produce parity specs** grounded in the existing codebase (web) so an implementation team can reproduce behavior with the new architecture.

---

## Outputs (required)

Update or create the following docs:
- `40_features/<feature>/README.md`
- `40_features/<feature>/feature_spec.md`
- `40_features/<feature>/acceptance_criteria.md`

If (and only if) ambiguity exists, also produce:
- `40_features/<feature>/ui/screens/<screen>.md` (screen contracts)
- `40_features/<feature>/flows/<flow>.md` (multi-screen flows)
- `40_features/<feature>/data/*.md` (data/rules/indexes notes)

If the behavior is shared across multiple features, put it under:
- `40_features/_cross_cutting/...` and link to it from feature docs.

---

## Source-of-truth code pointers

Use these as the canonical references for parity.

**Primary screens/components:**
- <paste file paths here>

**Related services/hooks:**
- <paste file paths here>

---

## What to capture (required sections)

For each feature or screen contract, include:
- **Owned screens** (names)
- **Primary user flows** (happy path + alt paths)
- **Entities touched** (and what fields are read/written)
- **Offline behavior**:
  - create/edit/delete/search
  - pending UI + retries
  - app restart behavior
  - reconnect behavior
  - media placeholders + uploads
- **Collaboration needs**:
  - yes/no
  - if yes, what should propagate and what the SLA is while foregrounded
- **Error states**:
  - empty/loading/error/offline
  - permission denied
  - quota/full storage
- **Risk level** (low/med/high) with *why*
- **Dependencies** (auth shell, sync engine, media pipeline, conflict UI, metadata caches, etc.)
  - Use Offline Data v2 terms where possible: native Firestore, scoped listeners, request-doc framework, offline UX primitives, and optional derived search index.

---

## Evidence rule (anti-hallucination)

For each non-obvious behavior:
- Provide **parity evidence**: point to where it is observed in the current codebase (file + component/function), OR
- Mark as an **intentional change** and explain why.

---

## Constraints / non-goals

- Do not prescribe “subscribe to everything” listeners; listeners must be **scoped/bounded** to the active context.
- Do not propose a bespoke “sync engine” (outbox/cursors/delta sync tables) as the default; Offline Data v2 relies on Firestore-native offline persistence.
- Any multi-doc invariant operation must be framed as **request-doc + Cloud Function transaction** (unless explicitly justified as provably safe).
- Do not do pixel-perfect design specs.
- Focus on behaviors where multiple implementations would diverge.

