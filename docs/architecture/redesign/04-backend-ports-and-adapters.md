# Backend Ports and Adapters

Status: proposed architecture
Architecture version: 0.1
Last reviewed: 2026-08-31

## Purpose

This document defines the application-facing ports that keep Ledger independent
of the Supabase/PowerSync implementation while preserving the capabilities
needed for reliable offline operation. Supabase/PowerSync is the only production
implementation planned for the redesigned app.

## Port Design Rules

1. A reviewed capability dossier defines the observable contract before a port
   is accepted; an existing service or repository protocol is not automatically
   the target port.
2. A port is named for a Ledger capability, not a vendor product.
3. Port values contain domain and standard Swift types only.
4. Reads and commands use separate ports.
5. Commands expose queued/applied/rejected semantics explicitly.
6. Arbitrary collection names, SQL, field paths, and dynamic dictionaries never
   cross an application port.
7. Cancellation and observation use Swift concurrency primitives, not SDK
   listener handles.
8. Transport errors are mapped into the shared application error taxonomy.
9. A port should be small enough to have meaningful contract tests.

### Source-service review rule

Current Swift services and MCP modules are inventoried as evidence of existing
capabilities and dependencies. Before deriving a target port from them, review
the capability against canonical specs, redesign decisions, production shape,
offline/failure behavior, and the required preserve/correct/improve/redesign/
retire classification. Do not elevate a generic CRUD method, Firestore query,
unordered page, listener timing detail, or Admin SDK bypass into a target
contract merely because callers currently depend on it.

## Port Families

### Identity

```swift
protocol IdentitySessionProviding: Sendable {
    func session() async -> IdentitySession?
    func observeSession() -> AsyncStream<IdentitySession?>
    func accessToken() async throws -> AccessToken
}

protocol AccountSessionEnding: Sendable {
    func pendingWorkSummary() async throws -> PendingLocalWorkSummary
    func endSession(_ disposition: SessionEndDisposition) async throws
}
```

The application receives a `PrincipalID` and safe display information, not an
identity-provider user or Supabase session object. Provider tokens are opaque
and used only by infrastructure.

`SessionEndDisposition` permits ordinary clean logout, sync-then-logout, or
explicitly confirmed destructive local removal. The coordinator owns ordering
across sync shutdown, queue/media disposition, database/key cleanup, cache
cleanup, and provider signout; feature code cannot call provider signout
directly and bypass the durability policy.

### Account discovery and membership

```swift
protocol AccountQuerying: Sendable {
    func watchAuthorizedAccounts() -> AsyncThrowingStream<[AccountSummary], Error>
    func watchMembership(accountId: AccountID) -> AsyncThrowingStream<MembershipSnapshot, Error>
}

protocol MembershipQuerying: Sendable {
    func watchDirectory(
        accountId: AccountID
    ) -> AsyncThrowingStream<MemberDirectorySnapshot, Error>
}

protocol InviteQuerying: Sendable {
    func preview(_ token: InviteToken) async throws -> InvitePreview
    func watchPending(
        accountId: AccountID
    ) -> AsyncThrowingStream<InviteDirectorySnapshot, Error>
}

protocol AccountOperations: Sendable {
    func create(_ command: CreateAccountCommand) async throws -> OperationReceipt
}

protocol MembershipOperations: Sendable {
    func updateAccess(
        _ command: UpdateMemberAccessCommand
    ) async throws -> OperationReceipt
}

protocol InviteOperations: Sendable {
    func create(_ command: InviteMemberCommand) async throws -> OperationReceipt
    func revoke(_ command: RevokeInviteCommand) async throws -> OperationReceipt
    func accept(_ command: AcceptInviteCommand) async throws -> OperationReceipt
}
```

Account discovery must come from authorized local state and refresh when the
server changes membership. Account selection itself is an application-shell
workspace transition, not a server-side “active account” record and not an
authorization claim. Member/invite directories are separate capability-gated
queries; ordinary members do not receive administration rows merely because
they belong to the Account.

Invite preview is an online, rate-limited, non-enumerating query over an opaque
one-time secret and returns only approved display fields. Raw invite secrets,
token digests, Auth subjects and private member data never enter PowerSync. The
create/revoke/accept handlers derive the actor from authentication, validate
role and proposed financial permissions, and return the shared durable result.

