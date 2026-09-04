# Decision Packet — O-042/O-043 Client Rename and Display-Name Boundary

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-09-04
Owners: Client Identity, Projects, App, MCP, Offline Operations, Migration
Unlocks: Client create/rename provider implementation and exact cross-runtime validation
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

Affected blockers: `O-042`, `O-043`

## Decisions Requested

Approve or reject these two independent policies.

### O-042 — Archived rename and unchanged save

> An authorized user may rename an archived Client under the same capability and
> expected-revision rules as an active Client. Rename changes only current
> display, never lifecycle or frozen history. If the canonical submitted display
> name exactly equals the Client's current canonical value after a matching
> revision precondition, the server records a successful no-change operation but
> does not update the Client row, increment revision, change `updated_at`, or
> append a rename-change event.

### O-043 — Shared Client display-name submission contract

> New and edited Client display-name submissions trim one explicit
> language-neutral edge-scalar set, reject an explicit unsafe-control set,
> require a nonempty remainder, preserve every other accepted Unicode scalar
> without NFC/NFKC normalization or case folding, and permit at most 512 UTF-8
> bytes. Swift, MCP/JavaScript, PostgreSQL and migration fixtures implement the
> same vectors. Existing source values are never silently normalized, truncated
> or replaced to satisfy the new-submission rule.

These are product recommendations. They are not implementation, schema,
migration, provider, production, release or cutover approval.

## Why Decisions Are Required

The current canonical Client spec establishes stable Client identity, mutable
current display, archived-history preservation and frozen historical snapshots.
It does not say whether archive removes rename eligibility or what an unchanged
save means for revision and audit state. Those are observable product semantics,
not adapter details.

The verified Swift `ClientDisplayName` currently rejects only values that
Foundation considers whitespace-only. It otherwise preserves unbounded input,
including control scalars and `U+0000`. JavaScript's trim and UTF-16 behavior are
not identical to Foundation's, while PostgreSQL `text` and `jsonb` cannot contain
NUL. Therefore the target cannot truthfully promise byte-identical app/MCP/
Postgres behavior until one explicit language-neutral submission boundary is
approved.

Any READY dossier or scaffold that assumes archived rename eligibility,
same-value revision advancement, or the existing permissive display-name value
is provisional. It cannot convert those assumptions into product authority.

## Confirmed Constraints This Packet Cannot Reopen

- Client ID, not display name, is Account-scoped identity. Duplicate display
  names remain valid and do not merge Clients or authorize relationships.
- Rename may change only the current Client display value. It cannot change
  Account, Client ID, lifecycle, Project ownership, creation audit, money or
  frozen Invoice/report/paid-history/audit snapshots.
- Archive preserves identity and history and removes the Client from ordinary
  new-Project selection. O-025 owns Client reassignment and duplicate-Client
  merge; no unconfirmed delete or restore policy is inferred here.
- Every submitted command remains subject to authenticated Principal binding,
  active Account membership, Client-management capability, exact Client scope,
  OperationID binding and optimistic revision checks.
- App and MCP must use one application contract. Neither transport may invent a
  different minimum, trim rule, no-op rule or authorization shortcut.
- Source migration must remain lossless and evidence-backed. New-submission
  validity does not authorize silent source-data repair.

## O-042 Options

### Archived-Client eligibility

#### Option A — Rename active and archived Clients (recommended)

Archive affects selection and lifecycle, not identity resolution. Allowing an
authorized rename lets users correct or clarify the current label used by
current Client/Project views while leaving archive state and frozen history
unchanged. The same capability and concurrency rules apply to both states.

#### Option B — Active Clients only

Reject rename while archived. A user must restore, rename and rearchive, which
creates unrelated lifecycle revisions/events and may be impossible when restore
has independent eligibility rules.

#### Option C — Archived rename only through an elevated correction workflow

Require Owner/Admin or a separate administrative command. This is defensible if
archived labels are legally frozen, but no current product authority establishes
that distinction, and it adds a second rename path.

### Same-value save and revision behavior

