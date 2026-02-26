# Phase 2: Swift Data Models + Service Layer — Design

## Decisions

- **Codable with @DocumentID** — Firestore SDK handles serialization. Greenfield data — no legacy field migrations needed.
- **Native cache-first** — iOS Firestore SDK's `addSnapshotListener` delivers cached data first automatically. No `getDocsFromCache` prelude needed (that was a React Native workaround).
- **Core services first** — 8 services needed for first screens. Rest added when their screens need them.
- **Testability by default** — Pure functions for business logic, protocol-based services for mocking.

---

## Architecture Overview

```
┌──────────────────────────────────────────────┐
│  Views (Phase 3-4)                           │
│  Read from @Observable state managers        │
├──────────────────────────────────────────────┤
│  State Managers (@Observable)                │
│  AccountContext, ProjectContext, SyncStatus   │
│  Own subscriptions, expose published state   │
├──────────────────────────────────────────────┤
│  Services (protocol + implementation)        │
│  ProjectService, ItemsService, etc.          │
│  Thin wrappers around FirestoreRepository    │
├──────────────────────────────────────────────┤
│  FirestoreRepository<T: Codable>             │
│  Generic CRUD + real-time subscriptions      │
│  Handles paths, encoding, decoding           │
├──────────────────────────────────────────────┤
│  Firestore SDK                               │
│  Native cache, offline writes, snapshots     │
└──────────────────────────────────────────────┘
```

---

## Layer 1: Models (Swift structs, Codable)

All models are plain structs. No classes, no @Observable. Just data + Codable.

### Shared Types

```swift
// AttachmentRef — used by Item, Transaction, Space
struct AttachmentRef: Codable, Hashable {
    var url: String
    var kind: AttachmentKind = .image
    var fileName: String?
    var contentType: String?
    var isPrimary: Bool?
}

enum AttachmentKind: String, Codable {
    case image, pdf, file
}
```

### Core Models (port now)

| Model | Firestore Path | Fields | Notes |
|-------|---------------|--------|-------|
| Account | `accounts/{id}` | 3 + timestamps | Minimal |
| Project | `accounts/{aid}/projects/{id}` | 6 + budgetSummary + timestamps | Nested BudgetSummary struct |
| Transaction | `accounts/{aid}/transactions/{id}` | 21 + timestamps | Largest model, many optionals |
| Item | `accounts/{aid}/items/{id}` | 14 + timestamps | `name` field, no legacy `description` |
| Space | `accounts/{aid}/spaces/{id}` | 7 + timestamps | Nested Checklist/ChecklistItem |
| BudgetCategory | `accounts/{aid}/presets/default/budgetCategories/{id}` | 7 + metadata + timestamps | Nested metadata struct |
| ProjectBudgetCategory | `accounts/{aid}/projects/{pid}/budgetCategories/{id}` | 3 + timestamps | Simple |
| AccountMember | `accounts/{aid}/users/{uid}` | 5 + timestamps | Read-only from client |

### Model Definitions

All models use `@DocumentID var id: String?` for Firestore document ID mapping. This is the official Firebase pattern — `Optional<String>` satisfies `Identifiable` via Swift's conditional `Hashable` conformance. The ID is `nil` only during local construction; Firestore populates it on decode, and our `create()` pre-generates it before display.

Audit fields: `@ServerTimestamp` for `createdAt`/`updatedAt` on all models. `createdBy`/`updatedBy` as optional `String?` on models that write them (Item, ProjectBudgetCategory). These are audit-only — never displayed in UI.

#### Item

```swift
import FirebaseFirestore

struct Item: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var spaceId: String?
    var name: String = ""
    var notes: String?
    var status: String?
    var source: String?
    var sku: String?
    var transactionId: String?
    var purchasePriceCents: Int?
    var projectPriceCents: Int?
    var marketValueCents: Int?
    var purchasedBy: String?
    var bookmark: Bool?
    var budgetCategoryId: String?
    var images: [AttachmentRef]?
    var createdBy: String?
    var updatedBy: String?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
```

#### Transaction

```swift
struct Transaction: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var projectId: String?
    var transactionDate: String?
    var amountCents: Int?
    var source: String?
    var isCanonicalInventory: Bool?
    var canonicalKind: String?
    var isCanonicalInventorySale: Bool?
    var inventorySaleDirection: InventorySaleDirection?
    var itemIds: [String]?
    var status: String?
    var purchasedBy: String?
    var reimbursementType: String?
    var notes: String?
    var transactionType: String?
    var isCanceled: Bool?
    var budgetCategoryId: String?
    var hasEmailReceipt: Bool?
    var receiptImages: [AttachmentRef]?
    var otherImages: [AttachmentRef]?
    var transactionImages: [AttachmentRef]?
    var needsReview: Bool?
    var taxRatePct: Double?
    var subtotalCents: Int?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
```

