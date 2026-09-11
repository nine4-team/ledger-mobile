# Decision Packet — O-048/O-049/O-050 Project Rename Boundary

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-09-06
Owners: Projects, App, MCP, Offline Operations, Security, Migration
Unlocks: a future provider-backed Project rename vertical slice after separate
READY review
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

Affected blockers: `O-048`, `O-049`, `O-050`

## Decisions Requested

Approve, reject, or revise these three independent recommendations.

### O-048 — Archived rename, same-value, revision, and audit semantics

> An authorized user may rename an active or archived Project through the same
> `RenameProject` command. Rename changes only the Project's current display
> name; it never changes stable identity, Client relationship, lifecycle, or
> frozen history. After authorization, exact Project lookup, and an exact
> expected-revision match, a submitted name equal to the current canonical UTF-8
> bytes produces an immutable successful `no_change` result without updating the
> Project row, advancing its revision or timestamps, or recording a rename-change
> audit fact. A different name advances the Project revision exactly once and
> records one immutable rename result/change fact in the same transaction.

### O-049 — One Project display-name contract for create and rename

> Project creation and Project rename use one versioned, language-neutral
> `ProjectDisplayName` submission conversion. It trims one explicit edge-scalar
> set, rejects an explicit unsafe-control set, requires a nonempty remainder,
> preserves all other accepted Unicode scalars without normalization or case
> folding, and permits at most 512 canonical UTF-8 bytes. Swift,
> MCP/JavaScript, PostgreSQL, PowerSync, and migration fixtures use identical
> vectors. Existing source values are never silently normalized, truncated, or
> replaced to satisfy this new-submission rule.

### O-050 — Exact Project rename authority

> Project rename requires a validated Auth identity mapped to the command actor,
> active membership in the exact Account, and the Account's
> `can_manage_projects` capability. Financial visibility, Project-budget
> management, Client management, and shared-reference-data management neither
> grant nor are required for rename. The rule is the same for active and archived
> Projects if O-048 is approved. Clients receive no direct Project-table mutation
> privilege; only the trusted scoped command may apply a rename.

These are proposed product and security recommendations only. They do not
authorize implementation, schema or RLS changes, provider work, hosted
provisioning, source migration, deployment, release, or cutover.

## Why Decisions Are Required

The canonical Project spec establishes stable Project identity and says Project
rename, Client rename, Project details update, Project archive, and future Client
reassignment are distinct operations. It does not decide whether an archived
Project remains rename-eligible, what an unchanged Save means for revision and
audit evidence, or which Account capability authorizes rename.

The verified provider-free `ProjectRenameOperation` and
`ProjectRenameUseCase` preserve stable AccountID, ProjectID, typed display name,
expected Project revision, OperationID, actor, contract version, fingerprint,
and receipt lifecycle. They intentionally stop before local persistence,
optimistic projection, trusted authorization, authoritative mutation, audit,
app/MCP wiring, and migration. Those executable contracts are prerequisites,
not authority for the choices in this packet.

The current Swift `ProjectDisplayName` rejects only values that Foundation
considers whitespace-only and otherwise preserves unbounded text, including
`U+0000`. Existing Project creation SQL uses PostgreSQL `text` and `btrim`, which
cannot represent NUL and does not match Swift or JavaScript scalar behavior.
Using those current implementations as the rename policy would silently choose
different user-visible command bytes by runtime and would also leave create and
rename contradictory.

The security architecture requires a command-specific capability after
Principal resolution and active membership. The isolated Project-setup and
Project-archive spikes already exercise a `can_manage_projects` predicate, but
that verified implementation evidence is not by itself product approval for
Project rename.

## Confirmed Constraints This Packet Cannot Reopen

- AccountID plus ProjectID, never display name, route text, Client name, or
  provider path, identifies the Project. Duplicate Project names remain valid.
- Rename and Project creation remain separate typed commands with separate
  contract versions and payloads. An approved shared `ProjectDisplayName`
  conversion does not merge their operations, queues, results, or audit facts.
- Rename cannot change AccountID, ProjectID, ClientID, description, categories,
  allocations, budget, media, lifecycle, children, preferences, notes,
  accounting evidence, or historical display-name snapshots.