### Clients, Projects, notes, preferences, and reference data

```swift
protocol ClientProjectDirectoryQuerying: Sendable {
    func watchClients(accountId: AccountID)
        -> AsyncThrowingStream<ClientListSnapshot, Error>
    func watchProjects(accountId: AccountID)
        -> AsyncThrowingStream<ProjectListSnapshot, Error>
}

protocol ProjectNoteQuerying: Sendable {
    func watchNotes(_ request: ProjectNotePageRequest)
        -> AsyncThrowingStream<ProjectNotePage, Error>
}

protocol ReferenceDataQuerying: Sendable {
    func watchReferenceData(accountId: AccountID)
        -> AsyncThrowingStream<ReferenceDataSnapshot, Error>
}

protocol ItemQuerying: Sendable {
    func watchItems(_ request: ItemListRequest)
        -> AsyncThrowingStream<ItemListSnapshot, Error>
    func search(_ request: ItemSearchRequest)
        -> AsyncThrowingStream<ItemSearchPage, Error>
}

protocol ItemDetailReadModelQuerying: Sendable {
    func watchItem(_ id: ItemID)
        -> AsyncThrowingStream<ItemDetailSnapshot, Error>
}

protocol ProjectItemAccountingQuerying: Sendable {
    func watchAccountingSections(projectId: ProjectID)
        -> AsyncThrowingStream<ProjectItemAccountingSnapshot, Error>
}

protocol TransactionQuerying: Sendable {
    func watchTransactions(_ request: TransactionListRequest)
        -> AsyncThrowingStream<TransactionListSnapshot, Error>
    func watchTransaction(_ id: TransactionID)
        -> AsyncThrowingStream<TransactionDetailSnapshot, Error>
    func search(_ request: TransactionSearchRequest)
        -> AsyncThrowingStream<TransactionSearchPage, Error>
}

protocol ItemHistoryQuerying: Sendable {
    func watchItemHistory(_ id: ItemID)
        -> AsyncThrowingStream<ItemHistorySnapshot, Error>
    func watchProjectHistory(_ request: ProjectHistoryRequest)
        -> AsyncThrowingStream<ProjectHistoryPage, Error>
}

protocol InventoryPlanningQuerying: Sendable {
    func watchPlannedPurchases(accountId: AccountID)
        -> AsyncThrowingStream<InventoryPlanningSnapshot, Error>
}

protocol InvoiceQuerying: Sendable {
    func watchInvoices(_ request: InvoiceListRequest)
        -> AsyncThrowingStream<InvoiceListSnapshot, Error>
    func watchInvoice(_ id: InvoiceID)
        -> AsyncThrowingStream<InvoiceDetailSnapshot, Error>
}

protocol BillingSummaryQuerying: Sendable {
    func watchBillingSummary(projectId: ProjectID)
        -> AsyncThrowingStream<ProjectBillingSummarySnapshot, Error>
}

protocol SpaceQuerying: Sendable {
    func watchSpaces(_ request: SpaceListRequest)
        -> AsyncThrowingStream<SpaceListSnapshot, Error>
    func watchSpace(_ id: SpaceID)
        -> AsyncThrowingStream<SpaceWorkspaceSnapshot, Error>
}

protocol ClientOperations: Sendable {
    func create(_ command: CreateClientCommand) async throws -> OperationReceipt
    func rename(_ command: RenameClientCommand) async throws -> OperationReceipt
    func archive(_ command: ArchiveClientCommand) async throws -> OperationReceipt
}

protocol ProjectOperations: Sendable {
    func create(_ command: CreateProjectCommand) async throws -> OperationReceipt
    func rename(_ command: RenameProjectCommand) async throws -> OperationReceipt
    func updateDetails(
        _ command: UpdateProjectDetailsCommand
    ) async throws -> OperationReceipt
    func configureCategories(
        _ command: ConfigureProjectCategoriesCommand
    ) async throws -> OperationReceipt
    func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt
}

protocol ProjectNoteOperations: Sendable {
    func add(_ command: AddProjectNoteCommand) async throws -> OperationReceipt
    func edit(_ command: EditProjectNoteCommand) async throws -> OperationReceipt
    func remove(_ command: RemoveProjectNoteCommand) async throws -> OperationReceipt
}

protocol ProjectPreferenceOperations: Sendable {
    func update(
        _ command: UpdateProjectPreferencesCommand
    ) async throws -> OperationReceipt
}
```

