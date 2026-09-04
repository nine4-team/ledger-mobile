// READY CONTRACT — TARGET QUERY-PORT INVENTORY GENERATOR
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// The future dependency-free Node generator is a technical conversion control.
// It recursively scans LedgerTargetCore Swift sources and inventories every
// direct instance-method requirement declared by every public protocol whose
// name ends exactly `Querying`. A protocol may omit `public` on its method
// requirements; the protocol declaration itself establishes public scope.
//
// The scanner must be a deterministic lexical state machine, not a regex-only
// approximation or a Swift compiler/runtime dependency. It masks line/block
// comments and string literals, tracks nested braces, parentheses and generic
// delimiters, and accepts multiline declarations, attributes, async/throws,
// return clauses and where clauses. It excludes implementations, extensions,
// comments, strings, private/internal protocols and protocols whose names do
// not end exactly `Querying`.
//
// Every direct `func` requirement is parsed. A selector beginning with `watch`
// is classified as observation; every other selector is classified as the
// reserved future `request_response` category. Unsupported or ambiguous direct
// functions, malformed declarations, duplicate selectors/overloads, empty
// Querying protocols, and missing/ambiguous/invalid-status manifest owners must
// fail closed. The generator must never silently omit a method.
//
// Each method receives a stable TQUERY identity derived only from its owning
// conversion-manifest surface ID, protocol name and selector. A separate
// signature hash detects any parameter-label/type, generic, attribute,
// async/throws, return-type or where-clause drift without changing identity.
// Output is deterministically sorted, contains no timestamps, and normalizes
// CRLF, insignificant whitespace and masked comments.
//
// `generate` writes both reviewed artifacts:
// docs/plans/ledger-accounting-redesign/conversion/
//   target-query-port-inventory.generated.json
// docs/plans/ledger-accounting-redesign/conversion/
//   target-query-port-inventory.generated.md
// `check` computes both in memory, byte-compares them with the tracked files,
// reports missing or stale output, and never writes. The generated diff is a
// mandatory human-review surface; CI proves freshness, not human approval.
//
// The implementation must preserve the exact verified baseline of 16 owning
// surfaces, 16 public `*Querying` protocols and 18 direct methods, including the
// two existing multi-method protocols. It introduces no query predicates,
// ordering, pagination, readiness, result semantics, source-query parity,
// Firestore mapping, logical/physical index, SQL, RLS, Sync Stream, PowerSync,
// provider, hosted, production, runtime-manifest or product behavior.
