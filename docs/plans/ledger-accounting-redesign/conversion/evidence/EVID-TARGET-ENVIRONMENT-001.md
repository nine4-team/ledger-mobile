# EVID-TARGET-ENVIRONMENT-001 — Isolated Target Environment Foundation

- Timestamp: 2026-09-01
- Class: implementation / environment isolation / local offline foundation
- Repository baseline: `16cfa68c79e5fabcf04c0749f533c1c6cfad5f4e`
  on `codex/supabase-powersync-implementation`; checkpoint worktree was dirty
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6`
  on `firebase`
- Target environment: synthetic target staging identifiers only
- Contract version fixture: schema/query/operation/sync `1`
- Production reads or mutations: none
- Hosted Supabase/PowerSync resources created or contacted: none
- Operator: Codex

## Surfaces

- `CONFIG-1FC6F8A5DFA5` — target boundary/test/build CI definition
- `CONFIG-031396750B85` — standalone target Swift package graph
- `CONFIG-2EBA890AF767` — generated standalone target application project
- `CONFIG-634171BE50F3` — target-only staging scheme
- `CONFIG-77D38BB6819B` — reproducible target project specification
- `CONFIG-81235587F306` — dependency/import/source-contamination guard
- `FILE-A6E49E3815F4` — known Firebase-production identifier binary guard
- `SWIFT-061553E63650` — fixed unprovisioned staging application shell
- `SWIFT-481A2D09BC68` — target environment and local namespace contracts
- `TEST-0AD8A0619179` — deterministic target contract suite
- `CONFIG-D94C7653FB36` — inspected unchanged source application project

## Result

The first target foundation is compiled outside the Firebase application:

- `LedgerTargetCore` is a public Swift package library with no package
  dependencies and no Firebase, Supabase, PowerSync, or Google Sign-In import;
- `LedgerTargetCoreTests` depends only on that library;
- a separate generated `LedgerTarget.xcodeproj` builds one
  `LedgerTargetStaging` application for iOS and macOS from a committed
  XcodeGen specification;
- the generated project and scheme are byte-stable across repeated generation,
  use bundle `apps.nine4.ledger.staging`, display/product name
  `Ledger STAGING`, and link only the local target core;
- the app projection is fixed at compilation, displays
  `STAGING • NO HOSTED SERVICES`, and uses only explicit
  `unprovisioned-*-staging` resource identifiers;
- the pull-request workflow defines a separate macOS target job for the
  boundary check, package suite, macOS build, iOS Simulator build, and clean
  tracked-diff check; the job has not yet produced external run evidence;
- the source `LedgeriOS.xcodeproj` has no target-only source/test references;
- the target environment kind is closed to local, staging, and production
  target values, so Firebase cannot be selected as a target runtime;
- a manifest must bind every closed component exactly once to the same
  environment, exact build identity, exact contract versions, and explicit
  allowlists before dependencies can be constructed;
- stable diagnostics reject unsafe/forbidden identifiers without echoing them;
  and
- database, encryption-key, operation-queue, attachment-cache, and keychain
  namespaces are deterministic across restart and isolated by bundle,
  environment, Principal, and Account.

The current Firebase application project file has no checkpoint diff. An early
test run against the existing app target passed the same ten tests but booted
the source-era Firebase-linked test host; that result was deliberately not used
as isolation proof. The contracts and suite were moved into the standalone
package, and the dependency-free package result below is the accepted evidence.

## Reproduction

```bash
node --check scripts/check-target-environment.mjs
npm run target:environment:check
npm run target:environment:test
npm run target:project:generate
xcodebuild -project LedgeriOS/LedgerTarget.xcodeproj \
  -scheme LedgerTargetStaging -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project LedgeriOS/LedgerTarget.xcodeproj \
  -scheme LedgerTargetStaging -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
git diff -- LedgeriOS/LedgeriOS.xcodeproj/project.pbxproj
```

Results on 2026-09-01:

- target graph/import/source-contamination check: pass;
- Swift package build: pass;
- twelve tests in one suite: pass;
- repeated XcodeGen project/scheme SHA-256 values: stable
  (`0657194a…` and `388303af…`);
- macOS target staging app build: pass;
- generic iOS Simulator target staging app build: pass;
- recursive byte scan of both compiled app bundles found the staging bundle and
  unprovisioned PowerSync identifiers and found none of the known Firebase or
  target-production identifiers;
- source application project diff: empty.

## Proven Test Obligations

- `TARGET-ENV-TEST-001`: complete manifests validate; forbidden runtime kinds,
  mixed resources, contract mismatches, unsafe identifiers, and pre-bootstrap
  dependency construction fail deterministically.
- `TARGET-ENV-TEST-002`: a mixed PowerSync environment and known production
  identifiers are rejected before dependency construction.
- `TARGET-ENV-TEST-003`: local namespaces are stable for the same identity
  after restart and distinct across Principal and Account inputs.
- `TARGET-ENV-TEST-004`: a stale persisted environment binding is rejected
  before the local-state opener runs; sentinel existing bytes remain unchanged,
  and the matching binding reopens the same isolated state.

## Explicit Limits

This is partial evidence for an `in_progress` technical-control slice. It does
not prove:

- an external CI run, signed staging distribution, visual/physical-device
  banner verification, deep links, update feed, or actual hosted-resource
  projection;
- the complete build/release operational gate
  (`TARGET-ENV-TEST-005`);
- Supabase Auth, Postgres, RLS, Storage, PowerSync Sync Streams, or the
  A-003/A-004 vertical spike; or
- deployment, migration, cutover, or production authority.