Project creation binds one stable `ClientID` and the complete selected-category
set, preserving absent versus enabled-without-allocation versus explicit zero.
Hero media uses the separate durable attachment receipt. `ChangeProjectClient`,
Client merge, and physical Project deletion are deliberately absent until O-025
and O-024 define their correction, history, dependency and retention semantics.

Reference-data commands are capability-specific—category definition/archive/
order, vendor suggestion ordered-set changes, and Space-template lifecycle—not
generic CRUD. Their role/capability grants remain gated by O-026. Read access is
separate so authorized forms can operate offline without receiving mutation
authority. Personal Project preferences additionally require the current
Principal predicate and never rely on a caller-supplied user path.

### Workspace queries

```swift
protocol ProjectWorkspaceQuerying: Sendable {
    func watchProject(_ id: ProjectID) -> AsyncThrowingStream<ProjectWorkspaceSnapshot, Error>
}

protocol InventoryWorkspaceQuerying: Sendable {
    func watchInventory(accountId: AccountID) -> AsyncThrowingStream<InventoryWorkspaceSnapshot, Error>
}

protocol UniversalSearchQuerying: Sendable {
    func search(
        _ request: UniversalSearchRequest
    ) -> AsyncThrowingStream<UniversalSearchPage, Error>
}

protocol EntityLookupQuerying: Sendable {
    func fetch(_ request: EntityLookupRequest) async throws -> EntityLookupPage
}

protocol ReportQuerying: Sendable {
    func prepare(_ request: ReportRequest) async throws -> ReportSnapshot
}

protocol ExportQuerying: Sendable {
    func prepare(_ request: ExportRequest) async throws -> ExportSnapshot
}
```

These ports return local read models. They do not promise that every backend
stores a `ProjectWorkspaceSnapshot` directly.

Search, report, and export requests select named projection profiles, not raw
table fields or a `full` backend document mode. Results include readiness,
visibility scope, stable ordering/cursor state, and source/authority versions.
Rendering PDF/CSV is a separate pure presentation concern and cannot widen the
snapshot's authorized fields.

### Context-specific operations

Avoid a single god command bus at feature call sites. Prefer bounded-context
ports with typed inputs and a shared receipt:

