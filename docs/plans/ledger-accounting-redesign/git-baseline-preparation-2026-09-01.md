# Ledger Git Baseline Preparation Result

Date: 2026-09-01
Preparation worktree: /Users/benjaminmackenzie/.codex/worktrees/1715/ledger_mobile
Supplied snapshot HEAD: d83c64724fe4e92be27c62f425979bd30fcfc9bb
Current Firebase baseline: fe018501d67cc84b6f140b2645b8a8149ea5c4f6
Current Firebase branch: firebase
Dedicated redesign branch: codex/supabase-powersync-implementation
Production changes performed: none
History rewrites, releases, deployments, cutovers, or production mutations: none

This file records both the initial audit and the completed preparation. It is
not one of the 197 pre-existing dirty paths counted below.

## Executive Result

Git preparation is complete under the branch policy confirmed by the owner:
`firebase` and `main` represent the latest current Firebase application, while the
accounting redesign and Supabase/PowerSync program stay on a dedicated branch.

- Local and remote `firebase` and local/remote `main` all resolve to
  `fe018501d67cc84b6f140b2645b8a8149ea5c4f6`.
- GitHub's default branch and `origin/HEAD` point to `firebase`; remote `dev` is
  absent after the coordinated rename.
- The shared branches were advanced only by fast-forward. No merge commit,
  force-push, reset, rebase, or history rewrite was used.
- The original shared checkout at `/Users/benjaminmackenzie/Dev/ledger_mobile`
  is clean on local `firebase`, tracking `origin/firebase`, at `fe018501`.
- Its exact 197-path pre-cleanup state remains recoverable as stash
  `beab1eef154623ac38ad28accd4d87e354360904` with message
  `pre-supabase-branch-cleanup-2026-09-01`.
- The 16 current Firebase implementation paths are commit `fe018501`.
- The 64 accounting/product redesign paths and four supporting non-item audit
  paths are commit `59077f14` on the dedicated redesign branch.
- The 69 conversion architecture/control paths and 44 generated-evidence paths
  are commit `3e1d435b` on the dedicated redesign branch.
- No accounting-redesign, Supabase, PowerSync, conversion-control, or generated
  evidence path is present on `firebase` or `main`.
- The live production Sparkle feed and release notes still match the build 83
  files inherited from the prior `origin/dev` tip. This preparation did not
  release or deploy the new Firebase implementation commit.
- No Git tags, GitHub Releases, GitHub deployments, branch protections, or
  repository rulesets exist. Git alone does not prove the current TestFlight
  build or external-tester state.
- The supplied snapshot contains 57 modified tracked paths and 140 untracked
  paths: 197 paths total.
- Ownership is classifiable for every supplied path: 16 current-release
  implementation paths, 64 accounting/product redesign paths, 69 conversion
  control/architecture paths, and 48 evidence paths. No unrelated or
  classification-ambiguous path was found.
- The conversion controls pass with zero errors. One expected warning records
  that build 82 release notes were deliberately retired by the committed build
  83 publication; build 83 is classified as the current source-only release
  evidence.

## Final Git Topology

| Ref | SHA | Purpose |
| --- | --- | --- |
| local/remote `firebase` | `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` | current and GitHub-default Firebase application baseline |
| local/remote `main` | `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` | same current Firebase application baseline |
| `origin/codex/supabase-powersync-implementation` | `3e1d435ba0205cfc0705ef242dc64a4250fb7aa5` before this final audit commit | dedicated redesign program |

The requested rename from `dev` to `firebase` was completed after the baseline
preparation through a coordinated create/change-default/delete sequence. The
Firebase commit did not change: `firebase` and `main` remain at `fe018501`.
GitHub's default branch and `origin/HEAD` now resolve to `firebase`, remote
`dev` was removed, and the dedicated Supabase branch/worktree was not modified.

## Pre-execution Git Topology After Fetch

The audit ran:

    git fetch --all --tags --prune --verbose

