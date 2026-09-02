# EVID-CLIENT-PROJECT-DIRECTORY-001 — Client/Project Directory Read Contracts

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free Client and Project read domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-401EBD892749`, `TEST-0911D1BF8A05`
- Slice dossier:
  `conversion/implementation-slices/client-project-directory-read-contracts.json`
- Ready-gate state: ready; behavior and executable self-tests are not yet
  implemented

## Selection and Scope

The Phase 1 audit moved from platform mechanics to the first confirmed product
identity boundary. D-006 and the canonical Client spec require one Account-
scoped Client identity and a required same-Account `project.clientId`; the
backend-neutral architecture already names `ClientProjectDirectoryQuerying` and
local Client/Project snapshots. These read contracts can be made executable
without choosing a provider, authentication system, schema, mutation policy or
any open accounting rule.

Exactly two target-only comment scaffolds are claimed in the existing
provider-free core/test targets. Existing Project models, views, MCP tools and
all Firebase code remain unadvanced. The slice deliberately stops before
creation, rename, archive commands, Client merge, Project reassignment or
physical deletion; O-024/O-025 therefore remain untouched.

## Ready-Gate Contract

The dossier freezes six exact canonical/architecture requirements and requires:

- stable `ClientID` and `ProjectID` values under one immutable `AccountID`;
- a current Client summary with required display name, lifecycle and ordered
  audit timestamps;
- a Project summary whose current Client uses the exact same Account and whose
  display name can never substitute for identity;
- validated duplicate-free Client/Project list snapshots built on the verified
  query fingerprint, readiness/quality, completeness, `LocalDataVersion` and
  as-of contract;
- the exact provider-free `ClientProjectDirectoryQuerying` watch port named by
  architecture; and
- stable restart/refusal proof with no database, PowerSync, network, provider,
  app/MCP entry point, source transform or production behavior.

Postgres, handlers, Data API, RLS, Sync Streams, media, concrete app/MCP wiring,
migration and observability are explicit non-applicabilities. Later vertical
slices remain responsible for authorization/download absence, server schema and
query implementations, migration correlation and actual user-facing wiring.

## Ready-Gate Verification

The two comment-only hashes are acknowledged through the reviewed Project/
Client batch and both surfaces are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart,
offline-rejection and exact-commit operational obligations. Conversion checking
must pass before behavioral implementation begins.

## Permanent Limits

This ready gate and later read-contract implementation cannot:

- use Client or Project names as identity, authorization or Transfer evidence;
- choose Client merge, Project reassignment, physical deletion, creation/edit
  commands or any O-024/O-025 outcome;
- expose or authorize server rows, define RLS/Sync Streams, claim offline
  download completeness or prove cross-account absence on a physical device;
- transform Firebase `clientName`, create/backfill Clients, resolve homonyms or
  claim source migration reconciliation;
- wire current app/MCP entry points or alter either application project; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
