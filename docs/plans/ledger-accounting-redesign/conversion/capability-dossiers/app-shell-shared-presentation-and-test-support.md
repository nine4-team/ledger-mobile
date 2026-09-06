# Capability Dossier — App Shell, Shared Presentation, and Test Support

Status: reviewed static characterization; the final repository-discovered
presentation, shell, pure-calculation, navigation, platform-capture, and test
surfaces have approved M0 dispositions, and all 39 target-relevant surfaces have
complete provider-neutral M2 maps; target implementation remains gated

## Outcome

The redesigned app keeps Ledger's useful iOS/macOS presentation language and
fast interaction patterns without allowing views, menus, formatters, or generic
controllers to become a second source of business truth. Screens render typed,
authorized local snapshots and emit typed user intents. Application handlers
own validation and durable operations. The app shell owns workspace lifecycle
and readiness, but it does not construct vendor repositories, start overlapping
entity listeners, calculate accounting, or silently discard failures.

This dossier closes the last repository-discovered M0 inventory block. It does
not assert that every current UI behavior is correct, and it does not promote
Firebase-shaped view code into a target adapter.

## Source Surfaces and Current Findings

### Reusable presentation

- The theme, cards, badges, buttons, form containers, pickers, list controls,
  selection indicators, loading/error views, scroll affordances, adaptive
  layouts, and accessibility helpers are largely backend-independent. Their
  visual and interaction outcomes are reusable.
- Action-menu and form types commonly carry arbitrary closures. That is an
  acceptable presentation mechanism only when the parent converts the gesture
  into a named intent and renders the resulting durable operation state. A
  closure is not authorization, validation, or an operation contract.
- Some shared controls encode domain lists and labels directly, including Item
  status, category, Transaction association, and Inventory movement language.
  Those options must come from the owning capability contract rather than stay
  frozen inside a generic component.

### App shell, navigation, and account lifecycle

- `MainTabView` preserves a useful Projects/Review/Search/Settings information
  architecture and platform-specific navigation. It also activates the current
  Inventory listener from the UI and depends on Firebase-shaped Account and
  Inventory contexts.
- `AccountGateView`, `AuthView`, `AccountToolbarMenu`, and `UsersView` directly
  consume the current Auth/account services; `AuthView` imports Firebase Auth
  and `UsersView` opens Firestore listeners itself. Several invite/member writes
  suppress errors with `try?`.
- Current route structs correctly use stable IDs. Route resolution may provide
  an immediate cached first paint, but a missing object is ambiguous until the
  owning local query reports readiness. Navigation must not infer deletion or
  permission from a partially synchronized collection.
- Several `*PlaceholderView` files are obsolete scaffolding. They are not
  requirements and must not survive beside the real redesigned screens.

### Item actions, editors, lists, and calculations

- `ItemActionsController` constructs concrete services, sends raw
  `[String: Any]`/`NSNull` patches, uses fire-and-forget `try?`, clears
  relationships directly, and deletes Items without exposing a typed durable
  result. `ItemActionSheetsModifier` and `MakeCopiesModal` repeat that
  orchestration. These are provider-shaped command paths, not reusable
  presentation abstractions.
- `ItemMenuBuilder`, `ItemConflictSheet`, `AddExistingItemsCalculations`, shared
  enums, and associated tests still encode source-era Sale, Payment to Business,
  transaction-link, return/reassign, and status assumptions. The useful menu
  hierarchy and conflict-confirmation UX remain, but available actions and
  wording must be derived from story-specific capabilities and current local
  eligibility snapshots.
- Item detail/note/category/status editors preserve useful form outcomes, but
  raw dictionary patches become typed drafts and named commands. Server-
  validated locks, revision conflicts, authorization, and operation rejection
  remain visible instead of being dismissed as generic save errors.
- Current list filtering and grouping is deterministic and well tested, but it
  reads legacy model fields such as `transactionId`, URL presence, source text,
  status strings, and project price. Display grouping by normalized source/name/
  SKU cannot merge physical Item identity or serve as accounting authority.
  Totals may format authorized projection values; they may not reconstruct
  paid, open, recognized, or provenance amounts from presentation models.

### Camera, documents, images, and local utilities

