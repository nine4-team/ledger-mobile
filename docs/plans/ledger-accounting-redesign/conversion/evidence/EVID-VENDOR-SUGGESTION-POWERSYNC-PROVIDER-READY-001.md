# EVID-VENDOR-SUGGESTION-POWERSYNC-PROVIDER-READY-001 — Vendor Suggestion Offline Picker Candidate

- Status: DRAFT / independent READY review returned NO-GO; executable work is decision-blocked
- Date: 2026-09-06
- Environment: dedicated target worktree only
- Production/Firebase impact: none
- Slice: `vendor-suggestion-powersync-provider-and-picker`
- Claimed leaves: 10 comment-only files plus one runner-valid, explicitly skipped pgTAP scaffold

## Outcome Proposed

The rejected candidate would have let an active member read the Account's active
and archived vendor-suggestion rows and select only active rows. Product authority
does not yet approve that reader population, broad archived-row disclosure, or
the proposed picker/free-text behavior, so none may be implemented from this
draft. Any eventual selection remains record-owned source text and cannot create
Vendor or accounting identity.

This is a rejected design candidate, not a real offline read workflow, executable
picker, or current-app parity implementation. If O-026/O-047 later authorize a
reader and this candidate is refrozen, its target table would initially be empty
unless separately authorized population work exists; this draft creates no
hardcoded defaults, Firebase import, writer, population, or curation behavior.

## Authority and Candidate Selection

The verified provider-free contract
`vendor-suggestion-reference-read-contracts.json` and
`EVID-VENDOR-SUGGESTION-REFERENCE-001` own identity, value, lifecycle, order,
revision, readiness and free-text-only selection semantics. The canonical
accounting spec keeps vendor/source evidence on its owning record. Architecture
03/04/06 owns offline truth, narrow ports and authorization boundaries.

Three initial read-only audits ranked this above the remaining candidates, but
the required adversarial READY review found that those audits had mistaken a
provider-free value contract and general architecture for product entitlement:

- Vendor suggestions have a complete provider-free value/query shape, but
  O-026/O-047 leave reader roles, archived disclosure and picker behavior open.
- A Space-template browser would stop before apply/save and therefore has less
  immediate product value.
- Project/Client/Space writers remain blocked on unresolved text, lifecycle,
  no-change and command-authorization policy.

The final review therefore returned NO-GO. O-026 blocks the shared-reference
authorization matrix; O-047 now owns read entitlement, archived disclosure and
picker/free-text behavior. The provider-free snapshot remains useful only after
an authorized subset has been established elsewhere.

## Frozen Candidate Boundary

- After O-026/O-047 approval, a new READY candidate may add
  `public.spike_vendor_suggestions` with exact Account identity, preserved
  display value, stored normalized comparison key, active/archive lifecycle,
  UInt32-range order and a revision preserving `0...UInt64.max`. Account-scoped identity, normalized
  key and presentation order are unique.
- Reject blank, edge-whitespace, control-containing or over-200-byte display
  values. The local provider reconstructs the verified Swift value and rejects
  any stored normalized key that disagrees; database `lower()` alone is not
  treated as cross-runtime authority.
- Enable and force RLS with least-privilege grants and the approved O-026/O-047
  read policy. Reader roles and broad-versus-contextual archived Sync remain open.
- Add a parameterized PowerSync stream only after the same policy is approved;
  parameters narrow scope but do not authorize it, and revision uses canonical
  unsigned decimal text.
- After O-026/O-047 approval, preserve the complete approved local
  authorization/capability sentinel; membership may be one required input but
  is not sufficient authorization. Only current-process exact-stream completion
  followed by a causally later reread may become ready or authoritative empty.
  Restart, generic last-sync status and retained stream epochs are never
  completeness.
- The provider owns its subscription and every observation task, rejects late
  watches and drains them before the Account workspace closes SQLite.
- Add presentation, AppModel, runtime and isolated picker only after O-047 fixes
  readiness, stable-ID selection, clearing and independent free-text behavior.
- Add no MCP surface because this slice has no MCP consumer.

## O-026 Exclusions

No suggestion add, default seed, save-as-suggestion, rename, merge, archive,
reactivate, reorder, mutation capability, settings control, fixed/excluded
option policy, source import or current Firebase picker replacement is included.
Current Firebase whole-array/default-seeding behavior is source evidence, not a
target design to copy.

## READY Leaves