Fetch changed only remote-tracking metadata. origin was already current.
skeleton/main advanced from e14a5e6a to 6d6d0f1e; that unrelated remote is not
part of the Ledger branch recommendation.

| Ref | SHA | Relationship |
| --- | --- | --- |
| supplied snapshot / local dev | d83c64724fe4e92be27c62f425979bd30fcfc9bb | local dev, checked out in the original shared worktree; one commit behind origin/dev |
| origin/dev | 369979cb579d9a6fd665c4ae68b9b0bbc7353486 | server default branch tip; Sparkle build 83 artifacts |
| local main | 7ef25018630ed359ec88abc5e5e2e0bd6cfc927a | 187 commits behind origin/main |
| origin/main | 48cd1dd60a656cbb5e39c705643d9dc1776ca337 | strict ancestor of origin/dev |
| server default | dev | confirmed by git remote show origin and GitHub repository metadata |
| cached origin/HEAD | origin/main | stale local symbolic ref; do not use as authority until refreshed |

Pairwise rev-list left/right counts:

| Comparison | Left-only | Right-only | Merge base |
| --- | ---: | ---: | --- |
| dev...origin/dev | 0 | 1 | d83c64724fe4e92be27c62f425979bd30fcfc9bb |
| main...origin/main | 0 | 187 | 7ef25018630ed359ec88abc5e5e2e0bd6cfc927a |
| dev...main | 409 | 0 | 7ef25018630ed359ec88abc5e5e2e0bd6cfc927a |
| dev...origin/main | 222 | 0 | 48cd1dd60a656cbb5e39c705643d9dc1776ca337 |
| origin/dev...main | 410 | 0 | 7ef25018630ed359ec88abc5e5e2e0bd6cfc927a |
| origin/dev...origin/main | 223 | 0 | 48cd1dd60a656cbb5e39c705643d9dc1776ca337 |

Ancestry checks:

    git merge-base --is-ancestor origin/main origin/dev
    # exit 0

    git merge-base --is-ancestor origin/dev origin/main
    # exit 1

Relevant release commits:

- d83c6472: chore(release): prepare build 83; changes only the Xcode project
  version from the prior build to 83.
- 369979cb: chore(release): publish Sparkle build 83 artifacts; adds the build
  83 notes/ZIP and updates the appcast.
- origin/main contains 31173f8d, Prepare build 19 release, followed by
  48cd1dd6, Document external TestFlight distribution. Its Xcode project
  version is 19, while origin/dev is version 83.

Release metadata:

- git tag --list count: 0
- gh release list count: 0
- GitHub deployments returned: 0
- dev branch protection: absent
- main branch protection: absent
- repository rulesets returned: 0

## Production-Baseline Evidence

The live feed at https://ledger-nine4.web.app/sparkle/appcast.xml advertises
Ledger 1.0 build 83, published 2026-08-31. The following comparisons match:

    git show origin/dev:firebase/hosting/sparkle/appcast.xml | shasum -a 256
    curl -fsSL https://ledger-nine4.web.app/sparkle/appcast.xml | shasum -a 256
    # both 38c0cd711bf94a266c8ed42ee56dd22fbc13864c6adf0bb9c617566b96b91d5a

    git show origin/dev:firebase/hosting/sparkle/Ledger-1.0-83.md | shasum -a 256
    curl -fsSL https://ledger-nine4.web.app/sparkle/Ledger-1.0-83.md | shasum -a 256
    # both 8dc28372044c1b02be9ed653d9bac14eca0b32a054c183ffb3b574d2ef9a098a

The live ZIP reports content-length 21823732, matching the appcast and the file
committed by 369979cb.

Conclusion: origin/dev has a proved current macOS production artifact. main is
an ancestor containing an older build-19 release preparation, but there is no
tag, release manifest, deployment record, or current live artifact that makes
main the current production baseline. Do not call main "production" merely
because of its name. The current TestFlight/external-tester build still requires
read-only App Store Connect evidence if exact iOS deployment correspondence is a
release decision.

## Pre-execution Provenance and Commit-Boundary Finding

