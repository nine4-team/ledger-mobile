# EVID-ITEM-SPACE-ASSIGNMENT-LOCAL-DURABILITY-PROVIDER-001 — Item-to-Space Local Durability Provider

- Status: verified at exact corrected implementation commit
  `261de4709237a960eecd995c2733f5f48f31dcc5`; immutable CI passed
- Date: 2026-09-06
- Base commit: `762f69e11d6218de635fc46253ecae6e448d59b9`
- Base CI: Actions run `34025105217` passed all three jobs
- Environment: dedicated target worktree and disposable encrypted local databases only
- Production/Firebase impact: none
- Corrected-DRAFT review: two independent reviewers return GO with no P0-P3 findings
- Exact READY commit: `7cc00eacc0ac29b319eed07748e8377b14b28a47`
- Exact READY CI: Actions run `34026558345` passed all three jobs

## Selected Boundary

The next product-facing prerequisite is exact encrypted local acceptance of the
already-verified `AssignItemsToSpaceCommand`. An accepted command atomically
creates one shared queued local-operation record and one command-specific,
`localOnly` evidence record. It survives restart and is observable through the
existing Account runtime lifecycle.

This is deliberately not authoritative assignment. It does not mutate or
optimistically project Item or Space rows, enqueue PowerSync `ps_crud`, define
an upload request, call a server, grant authorization, or expose user-facing UI.
Those later layers remain blocked by authoritative Item schema/O-027,
command-specific capability policy, A-015 optimistic-projection selection,
O-037 archive-race/resolvable-placement behavior, and the missing Item-selection
read model.

## Why This Slice Is Authorized

- `docs/specs/spaces.md` defines exact same-scope durable bulk assignment and
  separates placement from accounting and attachment effects.
- `ItemSpaceAssignmentOperation.swift` and its tests already verify canonical
  Project/Business-Inventory scope, stable Item ordering, exact revisions,
  preconditions, fingerprint and receipt semantics.
- `ItemSpaceAssignmentUseCase.swift` already verifies represented-destination
  selection and the one-call application boundary.
- The shared operation lifecycle, pending-work provider, encrypted Account
  runtime and close semantics are implemented dependencies.
- The offline architecture requires durable local command acceptance before a
  later authoritative adapter exists.

## Frozen Implementation Boundary

- Own exactly the new store and test leaves. Modify shared schema/runtime/facade
  and target-environment checks only as listed in the dossier.
- Validate constructor-bound Account and Principal before any database access;
  preserve the verified command's exact stable `OperationID` without inventing
  an additional encoded-ID format.
- Persist canonical envelope JSON, command fingerprint, destination, exact
  scope, Space revision, ordered Item IDs/revisions and timestamps without
  numeric loss; all revisions use canonical decimal text. Preserve every finite
  client time already accepted by the frozen command contract—including
  negative and fractional-millisecond values—inside exact canonical command and
  envelope JSON; do not add a redundant integer timestamp that narrows command
  admissibility. For new admission only, provider-owned acceptance time is
  truncated toward zero to canonical milliseconds and must be finite,
  nonnegative, fit `Int64`, and round-trip exactly through the public `Date`
  snapshot representation. It is checked after replay lookup and before either
  write; exact replay uses persisted acceptance evidence and never consults the
  fresh clock.
- Use one `localOnly` command table and the existing `localOperations` table in
  a single transaction. `spike_item_space_assignment_commands` uses operation
  ID as implicit
  text `id`; required text `account_id`, `actor_principal_id`,
  `contract_version`, `destination_space_id`, `scope_kind`,
  `expected_space_revision`, `items_json`, `fingerprint`, `command_json`;
  nullable text `project_id` present exactly for Project scope; required integer
  `accepted_at_ms`; and index
  `item_space_assignment_command_account` on `account_id`. Scope is exact
  `project` with required `project_id`, or `business_inventory` with null
  `project_id`. `items_json` is sorted-key canonical JSON
  `{schemaVersion:"item_space_assignment_items_v1",items:[{itemId,expectedRevision}]}`
  in stable command order with decimal-text revisions. Do not
  use `insertOnly` and do not generate `ps_crud`.
