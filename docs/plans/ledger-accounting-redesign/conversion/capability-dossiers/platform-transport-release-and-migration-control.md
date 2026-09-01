# Capability Dossier — Platform, Transport, Release, and Migration Control

Status: reviewed static characterization; 38 of 41 target-relevant surfaces are
exactly target-mapped. The SDK lock graph, cross-cutting offline contract and
price/tax helper remain honestly withheld on A-003/A-004, A-015/A-016/physical
verification, and O-008/O-031 respectively; implementation and cutover remain
unauthorized

## Outcome

Ledger starts only when one complete, internally consistent environment manifest
can construct all required dependencies. The app, MCP, migration runner, local
database, Storage, Auth, Sync, release artifacts, links, telemetry, and operator
tools cannot silently mix production and staging. Every request is bound to an
authenticated Ledger Principal and selected authorized Account. Every target
capability/error/version is machine-readable from the same contracts used by the
app. Releases and migrations are repeatable, signed/evidenced, reversible within
their declared boundary, and fail closed before an unintended read or write.

## Source Surfaces and Current Findings

### App composition and backend plumbing

- `LedgerApp` directly configures Firebase, Google Sign-In, Firestore cache,
  every Firebase-shaped service/context, media queue, global URL cache, deep
  links, Sparkle, network recovery and debug emulator state in one initializer.
- `RepositoryProtocol` exposes arbitrary collection fields, dictionaries,
  deletes, and Firebase listener types. `BatchWriting` abstracts Firestore paths
  and operations rather than Ledger behavior. Neither is a target backend-
  neutral boundary.
- `FirebaseEmulatorConfig`, the emulator scheme and source integration helpers
  are useful only for the running Firebase system and source fixtures. They do
  not become a target adapter.
- Current macOS Firebase configuration deliberately uses memory-only Firestore,
  which means current offline behavior differs by platform. URL cache and
  media queues do not make structured data uniformly durable.

### MCP transport and contract publication

- MCP stdio/HTTP entrypoints construct a Firebase Admin server. `server.ts`
  embeds a large manually maintained instruction string that now contradicts
  the approved target Transaction, Invoice, Quick Draft, report and correction
  rules.
- `config.ts` contains built-in production Account/User IDs. HTTP permits an
  unauthenticated environment-account fallback and a static bearer actor that is
  not a stable Ledger Principal. These are unsafe target defaults.
- The schema and server-info resources duplicate current DTO fields, enums and
  business rules by hand; stale advertised capabilities can direct a client to
  destructive or superseded behavior.
- Current structured errors, response-size controls and basic telemetry are
  valuable, but error semantics are per-tool, not operation-result contracts.
  Not-found/permission behavior can leak existence, and telemetry lacks trusted
  Principal/Account/operation/contract/environment correlation and explicit
  redaction classes.
- Current TypeScript types/enums/format/note/pricing helpers mix pure reusable
  values with Firebase and superseded accounting shapes. Target generated types
  come from reviewed versioned contracts; code does not publish raw database
  schema as the product API.

### Environment, build, release, hosting, and links

- Xcode project/schemes, `Info.plist`, entitlements and resolved Swift packages
  contain Firebase/Google callback schemes, a Firebase Hosting Sparkle feed and
  the current SDK graph. The plain scheme intentionally launches current
  production Firebase; the emulator scheme is explicit.
- There is no isolated target-staging app configuration with separate bundle/
  local-state namespace, visible environment banner and production-endpoint
  refusal. That remains a required implementation-tracker foundation.
- TestFlight and Sparkle build/distribution scripts preserve useful release
  outcomes but need one target environment/release manifest, reproducible inputs,
  signed artifact hashes, schema/contract compatibility, rollout gates and
  post-release observation.
- Firebase Hosting currently owns Sparkle assets and may own invite/deep-link
  entry points. Target links use stable HTTPS product URLs independent of Auth/
  data providers; the hosting implementation may move separately.

### Existing migration and repair tooling