Task records were available and support the path classification:

- 01a05033-f5e2-7582-8fa9-90e45c149338 authored the current ProtoItem/Quick Add
  implementation and the accounting/product redesign specifications and impact
  analysis.
- 01a0597e-a903-72f1-83da-ad0e7d114ac0 authored the Supabase/PowerSync
  architecture, conversion control plane, classification batches, generated
  audits, evidence, and continuity mechanisms.

Repository evidence agrees with those task records:

- Current-release diffs are limited to Swift ProtoItem/assignment UI, matching
  MCP schemas/projections, and focused encoding/schema tests.
- Product documents establish the target accounting model and explicitly mark
  older Firebase-era plans as current or historical evidence.
- Conversion files consistently cite source baseline d83c6472, the dirty shared
  worktree, and zero production or target implementation.
- The required conversion check passes with 686 recorded surfaces, 674
  discovered surfaces, zero errors, and zero warnings.

The critical dependency is machine-verifiable:

    shasum -a 256 LedgeriOS/LedgeriOS/Models/ProtoItem.swift
    # 807954a69ecf0f4f96592bbcec3c2802e9c615d0abfb5d0f6a92e2c059bb9b05

    git show HEAD:LedgeriOS/LedgeriOS/Models/ProtoItem.swift | shasum -a 256
    # 1e77f7e50c4bf39b7ac2e988879390256becdffca5822bc5a6382d45ee4066d1

    shasum -a 256 mcp-server/src/tools/quick-draft-items.ts
    # 7d5dcc7ea29a52f952a67a9b57f486793baf5e7f317fa7b927bc25f365459367

    git show HEAD:mcp-server/src/tools/quick-draft-items.ts | shasum -a 256
    # 4f77cc0a4c6e999d15fc2eeb05091d4cda33f79709a9ddc049a116dc3007a903

conversion-manifest.json acknowledges the dirty-current hashes, not the HEAD
hashes, under M0-ITEM-CREATION-LINK-001. Therefore:

1. committing conversion control without the current-release implementation
   creates a non-reproducible commit;
2. committing all 197 files together improperly bundles release code, product
   authority, architecture, control machinery, and evidence; and
3. committing the current-release implementation first requires an explicit
   owner decision because it persists assignmentHint/clientPaid/businessPaid/
   fromInventory on Firebase ProtoItems, while the later target decisions retire
   proto writers, recommend no persisted payer hint, and keep Firebase changes
   restricted to pre-cutover compatibility.

This was the ambiguity before the owner confirmed that the 16-file Firebase
implementation belongs in the current release baseline. That decision allowed
the dependency-safe commit order recorded above.

## Verification Results

Passed:

    node scripts/supabase-conversion-ledger.mjs check
    # 687 recorded, 674 discovered, 0 errors, 1 expected retired-source warning

    npm run conversion:capabilities:check
    # generated artifacts current

    npm run conversion:queries:check
    # generated artifacts current

    npm run conversion:residuals:check
    # 263 mapped, 164 residual, 43 blockers

    npm run conversion:gate:m0
    # M0 PASS: Inventory classified

    npm run conversion:report
    # 687 recorded, 674 discovered, 0 errors, 1 expected retired-source warning

    npm run conversion:profiles:check-readonly
    # no recognized mutation APIs; execution gates retained

    git diff --check
    # pass

    node --check on both continuity/conversion hooks and all ten new .mjs scripts
    # pass

    Ruby YAML parse of .github/workflows/supabase-conversion-control.yml
    # pass

    JSON.parse over 67 dirty/new JSON files
    # pass

    relative-link validation over 99 redesign architecture/program/spec Markdown files
    # pass

    cd mcp-server && npm ci && npm run build
    # TypeScript build pass

    cd mcp-server && npx vitest run test/item-image-tool-schema.test.ts \
      --pool=forks --poolOptions.forks.singleFork
    # 1 file, 2 tests passed; no emulator variables enabled

    cd LedgeriOS && xcodebuild test -scheme LedgeriOS \
      -destination 'platform=iOS Simulator,name=iPhone 17e' \
      -only-testing:LedgeriOSTests/ModelCodableTests \
      -derivedDataPath DerivedData -quiet
    # exit 0; focused changed Codable surface passed under the plain scheme