- Populate `spike_local_operations` with the same operation/account/actor/
  contract/fingerprint, destination Space `subject_id`, `queued` local state,
  identical accepted/updated milliseconds, `assign_items_to_space` command
  type, Space revision decimal text, canonical envelope JSON, and every terminal
  field null. Create no operation-result row.
- Replay validates every stored field and returns only the exact existing local
  state. Changed replay uses `OperationContractFailure.payloadMismatch`;
  Account/Principal mismatch uses existing runtime scope failures; malformed
  rows use `ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence`;
  terminal rows fail closed. No path repairs or mutates contradictory evidence.
- Preserve cancellation as control flow. Pre-commit cancellation leaves no
  evidence; post-commit cancellation cannot revoke the accepted receipt.
- Provide only an assignment-specific operation watch and finite submit method
  through the existing close-aware Account runtime. Close drains provider
  watches and admitted runtime operations before database close.
- `pendingWorkSummary()` counts the assignment once through the existing generic
  local-operation row. Existing upload selection/order remains byte-frozen.
- Non-destructive close/reopen retains command and operation rows. This slice
  exposes no deletion or repair API; later session-ending destructive cleanup
  and terminal reconciliation/retention policy remain authoritative for removal.

The provider's finite failure taxonomy is `invalidAcceptanceTime`,
`malformedLocalEvidence`, and `operationNotFound`. Existing runtime scope
failures and `OperationContractFailure.payloadMismatch` remain authoritative;
cancellation remains control flow, canonical encoding failure uses
`ItemSpaceAssignmentFailure.invalidEncodedCommand`, and generic persistence
failures map to `ItemSpaceAssignmentFailure.localAcceptanceFailed`. Their exact
diagnostic codes are respectively
`item_space_assignment_acceptance_time_invalid`,
`item_space_assignment_local_evidence_malformed`, and
`item_space_assignment_operation_not_found`. Runtime closure uses
`LedgerOfflineClientRuntimeFailure.runtimeClosed`; diagnostics contain no identifiers,
payloads, SQL, paths, credentials, or remote-success claims.
This restriction applies to emitted `diagnosticCode` strings. The existing typed
`OperationContractFailure.payloadMismatch(OperationID)` retains its in-memory
associated value and is neither stringified nor logged by this slice.
Injected transaction admission, existing-row read, first/second write, watch
construction, watch query/read, and watch iteration failures must prove the
mapping with no partial mutation or emission. `CancellationError` passes
through unchanged on both submit and watch paths.

The watch accepts only an opaque OperationID and therefore does not infer
Account scope from its format. Its SQL is scoped by exact ID plus the
constructor Account/Principal. It emits only a fully validated queued snapshot;
absent/foreign rows are not found, and non-queued, terminal, or result evidence
is malformed. It defines no applying or terminal vocabulary.

## Required Proof

The dossier freezes thirteen verification obligations spanning both scopes,
canonical ordering/full-`UInt64` revision text, exact timestamp boundaries,
pre-database scope refusal, atomic rollback, exact replay,
concurrent same-ID acceptance, encrypted restart, cancellation boundaries,
malformed/cross-scope refusal, watch drainage, runtime close, pending-work count,
unchanged `ps_crud`/upload ordering, static containment, complete local gates and
immutable READY/implementation CI.

## Executable Outcome

The executable target now provides one Account/Principal-bound
`ItemSpaceAssignmentPowerSyncStore`. It atomically accepts the unchanged
canonical command into the exact local-only command table plus the shared
queued-operation table, revalidates every durable field on replay and watch,
and exposes submission and a dedicated queued-only observation through the
close-aware public runtime. `LedgerOfflineClientRuntime` nominally satisfies
the verified `ItemSpaceAssigning` port, so the existing application use case
consumes the target runtime without another adapter.

