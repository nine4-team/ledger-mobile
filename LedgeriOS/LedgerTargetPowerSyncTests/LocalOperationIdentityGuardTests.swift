// Comment-only READY scaffold: executable tests replace this comment only after
// this exact synchronized checkpoint passes immutable CI. The shared local
// OperationID ownership dossier has completed independent review and promotion.
//
// Required proof uses fresh encrypted Account databases and all five currently
// executable command families: create Client, create Project, archive Project,
// archive Client, and assign Items to Space. It covers every distinct-family
// pair in both submission orders and every unordered pair concurrently with
// exactly one durable family. For each family, independent store instances also
// race the same ID with equal payload (one graph and converged receipts) and
// changed payload (one winner, one mismatch, one graph). Deliberate equal-
// fingerprint/different-family collisions, exact same-family replay, and
// changed-payload replay are separate cases.
//
// Table-driven isolated evidence covers every OperationID-bearing source:
// local operation, operation result, every command entry produced in ps_crud by
// an insert-only command view, a forbidden local operation-result table ps_crud
// mutation, pending Client, pending Project, pending Project allocation, Project archive overlay, Client archive overlay, and Item
// assignment command. The public Project-archive and Client-archive stores
// retain disjoint required ID prefixes, so their direct same-ID cross-family
// cases prove pre-database invalid-identity refusal. Direct synthetic guard
// classification still covers both directions of that family pair using an ID
// valid for the destination and corrupt source-family evidence. Command-only,
// result-only, overlay-only, pending-only, ambiguous pending-Client, multiple-
// family, wrong-family, foreign-scope, and malformed graphs must reserve the ID
// without receipt, repair, deletion, pending-count change, or unrelated ps_crud
// mutation. An untyped, nonterminal, or malformed operation-only row does too;
// a typed canonical applied/rejected create-Client/create-Project row instead
// proceeds to exact family replay validation after queue and reconciled/rejected
// pending drainage. Any pending graph still present must validate exactly; this
// slice authorizes no new cleanup. Positive applied-with-pending, applied-after-
// authoritative-reconciliation, and rejected-after-drain replay cases plus exact
// typed-row/pending tampering negatives are mandatory.
//
// Failure and cancellation checkpoints cover inventory construction/read,
// after ownership inspection, each provider's existing graph writes, before
// commit, and after commit. Pre-commit failure leaves no new ownership graph;
// post-commit cancellation cannot erase accepted work. Exact valid and malformed
// reservations survive repeated encrypted close/reopen. Raw database failures
// map through each provider's bounded local-acceptance taxonomy and
// CancellationError remains control flow. Stable payloadMismatch may carry only
// the caller-supplied OperationID already present in the submitted command;
// errors must never expose stored foreign IDs, payload fields, scope, SQL, paths,
// credentials, provider messages, or cross-tenant ownership details.
//
// Static proof must fail when an operation-bearing schema relation, upload
// command table, or accepting provider is absent from the centralized inventory;
// when any store can write before guard inspection; or when Client/Project
// creation omits explicit command-family/canonical-envelope ownership evidence.
// The frozen powersync-sqlite-core-swift 0.5.3 revision is checked explicitly,
// and executable tests insert through each of the four insert-only views to prove
// exactly one matching ps_crud entry and no query-visible/backing command row
// before or after the relevant queue lifecycle.
// Dedicated migration proof uses only disposable synthetic pre-foundation rows:
// unambiguous legacy graphs proceed to exact replay validation, ambiguous rows
// remain reserved, and no bootstrap repair/backfill/deletion occurs. Dedicated
// reconciliation proof covers both create families before and after authoritative
// pending-row removal and refuses detached visible-result or local result-
// mutation queue evidence without changing normal reconciliation.
// Existing upload ordering, pending-work counts, provider behavior, and both
// isolated target builds remain green. This slice creates no additional local
// table and no server, synchronization, UI, MCP, hosted, migration, or
// production behavior.