All options compare the canonical submitted value to the current canonical
value only after authorization, exact Client lookup and expected-revision match.
A stale command cannot obtain success merely because its text happens to equal
the current value.

#### Option 1 — Successful no-change result, no revision churn (recommended)

Return an immutable successful `no_change` outcome bound to the OperationID and
observed Client revision. Do not update Client columns or append a rename-change
event. Exact replay returns that same result. This makes an ordinary Save safe,
preserves meaningful revisions, and avoids false conflicts and audit noise.

#### Option 2 — Reject unchanged value

Return a stable validation/business rejection. This keeps revisions clean but
makes harmless Save behavior channel-sensitive and forces every caller to race
the server's current value to avoid an error.

#### Option 3 — Treat unchanged text as a change and increment revision

Update audit time and revision exactly like a different value. This is simple at
the handler but makes revision mean “command accepted” rather than “Client state
changed,” creates avoidable offline conflicts, and records misleading rename
activity.

## Recommended O-042 Contract

If Option A plus Option 1 is approved:

- active and archived Clients use one `RenameClient` command and authorization
  path; archive/restore state is neither a precondition nor a command member;
- authorization and exact expected revision are checked before same-value
  comparison, so unauthorized, missing and stale requests remain failures;
- equality means exact canonical UTF-8 bytes after O-043 submission validation;
  it is not case-insensitive, locale-sensitive, normalized-Unicode or trimmed-a-
  second-time equality;
- a different value updates current display, authoritative update time and
  revision exactly once and emits the ordinary immutable result/change evidence;
- an equal value records one immutable successful no-change operation result
  with the unchanged observed revision, but changes no Client or history row;
- offline submission may durably queue the no-change command for authoritative
  authorization/result, but creates no display overlay or projected revision;
  it must not synthesize final server success locally;
- pending-create/rename and multiple-rename commands remain FIFO. A same-value
  command relative to the latest effective pending value depends on earlier
  commands and resolves at the server against its expected revision; and
- app and MCP present no-change as successful Save completion, not as a conflict,
  rename event or lifecycle transition.

This policy does not decide whether an aliased/merged loser may be renamed. That
remains part of O-025's merge/lifecycle design.

## O-043 Options

All options require one rule across create and rename and preserve lossless
source evidence. They differ in how much new input becomes canonical.

### Option A — Exact trim/control contract with a 512-byte maximum (recommended)

Trim a fixed edge set, reject unsafe controls and line breaks, preserve all other
scalars exactly, and enforce the limit on canonical UTF-8 bytes. This produces a
single-line display value, avoids runtime-library drift, remains generous for
real names, and bounds database indexes, Sync payloads, UI and logs.

### Option B — Preserve outer whitespace; reject blank-only/control input

Keep every accepted scalar and reject only an all-trimmable value. This is more
literal but makes accidental leading/trailing whitespace canonical and retains
the current app/MCP ambiguity about how blankness is computed.

### Option C — Runtime-native trim with a character-count maximum

Let Swift, JavaScript and SQL use their native whitespace/length functions.
Reject. Their whitespace tables and UTF-16/scalar/code-point counts differ, so
the same user-visible input can canonicalize or fail differently by channel.

### Option D — Preserve every source-compatible string, including NUL

Reject as a target submission contract. PostgreSQL `text`/`jsonb` cannot
represent `U+0000`, and transport-side substitution or stripping would corrupt
the command fingerprint and migration evidence.

## Recommended O-043 Exact Algorithm

If Option A is approved, one versioned `ClientDisplayNameSubmission` conversion
is used for Client create and rename:

1. Require valid Unicode scalar input. JavaScript lone UTF-16 surrogates and any
   decoder replacement of malformed input are invalid; do not silently emit
   `U+FFFD`.
2. Trim from both ends only these scalar values:
   `U+0009–U+000D`, `U+0020`, `U+0085`, `U+00A0`, `U+1680`,
   `U+2000–U+200A`, `U+2028`, `U+2029`, `U+202F`, `U+205F`, `U+3000`, and
   `U+FEFF`.