```swift
protocol ItemOperations: Sendable {
    func create(_ command: CreateItemCommand) async throws -> OperationReceipt
    func updateDetails(
        _ command: UpdateItemDetailsCommand
    ) async throws -> OperationReceipt
    func setSpace(_ command: SetItemSpaceCommand) async throws -> OperationReceipt
    func setStatus(_ command: SetItemStatusCommand) async throws -> OperationReceipt
    func setBookmark(
        _ command: SetItemBookmarkCommand
    ) async throws -> OperationReceipt
    func linkAsClientPaid(_ command: LinkItemClientPaidCommand) async throws -> OperationReceipt
    func linkAsBusinessPaid(_ command: LinkItemBusinessPaidCommand) async throws -> OperationReceipt
}

protocol BulkItemOperations: Sendable {
    func updateDetails(
        _ command: BulkUpdateItemDetailsCommand
    ) async throws -> BulkOperationReceipt
}

protocol InventoryPlanningOperations: Sendable {
    func setIntent(
        _ command: SetInventoryPurchaseIntentCommand
    ) async throws -> OperationReceipt
    func clearIntent(
        _ command: ClearInventoryPurchaseIntentCommand
    ) async throws -> OperationReceipt
}

protocol VendorDocumentIntakeOperations: Sendable {
    func commit(
        _ command: CommitVendorDocumentDraftCommand
    ) async throws -> OperationReceipt
}

protocol InvoiceOperations: Sendable {
    func create(_ command: CreateInvoiceCommand) async throws -> OperationReceipt
    func reviseCreated(
        _ command: ReviseCreatedInvoiceCommand
    ) async throws -> OperationReceipt
    func markSent(_ command: MarkInvoiceSentCommand) async throws -> OperationReceipt
    func cancel(_ command: CancelInvoiceCommand) async throws -> OperationReceipt
    func collect(_ command: CollectInvoiceCommand) async throws -> OperationReceipt
}

protocol ExpenseOperations: Sendable {
    func create(_ command: CreateExpenseCommand) async throws -> OperationReceipt
    func updateOpen(_ command: UpdateOpenExpenseCommand) async throws -> OperationReceipt
    func cancelOpen(_ command: CancelOpenExpenseCommand) async throws -> OperationReceipt
}

protocol FeeOperations: Sendable {
    func create(_ command: CreateFeeCommand) async throws -> OperationReceipt
    func updateOpen(_ command: UpdateOpenFeeCommand) async throws -> OperationReceipt
    func cancelOpen(_ command: CancelOpenFeeCommand) async throws -> OperationReceipt
}

protocol BudgetQuerying: Sendable {
    func watchProjectBudget(
        _ id: ProjectID
    ) -> AsyncThrowingStream<ProjectBudgetSnapshot, Error>
}

protocol SpaceOperations: Sendable {
    func create(_ command: CreateSpaceCommand) async throws -> OperationReceipt
    func updateDetails(
        _ command: UpdateSpaceDetailsCommand
    ) async throws -> OperationReceipt
    func reviseChecklists(
        _ command: ReviseSpaceChecklistsCommand
    ) async throws -> OperationReceipt
    func assignItems(
        _ command: AssignItemsToSpaceCommand
    ) async throws -> OperationReceipt
    func archive(_ command: ArchiveSpaceCommand) async throws -> OperationReceipt
}

protocol SpaceReviewOperations: Sendable {
    func create(
        _ command: CreateSpaceReviewNoteCommand
    ) async throws -> OperationReceipt
    func revise(
        _ command: ReviseSpaceReviewNoteCommand
    ) async throws -> OperationReceipt
    func remove(
        _ command: RemoveSpaceReviewNoteCommand
    ) async throws -> OperationReceipt
}

protocol TransferOperations: Sendable {
    func transfer(_ command: TransferItemsCommand) async throws -> OperationReceipt
}

protocol PurchaseOperations: Sendable {
    func recordProjectPurchase(
        _ command: RecordProjectPurchaseCommand
    ) async throws -> OperationReceipt
    func recordInventoryPurchase(
        _ command: RecordInventoryPurchaseCommand
    ) async throws -> OperationReceipt
}

protocol ItemMovementOperations: Sendable {
    func placeInventoryItemInProject(
        _ command: PlaceInventoryItemInProjectCommand
    ) async throws -> OperationReceipt
    func removeUnpaidItemFromProject(
        _ command: RemoveUnpaidItemFromProjectCommand
    ) async throws -> OperationReceipt
    func returnPaidItemToInventoryAndCreateCredit(
        _ command: ReturnPaidItemToInventoryAndCreateCreditCommand
    ) async throws -> OperationReceipt
    func acquireProjectItemIntoInventory(
        _ command: AcquireProjectItemIntoInventoryCommand
    ) async throws -> OperationReceipt
    func restoreItemToSourceProject(
        _ command: RestoreItemToSourceProjectCommand
    ) async throws -> OperationReceipt
    func recordItemVendorDisposition(
        _ command: RecordItemVendorDispositionCommand
    ) async throws -> OperationReceipt
}

protocol MoneyReturnOperations: Sendable {
    func recordInventoryVendorRefund(
        _ command: RecordInventoryVendorRefundCommand
    ) async throws -> OperationReceipt
    func recordProjectVendorRefund(
        _ command: RecordProjectVendorRefundCommand
    ) async throws -> OperationReceipt
    func settleClientCreditAsCashRefund(
        _ command: SettleClientCreditAsCashRefundCommand
    ) async throws -> OperationReceipt
}

protocol CorrectionOperations: Sendable {
    func correctPurchase(_ command: CorrectPurchaseCommand) async throws -> OperationReceipt
    func correctReturn(_ command: CorrectReturnCommand) async throws -> OperationReceipt
    func correctTransactionScope(
        _ command: CorrectTransactionScopeCommand
    ) async throws -> OperationReceipt
    func reverseTransfer(_ command: ReverseTransferCommand) async throws -> OperationReceipt
}
```