Expected blocked gates:

    npm run conversion:gate:m1
    # M1 BLOCKED: 2 coverage blockers, 0 structural errors

    npm run conversion:gate:m2
    # M2 BLOCKED: 164 coverage blockers, 0 structural errors

The plain LedgeriOS unit suite was run with all emulator-backed integration
suites skipped:

    cd LedgeriOS
    xcodebuild test -scheme LedgeriOS \
      -destination 'platform=iOS Simulator,name=iPhone 17e' \
      -skip-testing:LedgeriOSTests/ItemCRUDIntegrationTests \
      -skip-testing:LedgeriOSTests/TransactionCRUDIntegrationTests \
      -skip-testing:LedgeriOSTests/RelationshipIntegrationTests \
      -skip-testing:LedgeriOSTests/SpaceCRUDIntegrationTests \
      -skip-testing:LedgeriOSTests/InventoryOperationsIntegrationTests \
      -derivedDataPath DerivedData -quiet

Result: build succeeded; 1,034 tests passed and two pre-existing, out-of-scope
tests failed:

- InvoiceReportAggregationTests/fallbackPrice(): expected a fallback-price row
  to be marked missing, but isMissingPrice was false.
- TransactionCreationStepResolverTests/plannedPurchaseRequiresProjectPrice():
  expected missingProjectPrices, received readyToSell.

Neither failing test nor its production calculation file is modified in the
supplied snapshot. All 24 ModelCodableTests passed, including the modified
ProtoItem encoding coverage. The current-release UI compiled. The result bundle
is:

    LedgeriOS/DerivedData/Logs/Test/Test-LedgeriOS-2026.09.01_12-19-47--0700.xcresult

MCP npm ci reported 34 dependency audit findings (2 low, 15 moderate, 14 high,
3 critical). No dependency update or audit fix was attempted because that would
change the lock graph beyond this preparation task.

## Executed Commit, Push, and Cleanup Sequence

1. Fetched and rechecked remote tips and ancestry. `origin/main` was an ancestor
   of `origin/dev`; neither remote moved during preparation.
2. Created `fe018501` on top of the published build 83 commit and verified the
   changed Swift/MCP surface. Atomically fast-forwarded both `origin/dev` and
   `origin/main` to that commit.
3. Created `codex/supabase-powersync-implementation` from `fe018501` and made two
   separate commits: product authority/supporting audit (`59077f14`) and
   conversion architecture/control/generated evidence (`3e1d435b`).
4. Updated the recorded Firebase source baseline to `fe018501`, classified the
   build 82-to-83 release-evidence transition, regenerated derived reports, and
   reran the conversion controls before committing.
5. Pushed the dedicated redesign branch without merging it into either shared
   branch.
6. Compared all 197 original dirty paths with the committed branch package.
   Thirteen paths differed only because this isolated preparation had advanced
   their baseline/control metadata and generated derivatives. Preserved the
   exact original state in recoverable stash `beab1eef`, then fast-forwarded the
   original checkout and local `main` to `fe018501`.
7. Coordinated the shared-branch rename after preparation: created/preserved
   `firebase` at `fe018501`, changed the GitHub default and `origin/HEAD` to
   `firebase`, moved the original checkout to local `firebase` tracking
   `origin/firebase`, and removed remote `dev`. The Supabase branch/worktree was
   left unchanged.

## Remaining Decisions and Coordination

1. Add the conversion workflow as a required check before any redesign branch
   is merged. The repository currently has no protection/ruleset enforcement.
2. Query App Store Connect read-only if exact TestFlight build/external-tester
   correspondence is needed; Git and the Sparkle feed prove only the macOS
   build-83 lineage.