- The native camera, document picker, selectable note text, PDF text extraction,
  zoom/pan/annotation interaction, and currency/selection/progress calculations
  preserve valuable platform outcomes.
- Camera bytes are only captured when handed to the caller; target acceptance
  occurs only after encrypted durable local persistence under the media contract.
- `ZoomableScrollView` loads URL values directly with `URLSession` and a global
  cache. `CreateItemsFromImagesModal`/`ImageGroupingState` identify images by
  URL. Target presentation resolves stable Attachment IDs to authorized local
  bytes or short-lived delivery, and grouping is keyed by stable attachment
  identity rather than bearer URLs.
- Imported document/PDF bytes require bounded size/type validation, scoped
  access lifetime, cancellation, redaction rules, and an explicit durable import
  operation before the UI reports acceptance.

### Existing tests

- Pure tests for currency, generic selection, progress geometry, action-menu
  expansion, selector layout, and stable-ID navigation are useful target test
  assets.
- Tests for listener teardown retain the lifecycle outcome but must be rewritten
  around workspace/Sync Stream subscriptions and readiness, not Firestore
  `ListenerRegistration` mocks.
- Firestore relationship integration tests are source-only evidence. Target
  relationship tests exercise application handlers, Postgres constraints/RLS,
  PowerSync local projections, offline restart, rejection, and reconciliation.
- Sale/payment-to-business display, transaction-step, bulk-sale, Item menu, and
  raw `transactionId` grouping tests encode superseded accounting. They are
  replaced by the approved Purchase/Return/Transfer and story-specific Item/
  Invoice/Inventory contracts; they are never ported merely to make old tests
  green.

## Product and Spec Reconciliation

App-shell and reusable presentation surfaces do not create a separate product
authority. Each screen, route, formatter, action, and test fixture inherits the
canonical target spec and decision IDs of its owning capability dossier. The
five redesign specs are the reviewed product set for accounting, Item,
Client/Transfer, and receipt-line UI; `offline-first.md` and
`financial-access-controls.md` add cross-cutting observable constraints.

Generic UI behavior may be preserved only when it does not encode Firebase
listeners, legacy Transaction taxonomy, duplicated accounting arithmetic, URL
identity, or incomplete-sync-as-empty behavior. Presentation tests must assert
the owning target contract, including pending/rejected operations and data
readiness, rather than source-era implementation parity.

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | iOS/macOS navigation outcomes; accessible design tokens and generic controls; stable-ID routes; deterministic display-only formatting; selection and in-page find behavior; camera/document acquisition; zoom/annotation interaction; visible loading, empty, conflict, retry, and operation-result states |
| Correct | View-owned SDK listeners; service construction in controllers; raw dictionaries/null sentinels; swallowed errors; immediate account switching/logout without pending-work policy; URL identity; incomplete-sync treated as absence; display grouping or selection sums treated as accounting truth |
| Improve | Typed view state and intents; operation receipt/rejection rendering; stable restoration keys per Account/environment; local readiness and stale indicators; accessibility/dynamic-type/platform parity; cancellation and bounded import; deterministic list cursors/facets; screenshot and fault-state coverage |
| Redesign | App workspace coordinator; Auth/account/member screens; Item action eligibility/menu/editor flows; list facets backed by named projections; attachment resolver; listener-lifecycle tests; accounting and relationship tests |
| Retire | Placeholder screens; generic Item patch/delete/link controller; target Firestore listener tests; URL-keyed media grouping; source-era Sale/payment and direct transaction-link menu semantics |
| Source only | Firestore relationship integration tests and the legacy Sale golden MCP fixture |

## Target Contracts

### Presentation boundary

Every feature screen consumes an immutable typed snapshot containing stable IDs,
authorization-safe fields, explicit readiness/staleness, and operation state.
It emits a named intent carrying the minimum user input and expected revision.
The screen never receives a database path, vendor SDK object, raw table row,
arbitrary field dictionary, service-role capability, or permission to compose a
multi-entity accounting write.

Reusable components may own ephemeral presentation state such as expansion,
focus, tab selection, draft text, local selection, and animation. Persisted
product state, money, relationships, access, archive state, and operation status
belong to the owning local projection/application contract.

