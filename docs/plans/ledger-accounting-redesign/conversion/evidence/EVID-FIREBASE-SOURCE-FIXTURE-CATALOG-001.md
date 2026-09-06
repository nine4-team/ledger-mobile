# EVID-FIREBASE-SOURCE-FIXTURE-CATALOG-001 — Firebase Source Fixture Catalog READY

- Status: READY scaffold only; no executable fixture contract or fixture data
- Date: 2026-09-06
- Environment: isolated provider-free migration test target only
- Production/Firebase impact: none
- Slice: `firebase-source-fixture-catalog`
- Claimed surfaces: `SWIFT-B4A356C2FE88`, `TEST-1C328F2AB1C1`

## Proposed Outcome

The candidate defines a versioned, canonical, synthetic-only representation
of known Firebase source shapes for deterministic migration tests. A validated
bundle would preserve explicit source types and raw malformed or ambiguous
evidence, bind canonical manifest content plus every component and entity by
exact domain-separated counts and SHA-256 preimages, and
derive only a `source_fixture` `MigrationSourceSnapshot` plus source entity
identity for the verified MigrationRunIntegrity plan.

It would not transform or load a row, access Firebase, initialize a provider,
read credentials, claim production completeness, or authorize migration apply.

## Current READY Boundary

`FirebaseSourceFixture.swift` and `FirebaseSourceFixtureTests.swift` contain
comments only. The four v1 JSON resources are exact empty schema-version-zero
markers with `ready_scaffold_only` and `evidence_only`; they contain no fixture
record or passing evidence. `Package.swift` copies them only into the separate
migration test target. The environment checker refuses executable Swift or a
nonempty/resource-schema change before a separate READY gate.

The future v1 matrix is frozen in the dossier: exact tagged Firebase value
encodings and bounds; a domain-separated, length-prefixed digest over canonical
manifest content plus the three payloads, with canonical manifest content
authenticated and included in source byte count while only final envelope
framing and the digest field are excluded recursively; a pre-decode raw-envelope
ceiling;
golden preimage/digest vectors; malformed/ambiguous/orphan and cross-Account
cases; logical-path/duplicate/tamper/oversize refusal; exact reviewed-catalog
digests; schema-specific prohibited-field checks; recorded human privacy review;
metadata-only media faults; MigrationRunIntegrity compatibility; exact
reconciliation coverage; and static provider/application isolation. It does not
claim that arbitrary strings can be reliably recognized as PII.

## Explicit Non-Reuse and Limits

The existing read-only profilers are aggregate production-evidence generators,
not record-level fixture exporters. The legacy `migration/` package is the
reverse Supabase-to-Firestore direction and includes provider, credential,
production-write, Auth-import, media-copy, and heuristic normalization behavior.
Neither those paths nor visible `migration/out` reports may be imported, invoked,
copied, or treated as fixture schema/evidence.

The Core contract receives caller-supplied bytes and therefore validates logical
relative paths only. A separate future fixture-loader slice must own filesystem
enumeration, `lstat`/no-follow checks, regular-file and realpath containment,
file-identity/read-after-stat guarantees, and TOCTOU resistance. Those guarantees
are not attributed to this byte-only contract.

This READY scaffold uses no production data, identity, project, Account, bucket, URL,
credential, token, user media, hosted resource, Firebase application change,
export, transform, load, reconciliation execution, release, or cutover. All
tests remain planned and the evidence establishes no implementation status.