3. Product, hosted-resource/spend, migration, release, deployment, and cutover
   approvals remain separate. This preparation grants none of them.

## Complete Supplied-Snapshot Inventory

Status legend: M = modified tracked path; ?? = untracked path.

### Current release implementation (16)

- M  LedgeriOS/LedgeriOS/Components/ItemDraftCard.swift
- M  LedgeriOS/LedgeriOS/Logic/TransactionMenuBuilder.swift
- M  LedgeriOS/LedgeriOS/Models/ProtoItem.swift
- M  LedgeriOS/LedgeriOS/Views/Creation/ItemDraftCaptureSheet.swift
- M  LedgeriOS/LedgeriOS/Views/Creation/NewItemView.swift
- M  LedgeriOS/LedgeriOS/Views/Projects/ItemQuickDraftDetailView.swift
- M  LedgeriOS/LedgeriOS/Views/Projects/ItemsTabView.swift
- M  LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift
- M  LedgeriOS/LedgeriOS/Views/RootView.swift
- M  LedgeriOS/LedgeriOSTests/ModelCodableTests.swift
- M  mcp-server/src/tools/quick-draft-items.ts
- M  mcp-server/src/tools/schema.ts
- M  mcp-server/src/types.ts
- M  mcp-server/src/util/enums.ts
- M  mcp-server/src/util/projections.ts
- M  mcp-server/test/item-image-tool-schema.test.ts

### Accounting/product redesign specs (64)

- ?? docs/plans/inventory-project-net-ledger/report-source.md
- ?? docs/plans/invoice-centered-project-accounting/impact-analysis.md
- ?? docs/plans/ledger-accounting-redesign/README.md
- ?? docs/plans/ledger-accounting-redesign/decision-log.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-002-O-011-O-014-transfer-edge-policy.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-003-O-004-O-005-O-010-client-credit-and-zero-invoice.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-006-O-033-expense-locks-and-collection-payment.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-007-O-015-item-accounting-and-provenance.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-008-O-030-receipt-line-treatment-and-rounding.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-009-O-034-invoice-adjustments-and-sent-revisions.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-016-O-017-O-027-item-capture-and-acquisition-readiness.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-018-O-020-O-022-proto-migration-and-authority-cutover.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-023-attachment-reference-and-retention.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-024-O-025-project-and-client-lifecycle.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-026-shared-reference-data-authorization.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-028-vendor-adjustment-and-credit-balance.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-029-O-032-transaction-posting-and-lifecycle.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-031-item-tax-and-acquisition-basis.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-035-O-036-client-summary-and-shared-evidence.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/O-037-space-archive-and-item-assignment.md
- ?? docs/plans/ledger-accounting-redesign/decision-packets/README.md
- ?? docs/plans/ledger-accounting-redesign/item-intake-handoff.md
- ?? docs/plans/non-item-receipt-lines/design.md
- M  docs/plans/returned-paid-item-credit-plan.md
- M  docs/plans/transaction-taxonomy-execution-plan.md
- M  docs/plans/transaction-taxonomy-master-tracker.md
- M  docs/plans/transaction-taxonomy-migration-impact-audit.md
- M  docs/plans/transaction-taxonomy-open-decisions.md
- M  docs/plans/transaction-taxonomy-system-design-recommendation.md
- M  docs/plans/transaction-type-migration.md
- M  docs/specs/README.md
- M  docs/specs/_app-map.md
- M  docs/specs/_changelog.md
- M  docs/specs/_index.md
- M  docs/specs/add-existing-items.md
- M  docs/specs/agent-transaction-taxonomy-guide.md
- M  docs/specs/authentication-offline-access.md
- M  docs/specs/billing-invoicing.md
- M  docs/specs/budget-management.md
- ?? docs/specs/client-identity-and-project-transfers.md
- M  docs/specs/data-model.md
- M  docs/specs/financial-access-controls.md
- M  docs/specs/inventory-as-store.md
- ?? docs/specs/inventory-item-invoicing-lifecycle.md
- M  docs/specs/inventory-source-naming.md
- ?? docs/specs/invoice-centered-project-accounting.md
- M  docs/specs/invoice-redesign-change-plan.md
- M  docs/specs/invoice-transaction-redesign-draft.md
- M  docs/specs/item-entry-flow.md
- M  docs/specs/items.md
- M  docs/specs/lineage-tracking.md
- M  docs/specs/offline-first.md
- M  docs/specs/projects.md
- M  docs/specs/proto-item-capture.md
- M  docs/specs/purchase-handling-and-inventory-intent.md
- M  docs/specs/reassign-vs-sell.md
- M  docs/specs/reports.md
- M  docs/specs/return-and-sale-tracking.md
- M  docs/specs/sale-transactions.md
- M  docs/specs/spaces.md
- M  docs/specs/transaction-creation.md
- M  docs/specs/transaction-type.md
- M  docs/specs/vendor-credits.md
- M  docs/specs/write-tiers.md