| Surface | Path | Candidate responsibility |
|---|---|---|
| `CONFIG-C35C70C22D3B` | `supabase/migrations/20260906061012_vendor_suggestion_reference_read.sql` | SELECT-only schema/RLS migration |
| `CONFIG-F2A050C625BB` | `supabase/tests/vendor_suggestion_reference_read.test.sql` | pgTAP schema/security verification |
| `CONFIG-456D371094F4` | `scripts/test-local-vendor-suggestion-read.mjs` | disposable Data API verification |
| `SWIFT-1854C369125A` | `LedgeriOS/LedgerTargetPowerSync/VendorSuggestionPowerSyncQuery.swift` | local provider and subscription ownership |
| `TEST-7C2F42BE6C1D` | `LedgeriOS/LedgerTargetPowerSyncTests/VendorSuggestionPowerSyncQueryTests.swift` | provider/offline verification |
| `SWIFT-C73CD63C401A` | `LedgeriOS/LedgerTargetAppModel/VendorSuggestionPickerPresentation.swift` | pure presentation mapping |
| `TEST-A03D922ACD36` | `LedgeriOS/LedgerTargetAppModelTests/VendorSuggestionPickerPresentationTests.swift` | presentation verification |
| `SWIFT-7947DB9A7607` | `LedgeriOS/LedgerTargetAppModel/VendorSuggestionPickerAppModel.swift` | generation-safe selection/watch model |
| `TEST-46C1EA676FF3` | `LedgeriOS/LedgerTargetAppModelTests/VendorSuggestionPickerAppModelTests.swift` | AppModel verification |
| `SWIFT-92517AD05CF0` | `LedgeriOS/LedgerTargetApp/VendorSuggestionPickerRuntimeAdapter.swift` | thin target runtime adapter |
| `SWIFT-0CAF55A667DD` | `LedgeriOS/LedgerTargetApp/VendorSuggestionPickerView.swift` | isolated staging picker |

Ten listed leaves currently contain comments only. The SQL test contains one
explicitly skipped pgTAP plan so the repository-wide runner remains valid; it
makes no placeholder pass or security assertion. Generated Xcode membership and
the conversion discovery allowlist changed only so these exact files remain
visible to controls.

## Rejected Candidate Base and Future Refreeze Requirement

The rejected draft was based on exact commit
`6f1f213cc3d74ad80bb894cabd93a040fc091e37`; there is no READY commit. The
candidate named exact shared surfaces `CONFIG-428FDE11BBE4`
(`powersync/sync-streams.yaml`), `SWIFT-19D4AA7B766B`
(`LedgeriOS/LedgerTargetPowerSync/LedgerPowerSyncSchema.swift`),
`SWIFT-75CFE285AF37`
(`LedgeriOS/LedgerTargetPowerSync/AccountWorkspacePendingWorkRuntime.swift`),
`TEST-8D6A15063B2D`
(`LedgeriOS/LedgerTargetPowerSyncTests/AccountWorkspacePendingWorkRuntimeTests.swift`),
`SWIFT-061553E63650` (`LedgeriOS/LedgerTargetApp/LedgerTargetStagingApp.swift`),
`CONFIG-81235587F306` (`scripts/check-target-environment.mjs`),
`CONFIG-7AE45AD102EA` (`package.json`), `CONFIG-1FC6F8A5DFA5`
(`.github/workflows/supabase-conversion-control.yml`), `CONFIG-2EBA890AF767`
(`LedgeriOS/LedgerTarget.xcodeproj/project.pbxproj`) and `FILE-208B7E9D7F47`
(`scripts/supabase-conversion-ledger.mjs`). This list authorizes no implementation.
A future approved candidate must refreeze its exact base, leaves, shared paths,
surface IDs and mechanically generated conversion artifacts, then repeat review.

## Current Supabase Guidance Review

The 2026-09-06 Supabase changelog scan found no breaking change affecting the
conditional read-only schema/RLS/Data API design. Current official RLS and Data
API guidance requires explicit least-privilege grants and row policies, enabling
RLS on public tables, and positive/negative database policy tests. If O-026/O-047
authorize a future reader, the refrozen candidate must follow that guidance by
defining the approved narrow grants and complete authorization/capability policy and proving them with
pgTAP plus Data API verification. This blocked draft grants no authenticated
SELECT and implements no membership policy.

## Required Proof Before Promotion

The draft dossier defines thirteen future tests covering database shape, grant/RLS behavior,
Data API denial, exact Sync fields/security, encrypted local mapping, causal
readiness, restart, malformed evidence, revocation, cancellation/drainage,
runtime close ordering, pure presentation, AppModel selection, both platform
builds and immutable exact-commit CI. Real authenticated hosted PowerSync TEST-011
also blocks `verified` status, not only A-003/A-004, rehearsal and cutover status.

Independent review found three P1 blockers: invented read/archive entitlement,
invented picker/free-text behavior, and an incorrect positive-only revision
strengthening. It also required the expanded identity/token/Sync negative matrix,
explicit `implemented` ceiling before hosted TEST-011, exact base/touchpoints and
removal of the fixed/excluded-option test overclaim. These corrections are now
recorded. No executable implementation, hosted resource, Firebase edit, source
import, production access, release, migration or cutover is authorized.