#### Project

```swift
struct Project: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var name: String = ""
    var clientName: String = ""
    var description: String?
    var mainImageUrl: String?
    var isArchived: Bool?
    var budgetSummary: ProjectBudgetSummary?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

struct ProjectBudgetSummary: Codable, Hashable {
    var totalBudgetCents: Int?
    var categories: [BudgetSummaryCategory]?
}

struct BudgetSummaryCategory: Codable, Hashable {
    var budgetCategoryId: String?
    var budgetCents: Int?
}
```

#### Space

```swift
struct Space: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var name: String = ""
    var notes: String?
    var images: [AttachmentRef]?
    var checklists: [Checklist]?
    var isArchived: Bool?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

struct Checklist: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var items: [ChecklistItem] = []
}

struct ChecklistItem: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var text: String = ""
    var isChecked: Bool = false
}
```

#### BudgetCategory

```swift
struct BudgetCategory: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var name: String = ""
    var slug: String?
    var isArchived: Bool?
    var order: Int?
    var metadata: BudgetCategoryMetadata?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

struct BudgetCategoryMetadata: Codable, Hashable {
    var categoryType: BudgetCategoryType?
    var excludeFromOverallBudget: Bool?
}
```

#### ProjectBudgetCategory

```swift
struct ProjectBudgetCategory: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var budgetCents: Int?
    var createdBy: String?
    var updatedBy: String?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
```

#### Account

```swift
struct Account: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var name: String = ""
    var ownerUid: String?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
```

#### AccountMember

```swift
struct AccountMember: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var uid: String?
    var role: MemberRole?
    var email: String?
    var name: String?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
```

### Enums

```swift
enum BudgetCategoryType: String, Codable {
    case general, itemized, fee
}

enum MemberRole: String, Codable {
    case owner, admin, user
}

enum InventorySaleDirection: String, Codable {
    case businessToProject = "business_to_project"
    case projectToBusiness = "project_to_business"
}
```

### File Organization

```
LedgeriOS/
├── Models/
│   ├── Account.swift
│   ├── Project.swift
│   ├── Transaction.swift
│   ├── Item.swift
│   ├── Space.swift
│   ├── BudgetCategory.swift
│   ├── ProjectBudgetCategory.swift
│   ├── AccountMember.swift
│   └── Shared/
│       ├── AttachmentRef.swift
│       └── Enums.swift
```

---

## Layer 2: FirestoreRepository<T>

Generic repository that handles all Firestore operations for any Codable type.

### Protocol (for testing)

```swift
protocol Repository<T> {
    associatedtype T: Codable & Identifiable

    func get(id: String) async throws -> T?
    func list() async throws -> [T]
    func list(where field: String, isEqualTo value: Any) async throws -> [T]
    func create(_ item: T) throws -> String
    func update(id: String, fields: [String: Any]) async throws
    func delete(id: String) async throws
    func subscribe(onChange: @escaping ([T]) -> Void) -> ListenerRegistration
    func subscribe(id: String, onChange: @escaping (T?) -> Void) -> ListenerRegistration
}
```

### Implementation

```swift
final class FirestoreRepository<T: Codable & Identifiable>: Repository {
    private let collectionPath: String
    private let db = Firestore.firestore()

    init(path: String) {
        self.collectionPath = path
    }

    private var collectionRef: CollectionReference {
        db.collection(collectionPath)
    }

    func get(id: String) async throws -> T? {
        let snapshot = try await collectionRef.document(id).getDocument()
        return try snapshot.data(as: T.self)
    }

    func create(_ item: T) throws -> String {
        let docRef = collectionRef.document()  // Pre-generate ID
        try docRef.setData(from: item)          // Fire-and-forget (no await)
        return docRef.documentID
    }

    func subscribe(onChange: @escaping ([T]) -> Void) -> ListenerRegistration {
        collectionRef.addSnapshotListener { snapshot, error in
            guard let docs = snapshot?.documents else { return }
            let items = docs.compactMap { try? $0.data(as: T.self) }
            onChange(items)
        }
    }

    // ... etc
}
```

Key points:
- `create` returns ID synchronously (pre-generated), writes fire-and-forget — **offline-first**
- `subscribe` uses native `addSnapshotListener` — delivers cached data first (with `isFromCache` metadata), then server data. No `getDocsFromCache` prelude needed (that was a React Native Firebase workaround).
- Codable handles all serialization — no manual normalizers
- Protocol enables mock repositories in tests
- All write operations call `syncTracker.trackPendingWrite()` for future sync status visibility

---

## Layer 3: Services

Thin wrappers that know collection paths and add entity-specific query logic.

