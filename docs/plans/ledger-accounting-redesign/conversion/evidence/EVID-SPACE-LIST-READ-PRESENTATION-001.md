# EVID-SPACE-LIST-READ-PRESENTATION-001 — Active Space List Contract

- Timestamp: 2026-09-06
- Class: implementation / provider-free active Space browser integrity contract; no hosted rehearsal
- Reviewed base: `2297e8dbe7f7f0febb7e33b4da0be591d4c82ade`
- Exact READY checkpoint: `c9d4d8bbce6319f81aacb5851b16035d3c7ab809` / Actions run `34062468352`
- Target branch: `codex/supabase-powersync-implementation`
- Slice: `space-list-read-and-presentation-contracts`
- Implementation state: locally reviewed and implemented; exact implementation CI pending

## Bounded Outcome

The slice freezes a provider-free active Space browser for exactly one Account
and one immutable Project-or-Business-Inventory scope. It owns stable Space
identity, deterministic folded-name/exact-name/ID order, complete checklist
progress, explicit local readiness and evidence-bound selection into the
existing exact-Space detail contract.

The shipped Project and Inventory tabs browse active Spaces, so this slice does
not invent an archived segment. Archived lifecycle remains explicit in source
evidence and may still be addressed by the separately verified exact-Space
detail contract. O-037 archive effects remain unresolved.

## Canonical Parity and Truthfulness Boundary

`docs/specs/spaces.md` now explicitly preserves the complete target browser:
active Project/Inventory rows, deterministic order, case-insensitive search,
authoritative Item count, checklist progress, authorized primary-image behavior
and stable-ID navigation. This slice is the spec-authorized isolated staging
foundation only. Source Space cards show Item counts, but the target does not
yet have an authoritative exact-scope Item summary/count projection. The
contract therefore represents Item count as unavailable and never as numeric
zero. Search and card media remain required production parity and are deferred
rather than silently removed. Source browser surfaces stay `target_mapped`.

An empty active list is authoritative only from ready, complete,
source-exhaustive evidence for the exact request. Waiting, partial, stale,
incomplete and failed evidence cannot become a false empty state. A selection
must still exist as an active row in the unchanged current presentation before
it can derive the existing `SpaceCoreDetailsRequest`.

## Frozen Implementation Boundary

Only these target leaves changed during implementation:

- `LedgeriOS/LedgerTargetCore/SpaceDirectoryPresentation.swift`
- `LedgeriOS/LedgerTargetCoreTests/SpaceDirectoryPresentationTests.swift`

Their exact pre-implementation hashes and permitted changes live in the slice
dossier. The implemented SHA-256 hashes are:

- `SpaceDirectoryPresentation.swift` — `5546daf4452220b2dca5f8782054ae0b6c95f560a54456f7d204d8355601b676`;
- `SpaceDirectoryPresentationTests.swift` — `9b5d278ed8b23fd26c6f7991da443343cc6b791c0974f4879862a256070d165e`.

No provider, persistence, Postgres, RLS, PowerSync, app/MCP, source migration,
Firebase, hosted, production, release or cutover behavior advances.

## Review and Verification

The request, presentation-evidence and selection fingerprints each freeze an
exact version string, exact basis fields, `OperationContractCodec` canonical
sorted-key encoding and lowercase SHA-256 construction. The dossier carries
reciprocal requirements and executable obligations for
scope, order, duplicate names, active filtering, checklist progress, unavailable
Item count, every readiness state, cancellation and stable-ID detail selection.
The first independent READY review returned NO-GO and identified missing
canonical browser authority, non-exact fingerprint material and an invalid
dependency identifier; those findings were corrected without widening this
slice. Narrow independent re-review returned GO with no P0-P3 finding. Exact
READY commit `c9d4d8bbce6319f81aacb5851b16035d3c7ab809` then passed all three
immutable Actions jobs in run `34062468352` before executable edits.

## Implementation and Quality-Control Trial

One write-capable subagent changed only the two frozen leaves. Its first
candidate passed six focused tests and a full Swift suite, but root and an
independent read-only reviewer both rejected it. The review found that a
retryable or required-update failure could retain a ready-complete cached empty
snapshot which a caller could project as authoritative empty. It also found
that strict restart decoding stopped at outer containers, presentation and
selection fingerprints lacked independent basis assertions, unexpected port
errors could be swallowed by a test helper, and several dossier-promised
negative cases were absent.

The corrected implementation:

- projects failed cache only as explicit stale, incomplete failure evidence, so
  cached empty evidence cannot prove absence;
- strictly reconstructs nested Project-or-Inventory scope, checklist collection,
  checklist, checklist item, presentation row and update associated-value shapes;
- independently asserts the exact version and basis fields for request,
  presentation-evidence and selection fingerprints;
- rejects selection against independently valid wrong-Account or wrong-scope
  presentations and rejects rebound retryable/required-update cache; and
- keeps unexpected upstream errors observable while preserving bounded domain
  failures and cancellation drainage.

Final root and independent re-review returned GO with no P0-P3 findings. Root
ran the six focused tests successfully and `swift test --package-path LedgeriOS`
passed all 661 tests in 98 suites in 31.175 seconds. Final independent batch
re-review reproduced all 661 tests, the six focused tests and conversion
controls and returned GO with no P0-P3. The complete local conversion,
target-app/build and disposable Supabase provider jobs pass; one exact immutable
implementation CI run remains required before verified status.