- O-024 continues to own physical Project deletion. O-025 continues to own
  Project Client reassignment and Client merge/correction. Rename cannot act as
  a substitute for either decision.
- Local validation, synchronized membership, or a represented Project never
  grants current server authority. The trusted handler re-derives Principal,
  membership, capability, scope, state, and revision.
- Exact OperationID ownership, payload fingerprinting, replay, dependency-aware
  FIFO upload, CancellationError passthrough, runtime drainage, and immutable
  result validation remain architecture requirements; this packet does not
  weaken or replace them.
- Migration remains lossless and evidence-backed. New-submission validity does
  not authorize source repair, and no source Firebase surface changes here.

## O-048 Options

### Archived-Project eligibility

#### Option A — Rename active and archived Projects (recommended)

Archive affects ordinary selection and new activity, not the stable identity or
the correctness of its current label. The same rename command and capability can
correct current display while leaving archive state and all frozen evidence
unchanged.

#### Option B — Active Projects only

Reject rename while archived. A user would need a separately authorized restore,
rename, and rearchive sequence, producing unrelated lifecycle transitions and
potentially making a simple correction impossible.

#### Option C — Elevated archived correction only

Allow archived rename only through an Owner/Admin correction command. This is
defensible if archived labels are legally frozen, but no current product
authority establishes that distinction and it creates a second mutation and
authorization path.

### Same-value, revision, and audit behavior

All options compare the submitted canonical UTF-8 bytes with the current stored
canonical bytes only after authorization, exact Account/Project resolution, and
expected-revision match. A stale command cannot succeed merely because its text
happens to equal the current value.

#### Option 1 — Successful no-change with no revision or audit churn (recommended)

Persist an immutable successful `project_rename_no_change` operation result
bound to the OperationID, command fingerprint, Project, observed revision, and
server decision time. Do not update Project columns, increment revision, change
`updated_at`/`updated_at_ms`, or append a rename-change fact. Exact replay returns
the same result. This keeps revision and change audit tied to state changes while
making an ordinary unchanged Save safely idempotent.

#### Option 2 — Reject unchanged value

Return one stable business rejection. This keeps revisions clean but makes a
harmless Save channel-sensitive and forces callers to race the current value to
avoid an error.

#### Option 3 — Treat unchanged text as a change

Advance revision and update/audit time exactly like a different value. This is
simple at the handler but makes revision mean command acceptance rather than
Project-state change and records a misleading rename event.

## Recommended O-048 Exact Semantics

If Option A and Option 1 are approved:

- both active and archived Projects use one `RenameProject` path; archive state
  is neither changed nor copied into the command;
- expected revision is exact lexical UInt64 command evidence. The physical
  Project revision remains a positive signed bigint; an expected value above
  `Int64.max` cannot match an authoritative row;
- equality is exact canonical UTF-8 byte equality after O-049 validation, not
  case-insensitive, locale-sensitive, normalized-Unicode, or second-pass-trimmed
  equality;
- equal value plus matching revision succeeds even when the Project revision is
  `Int64.max`, because no increment occurs;
- a changed value at `Int64.max` produces a stable
  `project_rename_revision_exhausted` rejection without mutation;
- a changed value atomically updates only current display name, increments
  revision from `N` to `N + 1`, updates the authoritative Project update time,
  and records one immutable `project_renamed` result/change fact with resolved
  actor and server time;
- a no-change result records the unchanged observed revision. It is operation
  audit evidence, not a false Project-change event;
- neither branch rewrites creation time, archive time, Client relation, child
  rows, historical snapshots, or any other Project responsibility; and
- exact replay returns the immutable prior outcome, while changed reuse of the
  OperationID, command family, Project, revision, name bytes, actor, Account,
  contract, or fingerprint is a payload/identity mismatch.

## O-049 Options

### Option A — Explicit scalar contract with a 512-byte maximum (recommended)

Trim a fixed edge set, reject unsafe controls and line breaks, preserve all
other scalars exactly, and enforce the maximum on canonical UTF-8 bytes. This
gives Project create and rename one bounded, single-line value across runtimes.

### Option B — Preserve outer whitespace; reject only blank/control input

This is more literal but makes accidental outer whitespace canonical and
changes existing form expectations.

### Option C — Runtime-native trim and character count

Reject. Foundation, JavaScript, and PostgreSQL use different whitespace tables
and different notions of character length.