### Supabase/PowerSync conversion control and architecture (69)

- ?? .codex/hooks.json
- ?? .codex/hooks/ledger-conversion-continuity.mjs
- ?? .github/workflows/supabase-conversion-control.yml
- M  .gitignore
- M  AGENTS.md
- ?? docs/architecture/redesign/01-system-context-and-principles.md
- ?? docs/architecture/redesign/02-domain-and-application-architecture.md
- ?? docs/architecture/redesign/03-data-sync-and-offline.md
- ?? docs/architecture/redesign/04-backend-ports-and-adapters.md
- ?? docs/architecture/redesign/05-supabase-powersync-reference.md
- ?? docs/architecture/redesign/06-security-and-access-control.md
- ?? docs/architecture/redesign/07-migration-release-and-cutover.md
- ?? docs/architecture/redesign/08-verification-observability-and-operations.md
- ?? docs/architecture/redesign/README.md
- ?? docs/architecture/redesign/architecture-decisions.md
- ?? docs/architecture/redesign/product-decision-traceability.md
- ?? docs/plans/ledger-accounting-redesign/conversion/README.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/app-shell-shared-presentation-and-test-support.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/identity-account-session-and-operation-lifecycle.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/inventory-provenance-transactions-receipts-and-corrections.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/invoicing-collection-and-budget-authority.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/media-attachments-and-offline-byte-durability.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/platform-transport-release-and-migration-control.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/projects-clients-settings-and-reference-data.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/reporting-search-and-cross-domain-projections.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/spaces-review-and-work-queues.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-dossiers/unified-item-creation-accounting-link-and-legacy-capture.md
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-evolution-method.md
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-APP-SHELL-PRESENTATION-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-BACKEND-AUTH-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-BACKEND-FUNCTIONS-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-BACKEND-RULES-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-BACKEND-STORAGE-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-CAPABILITY-CONTROL-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-CUTOVER-CONTROL-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-IDENTITY-LIFECYCLE-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-INVENTORY-TRANSACTION-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-INVOICING-BUDGET-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-ITEM-CREATION-LINK-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-MEDIA-LIFECYCLE-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-PLATFORM-CONTROL-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-PROJECT-CLIENT-REFERENCE-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-QUERY-PROFILE-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-REPORTING-SEARCH-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-RESIDUAL-CONTROL-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/classification-batches/M0-SPACES-REVIEW-001.json
- ?? docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json
- ?? docs/plans/ledger-accounting-redesign/conversion/current-backend-contract.md
- ?? docs/plans/ledger-accounting-redesign/conversion/current-capability-register.md
- ?? docs/plans/ledger-accounting-redesign/conversion/current-query-contract.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence-index.md
- ?? docs/plans/ledger-accounting-redesign/conversion/execution-state.md
- ?? docs/plans/ledger-accounting-redesign/conversion/implementation-slices/_template.json
- ?? docs/plans/ledger-accounting-redesign/conversion/product-authority-crosswalk.json
- ?? docs/plans/ledger-accounting-redesign/conversion/target-mapping-method.md
- ?? docs/plans/ledger-accounting-redesign/conversion/vertical-slice-implementation-method.md
- ?? docs/plans/ledger-accounting-redesign/implementation-tracker.md
- ?? docs/plans/ledger-accounting-redesign/pre-cutover-testing-plan.md
- ?? docs/plans/ledger-accounting-redesign/production-compatibility-plan.md
- ?? docs/plans/ledger-accounting-redesign/vertical-spike-protocol.md
- M  package.json
- ?? scripts/check-firebase-readonly-profilers.mjs
- ?? scripts/extract-current-capability-surfaces.mjs
- ?? scripts/extract-firestore-query-contract.mjs
- ?? scripts/generate-m2-residual-register.mjs
- ?? scripts/lib/firebase-readonly-profile.mjs
- ?? scripts/profile-firebase-firestore-auth-readonly.mjs
- ?? scripts/profile-firebase-storage-readonly.mjs
- ?? scripts/supabase-conversion-ledger.mjs