### Workspace shell and readiness

After local unlock, the app shell selects one authenticated Principal and one
authorized Account workspace. A coordinator opens the environment/account-
namespaced local database, establishes the required Sync subscriptions, and
publishes one `WorkspaceReadinessSnapshot` covering session, local database,
required streams, pending operations, pending media, last successful sync, and
degraded/revoked state.

Account switch and logout run the identity dossier's pending-work policy before
closing a workspace. Switching cancels old Account tasks/subscriptions and
prevents late results from entering the new workspace. Re-entering the same
workspace is idempotent. The shell does not keep Inventory alive through a
separate global listener; required Account projections are declared once and
observed from the local database.

### Navigation and restoration

Routes contain stable entity IDs plus only the parent scope needed to resolve
authorization. Destination resolution returns `loading`, `ready`, `notFound`,
`notAuthorized`, `notSynced`, or `failed` without revealing inaccessible
existence. Restoration keys are namespaced by environment, Principal, and
Account; stale routes fail safely after account switch, archive, revoke, or
migration.

### Menus, forms, and operations

The owning feature supplies an `AvailableActionsSnapshot`; presentation does not
derive financial eligibility from raw fields. Each destructive or accounting
action opens the story-specific flow already defined by the Item, Inventory,
Transaction, Invoice, Space, or identity dossier. Typed edit drafts distinguish
unchanged, set, and clear values without `NSNull`. Submission returns the shared
durable operation receipt and renders optimistic, queued, confirmed, rejected,
conflicted, and retryable states.

Copying Items creates new stable Item identities through one idempotent command
and explicitly applies the approved evidence/relationship-copy policy. It does
not nil a Firestore document ID, loop independent creates, or inherit a frozen
accounting relationship by accident.

### Local lists, filtering, and totals

Named local queries own scope, visibility, stable ordering/cursor, filters,
facets, and readiness. In-memory filtering is allowed for an already authorized,
bounded working set and must preserve the same semantics. Display groups are
explicitly non-identity views; every row retains its physical Item ID.

Selection totals accept already-authorized integer-cent projection values and a
declared metric. They do not choose whether a value means project price, paid,
open, recognized, refund, or spend. Search/list state distinguishes no matches
from not-yet-synced and partially available data.

### Platform capture and attachment display

Camera/document/PDF inputs enter the media operation lifecycle immediately.
The UI may preview captured local bytes, but it reports accepted only after a
durable encrypted record exists. Attachment display uses stable IDs and an
authorized resolver that prefers local bytes; direct remote URL fetch and URL-
keyed identity are not target contracts.

## Verification Contract

- composition and lint tests proving redesigned views do not import Firebase,
  Supabase, PowerSync, Postgres clients, or construct infrastructure services;
- workspace activate/same-workspace/account-switch/logout/revoke/background/
  restart tests with no duplicate subscriptions, cross-account leakage, or
  pending-operation loss;
- route restoration and readiness tests for cached, missing, unauthorized,
  archived, not-yet-synced, and environment/account mismatch states;
- menu/action snapshots derived from every story-specific eligibility state,
  including offline queued, frozen Invoice, archived Space, correction, and
  destructive-operation cases;
- typed form tests for set/clear/unchanged, integer-cent parsing, revision
  conflict, rejection, retry, and idempotent submission;
- local list/filter/sort/cursor tests with stable IDs, deterministic ties,
  limited financial access, partial streams, large projects, and no display-
  grouping identity merge;
- camera/document/PDF/attachment tests covering permission, cancellation,
  process death, local-byte durability, size/type rejection, offline display,
  account switch, and URL expiry;
- accessibility, Dynamic Type, VoiceOver, keyboard, iOS/macOS and degraded/
  error-state presentation tests; and
- explicit replacement coverage showing no target test asserts source-era Sale,
  Payment to Business, direct `transactionId` relationship edits, Firestore
  listener mechanics, or raw document-array consistency.

This dossier does not authorize target code, schema, RLS, Sync Streams,
migration, production reads/mutations, release, or cutover. Product specs and
the decision log remain product authority; open O-002–O-043 and architecture
spike gates remain in force where referenced by the owning dossiers.