### Protocol Pattern

```swift
protocol ProjectServiceProtocol {
    func getProject(accountId: String, projectId: String) async throws -> Project?
    func createProject(accountId: String, name: String, clientName: String, description: String?) throws -> String
    func updateProject(accountId: String, projectId: String, fields: [String: Any]) async throws
    func deleteProject(accountId: String, projectId: String) async throws
    func subscribeToProjects(accountId: String, onChange: @escaping ([Project]) -> Void) -> ListenerRegistration
    func subscribeToProject(accountId: String, projectId: String, onChange: @escaping (Project?) -> Void) -> ListenerRegistration
}
```

### Implementation

```swift
struct ProjectService: ProjectServiceProtocol {
    let syncTracker: SyncTracking

    func createProject(accountId: String, name: String, clientName: String, description: String?) throws -> String {
        let repo = FirestoreRepository<Project>(path: "accounts/\(accountId)/projects")
        var project = Project()
        project.accountId = accountId
        project.name = name
        project.clientName = clientName
        project.description = description
        let id = try repo.create(project)
        syncTracker.trackPendingWrite()
        return id
    }

    // ... other methods build repo with the right path, call syncTracker on writes
}
```

### Services to Implement (core)

| Service | Collection Path | Key Operations |
|---------|----------------|----------------|
| AccountsService | `accounts` | get, subscribe |
| ProjectService | `accounts/{aid}/projects` | CRUD, subscribe, subscribeList |
| TransactionsService | `accounts/{aid}/transactions` | CRUD, subscribe, scoped queries |
| ItemsService | `accounts/{aid}/items` | CRUD, subscribe, scoped queries |
| SpacesService | `accounts/{aid}/spaces` | CRUD, subscribe (filter !isArchived) |
| BudgetCategoriesService | `accounts/{aid}/presets/default/budgetCategories` | CRUD, subscribe, reorder |
| ProjectBudgetCategoriesService | `accounts/{aid}/projects/{pid}/budgetCategories` | set, subscribe |
| BudgetProgressService | (computed from transactions + categories) | subscribe, pure aggregation |

### Scoped Queries

Items and Transactions need scope-aware queries (project vs inventory):

```swift
enum ListScope {
    case project(String)   // projectId
    case inventory         // projectId == nil
    case all               // no filter
}
```

Services add `.whereField("projectId", isEqualTo: projectId)` or `.whereField("projectId", isEqualTo: NSNull())` based on scope.

---

## Layer 4: State Managers (@Observable)

Replace Zustand stores. These are the objects that views will consume.

### AccountContext

```swift
@MainActor
@Observable
final class AccountContext {
    var currentAccountId: String?
    var account: Account?
    var member: AccountMember?

    private var listeners: [ListenerRegistration] = []

    func activate(accountId: String, userId: String) { ... }
    func deactivate() { ... }
}
```

### ProjectContext

```swift
@MainActor
@Observable
final class ProjectContext {
    var currentProjectId: String?
    var project: Project?
    var projects: [Project] = []
    var transactions: [Transaction] = []
    var items: [Item] = []
    var spaces: [Space] = []
    var budgetCategories: [BudgetCategory] = []
    var budgetProgress: BudgetProgress?

    private var listeners: [ListenerRegistration] = []

    func activate(accountId: String, projectId: String) { ... }
    func deactivate() { ... }
}
```

**Lifecycle:** This mirrors the current RN `ProjectShell` component, which creates 8 parallel subscriptions when a project is opened and tears them all down on unmount. In SwiftUI, `activate()` is called from `.task(id: projectId)` on the project detail view (auto-cancels on disappear or ID change), and `deactivate()` removes all `ListenerRegistration`s. When the user switches projects, the old subscriptions are torn down and new ones created.

### SyncTracking (stub now, implement later)

All write operations call `trackPendingWrite()` from day one. Start with a no-op so we don't have to retrofit services later:

```swift
protocol SyncTracking {
    func trackPendingWrite()
}

struct NoOpSyncTracker: SyncTracking {
    func trackPendingWrite() {}  // Swap for real implementation when SyncStatus UI is built
}
```

---

## Layer 5: Pure Business Logic (testable)

Extracted from services, tested independently. No Firestore dependency.