There is deliberately no generic `createTransaction`, `updateTransaction`,
`returnItems`, `setTransactionItemIds`, or `correctTransactionAndItems` port.
Purchase/Return, physical placement, billing credit, Transfer and correction
have different validation and audit effects. A future `VoidTransaction` or
`DeleteSupersededTransaction` is advertised only after O-029 closes and cannot
be implemented as a status/delete field mutation.

There is likewise no `markInvoicePaid`, selected-line collection, generic
Invoice-line CRUD, or client-supplied source-amount port. Created-Invoice
membership is changed through `reviseCreated`; sent membership changes remain
capability-gated by O-034. All readers observe live source values until the
trusted collection handler freezes them.

Adapters may share an internal operation dispatcher. Public use cases remain
typed and discoverable. Operations blocked by an open product decision do not
appear in the enabled capability set even if their prospective contract is
documented.

### Operation status

```swift
protocol OperationQuerying: Sendable {
    func watchOperation(_ id: OperationID) -> AsyncThrowingStream<OperationSnapshot, Error>
    func watchUnresolvedOperations(accountId: AccountID) -> AsyncThrowingStream<[OperationSnapshot], Error>
}
```

### Attachments

```swift
protocol AttachmentStoring: Sendable {
    func enqueue(_ capture: LocalAttachmentCapture) async throws -> AttachmentReceipt
    func retry(_ id: AttachmentID) async
    func removeFailed(_ id: AttachmentID) async throws
    func localOrRemoteSource(_ id: AttachmentID) async -> AttachmentDisplaySource?
}

protocol AttachmentOperations: Sendable {
    func attachToItem(
        _ command: AttachMediaToItemCommand
    ) async throws -> OperationReceipt
    func attachToSpace(
        _ command: AttachMediaToSpaceCommand
    ) async throws -> OperationReceipt
    func attachToTransaction(
        _ command: AttachMediaToTransactionCommand
    ) async throws -> OperationReceipt
    func reorderItemMedia(
        _ command: ReorderItemMediaCommand
    ) async throws -> OperationReceipt
    func setPrimaryItemMedia(
        _ command: SetPrimaryItemMediaCommand
    ) async throws -> OperationReceipt
}
```

The port owns lifecycle semantics, not a method named for a Supabase Storage
upload primitive. Reference removal and physical-byte deletion are deliberately
absent from the enabled operation port until O-023 approves their product and
retention semantics. A future detach command must remove only the authorized
parent reference; physical cleanup remains reference-aware background retention.

### Sync health

```swift
protocol SyncHealthProviding: Sendable {
    func observeHealth() -> AsyncStream<SyncHealthSnapshot>
    func waitForLocalDurability(of operationId: OperationID) async throws
}
```

Waiting for local durability is allowed. Core UI flows must not wait for remote
commit unless the product explicitly defines the operation as online-only.

### Environment and clock

```swift
protocol LedgerEnvironmentProviding: Sendable {
    var environment: LedgerEnvironment { get }
    var backendKind: BackendKind { get }
    var buildContractVersion: OperationContractVersion { get }
}
```

The environment is fixed by the build/configuration and verified at startup. It
is not a user setting.

### Platform control and contract publication

These boundaries keep build, release, transport and operator mechanics out of
domain services while ensuring every client uses the same reviewed contracts:

```swift
protocol LedgerEnvironmentManifestValidating: Sendable {
    func validateBeforeOpeningInfrastructure(
        _ manifest: LedgerEnvironmentManifest
    ) throws -> ValidatedLedgerEnvironment
}

protocol ContractCatalogProviding: Sendable {
    func catalog() -> VersionedContractCatalog
}

protocol ProtectedArtifactExporting: Sendable {
    func export(_ request: ProtectedArtifactExportRequest) async throws
        -> ProtectedArtifactExportReceipt
}
```

`LedgerEnvironmentManifest` names environment, endpoint/resource identities,
local database/key namespace, release channel and schema/query/operation/Sync
contract versions. It contains no secret. Validation completes before Auth,
Storage, Sync, database or telemetry construction and refuses mixed resources.

`VersionedContractCatalog` is generated or parity-tested from the same command,
query, capability, error and authorization-policy registry used by app and MCP.
It is a product/API contract, not a dump of Postgres tables or persistence DTOs.

