# EVID-TRANSFER-DESTINATION-PICKER-READY-001 — Transfer Destination Picker READY Candidate

- Timestamp: 2026-09-05
- Class: comment-only READY candidate; no executable implementation
- Target branch: `codex/supabase-powersync-implementation`
- Slice dossier: `transfer-destination-powersync-picker.json`
- Verification state: independently reviewed READY; exact commit
  `2f87445cd51d6911a0655ad611fdedf035246665` passed all three immutable jobs in
  Actions run `33989797244`

## Outcome

The candidate traces the confirmed same-Client Transfer destination story into
one target-local read/presentation slice. It reuses the verified
`TransferDestinationSelectionQuerying` contract and the existing encrypted
Client/Project directory provider. Six comment-only Swift leaves reserve the
provider composition, tests, provider-free application state, tests, thin app
adapter and isolated staging view. No executable code exists in those leaves.

The canonical behavior is complete for this boundary: candidates are other
active Projects in the same Account whose exact non-null ClientID matches the
source Project. Business Inventory, the source Project, archived destinations,
missing/different Clients, display-name matching and row position are excluded.
The caller summary supplies only stable Account/Project request identity. Every
upstream update re-resolves that ProjectID and uses the current directory row's
Client/name/lifecycle; caller-stale relationship fields never filter candidates.
The selection snapshot preserves upstream order, fingerprints, completeness,
quality, local version and observation time. Complete-ready empty and incomplete
empty remain different states.

## Why This Is a Derived Read

`TQUERY-2D53E545A090` / `TACCESS-626ED0857269` has no unresolved logical axis.
It explicitly derives from the Project directory without separate canonical
authority. Therefore implementation must not add a Transfer-destination table,
Postgres view, SQL query, index, RLS policy, Sync Stream, subscription,
completeness source, cache or MCP query. The existing Project directory remains
the sole physical read path and the verified Core initializer remains the sole
eligibility projection.

## Frozen Implementation Boundary

- `TransferDestinationSelection.swift` and its tests remain byte-exact.
- `ClientProjectDirectoryPowerSyncQuery.swift` and its tests remain byte-exact.
- One module-internal adapter maps each existing Project-directory snapshot to
  the verified source-bound Transfer-destination snapshot.
- The existing Account workspace and public facade may add one typed,
  close-aware observation path; they expose no persistence or authorization
  implementation details.
- A Core-only AppModel owns source-generation replacement, exact presentation
  states and transient represented-ID selection.
- A thin runtime adapter and isolated staging view add no production route or
  action.
- Only runtime lifecycle tests, staging composition, target-boundary checks and
  deterministic target-project source membership may change outside the six
  claimed leaves. Because the unchanged project specification discovers app
  sources recursively, regeneration will also add the two already-tracked,
  byte-frozen, declaration-free Space-creation DRAFT app files. Compiling those
  comments grants no Space implementation or READY authority. Exact
  preimplementation hashes and permitted changes are in the dossier.

## Required Proof

Implementation must prove:

- exact same-Account/same-Client/other-active-Project filtering over the real
  encrypted local Project directory, including duplicate display names and
  same-ID source Client changes that immediately use only current evidence;
- preservation of upstream ordering and every readiness/version/fingerprint
  field with no second cache or completeness signal;
- explicit waiting, partial-nonempty, stale-nonempty, ready-nonempty,
  partial-empty, stale-empty, authoritative-empty and bounded-failure
  presentation, including incomplete-first retained rows after restart;
- cross-Account input and malformed/duplicate/tampered upstream evidence fail
  closed without hidden counts;
- initial absent source under partial/stale evidence emits incomplete zero
  candidates; disappearance clears prior candidates; reappearance resumes from
  the current row; and complete-ready absence fails boundedly;
- source replacement, cancellation, noncooperative late evidence and workspace
  close drain deterministically;
- only a currently represented stable destination ProjectID can be selected;
  removed choices clear; and
- all target tests, controls, deterministic project generation and macOS/iOS
  builds pass at exact commits.

## Permanent Exclusions

This candidate does not decide whether a Transfer action is shown for an
archived source Project. A currently represented archived source may remain
read-only source evidence and yield current same-Client destinations in the
isolated picker; that neither exposes nor authorizes a production action. Source
selection is isolated staging plumbing only. It
does not select Items or amount, request confirmation, choose a Space or tag,
create a Transfer/Transaction pair, move an Item, change an Invoice, apply a
payment/refund/credit/correction, or interpret O-002/O-011 through O-015, O-025,
or D-017. It reads no Firebase data and changes no Firebase app. A-003/A-004,
hosted Auth/Sync, migration, production, release and cutover remain unadvanced.

## Promotion Rule

Independent review returned GO after the candidate was corrected to:

- re-resolve current source relationship evidence instead of filtering with a
  caller-stale ClientID;
- cover source absence, disappearance, reappearance, same-ID Client change and
  current archived-source read evidence without deciding O-025 or production
  action eligibility;
- distinguish every partial/stale/ready nonempty and empty presentation state;
- require retained rows to reopen incomplete until new current-process
  completeness evidence; and
- acknowledge all four deterministic app-file memberships produced by project
  regeneration while keeping the two Space DRAFT leaves byte-exact and
  declaration-free.

The dossier is therefore READY. Exact corrected comment-only commit
`2f87445cd51d6911a0655ad611fdedf035246665` passed immutable Actions run
`33989797244` and became the executable implementation baseline.
