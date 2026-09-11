# EVID-PROJECT-ARCHIVAL-REVIEW-PROVIDER-001 — Project Archival Review Implementation

- Date: 2026-09-05
- Class: isolated local implementation / independently reviewed executable slice
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the Firebase checkout and released app were not changed
- Target branch: `codex/supabase-powersync-implementation`
- Frozen READY baseline: `1e893c6c02dc22a52cb1332e3a98a26c714d5fba`
- Slice dossier: `conversion/implementation-slices/project-archival-review-workflow.json`
- Claimed leaves: `CONFIG-00C8635E9EF9`, `CONFIG-DBE8715A260A`, `CONFIG-EADCA9A7026D`, `MCPMOD-4CB1EBAC253A`, `MCPMOD-84FF0804E57E`, `SWIFT-07516815EBBD`, `SWIFT-283C354B7848`, `SWIFT-754648D5F97F`, `TEST-3CB458C292B0`, `TEST-A920874A5571`

## Implemented Outcome

An authorized user can select an active or archived Project and page through its complete locally replicated note history. Archiving an active Project uses the existing durable archive operation and preserves every note row, content/tombstone, provenance field, revision and keyset order. The same selected Project and note observer survive the active-to-archived transition.

The implementation remains target-local and spike-prefixed. It reads no Firebase data, changes no Firebase code or resources, creates no hosted resource, registers no live MCP tool and performs no production migration, release or cutover.

## Security and Data Boundary

- `spike_project_notes` is a single Postgres authority with exact Account/Project and actor references, structural visible/tombstone constraints, paired edit/deletion audit, exact millisecond evidence and integral `0...UInt64.max` revisions.
- RLS is enabled and forced. PUBLIC and anon have no relation or function privileges; authenticated clients receive only the exact SELECT and read-RPC privileges. No direct note INSERT, UPDATE or DELETE policy or grant exists.
- The read RPC is security-invoker and derives authorization from signed identity plus active Account membership. It returns bounded, scope-bound keyset pages and revision text without leaking unauthorized Project existence.
- The on-demand PowerSync stream includes the Project anchor and complete exact-Project notes, has no lifecycle filter, and uses signed identity plus active membership rather than subscription parameters as authority.
- MCP transport remains unregistered and mechanically rejected if another source attempts to import or register it while gated. It accepts only scoped user bearer/public credentials and maps authentication, authorization, validation and retryable infrastructure failures distinctly.

## Offline and Lifecycle Proof

PowerSync's managed `id` cannot be named in a custom index because the SDK serializes only declared columns. The stream therefore copies the immutable source identifier into `keyset_id`; the decoder requires `keyset_id == id`, and the local index is `(account_id, project_id, created_at_ms, keyset_id)`. An executable SQLite query-plan test proves the descending keyset query uses that index without a temporary sort.

Local readiness is causal rather than inferred from cached rows. Stream completion carries its current-process epoch; every row/status invalidation triggers a one-shot reread, and only rows reread after the accepted completion can become ready. Membership loss clears completeness and represented rows, and reactivation requires another exact-stream completion.

Project-note presentation distinguishes authoritative empty from partial/stale empty, clears sensitive rows on upstream cancellation, rejects late prior-generation evidence and does not place stable note identifiers in accessibility labels. Archive acceptance is also generation-bound, so a delayed receipt cannot overwrite a newly selected Project.

Both Project-archive and the pre-existing Client-archive operation stores now register, cancel and drain their internal database watches. Runtime shutdown drains them before closing the encrypted structured database. Direct provider tests and a gated runtime ordering test cover the close boundary.

## Independent Review and Corrections

Three independent reviews examined database/MCP/contracts/Sync configuration, note-provider causal freshness and executable app/runtime behavior. They found no cross-tenant disclosure or unauthorized note mutation, and surfaced the following defects, all corrected and regression-tested:

- cached rows could be promoted by a later completion without a causal reread;
- upstream cancellation could leave prior note text visible;
- archive operation watches were not provably drained before database close;
- delayed local acceptance could overwrite a later Project selection;
- authoritative-empty note history rendered as blank space;
- Unicode whitespace validation differed between Swift, Postgres and TypeScript;
- MCP treated every 4xx response as automatically retryable;
- the local keyset index omitted the stable identifier tie-breaker;
- live MCP non-registration was documented but not mechanically enforced; and
- combined archive-before/after continuity was not exercised through Data API and app flows.

The root integrator independently inspected, extended and reran the delegated changes. A later local implementation review also found and closed the equivalent older Client-archive observer-drain race.

The first exact implementation commit `27cb52e7f19c6a53e2506a337e4e8fb1dadb9037` passed conversion and disposable-local-Supabase CI but exposed one scheduler-dependent test setup in the macOS job: provider shutdown could run before the controlled completeness stream had emitted any evidence, making a zero-termination count a valid pre-start outcome. The corrected test first observes the combined row/completeness result, then invokes provider shutdown and proves both active sources terminate exactly once. Thirty consecutive focused-suite repetitions pass locally; no production implementation behavior changed.

Corrected exact implementation commit `7d42bad01aa5473750d212a631158b079629d3d6` passed all three immutable jobs in Actions run `33998369665`: conversion state and traceability, the isolated target environment with all 546 Swift tests and both builds, and the disposable local Supabase provider suite.

## Local Verification

- clean local Supabase reset: passed all migrations and seed
- pgTAP: 256/256 assertions in 8 files, including 45 Project archival-review assertions
- database lint at error level: zero findings
- all eight local Data API/RPC runners: passed, including full Project-note history equality before and after archive
- target contract generation/check and negative registration controls: passed at catalog digest `0ea995bcdc4c4bf9317227711b5cd3617908308e8b66d694c0ff23e5be8a6b5c`
- MCP typecheck and tests: 26/26 passed
- complete Swift package: 546/546 tests in 88 suites passed
- Project-note provider: 11/11 passed
- Project-note provider repeated after the CI test-harness correction: 30 consecutive suites passed
- Project archive provider: 8/8 passed
- Project archive browser: 13/13 passed
- Account workspace runtime: 18/18 passed
- Client archive provider regression: 13/13 passed
- isolated target macOS and iOS Simulator builds: passed
- target environment/isolation and generated-artifact checks: passed before conversion promotion

## Remaining Gates

`PROJECTARCHIVALREVIEW-TEST-010` passed at corrected exact implementation commit `7d42bad01aa5473750d212a631158b079629d3d6` in immutable Actions run `33998369665`. The first exact commit's failed macOS job is retained above rather than hidden. `PROJECTARCHIVALREVIEW-TEST-011` remains planned until a real isolated authenticated PowerSync session proves exact authorized receipt and membership-revocation eviction. Local static configuration, fake freshness sources and SQLite tests do not prove that hosted behavior.

A-003 and A-004 therefore remain proposed. This implementation does not authorize hosted Supabase/PowerSync resources, source import, Firebase changes, production access, migration, deployment, release or cutover. Product specs and the decision log remain product authority.