Protected exports use an explicit visibility scope, short-lived local artifact
lease and destination receipt. Share, print and download paths never make a
temporary URL or unencrypted temporary file into durable domain state.

## Domain Models Versus Persistence DTOs

The target adapter owns persistence DTOs and mappers:

```text
SQLite row         <-> PowerSync DTO <-> Domain/read model
Postgres JSON      <-> Supabase DTO  <-> Domain result
```

Domain entities must not use:

- Supabase/PostgREST response types;
- PowerSync row or CRUD-entry types;
- `[String: Any]` update contracts; or
- permanent Storage download URLs as object identity.

Mapping failures return explicit diagnostics rather than silently hiding data.

## Legacy Firebase Boundary

The current Firebase application is outside this port/adapter architecture. It
continues running from its existing production code until the hard cutover. Do
not refactor its repositories, listeners, writes, Functions, rules, Storage, or
models to conform to these ports.

Firebase-specific work is limited to separate operational tooling and controls:

- read-only inventory/export and verified backups;
- source-to-target migration transformation and correlation;
- final pending-write drain or explicit disposition;
- maintenance mode and fail-closed write freeze at cutover; and
- retained read-only source/rollback evidence after cutover.

Migration tooling may decode Firebase documents, but those DTOs and SDK types
never enter the redesigned app or satisfy an application port.

## Supabase/PowerSync Adapter

The target adapter combines four infrastructure capabilities:

1. PowerSync SQLite for local queries and durable structured changes;
2. a PowerSync backend connector for authentication and upload processing;
3. Supabase Data API/RPC for authoritative command execution; and
4. Supabase Storage for attachment objects.

The adapter maps PowerSync watch queries into Swift `AsyncThrowingStream` read
models. Complex local operations are persisted and projected atomically, then
uploaded as one idempotent command. The adapter completes the corresponding
PowerSync queue entries only after the command receives a synchronous server
outcome or a durable server result is confirmed.

A permanent domain rejection is acknowledged and synchronized as an operation
result. A transient infrastructure failure remains queued for retry.

## Test and Preview Adapters

### In-memory domain adapter

Used for pure use-case and view tests. It provides deterministic records,
operation results, clocks, and errors. It need not imitate SQLite.

### Contract fixture adapter

Runs the complete target contract against local and cloud-staging
Supabase/PowerSync environments. Observable semantics include:

- locally durable submission;
- event ordering allowed by the contract;
- idempotent command result;
- authorized query filtering;
- cancellation;
- conflict/rejection mapping; and
- attachment lifecycle.

### Failure adapter

Injects network loss, stale revisions, expired tokens, delayed sync, permanent
rejections, and corrupted payloads for deterministic UI recovery tests.

## Contract Tests

Backend neutrality means the ports specify observable semantics even though the
initial production implementation is Supabase/PowerSync. The target adapter and
in-memory/failure adapters pass the applicable contracts for every capability
they advertise.

### Port and infrastructure contracts

Every implementation passes these for each capability it advertises:

| Contract | Required behavior |
|---|---|
| Identity | Session observation maps provider state without leaking provider types |
| Query initial state | Cached/local rows arrive without server round-trip |
| Query updates | Relevant local changes update the stream; cancellation stops delivery |
| Error mapping | Stable application/domain error, never a leaked vendor error contract |
| Local durability | An advertised offline-capable operation survives adapter recreation/restart |
| Environment isolation | Production and staging identities/data/Storage cannot be mixed |
| Attachment | Local display precedes upload; retry does not duplicate object metadata |
| Logout | Pending work invokes the disposition policy; permitted cleanup removes local data, media, signed URLs, and keys |

Equivalent guarantees do not require identical timing or internal event counts.

### Supabase/PowerSync redesigned accounting contracts

The target adapter and authoritative handlers additionally prove:

| Contract | Required behavior |
|---|---|
| Idempotency | Same operation ID and payload yield one authoritative effect/result; payload mismatch rejects |
| Transactional atomicity | Every command commits all canonical mutations and result evidence or none |
| Transient failure | Operation remains queued and later succeeds |
| Permanent rejection | Queue advances; rejection remains observable |
| Conflict | Stable domain conflict, not raw Postgres/HTTP/PowerSync error |
| Tenant isolation | RLS and Sync Streams expose no unauthorized account rows |
| Financial isolation | Restricted rows, counts, amounts, and provenance are absent locally |
| Accounting stories | Every approved redesigned command satisfies its product invariants and traceability tests |
| Provenance completeness | Inventory/project read models can explain authorized Item history offline when readiness reports complete |

