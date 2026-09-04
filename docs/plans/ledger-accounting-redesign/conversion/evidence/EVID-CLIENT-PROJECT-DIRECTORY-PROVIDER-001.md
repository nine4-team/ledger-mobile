# EVID-CLIENT-PROJECT-DIRECTORY-PROVIDER-001 — Client/Project PowerSync Directory Provider

- Status: READY contract; executable implementation intentionally absent
- Date: 2026-09-04
- Environment: isolated target worktree and disposable local fixtures only
- Production/Firebase impact: none
- Slice: `client-project-directory-powersync-provider`
- Surfaces: `SWIFT-B23F91245E50`, `TEST-5AAEE26660C8`

## Outcome

This checkpoint freezes the exact implementation boundary for making Ledger's
already-verified backend-neutral Client and Project directory contracts work
against the local PowerSync database and isolated staging app. The two claimed
Swift leaves remain comment-only at READY.

The implementation must deliver one coherent local flow: offline Client and
Project creation appears in the directory, any currently represented active
Client can be selected, Projects split into active and archived segments, and a
selected row derives the exact existing detail request. Local rows remain useful
while completeness is stated honestly.

## Required Safety and Offline Behavior

- The runtime is bound to one exact Principal and Account. Wrong-Account reads
  or writes and wrong-Principal writes fail before any operation, overlay or
  upload row exists.
- Authoritative rows appear only behind locally visible active-membership
  evidence. The same Principal's accepted pending rows remain visible as
  partial evidence before membership readback; hidden authority cannot replace
  or reconcile them.
- Client and Project stream completeness are independent reactive inputs. A
  global connection/has-synced flag cannot make either directory ready.
- Raw Project rows are counted before Client joining. A delayed Client produces
  incomplete evidence, never an authoritative empty result.
- LocalDataVersion binds exact content and readiness rather than a maximum
  timestamp. Stable ID order is technical only and settles no final sorting.
- Project-core readback may remove the exact Project overlay only after its
  relationship is locally complete. It cannot delete pending category
  allocations without aggregate-aware authoritative allocation evidence.
- Encrypted restart and cancellation are explicit executable obligations.

## Existing Physical Dependencies

The slice adds no Postgres object. It reuses the current spike-prefixed Client,
Project and membership tables, explicit grants, RLS policies, indexes, Sync
Stream rows, encrypted schema, pending-create overlays, create stores, detail
queries, staging target, and provider-free projection contracts. Those surfaces
retain their existing primary slice ownership.

## Excluded Scope

This READY boundary does not decide or implement Project/Client archive
mutation, text mutation, final sorting/search, Project card or budget preview,
MCP pagination/list/get APIs, Firebase compatibility, source migration, hosted
Auth/PowerSync, deployment, production access, release or cutover. O-024/O-025,
O-040 and O-042/O-043 remain outside. A-003/A-004 remain proposed.

## Review and Verification Plan

The planned executable suite covers pending and authoritative rows, same-name
identity, active/archived projection, current selection revalidation, exact
detail navigation, encrypted restart, default and reactive completeness,
missing relationships, malformed rows, Account/Principal/membership isolation,
hidden-authority ordering, exact overlay cleanup, allocation preservation,
consumer cancellation, fresh-runtime integration and both staging builds.

Independent implementation review is required again after the READY checkpoint;
local SQL isolation must never be reported as hosted RLS/Sync proof.

## READY Validation

The synchronized comment-only package passes locally before commit:

- conversion/query-port/query-authority/source-query/capability/residual checks
  and M0, with only the three pre-existing retired-path warnings;
- all 342 target Swift tests in 68 suites;
- all 11 target MCP tests and strict TypeScript/contract checks;
- byte-stable target Xcode project generation;
- macOS and generic iOS Simulator staging builds;
- local Supabase database lint, 42 pgTAP assertions, and the Client and Project
  RPC/Data API authorization/replay checks.

These results prove the READY control package did not break existing target
behavior. They do not claim the comment-only provider implementation exists or
that hosted PowerSync authorization has been exercised.

The generated Xcode project also catches up its source-directory membership for
the pre-existing comment-only `ClientRenameStagingExercise.swift` DRAFT file.
That deterministic generated-project change adds no executable rename behavior;
the file remains blocked by O-042/O-043 under its existing primary ownership.
