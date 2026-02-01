# Shared UI update process (multi-chat safe)

This doc exists to make Shared UI spec work **predictable across many AI chats**.

Canonical shared UI spec (single file):

- `40_features/_cross_cutting/ui/shared_ui_contracts.md`

## What this is for

- Prevent drift: shared UI behavior is defined **once**.
- Enable parallel work: multiple chats can safely extend the doc without reformatting it.
- Keep feature specs clean: features **reference** shared UI contracts instead of rewriting them.

## Hard rules

- **Single source of truth**: shared UI behavior lives in `shared_ui_contracts.md`.
- **No per-component contract files**: do not create `40_features/_cross_cutting/ui/components/*.md`.
- **Do not reorder headings** in `shared_ui_contracts.md`.
- **Evidence rule**: for non-obvious behavior, add parity evidence pointers into `/Users/benjaminmackenzie/Dev/ledger/...` or label an intentional delta.

## How to update shared UI (the process)

### Step 1) Choose the right section

Pick the single best matching stable heading in `shared_ui_contracts.md`.

If a new heading is unavoidable:

- Add it **only** under “Shared surfaces index”
- Use the same heading text in both places

### Step 2) Add content in this order

Within the chosen section, add:

- **Intent** (1–2 sentences)
- **Contract** (bullets; user-visible rules)
- **Parity evidence pointers** (file paths + components/functions)
- **Open questions** (if any)

Avoid implementation details unless they change user-visible behavior.

### Step 3) Update feature specs to reference, not redefine

When updating a feature spec:

- Link to the relevant section in `shared_ui_contracts.md`
- Only add feature-owned wiring (fields, permissions, routes, copy)

## How to split this across many AI chats

Use one chat per surface with an explicit boundary, for example:

- “Fill in List controls + control bar contract (search/filter/sort/group + restore).”
- “Define Selection + bulk actions (select-all semantics + partial failure UX).”
- “Define Media UI surfaces (upload/preview/gallery/quota) and RN deltas.”

Each chat should ideally edit **one section** (two max if tightly coupled).

## Definition of done (per section)

A section is “done enough” when:

- Contract bullets cover the user-visible behavior + edge cases
- Parity evidence exists for non-obvious rules
- RN deltas are labeled explicitly
- Feature specs link to it instead of restating it