### Option D — Preserve every source-compatible string, including NUL

Reject as a target submission contract. PostgreSQL `text`/`jsonb` cannot
represent `U+0000`; substitution or stripping would corrupt command bytes,
fingerprints, and migration evidence.

## Recommended O-049 Exact Algorithm

If Option A is approved, one versioned `ProjectDisplayName` submission
conversion is used by Project create and rename:

1. Require valid Unicode scalar input. Reject JavaScript lone UTF-16 surrogates
   and any decoder replacement of malformed input; never silently emit
   `U+FFFD`.
2. Trim from both ends only: `U+0009–U+000D`, `U+0020`, `U+0085`, `U+00A0`,
   `U+1680`, `U+2000–U+200A`, `U+2028`, `U+2029`, `U+202F`, `U+205F`,
   `U+3000`, and `U+FEFF`.
3. In the remainder, reject `U+0000`, `U+200B`, `U+FEFF`, `U+2028–U+2029`,
   `U+0001–U+001F`, and `U+007F–U+009F`. Thus tab, LF, and CR may be removed at
   an edge but are invalid in the interior; Project display names are
   single-line.
4. Perform no Unicode normalization, case folding, locale transformation, or
   whitespace collapsing. Duplicate names and canonically equivalent but
   byte-distinct Unicode spellings remain valid and distinct display values.
5. Reject an empty scalar sequence after trimming.
6. Encode the remainder as strict UTF-8 and reject more than 512 bytes. Never
   use Swift `Character`, UTF-16 code-unit, JavaScript `.length`, PostgreSQL
   character, or grapheme counts as a substitute.
7. Preserve every accepted scalar and canonical UTF-8 byte exactly in the
   command, fingerprint, local overlay, RPC validation, authoritative row,
   PowerSync projection, and readback comparison.

Stored/read evidence may remain broader than the new-submission type until
migration reconciliation is complete. Ordinary reads, Sync, and display must
not reapply submission trimming or silently reject a legacy value.

## O-050 Options

### Option A — Active member with `can_manage_projects` (recommended)

Require the exact Project-management capability already represented by isolated
target prerequisites. Rename is Project administration but not financial,
Client, or shared-reference-data administration.

### Option B — Any active Account member

This supports broad collaboration but lets every member alter a label used by
the whole Account, even when Project creation/archive is restricted.

### Option C — Account Owner/Admin only

This is strongest but unnecessarily prevents delegated Project managers from
maintaining Projects and would require a separate role interpretation not
established by current Project flows.

Under the recommended option, anonymous, unmapped, inactive/revoked,
cross-Account, forged-actor, and active-member-without-capability requests fail
with stable non-enumerating authorization outcomes. `can_manage_project_budgets`,
financial-category visibility, `can_manage_clients`, and O-026 reference-data
capabilities do not imply Project rename authority.

## Proposed Trusted Server Algorithm

This algorithm is conditional on approval of all three recommendations:

1. Validate the platform token, resolve Auth identity to one Principal, require
   payload actor equality, active exact-Account membership, and the O-050
   capability. Do not consult user-editable metadata.
2. Validate command/authority version, canonical envelope, exact O-049 name
   bytes, subject, expected-revision precondition, and fingerprint without
   echoing submitted text in diagnostics.
3. Acquire deterministic transaction locks for global OperationID ownership and
   the exact Account/Project subject before disclosing any stored result or
   Project state.
4. If an immutable result already exists, return it only when every operation,
   family, Account, actor, Project, revision, name, contract, and fingerprint
   binding matches and the result remains in the actor's authorized exact
   Account scope; otherwise return a bounded mismatch. This replay check occurs
   before comparing the now-advanced Project revision.
5. With no prior result, lock and read the Project, verify exact Account scope,
   apply the approved active/archived eligibility, and require its positive
   signed-bigint revision to equal the exact expected revision. Missing,
   foreign, unauthorized, and hidden state remains non-enumerating.
6. If the canonical bytes are equal, insert only the immutable no-change result
   described by O-048. Do not issue a Project `UPDATE` or rename-change audit
   insert.
7. If bytes differ and revision is `Int64.max`, insert the bounded exhausted
   rejection and make no Project change.