```swift
// BudgetProgress.swift — pure computation
struct BudgetProgress {
    let totalBudgetCents: Int
    let totalSpentCents: Int
    let categories: [CategoryProgress]

    struct CategoryProgress: Identifiable {
        let id: String
        let name: String
        let budgetCents: Int
        let spentCents: Int
        let categoryType: BudgetCategoryType
        let excludeFromOverallBudget: Bool
    }
}

// Pure function — no Firestore, no side effects
func buildBudgetProgress(
    transactions: [Transaction],
    categories: [BudgetCategory],
    projectBudgetCategories: [ProjectBudgetCategory]
) -> BudgetProgress {
    // Filter canceled transactions
    // Aggregate spending by category
    // Handle canonical inventory sales (directional amounts)
    // Respect excludeFromOverallBudget flag
}

func normalizeSpendAmount(_ transaction: Transaction) -> Int {
    // Returns positive or negative cents based on transaction type
    // Pure, testable
}
```

---

## Testing Strategy

### What Gets Tested

| Layer | Test Type | Example |
|-------|-----------|---------|
| Models | Codable round-trip | Encode Item → JSON → decode, assert equality |
| Pure logic | Unit tests | `buildBudgetProgress()` with known inputs |
| Services | Integration (mock repo) | ProjectService with MockRepository, assert correct calls |
| State Managers | Unit tests | Set up AccountContext, call activate(), assert state changes |

### Mock Repository

```swift
final class MockRepository<T: Codable & Identifiable>: Repository {
    var items: [T] = []
    var createCalled = false
    var lastCreatedItem: T?

    func get(id: String) async throws -> T? {
        items.first { "\($0.id)" == id }
    }

    func create(_ item: T) throws -> String {
        createCalled = true
        lastCreatedItem = item
        return "mock-id"
    }

    // ... etc
}
```

### Test Examples

```swift
// Pure logic test — no mocks needed
func testNormalizeSpendAmount_canceledTransaction() {
    var tx = Transaction()
    tx.amountCents = 5000
    tx.isCanceled = true
    XCTAssertEqual(normalizeSpendAmount(tx), 0)
}

func testBuildBudgetProgress_excludesArchivedCategories() {
    let categories = [makeBudgetCategory(isArchived: true)]
    let result = buildBudgetProgress(transactions: [], categories: categories, projectBudgetCategories: [])
    XCTAssertEqual(result.categories.count, 0)
}

// Codable round-trip test
func testItemCodableRoundTrip() throws {
    var item = Item()
    item.name = "Test Chair"
    item.purchasePriceCents = 15000
    item.images = [AttachmentRef(url: "https://example.com/img.jpg")]

    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(Item.self, from: data)

    XCTAssertEqual(decoded.name, "Test Chair")
    XCTAssertEqual(decoded.purchasePriceCents, 15000)
    XCTAssertEqual(decoded.images?.count, 1)
}
```

---

## File Structure (final)

```
LedgeriOS/LedgeriOS/
├── Models/
│   ├── Account.swift
│   ├── Project.swift
│   ├── Transaction.swift
│   ├── Item.swift
│   ├── Space.swift
│   ├── BudgetCategory.swift
│   ├── ProjectBudgetCategory.swift
│   ├── AccountMember.swift
│   ├── BudgetProgress.swift            ← pure computation struct
│   └── Shared/
│       ├── AttachmentRef.swift
│       └── Enums.swift
├── Services/
│   ├── Protocols/
│   │   ├── RepositoryProtocol.swift
│   │   ├── ProjectServiceProtocol.swift
│   │   ├── ItemsServiceProtocol.swift
│   │   ├── TransactionsServiceProtocol.swift
│   │   ├── SpacesServiceProtocol.swift
│   │   └── BudgetServiceProtocols.swift
│   ├── FirestoreRepository.swift       ← generic, one file
│   ├── AccountsService.swift
│   ├── ProjectService.swift
│   ├── TransactionsService.swift
│   ├── ItemsService.swift
│   ├── SpacesService.swift
│   ├── BudgetCategoriesService.swift
│   ├── ProjectBudgetCategoriesService.swift
│   └── BudgetProgressService.swift
├── Logic/
│   ├── BudgetCalculations.swift        ← pure functions
│   └── ScopeFilters.swift              ← pure functions
├── State/
│   ├── AccountContext.swift
│   ├── ProjectContext.swift
│   └── SyncTracking.swift              ← protocol + no-op stub
├── Auth/                               ← existing
├── Theme/                              ← existing
└── Views/                              ← existing
```

---

## What's Deferred

These are NOT in scope for Phase 2 core. Added when their screens need them:

- InvitesService, AccountMembersService (Settings screens)
- LineageEdgesService (Item detail audit trail)
- SpaceTemplatesService, VendorDefaultsService (Settings presets)
- BusinessProfileService (Account settings)
- ProjectPreferencesService, AccountPresetsService (Budget pinning)
- RequestDocsService, InventoryOperationsService, ReturnFlowService (Inventory operations)
- Report computation functions (Report screens)
- MediaManager (Photo/file upload — needs Firebase Storage)
- ListStateManager (local persistence — UserDefaults or SwiftData)
