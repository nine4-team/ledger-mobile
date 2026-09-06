# EVID-FIREBASE-SOURCE-FIXTURE-CATALOG-001 — Firebase Source Fixture Catalog

- Status: implemented; independent review and complete local gate passed; immutable implementation CI pending
- Date: 2026-09-06
- Environment: isolated provider-free migration test target only
- Production/Firebase impact: none
- Slice: `firebase-source-fixture-catalog`
- Claimed surfaces: `SWIFT-B4A356C2FE88`, `TEST-1C328F2AB1C1`

## Historical READY Gate

The comment-only contract and four empty schema-zero resource markers passed the
immutable READY gate at commit
`d281498bde31c27bd17879571ef67b42bfb1dc3d`, GitHub Actions run
`34056116157`. That checkpoint authorized only the local provider-free
implementation now present in this worktree. It did not authorize source
export, provider access, production data, migration execution, or cutover.

## Current Implementation Candidate

`FirebaseSourceFixture.swift` now implements a closed, bounded Firebase source
value model and validates one exact synthetic v1 catalog. It preserves integer,
IEEE-754 bit, timestamp, reference, geopoint, bytes, array, raw-UTF8 map-key,
unsupported, and malformed evidence without assigning target meaning. It binds
canonical manifest content, all three payload files, and every source record to
domain-separated length-framed hashes and derives only a `source_fixture`
`MigrationSourceSnapshot` plus deterministic entity plans.

Every versioned resource file is canonical sorted-key/no-escaped-slash JSON
followed by exactly one LF. Missing, repeated, or additional trailing bytes are
refused. The exact identities reviewed in this candidate are:

- manifest: 3,146 bytes,
  `e689aea023cb6fe666e1b37d45b130e534bacd52fd90ae0c54407b16118c3e20`;
- Auth metadata: 971 bytes,
  `060cc947968cc135a533822ae071e17ca5f232fcf99e4a0d867ae42e53d73f74`;
- Firestore documents: 6,231 bytes,
  `16f78cef5e69e720db2db9e70ec34c8ec02fe5f8e736d1139f3c08703e834d70`;
- Storage metadata: 2,351 bytes,
  `9d10c8143c923cce031a318700a4787bd0624794633b5b85aeddbd35aaa06f3d`;
- bundle: `1ecd6b1ed0bfbe4b9e65d0c55e367562d761cbe00fd0f38cdb86111fd2b7f4a2`;
- derived export ID: `1ecd6b1ed0bfbe4b9e65d0c55e367562`; and
- authenticated source byte count: 12,604.

The catalog contains 21 synthetic records across 15 entity groups covering
legacy and typed-value variants, proto Items, movement lineage, live/paid
Invoices, missing relationships, mixed categories, returns, credits,
malformed/ambiguous/orphan/cross-Account evidence, and metadata-only attachment
faults. `accountScopeID` is package-visible solely so the package-only guard can
derive its opaque Account digest; ordinary public evidence does not expose it.

Admission checks the reviewed component digest before privacy or semantic
parsing. Separate package-only validation directly proves schema-specific
prohibited identity, credential, token, URL, and media field rejection. This is
defense in depth and does not claim arbitrary-string PII detection.

## Candidate Verification

Local focused verification passes:

- `swift test --package-path LedgeriOS --filter FirebaseSourceFixtureTests`:
  seven tests passed;
- `npm run target:environment:check`: passed with exact source, resource,
  test-only SwiftPM registration, application non-linkage, regular-file,
  provider-import, visibility, digest, and LF-framing checks; and
- `git diff --check`: passed.

The complete local batch gate also passed: all conversion, query-authority,
residual, target-environment and generated-contract checks; 26 MCP tests; the
complete 655-test Swift package across 97 suites; XcodeGen stability; macOS and
generic iOS Simulator staging builds; local Supabase schema lint; 374 pgTAP
assertions across 11 SQL suites; and the local RLS/RPC/read matrices.

The tests exercise exact inclusive and limit-plus-one value/resource ceilings,
raw-UTF8 identity, canonical rejection, manifest/payload/entity digest vectors,
restart stability, direct prohibited-field validation, representative tamper
categories, MigrationRunIntegrity compatibility, exact count reconciliation,
and the non-operational boundary. Framing integer overflow is not claimed as an
executable vector because supported path/content/component ceilings make it
unreachable without constructing an unsupported in-memory value.

The first independent implementation audit returned NO-GO. Two correction
rounds closed every finding, and the final read-only re-review returned GO with
zero P0-P3 findings. This document does not yet claim an exact implementation
commit, immutable implementation CI, or verified status.

## Exact Privacy Review and Limits

An independent agent inspected every serialized string and metadata shape in
the exact four files above and found no real email, phone, URL, Firebase or
Supabase project/bucket, credential, token, private key, production object name,
or user media byte. The manifest truthfully records
`independent_agent_synthetic_review`; it does not claim human review. Any future
production-derived restricted snapshot still requires a separate human
privacy/security approval.

This candidate performs no filesystem discovery beyond caller-supplied bytes,
network/provider/database/Auth/Storage access, export, transform, load,
reconciliation execution, hosted rehearsal, production read/write, Firebase
application change, apply authorization, release, or cutover. A separate future
loader owns no-follow, containment, file-identity, and TOCTOU guarantees.