8. Otherwise update only display name, revision, and authoritative update time;
   append the immutable rename result/change fact. Commit mutation and result
   atomically.

The client roles receive no `INSERT`, `UPDATE`, or `DELETE` grant on the Project
table or operation/audit relations. If a private `SECURITY DEFINER` RPC is used,
it must pin an empty search path, schema-qualify every object, revoke `PUBLIC`
and `anon` execution, grant only the required `authenticated` entry point, and
repeat all authorization inside the function. RLS and Sync authorization remain
independent positive/negative test obligations; `TO authenticated` alone is not
authorization.

## Proposed Offline and Runtime Algorithm

1. Convert raw app or MCP text through the single O-049 submission boundary
   before allocating/persisting an operation. Invalid input creates no operation,
   command, overlay, `ps_crud` entry, or provider call.
2. In the exact Account/Principal runtime, require represented Project evidence
   or the exact same-runtime pending Project creation. Validate stable Project
   identity, scope, latest effective local revision, and lifecycle according to
   O-048; local membership evidence is feedback only, never server authority.
3. Atomically persist the operation and distinct rename command. If the new bytes
   differ from the latest effective local display, persist one operation-bound
   overlay with projected revision `N + 1`; refuse changed local admission at
   `Int64.max`. If bytes are equal, persist no overlay and no projected revision.
4. Queue a pending-create dependency before its rename and chain multiple renames
   in dependency-aware FIFO order. A dependent command is not retargeted if an
   earlier command rejects.
5. Survive encrypted close/reopen with exact command, dependency, overlay (when
   present), and operation identity. Cancellation and close drain admitted work;
   a late completion cannot mutate a closed or reopened runtime.
6. Never synthesize terminal success locally. Rejection removes only the exact
   operation overlay. Applied optimism clears only after an exact qualifying
   authoritative Project readback; a no-change result has no overlay to clear.

## Exact Decision and Test Vectors

### Lifecycle, revision, replay, and audit

| Case | Initial evidence | Command | Recommended outcome |
|---|---|---|---|
| active change | active, name `Alpha`, revision 7 | `Beta`, expected 7 | `project_renamed`; name `Beta`, revision 8; one change fact |
| archived change | archived, name `Alpha`, revision 7 | `Beta`, expected 7 | same change result; remains archived; history unchanged |
| exact no-change | active or archived, name `Alpha`, revision 7 | `Alpha`, expected 7 | `project_rename_no_change`; row/times/revision/change-audit unchanged |
| stale no-change | name `Alpha`, revision 8 | `Alpha`, expected 7 | revision conflict; never no-change success |
| signed maximum no-change | name `Alpha`, revision `Int64.max` | `Alpha`, expected `Int64.max` | successful no-change; no increment |
| signed maximum change | name `Alpha`, revision `Int64.max` | `Beta`, expected `Int64.max` | revision-exhausted rejection; no mutation |
| out-of-range expected | any physical row | expected `Int64.max + 1` through `UInt64.max` | cannot match; no numeric coercion or wrap |
| exact replay | prior changed/no-change command and OperationID | identical bytes | same immutable result, no second update/audit |
| changed replay | prior OperationID | any changed bound field | payload/identity mismatch, no mutation |
| two concurrent changes | name `Alpha`, revision 7; distinct operations expect 7 | `Beta` and `Gamma` | one serial winner changes revision to 8; loser conflicts |
| two concurrent no-changes | name `Alpha`, revision 7; distinct operations expect 7 | both submit `Alpha` | both may serialize as immutable no-change successes at revision 7; neither mutates |
| no-change then change | name `Alpha`, revision 7; distinct operations expect 7 | `Alpha` linearizes before `Beta` | no-change succeeds at 7, then change succeeds to 8 |
| change then former no-change | name `Alpha`, revision 7; distinct operations expect 7 | `Beta` linearizes before submitted `Alpha` | change succeeds to 8; the stale second command conflicts |

### Shared Project display-name vectors

