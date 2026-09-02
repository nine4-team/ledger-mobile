# EVID-CLIENT-PROJECT-DIRECTORY-001 — Client/Project Directory Read Contracts

- Timestamp: 2026-09-01
- Class: implementation / provider-free Client and Project read domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-401EBD892749`, `TEST-0911D1BF8A05`
- Slice dossier:
  `conversion/implementation-slices/client-project-directory-read-contracts.json`
- Slice state: verified at exact implementation commit
  `3c0b58b66e61ab8351d823bf0e0bdcaca7d1c9ff`

## Selection and Scope

The Phase 1 audit moved from platform mechanics to the first confirmed product
identity boundary. D-006 and the canonical Client spec require one Account-
scoped Client identity and a required same-Account `project.clientId`; the
backend-neutral architecture already names `ClientProjectDirectoryQuerying` and
local Client/Project snapshots. These read contracts can be made executable
without choosing a provider, authentication system, schema, mutation policy or
any open accounting rule.

Exactly two target-only implementation surfaces are claimed in the existing
provider-free core/test targets. Existing Project models, views, MCP tools and
all Firebase code remain unadvanced. The slice deliberately stops before
creation, rename, archive commands, Client merge, Project reassignment or
physical deletion; O-024/O-025 therefore remain untouched.

## Implemented Contract

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

`ClientDisplayName` and `ProjectDisplayName` preserve exact nonblank text while
never acting as identity. `ClientSummary` carries stable Client/Account identity,
lifecycle and finite ordered audit timestamps. `ProjectSummary` retains an exact
`clientId` plus an immutable current Client summary and refuses Account or Client
ID disagreement both at construction and decode.

`ClientListSnapshot` and `ProjectListSnapshot` reuse the shared
`ListLocalSnapshot` query/readiness/version/as-of evidence, reject duplicate row
identity, and revalidate Account/relationship boundaries after restart. The
architecture-named `ClientProjectDirectoryQuerying` protocol exposes only the
two Account-scoped Client and Project watch streams. Stable directory failures
contain no display name, query, path or vendor payload.

Postgres, handlers, Data API, RLS, Sync Streams, media, concrete app/MCP wiring,
migration and observability remain explicit non-applicabilities. Later vertical
slices remain responsible for authorization/download absence, server schema and
query implementations, migration correlation and actual user-facing wiring.

## Local Verification

The reviewed Project/Client batch acknowledges only these exact implementation
hashes:

- `ClientProjectDirectory.swift` —
  `d6fcb4ae91d358433ef1f492d6df9a8f185b419c0741a7b400e53efe715a4cc5`
- `ClientProjectDirectoryTests.swift` —
  `28b22dd21d195f41f7efc30a242d1631b827f1c99f26f98207c2489b8b8bd174`

The three focused tests prove:

- exact Account/Client/Project identity, including two same-name Clients that
  remain distinct and one exact Project relationship;
- byte-identical restart for ready, partial and authoritative-empty local
  evidence; and
- atomic refusal of blank names, reversed/nonfinite audit time, cross-Account
  embedding, mismatched Client ID, duplicate identity, malformed decoded rows,
  incomplete-as-authoritative evidence and wrong-Account port use, with every
  stable diagnostic code asserted.

Local commands passed on 2026-09-01:

- `swift test --package-path LedgeriOS --filter ClientProjectDirectoryTests` —
  3 tests passed;
- `swift test --package-path LedgeriOS` — 72 tests in 15 suites passed;
- `npm run target:environment:check` — isolated graph/source boundary passed;
- `npm run target:contracts:check` — generated catalog and strict TypeScript
  compilation passed; and
- `npm run target:staging:build:macos` and
  `npm run target:staging:build:ios` — both unsigned staging builds passed.

`DIRECTORY-TEST-001` through `003` therefore pass. Immutable GitHub Actions run
[`33584456794`](https://github.com/nine4-team/ledger-mobile/actions/runs/33584456794)
also passed for exact implementation commit
`3c0b58b66e61ab8351d823bf0e0bdcaca7d1c9ff`. Its `Conversion state and
traceability` job passed the synchronized control plane and clean generated
artifacts. Its `Isolated target environment` job passed graph/source-isolation,
generated contracts, all 72 target tests, macOS and generic iOS Simulator
builds, and clean tracked artifacts. `DIRECTORY-TEST-004` and all four slice
obligations therefore pass; exactly the two claimed target-only surfaces are
`verified`.

## Permanent Limits

This read-contract implementation cannot:

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
