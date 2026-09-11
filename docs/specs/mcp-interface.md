# MCP Interface

Status: [new — canonical target]
Last updated: 2026-09-07

## Purpose

Ledger's MCP interface lets an authorized client discover supported public
capabilities, read Ledger data, and invoke the same business operations as the
app. This spec owns the shared public interface behavior. Feature specs remain
authority for each entity, query, command, and accounting result.

The target preserves useful discovery, bounded-response, error, preview, and
approval capabilities from the shipped MCP server. It does not preserve raw
Firebase documents, provider paths, legacy entity shapes, or every historical
tool and resource name.

## Public Capability Discovery

- A client can discover the public interface version, supported feature flags,
  deprecations, and the approved typed schemas for available queries, commands,
  results, and resources.
- Discovery describes only capabilities supported by the running target. It
  must not advertise legacy-only writers as target operations or present an
  open product decision as implemented behavior.
- A feature flag reports availability, not authorization. Every later query or
  command independently enforces its exact environment, Principal, Account,
  scope, revision, and product rules.
- Public schemas expose stable IDs, allowed inputs, results, enums, and business
  constraints needed to call the interface correctly. They do not expose table
  layouts, RLS policy text, provider configuration, Storage paths, credentials,
  membership grants, hidden financial classifications, or private media
  metadata.
- A deprecated capability names its supported replacement when one exists.
  Removal requires explicit compatibility authority; this spec does not set a
  support period, and a deprecation list is not a promise to retain obsolete
  Firebase behavior.

## Authorized Read Shapes

- Every read is bound to the compiled environment, authenticated Principal,
  explicitly selected Account, and request or session context. Account
  discovery follows
  [Account Discovery and Workspace Selection](account-discovery-and-workspace-selection.md):
  its rows contain only Account ID and safe display name, never role or grant
  data.
- Summary, full, and explicit-field projections are allowed only over an
  approved public representation. `full` never means a raw database row, and a
  requested field cannot bypass authorization or reveal a hidden relationship,
  count, amount, category, attachment, or provenance value.
- List and search operations use deterministic ordering. Pagination and
  response-size limits are explicit. When a result is capped, the response says
  that it is incomplete and supplies an authorized continuation mechanism;
  truncation never silently looks like an authoritative end or empty result.
- Exact-ID batch reads preserve input identity and return bounded `found` and
  `missing` results without leaking another Account or hidden record. An ID the
  caller cannot discover is indistinguishable from unavailable. Malformed or
  excessive input fails through a stable bounded error; duplicate-input
  handling belongs to the owning query contract rather than this shared spec.
- Counts, totals, and completeness metadata describe only the authorized result
  set. Partial, stale, failed, and truncated evidence cannot be presented as a
  complete total or zero.
- MCP resources, when offered, are alternate representations of the same
  authorized queries. They use the same scope, visibility, freshness, and
  completeness rules; a resource URI cannot provide broader access than its
  corresponding query.

## Commands and Safety

- App and MCP invoke the same typed domain commands and receive compatible
  results. MCP does not recreate business rules, bypass a command's expected
  revision, or gain authority from a tool description, schema, feature flag, or
  cached read.
- The public target interface does not expose arbitrary table access, generic
  predicate-based bulk writes, raw field patches, or provider-specific paths.
  When an owning feature contract defines an atomic bulk command, it names the
  exact stable IDs and reports a bounded failure without partial success. This
  shared spec neither makes unrelated commands atomic nor authorizes a generic
  bulk writer.
- Structured errors use stable public codes, a safe message, and an actionable
  next step where appropriate. They never include credentials, SQL, provider
  errors, stack traces, hidden-record existence, internal paths, or data outside
  the caller's authorized scope.
- A dry run is a read-only preflight of a named command against identified
  evidence. It returns the proposed scope, effects, blockers, and evidence
  version, performs no mutation, grants no permission, and cannot authorize a
  later execution. Execution revalidates current authority and state.
- A destructive command requires explicit human confirmation of the exact
  target set and described effect through the approved MCP elicitation flow. A
  model-supplied boolean or confirmation string is not user authorization.
  Changed scope, revision, dependencies, or retention evidence invalidates the
  confirmation. Destructive media and session behavior also follow the shared
  [attachment retention](offline-first.md) and
  [pending-work](session-ending-pending-work.md) contracts.
- For a command the app can accept offline, MCP still uses the same authoritative
  result contract but does not invent an offline queue. A transport success, dry
  run, optimistic overlay, or queued upload is not authoritative application.

## Telemetry Safety

Telemetry is optional operational evidence, not a product data export or an
authorization mechanism. When enabled, it may record the public operation name,
contract version, bounded result code, duration, and non-sensitive counts or a
safe correlation value. It must not record credentials, tokens, raw request or
response bodies, notes, search text, media, financial values, hidden entity
names, provider paths, or cross-Account identifiers. Telemetry follows the
approved environment, access, retention, and deletion policy and must not make
a failed or denied operation observable to a less-authorized party.

## Acceptance Examples

- Discovery returns only the capabilities implemented by the running public
  contract; it exposes neither Firebase collections nor Account membership
  grants.
- Summary, approved-full, and explicit-field forms of one query enforce the
  same row and field visibility. Asking explicitly for a hidden field does not
  reveal it or confirm that it exists.
- A capped page is labeled incomplete and can continue without duplicates or
  gaps; a partial local result never claims a complete count.
- A mixed exact-ID request returns authorized records and bounded unavailable
  entries without identifying cross-Account or hidden records.
- A dry run leaves no local or remote write. Execution after a stale revision
  fails closed rather than applying the old plan.
- Destructive execution cannot proceed from model-authored confirmation and
  cannot reuse human confirmation after its exact target or effect changes.
- App and MCP calls to the same command produce the same validation, accounting,
  authorization, idempotency, and result semantics.

## Non-Goals and Release Boundary

This contract does not choose an MCP transport, pagination encoding, telemetry
vendor, provider adapter, table schema, RLS implementation, or exact historical
tool/resource naming. It does not authorize a generic database tool, a legacy
proto writer, production access, production data reads, migration, source
freeze, release, or cutover. Those actions retain their existing explicit
authorization gates.
