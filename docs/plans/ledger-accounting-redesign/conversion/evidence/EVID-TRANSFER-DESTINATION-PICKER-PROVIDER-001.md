# EVID-TRANSFER-DESTINATION-PICKER-PROVIDER-001 — Local Transfer Destination Picker

- Status: implemented and independently reviewed; exact implementation CI pending
- Date: 2026-09-05
- Environment: isolated target worktree and synthetic local fixtures only
- Production/Firebase impact: none
- Slice: `transfer-destination-powersync-picker`
- READY baseline: exact commit `2f87445cd51d6911a0655ad611fdedf035246665`, immutable Actions run `33989797244`

## Implemented Outcome

The target runtime can observe and present eligible Transfer destination
Projects from its existing encrypted local Project directory. Each update
re-resolves the stable source Project ID from current directory evidence and
returns only other active Projects with the source's current exact Client ID.
Caller-stale Client, name, and lifecycle fields never control filtering.

The provider adds no SQL, schema, RLS, Sync Stream, cache, completeness source,
MCP method, Transfer command, Item movement, amount, accounting effect,
production route, Firebase behavior, migration, release, or cutover authority.

## Executable Boundaries

- `TransferDestinationSelectionPowerSyncQuery` derives the verified Core
  snapshot from the existing Account-bound Project-directory watch and owns
  cancellation/drainage.
- `AccountWorkspacePendingWorkRuntime` and `LedgerOfflineClientRuntime` expose
  one typed, close-aware read path without exposing persistence details.
- `TransferDestinationSelectionStagingExercise` owns generation-safe source
  replacement, exact local-evidence states, and transient represented ProjectID
  selection.
- The target adapter and staging view are read-only composition. They compile
  on macOS and iOS; no interactive UI-rendering proof is claimed.

## Offline and Failure Proof

Executable tests prove that encrypted retained source/destination rows reopen
as partial or stale and incomplete. They become ready only after new
current-process Project completeness evidence. A second retained source-only
reopen proves local emptiness remains incomplete before that proof and becomes
authoritative no-destination only afterward.

Incomplete source absence emits zero candidates without using a caller-stale
Client ID. Source disappearance clears candidates; reappearance and same-ID
Client reassignment use only the current row. Complete-ready absence,
cross-Account input, upstream failure, consumer cancellation, workspace close,
and post-close registration all terminate boundedly.

Composite frozen tests remain the authority for malformed persisted Project
relationships, cross-Account relationships, duplicate Project identities,
duplicate candidates, and tampered directory/derived fingerprints. The derived
provider does not duplicate those validators.

## Review Corrections

Independent executable review first returned NO-GO because the initial tests
did not literally prove encrypted restart readiness, consumer-driven drainage
through the derived watch, or destination removal without selection
resurrection. Those cases were added. Re-review returned GO with no P0 or P1
finding. Its evidence-attribution correction is reflected in
`TRANSFERDESTPICKER-TEST-003`, and the staging verification now explicitly
treats builds as composition proof rather than interactive UI proof.

## Verification

- focused provider and AppModel suites pass;
- the complete Swift package suite passes with 522 tests across 86 suites;
- the target MCP contract suite passes;
- target-environment/source-boundary checks pass;
- deterministic project generation preserves the frozen package/project files
  and changes only the four authorized app memberships;
- macOS and generic iOS Simulator staging builds pass; and
- frozen Core, Project-directory, Space DRAFT, package, and target-project
  source files remain byte-exact where required.

Exact implementation-commit CI is still required for
`TRANSFERDESTPICKER-TEST-007`. Hosted authenticated Supabase/PowerSync
rehearsal and cutover readiness remain zero.
