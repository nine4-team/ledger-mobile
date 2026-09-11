# Migration and Release Safety

Status: canonical acceptance requirements from the authorized conversion goal;
not authorization to access production, provision hosting, migrate or release.

## Target Environment Isolation

Resolve one complete environment identity before any provider SDK or local store
opens: app/MCP, Supabase, PowerSync, Auth and Storage must belong to the intended
environment. Reject missing or cross-wired configuration visibly and fail closed.
Staging uses separate installation identity, database, keychain and media state;
it cannot fall back to production credentials/endpoints or reuse Firebase state.
Verify both allowed startup and refused configurations without contacting
production. A passed isolation check does not authorize hosted provisioning.

## Whole-Account Migration and Reconciliation

The target must preserve the complete Account's intended behavior and evidence,
not only Items or records that existing readers successfully decode. Inventory
source entities, embedded relationships, identity/membership, settings, notes,
Spaces/checklists, financial records, lineage and media. Include server-only
records and pending-operation evidence in the disposition review. Preserve,
transform, quarantine or explicitly retire each source class under its owning
spec and confirmed decisions; source implementation caches are not target truth.
Unreferenced generic quota/object starter scaffolds are not Ledger features or
target arbitrary-collection writers. Inventory and quarantine any discovered
data rather than importing executable behavior or silently dropping evidence.

Use immutable, authorized fixtures and deterministic source-to-target identity
maps. Default to dry-run, require explicit environment and Account scope, retain
raw evidence, and journal resumable/idempotent imports. Unknown shapes, ambiguous
payments, orphaned relationships and unapproved semantic choices must be visible
quarantines/blockers, not guessed values or silently dropped data. Repeated runs
and interruption must not duplicate or lose records, money, relationships or
objects. Repair tooling follows the same authorization and evidence rules.

Reconcile source coverage/counts, target relationships, exact amounts, paid/open
accounting, Item identity and history, restricted visibility, and media object/
reference coverage. Explain every approved difference by source identity and
owning authority. Verify identity access and target app/MCP readback as well as
database counts. Existing Client, proto, receipt and financial migration stories
remain the detailed owners; passing one does not prove whole-Account fidelity.

## Isolated Rehearsal and Rollback

Use the exact candidate artifact and declared environment/version in isolated
rehearsals, including restart, interruption/resume, restore and failure cases.
Verify iOS and macOS candidate signing, installation/channel identity, update
feed selection and artifact hashes as well as local-data compatibility. A
session-retention test alone does not prove release or signature safety.
Local proof does not replace hosted Supabase/PowerSync and physical-device
validation. Request authorization before hosted resources or production source
access; never read live production simply to finish this checklist.

Before authorized cutover, prove a final-source boundary, backup/restore,
reconciliation, stale-writer rejection/recovery and controlled authority opening.
O-018, O-020 and O-022 retain their existing product gates; this contract does
not select their unresolved policies. Production activation is separately
authorized and uses the tested artifact, not an unreviewed live repair.

Exercise rollback before target authority opens and recovery after target writes
begin. Do not point users back to stale Firebase after target-only writes:
preserve accepted work and evidence, stop unsafe writes, and follow a tested
forward recovery or explicitly approved reconciled back-migration. Record the
last reversible boundary and failure evidence in the existing workflow record.
Do not delete source evidence or old media merely because migration succeeded.

The proposed [migration architecture](../architecture/redesign/07-migration-release-and-cutover.md)
supplies technical design context, not approval of unresolved choices or
production operations. No Firebase v2 implementation, adapter or dual writing
is required. Signed app distribution follows the [app-shell contract](app-shell.md).