| Raw input | Recommended result |
|---|---|
| `"  Kitchen  "` | canonical bytes for `"Kitchen"` |
| `"Kitchen Design"` | preserve the interior `U+0020` |
| `"\u{00A0}Kitchen\u{3000}"` | canonical bytes for `"Kitchen"` |
| `"Kitchen\tDesign"`, `"Kitchen\nDesign"`, or `"Kitchen\rDesign"` | reject interior control/line break |
| `"\t Kitchen \r"` | canonical bytes for `"Kitchen"` |
| empty or all values from the edge-trim set | reject before operation creation |
| `"A\u{200B}B"`, interior `U+FEFF`, `U+0000`, DEL, or any C0/C1 control | reject |
| `"Caf\u{00E9}"` and `"Cafe\u{0301}"` | accept both and preserve distinct UTF-8 bytes |
| 511, 512, and 513 ASCII bytes | accept, accept, reject respectively |
| 128 and 129 four-byte emoji scalars | accept 512 bytes; reject 516 bytes |
| JavaScript lone high or low surrogate | reject without `U+FFFD` replacement |

Every scalar/range boundary and every listed vector must produce identical
Swift, TypeScript, JSON/RPC, PostgreSQL, PowerSync, and readback outcomes. Create
and rename must call the same converter and carry the same canonical bytes.

### Authorization and containment

- exact actor, active same-Account member, `can_manage_projects = true`: allow
  active and, if O-048 is approved, archived rename;
- same member with only Project-budget, financial, Client-management, or shared-
  reference capability: deny unless `can_manage_projects` is also true;
- anonymous, missing Principal mapping, forged actor, inactive/revoked member,
  cross-Account member, foreign Project, and removed capability: deny without
  revealing Project, operation, result, revision, or lifecycle existence;
- authenticated client direct `INSERT`, `UPDATE`, and `DELETE` on Project,
  operation-result, and rename-audit relations: deny; and
- authorization success/failure must agree across trusted RPC, RLS-visible
  readback, PowerSync stream eligibility, app, and gated MCP transport.

## Migration and Reconciliation Treatment

- Enumerate every source Project name with exact AccountID, ProjectID, source
  path/version, protected raw value or bytes, and cryptographic source hash
  before transformation.
- A source value already satisfying O-049 may import byte-for-byte. Do not trim,
  normalize, case-fold, or re-encode it through a lossy representation.
- A valid-Unicode source value outside the new contract becomes a review
  candidate linked to its exact preserved evidence. A reviewer may approve a
  replacement target display value; the migration must never silently trim,
  truncate, normalize, strip controls, or invent a placeholder.
- NUL, malformed Unicode evidence, or bytes that cannot enter PostgreSQL `text`
  are quarantined with exact protected evidence/hash and Project correlation
  until a replacement is explicitly approved.
- Cutover reconciliation proves each Project has either exact canonical import
  or an explicitly approved replacement, plus Account, stable ProjectID,
  ClientID, lifecycle, revision, timestamps, replacement approval, and any
  quarantine disposition.
- Existing synchronized/read models may need a broader legacy stored-value type
  until reconciliation completes. O-049 governs new submissions; it does not by
  itself authorize rewriting already imported Project rows.
- No migration, Firebase read/write, target backfill, hosted rehearsal, or
  production access is authorized by this packet.

## Affected Slices and Surfaces

Approval would affect the future provider-backed Project rename slice and must
be consumed by the already verified `project-rename-operation-contracts` and
`project-rename-use-case-contracts` dependencies without changing their stable
identity or separate-command guarantees.

O-049 also affects Project creation because one contract must own both create
and rename. Any future implementation must review the verified Project setup
operation/use case/provider, `ProjectDisplayName`, PostgreSQL Project constraints
and trusted create handler, PowerSync Project projections, Swift form validation,
and MCP create/update input together. Approval does not silently reclassify or
rewrite any of them.

The Project core-details and directory reads, Project archive browser, pending-
work runtime, local-operation identity guard, app Project detail/edit surfaces,
Project service/protocol/model, and the source `update_project` MCP surface are
shared touchpoints or dependencies that require exact inventory, hash binding,
and regression tests in a later READY dossier. Project details update,
preferences, note creation, Space providers, Client rename/reassignment, and
Project deletion remain separate workflows and gain no authority here.

## Required Acceptance Tests

- every lifecycle/revision/replay/audit and name vector above is executable and
  reciprocal across the owning requirement/test matrix;
- active and archived change and no-change cases preserve ClientID, lifecycle,
  children, frozen snapshots, creation/archive timestamps, and all non-name
  Project fields byte-for-byte;
