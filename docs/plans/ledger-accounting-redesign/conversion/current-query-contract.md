# Current Firestore Query and Listener Contract

Status: M0 source characterization; target schema and deployed-index parity are
not authorized or proven here

This document is the reviewed semantic companion to
`query-contract.generated.json`. The generated artifact is the line-level
inventory; this document explains the current query families, callers, index
implications, and offline expectations that must be preserved or deliberately
replaced in the Supabase/PowerSync implementation.

## Reproducible Inventory

Run:

```bash
npm run conversion:queries:generate
npm run conversion:queries:check
```

The extractor scans every Firestore-coupled Swift application file, MCP module,
Cloud Function and Function script, migration source, and repository audit or
repair script. Each occurrence records a stable ID, subsystem, file, line,
enclosing symbol, operation, and normalized source expression. It covers
filters, collection groups, ordering, limits, offsets, cursors, listeners,
document/collection/bulk reads, projections, and aggregates.

This is intentionally lexical evidence. Dynamic collection names and runtime
filter combinations require production-derived confirmation; an occurrence
does not prove a code path is active.

## Current Query Families

| Family | Current callers and shape | Current offline expectation | Supabase/PowerSync obligation |
|---|---|---|---|
| Account discovery and authorization | iOS and MCP collection-group `users.uid`; Function invite lookup by collection-group `invites.token`; limited account scan fallback | iOS account selection can use cached membership results, but authorization is ultimately Firebase-backed; MCP and Functions are online only | Auth/account resolution must be a separately tested security boundary. Local membership data may drive UI but cannot grant server authority |
| Generic account collections | iOS `FirestoreRepository` document get, unfiltered list, equality list, unfiltered/equality collection listeners, and document listener | Listeners render cached snapshots and pending local writes, then converge after reconnect; writes are intentionally accepted before server acknowledgement | App-facing reads/subscriptions need local SQLite queries with deterministic optimistic state, restart durability, rejection handling, and server convergence |
| Projects and project children | active/archived project equality; project Items/Transactions/Invoices; project notes ordered by `createdAt desc` and limited; project fee installments; preferences listeners | Project lists and locally scoped child data must remain usable offline once synchronized | Sync scope and local indexes must cover the selected Client/Project plus children; server queries remain account-scoped |
| Items and Inventory | equality on nullable `projectId`, `spaceId`, `budgetCategoryId`, `status`, `source`, `transactionId`, bookmark, and document-ID batches; dynamic multi-filter combinations; client filtering for image/transaction predicates | iOS commonly subscribes to broad account collections and derives UI views locally; MCP filtering is online | Preserve offline Inventory/project membership and explainable history locally. Define explicit local indexes/query APIs rather than reproducing arbitrary backend query composition |
| Transactions and accounting | equality on nullable `projectId`, category, type, purchaser, purchase handling, intended project, source, completeness, reimbursement and ingestion fields; array membership and document-ID batches; dynamic combinations and offset/limit | Current app data can be read from Firestore cache, but server Functions own some derived side effects | Target commands and projections must make optimistic accounting behavior explicit; MCP/server list behavior must use deterministic ordering and cursor pagination |
| Invoices and settlement | project/status filters, project-wide fetches, settlement transaction lookup, fee installments, and some in-memory membership inspection | Cached Invoice/Item/Transaction snapshots support viewing; collection and accounting invariants are not guaranteed by cache alone | Local Invoice views and accepted operations must be durable; authoritative collection validation belongs in Postgres command handlers |
| Quick drafts | project/intended project/transaction/status/capture-context equality, active-status `in`, optional client-side Inventory filtering, and offset/limit | Active draft listeners and locally persisted media queue support disconnected capture | Local draft/media state must survive process death and reconnect; Sync Streams must include every draft relationship needed by the active workflow |
| Lineage and provenance | `itemId ==` ordered by `createdAt asc`; from/to transaction and project equality; `itemId in` batches | Some lineage is fetched on demand rather than continuously subscribed | Inventory/project streams or an explicit durable history stream must retain enough occurrence evidence for offline sale/return/resale explanations |
| Derived-state Functions | project/category/item/space queries, array membership, name lookups, invite token lookup, and document-ID batches | Online server execution only; some asynchronous failures are currently suppressed | Replace with transactionally authoritative Postgres commands/projections or explicit retryable jobs; do not implement redesigned accounting in Firebase |
| Migration/audit/repair tooling | collection-group scans, scoped equality queries, projections, and targeted bounded reads | No product offline contract | Source-only tools must be retained, replaced, or retired explicitly and must never become production app dependencies |

