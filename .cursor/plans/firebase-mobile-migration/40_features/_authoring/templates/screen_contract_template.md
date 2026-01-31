# Screen contract template (`ui/screens/<screen>.md`)

## Intent
What this screen is for (1–3 sentences).

## Inputs
- Route params:
- Query params:
- Entry points (where navigated from):

## Reads (Firestore cache-first)
- Firestore queries / doc fetches (cache-first vs server-first posture, as applicable):
- Scoped listeners attached (what is listened to, and what is *not*):
- Derived view models:
- Cached metadata dependencies (categories/vendors/templates/etc):
- Optional derived search index usage (if applicable): how candidate IDs are produced and how canonical docs are fetched from Firestore:

## Writes (Firestore + request-doc)
For each user action, list:
- Direct Firestore write(s) (single-doc) **or** request-doc write (multi-doc/invariant operation)
- Request-doc fields (op id / request id, status model, error model) and the expected Cloud Function transaction
- Pending UX: what the user sees while the write is pending locally, syncing, or failed
- Retry/cancel semantics (especially for request-doc operations)

## UI structure (high level)
Sections/components and what each does.

## User actions → behavior (the contract)
Bullet list of every important action and the resulting behavior/state changes.

## States
- Loading:
- Empty:
- Error:
- Offline:
- Pending sync (local writes queued):
- Permissions denied:
- Quota/media blocked:

## Media (if applicable)
- Add/capture/select:
- Placeholder rendering (offline):
- Upload progress UX:
- Delete semantics:
- Cleanup/orphan rules:

## Collaboration / realtime expectations
- Should this reflect remote changes while foregrounded? What is the expected latency?
- What is OK to be stale until next delta run?

## Performance notes
- Expected dataset sizes
- Required indexes/search behavior
- Virtualization/debouncing needs

## Implementation reuse (porting) notes
- Reusable logic to port (file paths + symbols):
- Platform wrappers required (navigation, storage, media, share/print, background execution):
- Any intentional deltas (why porting isn’t possible 1:1):

## Parity evidence
List “Observed in …” bullets with file + component/function name for non-obvious behaviors.