- authorization precedes Project/result disclosure and covers every positive,
  negative, cross-tenant, revoked, actor-mismatch, direct-DML, RPC-grant, RLS,
  Sync, and gated-MCP case above;
- Project create and rename share exactly one converter and fixture corpus; a
  static guard rejects native `.trim`, Foundation trimming, character-count,
  SQL-`btrim`-only, or duplicated-validator drift;
- invalid raw input has zero OperationID allocation/persistence, provider calls,
  overlays, queue rows, and `ps_crud` changes;
- different-value offline acceptance is one local transaction for operation,
  command, and overlay; same-value acceptance is one transaction for operation
  and command with no overlay or projected revision;
- every transaction/checkpoint failure and CancellationError leaves no partial
  local state, and runtime close joins admitted writes/watches before database
  close while rejecting late work;
- pending Project create then rename, multiple rename chains, rejection rollback,
  applied exact readback, no-change result, encrypted restart, and independent
  Account/Principal/runtime isolation are proven;
- trusted server races cover same OperationID same/different payload and distinct
  operations at one revision without double mutation, result, or audit;
- schema constraints/indexes accept the exact 512-byte maximum and positive
  signed-bigint boundaries; SQL/RPC never converts revision through floating
  point; and
- migration fixtures cover exact import, every out-of-contract class, reviewed
  replacement, quarantine, and complete zero-silent-rewrite reconciliation.

## Approval Consequences

If O-048 is approved:

1. add the selected archived eligibility and same-value/revision/audit semantics
   to the canonical Project spec and record a confirmed D decision;
2. version the authoritative result codes and define immutable changed versus
   no-change evidence;
3. bind the future provider/app/MCP dossier to active/archived, no-change,
   revision-boundary, replay, offline-overlay, and concurrency proof; and
4. leave O-024/O-025 and every non-rename Project workflow unchanged.

If O-049 is approved:

1. add the exact scalar and UTF-8 algorithm as the canonical Project create/edit
   submission contract and record a confirmed D decision;
2. revise `ProjectDisplayName` ownership so one conversion is shared by create
   and rename without narrowing legacy read evidence accidentally;
3. update Swift, MCP/JavaScript, PostgreSQL, PowerSync, and migration fixtures as
   one coordinated implementation boundary; and
4. remove O-049 only from surfaces that prove the shared vectors and lossless
   migration dispositions.

If O-050 is approved:

1. add exact Project-rename capability authority to canonical security/product
   documentation and record a confirmed D decision;
2. specify a trusted command path with no client table writes and complete
   grant/RLS/Sync/RPC negative proof; and
3. remove O-050 only from slices whose server and transport authorization tests
   pass.

Approval of a recommendation removes only that product-decision blocker. It
does not make a provider slice READY, authorize code, approve an implementation
diff, close A-003/A-004 or O-024/O-025, provision hosted resources, approve
migration/rehearsal, or permit production/release/cutover work.

## Approval Checklist

### O-048

- [ ] Choose archived eligibility Option A, B, or C.
- [ ] Choose same-value Option 1, 2, or 3.
- [ ] Confirm authorization and revision match precede equality comparison.
- [ ] Confirm exact changed/no-change revision, timestamp, result, and audit
  behavior, including `Int64.max`.
- [ ] Confirm no lifecycle, Client, child, or frozen-history mutation.

### O-049

- [ ] Choose display-name Option A, B, C, or D.
- [ ] Confirm the exact edge-trim and rejected-scalar sets.
- [ ] Confirm single-line behavior, no normalization/case folding, and 512 UTF-8
  bytes.
- [ ] Confirm one converter/fixture corpus for create and rename across every
  runtime.
- [ ] Confirm lossless migration review/quarantine rather than silent repair.

### O-050

- [ ] Choose capability Option A, B, or C.
- [ ] Confirm active membership and exact actor binding are always required.
- [ ] Confirm archived and active Projects use the same role if O-048 Option A is
  selected.
- [ ] Confirm other financial/Client/reference capabilities neither grant nor
  are required for rename.
- [ ] Confirm trusted-command-only mutation and the complete negative security
  matrix.

Until explicit approval is recorded as confirmed decisions and canonical specs
are updated, O-048/O-049/O-050 remain open and no implementation may treat these
recommendations as authority.