## Ordering and Pagination Findings

- Only two explicit source orderings exist in the reviewed catalog:
  `lineageEdges(itemId, createdAt asc)` and project notes by `createdAt desc`.
- MCP list endpoints commonly use Firestore `offset` plus `limit` with no
  explicit order. That is inefficient at scale and does not define a stable
  cross-backend page contract when concurrent writes occur.
- Several MCP paths fetch a broad bounded or unbounded result and apply
  predicates in memory. Those client filters are part of current behavior but
  are not a target performance design.
- The target contract must choose deterministic sort keys and cursor semantics
  per list surface before claiming parity. It must not copy Firestore offset
  behavior merely for implementation convenience.

## Index Contract and Gaps

The repository declares one composite collection index and three
collection-group field indexes:

| Scope | Fields | Proven repository consumer |
|---|---|---|
| `lineageEdges` collection | `itemId ASC`, `createdAt ASC` | MCP item lineage query |
| `users` collection group | `uid ASC` | iOS and MCP account discovery |
| `invites` collection group | `token ASC` | invite lookup Function |
| legacy `members` collection group | `uid ASC` | No current membership collection consumer found; retained as legacy configuration evidence |

Single-field equality queries ordinarily rely on Firestore field indexing.
Dynamic MCP endpoints can combine multiple optional equality, membership, and
pagination clauses. The repository does not declare composite indexes for every
possible combination. Static source therefore proves the requested shapes but
does not prove which combinations succeed against deployed production indexes,
whether console-only indexes exist, or which shapes are used in practice.

The read-only production confirmation must record deployed index configuration
or execute an approved representative query matrix without mutations. Missing
index failures and console-only indexes remain a production-evidence blocker;
they are not a reason to reproduce Firestore indexes in the target schema.

## Target Mapping Rule

Backend-neutral ports describe capabilities such as “observe project Items” or
“list account Transactions with this supported filter set,” not Firestore
query-builder syntax. The iOS Supabase/PowerSync adapter must implement local
offline reads and subscriptions. MCP and server handlers may use Postgres
queries/RPCs. Migration and audit tooling remains source-specific until cutover.
No Firebase implementation of redesigned accounting is required.

The mechanical target-port inventory admits only exact manifest owners at
`implemented` or later active lifecycle states. Its generated review output
shows current owner status, while TQUERY identity, signature hash, inventory
digest, TACCESS identity, mapping hash, and logical-authority bytes remain stable
across status-only promotion. A logical row classified `mapped` is reviewed
semantic authority, not verification evidence. The source-reconciliation
category `verified_target_query_port` is valid only when the TQUERY owner joins
to the current manifest at `verified`, `rehearsed`, or `cutover_ready`; an
`implemented` or otherwise ineligible owner fails closed.

## Completeness and Limitations

The generated catalog is symbol-complete for recognized Firestore query/read
APIs in the configured source roots at its recorded source digest. Completeness
is checked mechanically and becomes stale when those source files change.
Remaining evidence gaps are runtime facts: dynamic paths, actual production
collections, deployed indexes, query frequency, missing-index failures, and
historical code that is no longer present. Those are owned by the fail-closed
production profile and deployment evidence, not by guesswork in this document.