3. In the remaining value, reject `U+0000`, `U+200B`, `U+FEFF`, line/paragraph
   separators `U+2028–U+2029`, and control scalars `U+0001–U+001F` plus
   `U+007F–U+009F`. This makes tab, LF and CR trimmable at an edge but invalid in
   the interior; Client display names are single-line.
4. Perform no Unicode normalization, case folding, locale transformation or
   whitespace collapsing. Composed and decomposed spellings remain distinct
   exact values, though duplicate names of either spelling are still allowed.
5. Reject an empty scalar sequence after trimming.
6. Encode the canonical remainder as strict UTF-8 and reject values longer than
   512 bytes. Do not count Swift `Character`, UTF-16 code units, JavaScript
   `.length`, PostgreSQL characters or grapheme clusters for this limit.
7. Preserve every accepted canonical scalar and its UTF-8 bytes exactly in the
   command, fingerprint, local overlay, RPC validation, authoritative row and
   readback comparison.

The stored/read representation may need to remain broader than the new-
submission type so migration evidence can be preserved. Code must not reapply
submission trimming during ordinary reads, Sync reconciliation or display.

## Cross-Runtime Ownership

| Boundary | Required responsibility |
|---|---|
| Swift domain/application | Convert raw UI intent once, using explicit scalar tables and UTF-8 byte count before creating an operation |
| MCP/JavaScript | Validate Unicode/UTF-16 explicitly, use the same scalar tables, and never rely on native `.trim()` or `.length` |
| canonical command | Carry only the approved canonical value; OperationID replay with any different bytes is a payload mismatch |
| PowerSync/SQLite | Store and compare exact canonical UTF-8; invalid input creates no operation, command or optimistic overlay |
| PostgreSQL handler | Repeat equivalent validity checks before mutation; reject NUL at the API boundary and do not approximate the rule with `btrim()` alone |
| schema/indexes | Bound stored canonical new values and preserve safe indexability without treating lowercased name as identity |
| migration | Preserve source bytes/hash and correlation; explicitly import, review or quarantine each value outside the new-submission contract |

PostgreSQL constraints may enforce parts of the contract only if they match the
approved vectors exactly. The trusted handler and shared fixtures remain the
normative enforcement path; a convenient SQL approximation must not disagree
with Swift or MCP.

## Authorization, Offline, Replay, and Privacy

- Display-name validity never proves Account membership, Client existence or
  capability. Authorization precedes subject/replay disclosure at the server.
- Invalid UI/MCP input creates no OperationID receipt, local overlay, upload row
  or provider request and returns one stable privacy-safe validation code.
- A valid different-value offline rename atomically persists its operation,
  command and separate local overlay. A valid same-value submission follows the
  O-042 no-change queue rule and creates no projected state.
- Chained offline renames compare exact canonical bytes and revisions. Rejection
  removes only the matching overlay; applied optimism waits for qualifying exact
  authoritative readback.
- Logs, analytics, errors and operation diagnostics never echo submitted or
  rejected Client text, raw command JSON, source bytes or credentials.

## Migration and Reconciliation

- Enumerate every Firebase Client name as raw source evidence with Client/
  Account correlation and an exact source-byte hash before transformation.
- A source value that already satisfies O-043 may import byte-for-byte. Do not
  trim or normalize it again.
- For a valid-Unicode source value outside the new contract, preserve the exact
  original evidence and produce a review candidate; a reviewer may approve a
  replacement target display value. Do not silently trim, normalize, truncate or
  substitute it.
- A value containing `U+0000`, malformed Unicode evidence or bytes that cannot
  enter PostgreSQL `text` is quarantined with its exact protected bytes/hash and
  source correlation until a replacement is explicitly approved. Do not insert
  a fabricated placeholder and claim reconciliation.
- Cutover requires every Client to have either an exact imported canonical value
  or an approved replacement linked to preserved source evidence. Editing a
  migrated Client later uses the new-submission contract.