### Generated evidence (48)

This bucket includes the read-only non-item audit producers/export helper as
evidence tooling; conversion-generated evidence itself comprises the other 44
paths.

- ?? docs/plans/ledger-accounting-redesign/conversion/capability-surfaces.generated.json
- ?? docs/plans/ledger-accounting-redesign/conversion/capability-surfaces.generated.md
- ?? docs/plans/ledger-accounting-redesign/conversion/conversion-coverage.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-APP-SHELL-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-IDENTITY-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-INVENTORY-TRANSACTION-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-INVOICING-BUDGET-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-ITEM-CREATION-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-MEDIA-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-PLATFORM-CONTROL-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-PROJECT-REFERENCE-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-REPORTING-SEARCH-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CAPABILITY-SPACES-REVIEW-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CONTINUITY-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-CONTROL-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M0-COVERAGE-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-APP-SHELL-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-BACKEND-CONTROL-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-DECISION-PACKETS-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-IDENTITY-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-INVENTORY-TRANSACTION-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-INVOICING-BUDGET-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-ITEM-CREATION-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-MEDIA-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-PLATFORM-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-PROJECT-REFERENCE-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-REPORTING-SEARCH-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-SPACES-REVIEW-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-SPIKE-PROTOCOL-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-M2-WHOLE-MANIFEST-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-PRODUCT-AUTHORITY-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-PROFILER-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-QUERY-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-SLICE-METHOD-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/evidence/EVID-SOURCE-BACKEND-001.md
- ?? docs/plans/ledger-accounting-redesign/conversion/implementation-slice-audit.generated.json
- ?? docs/plans/ledger-accounting-redesign/conversion/implementation-slice-audit.generated.md
- ?? docs/plans/ledger-accounting-redesign/conversion/product-authority-audit.generated.json
- ?? docs/plans/ledger-accounting-redesign/conversion/product-authority-audit.generated.md
- ?? docs/plans/ledger-accounting-redesign/conversion/query-contract.generated.json
- ?? docs/plans/ledger-accounting-redesign/conversion/query-contract.generated.md
- ?? docs/plans/ledger-accounting-redesign/conversion/residual-decision-register.generated.json
- ?? docs/plans/ledger-accounting-redesign/conversion/residual-decision-register.generated.md
- ?? docs/plans/non-item-receipt-line-audit-runs/2026-08-30T01-54-51-509Z.json
- ?? docs/plans/non-item-receipt-lines/production-audit-2026-08-29.md
- ?? scripts/audit-non-item-receipt-lines.mjs
- ?? scripts/export-transaction-receipt-attachments.mjs

### Unrelated/user-owned (0)

No supplied path was unrelated to the two evidenced workstreams. This does not
transfer ownership: every path remains user/other-agent-owned until its owner
approves the commit sequence.

### Ambiguous classification (0)

Every supplied path has a defensible topical bucket. Commit intent remains
ambiguous for the current-release implementation and for any control commit
that depends on its acknowledged hashes, as described above.