The live bootstrap binds the store to the encrypted structured workspace with
the selected Account and Principal. Runtime close drains admitted finite work
and assignment watches before the structured database closes. The generic
pending-work summary counts one accepted assignment while `ps_crud`, Item and
Space projections, operation results, and the existing uploader remain
unchanged.

## Executable Review Corrections

The first executable reviews returned NO-GO and found issues that passing tests
had not exposed. The corrected implementation and proof now:

- make exact replay independent of the current provider clock;
- compare exact canonical command bytes instead of decoded `Date` equality;
- admit only provider milliseconds that round-trip exactly through `Date`, and
  reject malformed persisted time symmetrically;
- inject cancellation after both rows are written but before transaction
  commit, proving complete rollback at the critical boundary;
- prove an admitted provider watch drains before structured database close;
- add nominal use-case conformance and exercise the live production bootstrap
  factory, resource binding, facade, watch, encrypted reopen, pending summary,
  and zero-`ps_crud` result;
- accept and observe an opaque non-prefix OperationID and reject foreign
  Principal or cross-operation observation; and
- structurally bind the checker to executable `@Test` functions, exact schema
  and SQL scope, runtime factory/lease/delegation/watch wiring, close order, and
  comment-stripped containment checks.

Two independent corrected-diff reviews then returned GO with no remaining
P0-P3 finding.

## Local Verification

- Focused Item-to-Space provider suite: 21/21 passed.
- Complete Swift target package: 606 tests across 93 suites passed both normally
  and with CI's `--no-parallel` execution.
- Target-environment isolation checker: passed.
- Query-port, logical-authority, source-query reconciliation, capability,
  extracted-query, M0, generated-contract and MCP gates passed; MCP ran 26 tests.
- Disposable local Supabase lint passed with no warnings; 374 pgTAP assertions
  plus the existing destination-read, note-read and Client/Project RPC/RLS/replay
  exercises passed. The local stack was stopped without backup afterward.
- Target staging builds succeeded for macOS and generic iOS Simulator with code
  signing disabled.
- Conversion ledger synchronization and the remaining repository gates are run
  from the explicit post-review source hashes recorded by this checkpoint.
- Exact implementation commit:
  `0e097a35c89336c7a90396e4eda9280222e3ab1a`. Actions run `34029102593`
  passed conversion/traceability and disposable-local-Supabase jobs, but its
  macOS job timed out in the existing Budget-category test `Provider shutdown
  joins row and completeness observers`. The log did not stop in the
  Item-to-Space suite. That run is non-passing evidence and cannot promote this
  slice.
- The separately owned Budget-category provider now has an independently
  reviewed one-file cancellation wake/drain correction committed as
  `a54719140a305012e3978eb809908ee77a17587a`. Its exact run `34030874960`
  passed conversion/traceability and disposable local Supabase again, but the
  serial target-test process timed out at a different provider-free
  Space-creation test that passes locally in 0.004 seconds. Event-order analysis
  confirms `--no-parallel` was honored. The second timeout is an unresolved
  shared-process/lifecycle failure and requires bounded prefix diagnostics, a
  causal correction, and exact synchronized all-job CI before
  `ITEMSPACELOCAL-TEST-013` advances.
- The separately reviewed target lifecycle correction then joined leaked test
  producers and closed Project Setup admitted-task drainage without changing
  Item-assignment code or scope. Exact corrected commit
  `261de4709237a960eecd995c2733f5f48f31dcc5` passed all three immutable jobs in
  Actions run `34035068558`: conversion controls, disposable local Supabase,
  all 611 serial target tests with normal process exit, both staging builds and
  clean artifacts. This satisfies `ITEMSPACELOCAL-TEST-013` and verifies the
  bounded local-durability provider.

## Explicit Non-Advancement

A-003/A-004/A-007/A-015/A-016 and O-023/O-027/O-037 remain unadvanced. No
Postgres migration, RLS policy, Sync Stream, Data API, RPC, Storage/media,
authorization capability, Item/Space projection, app UI, MCP, Firebase, source
data, migration, hosted resource, production access or cutover is authorized.