- Reconcile Client ID, Account, exact source hash, target canonical bytes,
  lifecycle, revision, replacement approval and every quarantine disposition.

## Required Acceptance Tests

### O-042 behavior

- active and archived Clients rename successfully without lifecycle change;
- archived rename updates current Client/Project display but never frozen name
  snapshots or Project revision;
- same canonical value plus matching expected revision returns successful
  no-change, preserves Client revision/update time and creates no rename event;
- stale/future expected revision rejects even when submitted text equals current;
- exact replay of change and no-change returns the same immutable result;
- concurrent same-revision different/equal commands serialize deterministically
  without double increment or misleading no-change success;
- offline no-change survives restart as pending/result evidence without an
  overlay, projected revision or locally invented terminal success; and
- app and MCP render equivalent changed, no-change, archived and conflict cases.

### O-043 shared vectors

- Swift, MCP/JavaScript and PostgreSQL accept/reject and canonicalize identical
  fixtures for every trim scalar and each boundary of every rejected range;
- fixtures include empty/all-trim, padded ordinary names, interior/edge tab/LF/
  CR, NUL, `U+200B`, edge/interior `U+FEFF`, `U+2028/U+2029`, C0/C1 controls,
  emoji and supplementary scalars;
- composed/decomposed equivalents remain byte-distinct and are not normalized;
- 511-, 512- and 513-byte canonical values cover ASCII and multibyte boundaries,
  including cases where Swift grapheme, Unicode-scalar, UTF-16 and UTF-8 counts
  differ;
- JavaScript lone high/low surrogates reject without replacement; JSON/RPC and
  PostgreSQL reject NUL without truncation or fingerprint drift;
- create and rename use the same converter and command bytes; invalid values
  create no local operation/overlay/provider call;
- exact command/fingerprint/replay and PowerSync readback preserve canonical
  UTF-8 bytes across termination and reconnect;
- database constraints/indexes accept the maximum and cannot fail later from an
  oversized index value; and
- migration fixtures cover exact-pass import, outer whitespace, controls,
  over-limit Unicode, NUL/malformed evidence, reviewed replacement and
  quarantine with zero silent rewrites.

## Approval Consequences

If O-042 is approved:

1. add archived rename eligibility and successful no-change semantics to the
   canonical Client spec and record a confirmed D decision;
2. revise the Client rename provider dossier/scaffolds that currently assume
   same-value revision advancement;
3. version the operation result so changed and no-change outcomes are explicit;
   and
4. add lifecycle, offline-no-overlay, replay and concurrency proof before the
   provider slice can advance.

If O-043 is approved:

1. add the exact scalar/UTF-8 algorithm to canonical Client create/edit authority
   and record a confirmed D decision;
2. introduce or revise the shared submission value without narrowing legacy read
   evidence accidentally;
3. update Swift, MCP, PostgreSQL, PowerSync and migration fixtures together; and
4. remove O-043 only from surfaces whose implementation proves the shared
   vectors and lossless migration dispositions.

Until approval, neither recommendation may be treated as a frozen product
invariant. Local architecture work may identify dependencies but may not choose
the behavior by implementation.

## Approval Checklist

### O-042

- [ ] Choose archived rename Option A, B or C.
- [ ] Choose same-value Option 1, 2 or 3.
- [ ] Confirm equality occurs only after authorization and revision match.
- [ ] Confirm lifecycle and frozen history never change during rename.
- [ ] Confirm offline same-value overlay/result behavior.

### O-043

- [ ] Choose validation Option A, B, C or D.
- [ ] Confirm the exact edge-trim and rejected-scalar sets.
- [ ] Confirm single-line behavior and no Unicode normalization/case folding.
- [ ] Confirm the 512 UTF-8-byte maximum.
- [ ] Confirm create/rename and Swift/MCP/PostgreSQL/PowerSync parity.
- [ ] Confirm lossless migration review/quarantine rather than silent repair.

Approval closes only O-042 and/or O-043 as explicitly selected. It does not close
O-024, O-025, A-003, A-004, migration/rehearsal, production or cutover gates.