- The `migration/` package is the reverse of the planned cutover: it reads a
  legacy Supabase web schema and writes Firebase/Auth/Storage, guesses payer/
  status/category relationships, rewrites media, and backfills cached budgets.
  It is source-history and fixture evidence, not a starting implementation for
  Firebase-to-target migration.
- Its CLI can enumerate all Supabase accounts, load service keys from local env
  files, select production Firebase, write with Admin credentials, and import
  Auth password hashes. The parity audit defaults to a named production Account.
  These defaults are prohibited in the target migration runner.
- Remaining one-off Firebase audits/repairs, Functions scripts, rules tests,
  seed bundles, backup lifecycle and deployment config describe source history.
  They remain operationally isolated until source retirement and never gain
  target accounting responsibility.

## Product and Spec Reconciliation

This is a technical-control dossier. It does not define product semantics and
does not use Firebase code as a target spec. Domain commands, queries, migration
transformations, and compatibility fixtures must reference their owning
canonical target spec and confirmed decision-log entries. The architecture
package governs Supabase/PowerSync composition, security, offline behavior,
migration, release, observability, and operations.

Current Firebase configuration, rules, Functions, migration scripts, and
emulator fixtures are source evidence only. They may support read-only export,
reconciliation, source freeze, rejected-write recovery, or rollback evidence;
they cannot authorize Firebase adapters or a second implementation of redesigned
behavior.

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | One app composition root; iOS/macOS; Google/system URL handling where provider-approved; camera/photo entitlements; explicit unit-test host; explicit source emulator testing; Swift package pinning; TestFlight and signed Sparkle delivery; MCP stdio/HTTP; structured stable errors; capability/version introspection; response budgets; telemetry; dry-run and reconciliation outcomes |
| Correct | Vendor SDK construction in UI root; cross-platform cache mismatch; built-in Account/User IDs; unauthenticated env Account/static actor; stale manual MCP instructions/schema; raw DTO publication; uncorrelated/unredacted logs; environment mixing; mutable/default-production migration tools; reverse-direction transform reuse; release without contract/schema evidence |
| Improve | Typed environment manifest, dependency factories, startup refusal, environment-specific local namespaces, generated contract catalog, correlation/redaction, health/readiness, reproducible releases, signed manifests, canary/rollback, link-provider independence, migration journal/resume/interrupt evidence |
| Redesign | `AppDependencies` target composition; Supabase/PowerSync/Auth/Storage adapters; Principal-bound MCP request context; versioned operation/query contracts; staging/prod deployment profiles; Firebase-export-to-target migration runner |
| Retire | Target generic repository/Firestore batch paths; target Firebase emulator/runtime config; default production IDs; unauthenticated Account fallback; target Admin-SDK domain composition; manual source-schema product contract; reverse Supabase-to-Firebase production migration; Firebase v2 rules/Functions/index work |
| Source only | Existing Firebase rules/config/tests/seed/backfills/repairs/emulator, reverse migration package and source rollback tooling after freeze |
| Open | A-003/A-004 vertical spike, A-007 Auth choice, A-015 optimistic projection, A-016 offline lease, O-022 freeze/recovery, production profile and final hosting/release topology |

## Target Platform Contract

### Environment manifest and composition

One signed/bundled `LedgerEnvironmentManifest` identifies environment kind,
app bundle, Auth issuer/audience, Supabase project/URL, PowerSync endpoint/
contract, Storage namespace, MCP base URL, universal-link hosts, database/key
namespace, operation/accounting contract versions, telemetry destination and
release channel. Secrets are injected through platform secret stores, not the
manifest or repository.

Startup validates the whole manifest before any SDK or local database opens.
Production identifiers cannot appear in staging, staging credentials cannot
open production local state, and missing/mismatched values terminate with a
visible diagnostic. There are no fallback Account/Principal/project IDs.

The composition root constructs the backend-neutral ports already defined in
`AppDependencies`. It contains infrastructure wiring only; it does not calculate
accounting, start duplicate scope listeners, or expose vendor SDK objects to
views/domain code. In-memory/fault adapters are test infrastructure. There is no
Firebase application adapter.

### MCP/API contract

