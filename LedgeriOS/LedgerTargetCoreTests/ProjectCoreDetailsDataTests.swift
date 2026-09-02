// Ready-gate scaffold for project-core-details-read-contracts verification.
//
// Planned tests must cover active and archived Project rows, an active Project
// with an archived Client, nil and canonical descriptions, UInt64.max revision,
// independently Account-bound and Project-bound request fingerprints, exact
// request/row/fingerprint matching, and ready/incomplete/partial/stale found and
// empty restart evidence. Only ready+complete+empty may be authoritative absence;
// local revision evidence must not be upgraded beyond its enclosing readiness.
//
// Negative cases must include cross-Account and wrong-Project rows, malformed
// Project/Client relationships, noncanonical or blank encoded descriptions,
// fingerprint/revision/cardinality/visible-count/time/completeness tampering,
// rebound snapshot/cached updates, invalid waiting state, non-enumerating
// unavailable state, exact distinct retryable/required-update failures, port-side
// request validation observed by a raw consumer, upstream failure, cancellation,
// and exact unique bounded provider-neutral diagnostic codes.
//
// Encoded-shape tests must exclude workspace children, media, Items,
// Transactions, Spaces, notes, preferences, budgets, Invoices, accounting,
// authorization, mutation, provider/schema/Sync, app/MCP, migration, hosted,
// production, release, and cutover claims. Complete conversion, target-isolation,
// generated-contract, full target-test, repeatable-project, both-build,
// clean-artifact, and immutable exact-SHA CI gates remain required.
