# EVID-SPACE-LIST-READ-PRESENTATION-001 — Active Space List Contract READY Boundary

- Timestamp: 2026-09-06
- Class: DRAFT-to-READY design evidence; no executable implementation or hosted rehearsal
- Reviewed base: `2297e8dbe7f7f0febb7e33b4da0be591d4c82ade`
- Target branch: `codex/supabase-powersync-implementation`
- Slice: `space-list-read-and-presentation-contracts`

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

Only these comment-only target leaves may change during implementation:

- `LedgeriOS/LedgerTargetCore/SpaceDirectoryPresentation.swift`
- `LedgeriOS/LedgerTargetCoreTests/SpaceDirectoryPresentationTests.swift`

Their exact pre-implementation hashes and permitted changes live in the slice
dossier. No provider, persistence, Postgres, RLS, PowerSync, app/MCP, source
migration, Firebase, hosted, production, release or cutover behavior advances.

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
immutable READY CI is still required before executable edits; executable review,
the complete local batch gate and one exact immutable CI run are required before
verified status.
