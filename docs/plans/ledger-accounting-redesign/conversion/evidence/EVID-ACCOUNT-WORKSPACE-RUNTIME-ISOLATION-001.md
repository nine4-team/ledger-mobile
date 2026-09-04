# EVID-ACCOUNT-WORKSPACE-RUNTIME-ISOLATION-001 — Account Workspace Runtime Isolation

- Status: READY reviewed; comment-only new implementation leaves; immutable CI pending
- Date: 2026-09-04
- Environment: isolated target worktree and disposable local fixtures only
- Production/Firebase impact: none
- Slice: `account-workspace-runtime-isolation`

## Outcome

This package freezes the prerequisite to a trustworthy pending-work summary:
the physical Account workspace database and key must be derived from one
validated target environment plus exact Principal and Account scope. The same
binding reopens the same encrypted state; any environment, bundle,
persistence-relevant manifest, Principal or Account change is isolated.

Only the new namespace-helper and focused-test leaves contain comments. The
existing Account runtime, staging root and shared directory-provider tests
remain byte-unchanged until this READY package passes independent review and
immutable CI.

## Corrected Gap

The current runtime takes a free namespace prefix, omits environment from the
Keychain namespace, uses raw Principal and Account strings as filesystem path
components, and publicly exposes `close(deleteDatabase:)`. The staging root
discards its already validated environment and passes only that free prefix.
Those mechanics are not sufficient for an environment-scoped pending-work
summary or safe session-ending policy evaluation.

The bounded correction will pass `ValidatedLedgerEnvironment` to bootstrap,
derive from its namespace plus persistence binding, validate before side
effects, use opaque contained physical components, include environment in key
identity, and make ordinary close preserve database and key unconditionally.

## Independent READY Review

The initial review returned NO-GO and the corrected-diff review returned GO with
no remaining P0-P3 finding. Before GO, the package was corrected to:

- include the existing directory-provider regression tests as an affected/shared
  surface without stealing their primary ownership;
- cite platform validation and offline local-data security from their actual
  architecture sections;
- distinguish namespace isolation after a changed persistence binding from a
  nonexistent stored-binding rejection mechanism;
- limit manifest claims to persistence-relevant fields; and
- state the Principal bootstrap versus Account-workspace topology while leaving
  authorized opening and one-workspace-at-a-time enforcement to the later
  activation/switch coordinator.

## Planned Verification

- identical environment/bundle/persistence-relevant-manifest/Principal/Account
  binding reopens exact
  encrypted local evidence;
- each individual persistence-relevant binding dimension produces distinct
  database and key identity;
- adversarial canonical IDs cannot escape or collide in filesystem paths;
- invalid derived namespace or scope evidence fails before filesystem, Keychain
  or database access and emits only bounded diagnostics;
- a changed persistence binding selects an isolated namespace; comparison with
  separately stored binding metadata is outside this slice and callers cannot
  supply a free binding;
- cross-Principal and cross-Account runtime requests still refuse before writes;
- the staging app carries its validated environment into bootstrap and exposes
  no free runtime environment/backend switch;
- ordinary close preserves local evidence and offers no delete flag; existing
  disposable test fixtures explicitly remove their directories after close;
- complete conversion, target, local Supabase, macOS and iOS CI gates pass on
  the exact synchronized implementation commit.

## Hard Boundary

This slice does not add Auth, a PowerSync connector or Sync Stream, an offline
authorization lease, Account activation/switching, pending-work aggregation,
provider signout, destructive removal, attachment retention/deletion, migration,
hosted access, production behavior or cutover authority. A-003/A-004 remain
proposed; A-007/A-016 and O-023 remain open.

The later activation/switch coordinator—not this namespace slice—must enforce
successful authorization-lease validation before opening protected Account
data and ensure only one Account-workspace database is open at a time.