Source migration fixtures have a separate transform/reconciliation suite. They
are not an application adapter contract.

## Composition Root

`LedgerApp` evolves into a small composition root that constructs an
`AppDependencies` value:

```swift
struct AppDependencies: Sendable {
    let identity: any IdentitySessionProviding
    let sessionEnding: any AccountSessionEnding
    let accounts: any AccountQuerying
    let clientProjectDirectory: any ClientProjectDirectoryQuerying
    let projects: any ProjectWorkspaceQuerying
    let projectNotes: any ProjectNoteQuerying
    let referenceData: any ReferenceDataQuerying
    let itemQueries: any ItemQuerying
    let itemDetails: any ItemDetailReadModelQuerying
    let projectItemAccounting: any ProjectItemAccountingQuerying
    let transactions: any TransactionQuerying
    let itemHistory: any ItemHistoryQuerying
    let inventoryPlanning: any InventoryPlanningQuerying
    let invoiceQueries: any InvoiceQuerying
    let billingSummary: any BillingSummaryQuerying
    let spaceQueries: any SpaceQuerying
    let inventory: any InventoryWorkspaceQuerying
    let search: any UniversalSearchQuerying
    let lookups: any EntityLookupQuerying
    let reports: any ReportQuerying
    let exports: any ExportQuerying
    let operations: any OperationQuerying
    let attachments: any AttachmentStoring
    let syncHealth: any SyncHealthProviding
    let capabilities: LedgerCapabilities
    let clients: any ClientOperations
    let projectOperations: any ProjectOperations
    let projectNoteOperations: any ProjectNoteOperations
    let projectPreferences: any ProjectPreferenceOperations
    let items: any ItemOperations
    let bulkItems: any BulkItemOperations
    let inventoryPlanningOperations: any InventoryPlanningOperations
    let vendorDocumentIntake: any VendorDocumentIntakeOperations
    let invoices: any InvoiceOperations
    let expenses: any ExpenseOperations
    let fees: any FeeOperations
    let budgets: any BudgetQuerying
    let spaces: any SpaceOperations
    let spaceReviews: any SpaceReviewOperations
    let transfers: any TransferOperations
    let purchases: any PurchaseOperations
    let itemMovement: any ItemMovementOperations
    let moneyReturns: any MoneyReturnOperations
    let corrections: any CorrectionOperations
}
```

Environment-specific factories construct the complete set. Mixing production
identity with staging Supabase data, or production Supabase Storage with staging
structured data, fails startup validation. Capability gating reflects unresolved
product/architecture decisions, not a Firebase/Supabase runtime switch.

## Incremental Refactor Sequence

1. Introduce typed IDs, receipts, operation states, and application errors in
   the redesigned target modules.
2. Define local query ports, command ports, identity, attachments, environment,
   and session-ending contracts.
3. Implement the encrypted PowerSync local schema and local read models.
4. Implement Supabase Auth/approved Auth integration, Postgres commands/RLS,
   PowerSync upload/Sync Streams, and Supabase Storage behind those ports.
5. Make each target vertical slice pass accounting, security, provenance,
   offline, fault, and migration-reconciliation contracts before it is enabled.
6. Delete target-incompatible Firebase imports from redesigned modules rather
   than wrapping them.

This sequence creates reusable architecture before changing production
authority.

## Anti-Patterns

- `BackendRepository<T>` with string paths and arbitrary filters.
- A protocol copied from or merely renaming existing Firestore methods.
- Domain models conditionally importing different SDK annotations.
- Views branching on `.firebase` versus `.supabase`.
- Importing existing Firebase repositories into the redesigned target instead of
  implementing the Supabase/PowerSync port.
- Catching every backend error and reporting local success.
- Treating “online” as proof a command is committed.
- Calling service-role APIs from the app.
- Implementing business invariants once per client rather than at the server
  authority.
- Letting MCP mutate tables in ways the app cannot express as a domain command.
