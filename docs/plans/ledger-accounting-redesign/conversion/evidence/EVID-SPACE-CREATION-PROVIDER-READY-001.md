# EVID-SPACE-CREATION-PROVIDER-READY-001 — Direct Space Creation Provider DRAFT

- Timestamp: 2026-09-05
- Class: reviewed design/DRAFT evidence; no executable implementation
- Target branch: `codex/supabase-powersync-implementation`
- Slice dossier: `space-creation-supabase-powersync-vertical-slice.json`
- Verification state: independent authority QC returned NO-GO for READY

## Outcome

The next proposed provider-backed slice was traced from canonical Space behavior
through the already-verified `CreateSpace` operation and direct-creation use case,
the existing Space destination provider, Postgres/RLS/Sync, encrypted local
optimism, isolated app presentation and target MCP parity. Twelve comment-only
target leaves reserve that boundary. They contain no executable Swift,
TypeScript, SQL, Data API request, test, hosted call, migration, release or
production behavior.

Independent review found three user-visible rules that current authority does
not settle. O-044 now owns exact cross-runtime Space-name and notes validation;
O-045 owns command-specific writer authorization; O-046 owns whether an archived
Project can receive a new Space. The combined decision packet records concrete
options, a recommendation and the acceptance tests required after approval.
The slice remains DRAFT and executable work is prohibited until all three are
approved and a corrected package passes independent READY review.

## Frozen Safe Scope

- One caller-preallocated SpaceID in one exact Account and immutable Project or
  Business Inventory scope.
- One shared operation envelope/fingerprint and zero expected-revision
  preconditions, reusing verified Core contracts without provider types.
- Encrypted atomic operation, insert-only command and separate pending Space;
  FIFO upload, exact replay, durable rejection and authoritative readback.
- Immediate pending-row visibility only in the exact active-membership
  Principal/Account/scope destination directory, always marked partial.
- Result-before-row, row-before-result, restart and membership loss/regain cannot
  clear optimism early, manufacture completeness, leak scope or resurrect a
  reconciled row.
- App and MCP use identical canonical bytes, scoped-user RPC and immutable result
  validation after O-044/O-045/O-046 are approved.
- Templates, checklists, attachments, review state, archive, Items, placement,
  accounting, Firebase, source migration, hosted resources and cutover remain
  outside.

## Discovered DRAFT Leaves

The classification batch `M0-SPACE-CREATION-POWERSYNC-PROVIDER-001` records the
exact IDs and hashes for the CLI-generated migration, planned pgTAP/Data API
leaves, PowerSync store/RPC/tests, Core-only AppModel/tests, thin app adapter/view,
and target MCP module/tests. Broad source `NewSpaceView`, `create_space`, and the
legacy Space CRUD integration suite remain mapped rather than being falsely
marked implemented by this narrower target slice.

## Shared Touchpoints Required Before READY

These remain owned by their existing slices. A corrected READY dossier must pin
their exact pre-implementation hashes and permit only the stated extension:

| Shared surface | Required bounded extension |
|---|---|
| existing `spike_spaces` migration / `CONFIG-048B775BE4E4` | Add notes and trusted creation/update audit fields without weakening scope, RLS, indexes or direct-write denial |
| local schema / `SWIFT-19D4AA7B766B` | Add only insert-only Space-create command and local-only pending-Space storage/indexes |
| destination query / `SWIFT-0A528DE84879` | Merge exact Principal/Account/scope optimism as partial while preserving membership/completeness/causality rules |
| Sync Streams / `CONFIG-428FDE11BBE4` | Reuse exact Project/Inventory Space streams and admit only the scoped immutable create result if not already covered |
| upload connector / `SWIFT-A9F7D22095F8` | Dispatch and validate only create-space-v1 through existing FIFO/result handling |
| workspace runtimes / `SWIFT-75CFE285AF37`, `SWIFT-548A8A928FAE` | Construct/expose the one typed create path and retain existing close/drain isolation |
| runtime tests / `TEST-8D6A15063B2D` | Prove pending-work accounting, bootstrap unwind, close races and observer drainage |
| staging composition / `SWIFT-061553E63650` | Compose only the isolated synthetic Space-create exercise |
| contracts / `CONFIG-B2A2BF619303`, `MCPMOD-C5E2CD8754AB` | Add the one versioned operation/result/error vocabulary and regenerate exact projections |
| package/project / `CONFIG-031396750B85`, `CONFIG-77D38BB6819B`, `CONFIG-2EBA890AF767` | Include the claimed target leaves and deterministically regenerate only the standalone target project |
| package/workflow/checkers / `CONFIG-7AE45AD102EA`, `CONFIG-1FC6F8A5DFA5`, `CONFIG-81235587F306`, `FILE-A6E49E3815F4` | Invoke only new local tests and enforce claimed-leaf/provider/Firebase/hosted boundaries |
| conversion controls / `FILE-208B7E9D7F47`, `CONFIG-A8BD153106B8` | Discover the three config leaves and re-acknowledge only exact authorized package/workflow fingerprints |

No READY review may treat these as implicit implementation permission or assign
them a second primary slice.

## Guardrails

A-003/A-004 remain proposed. Hosted authenticated PowerSync, A-016 offline lease,
production profiling, Firebase, source import, deployment, release and cutover
remain separately gated. This DRAFT is not Supabase migration authorization.