Every transport request validates the token then resolves `(issuer, subject)` to
one Ledger Principal, active membership, requested Account and capability. A
service credential may establish infrastructure authority but never substitutes
for the caller Principal. Static/operator access is a separately deployed,
allowlisted, short-lived, audited mode with no public fallback.

MCP tool/resource descriptions, input/output schemas, feature flags,
deprecations and contract versions are generated or tested against the same
typed command/query registry. Server startup fails if a registered tool lacks an
authorization policy, stable error/result mapping, telemetry class, version, and
test owner. Superseded tools remain explicitly deprecated/rejected during the
supported window rather than silently advertising old behavior.

Errors use stable domain codes and correlation IDs. Unauthorized and inaccessible
resources follow a non-enumerating policy. Logs/traces include environment,
release, Principal correlation, Account, tool/query/operation, contract version,
outcome, duration and bounded sizes while excluding tokens, private paths,
notes, receipt contents and protected financial values.

### Release and hosting

Each build embeds a release manifest containing commit, app/version/build,
environment kind, schema/query/operation/Sync contract versions and dependency
lock hash. CI builds target staging first, runs migration/offline/security/
accounting/report contracts, then promotes immutable reviewed artifacts. iOS and
macOS channels have compatible-schema gates, staged rollout/canary, monitoring,
rollback boundary and post-release reconciliation.

Universal/invite/update links use stable HTTPS domains and signed/allowlisted
route payloads. Hosting can be replaced independently; no link grants Account
membership or embeds backend secrets. Sparkle metadata and binaries remain
signed and hash-verified wherever hosted.

### Migration runner

The target runner reads only an immutable Firebase export/object manifest and
writes only an explicitly named isolated Supabase target by default. Production
mode requires a signed reviewed run plan, exact source/target/account checks,
maintenance/freeze evidence, fresh backup, dry-run/reconciliation success and a
separate operator invocation. It never discovers `--all`, defaults production,
loads arbitrary repository env files, or performs Auth/Storage/schema writes as
uncoordinated steps.

Every stage is versioned, deterministic, journaled, resumable and idempotent.
Raw source is preserved; transformations never guess payer/client/payment/
provenance. Unknowns quarantine with source IDs. Full counts/hashes,
relationships, money, attachments, identities and invariant reconciliation are
recorded before authority can change.

## Offline, Observability, and Operations

- Target structured offline behavior is proven through encrypted PowerSync
  local databases and operation/media durability, not inferred from Firebase
  cache or network reachability.
- Health separates Auth, local DB, required-stream readiness, upload queue,
  PowerSync replication, Supabase handler, Storage and MCP state.
- Metrics/alerts cover durable operation age/rejection, Sync lag/readiness,
  missing/unauthorized projections, attachment integrity, reconciliation drift,
  migration quarantine, release adoption and crash/error rates without sensitive
  payloads.
- Runbooks name detection, triage, safe retry, rollback/escalation and evidence
  capture. Operators never repair accounting through raw console edits.

## Verification Contract

- environment matrix/startup refusal, production/staging credential and local-
  state cross-wiring negative tests;
- app dependency graph contains no Firebase imports in redesigned modules and no
  vendor SDK in domain/application contracts;
- MCP anonymous/static/cross-account/revoked/limited-financial/expired-token and
  non-enumeration tests;
- generated schema/instruction/capability parity and deprecation tests;
- stable errors/correlation/redaction/size/latency and failure telemetry;
- offline restart, platform parity, database/key namespace and schema upgrade;
- deterministic clean builds, dependency locks, signing/notarization/TestFlight/
  Sparkle manifests, staged rollout and rollback rehearsal;
- universal/invite/update link allowlist/signature/no-authority tests;
- migration wrong-environment/default/no-plan refusal, interruption/resume,
  idempotency, quarantine, zero unexplained reconciliation and rollback; and
- proof that no source Firebase repair, Function, rule, index, emulator or reverse
  migration tool is linked into target runtime authority.

This dossier does not authorize target implementation, production reads/
mutations, migration, release, or cutover. It explicitly prohibits a Firebase
application adapter and a second Firebase v2 implementation.
