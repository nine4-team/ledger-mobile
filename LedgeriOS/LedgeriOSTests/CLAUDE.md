# Test Suite

> **Note:** Day-to-day app usage runs against **production** Firebase, not the emulator. Integration tests are the only thing in this project that requires the emulator. See the root `CLAUDE.md` for the production-default workflow and how to deploy `firestore.rules`.

Two test layers: **unit tests** (no emulator) and **integration tests** (Firestore emulator).

## Unit Tests

Pure function tests — calculations, validation, menu builders, Codable round-trips, RecordingBatch batch-write verification. No Firebase dependency at runtime.

```bash
cd LedgeriOS && xcodebuild test -scheme "LedgeriOS (Emulator)" \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -skip-testing:LedgeriOSTests/ItemCRUDIntegrationTests \
  -skip-testing:LedgeriOSTests/TransactionCRUDIntegrationTests \
  -skip-testing:LedgeriOSTests/RelationshipIntegrationTests \
  -skip-testing:LedgeriOSTests/SpaceCRUDIntegrationTests \
  -skip-testing:LedgeriOSTests/InventoryOperationsIntegrationTests \
  -derivedDataPath DerivedData -quiet
```

## Integration Tests

Write real data to the Firestore emulator, read it back, verify every field survives the round-trip. Tagged with `.integration` via Swift Testing `@Tag`.

**Require emulators running with test rules** (opens lineage edge writes for client-side batch operations):

```bash
# Terminal 1: start emulators with test rules
firebase emulators:start --import=./firebase-export --export-on-exit=./firebase-export \
  --config firebase.test.json

# Terminal 2: run integration tests
cd LedgeriOS && xcodebuild test -scheme "LedgeriOS (Emulator)" \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:LedgeriOSTests/ItemCRUDIntegrationTests \
  -only-testing:LedgeriOSTests/TransactionCRUDIntegrationTests \
  -only-testing:LedgeriOSTests/RelationshipIntegrationTests \
  -only-testing:LedgeriOSTests/SpaceCRUDIntegrationTests \
  -only-testing:LedgeriOSTests/InventoryOperationsIntegrationTests \
  -derivedDataPath DerivedData -quiet
```

**Run everything** (emulators must be running with test rules):

```bash
cd LedgeriOS && xcodebuild test -scheme "LedgeriOS (Emulator)" \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -derivedDataPath DerivedData -quiet
```

### Test Rules vs Production Rules

| File | Purpose |
|------|---------|
| `firebase/firestore.rules` | Production — lineage edges are server-only (`allow create: if false`) |
| `firebase/firestore.test.rules` | Test — lineage edges opened for client writes so `InventoryOperationsService` batch operations can be verified end-to-end |
| `firebase.test.json` | Firebase config pointing to test rules (same ports, same everything else) |

### Auth & Account Setup

`FirestoreTestHelper.signIn()` handles auth automatically:
- Signs in as `team@nine4.co` / `password123` (seeded emulator user)
- Creates a membership doc for the auth uid in the test account via the emulator REST API (bypasses security rules)
- Test account ID: `1dd4fd75-8eea-4f7a-98e7-bf45b987ae94` (seeded with `npm run dev:native`)
- Each test uses unique document IDs (UUID) so tests don't collide despite sharing one account

### Integration Test Suites

| Suite | File | Tests | What it catches |
|-------|------|-------|----------------|
| Item CRUD | `Integration/ItemCRUDIntegrationTests.swift` | 10 | Field round-trips, zero vs nil, false vs nil, update merge, NSNull clearing, delete, tax fields, raw field names |
| Transaction CRUD | `Integration/TransactionCRUDIntegrationTests.swift` | 9 | CodingKey remaps (`type`, `receiptEmailed`), arrayUnion/Remove, enum encoding, bool distinction |
| Relationships | `Integration/RelationshipIntegrationTests.swift` | 6 | Bidirectional item↔transaction linking, move between transactions, space/project assignment |
| Space CRUD | `Integration/SpaceCRUDIntegrationTests.swift` | 3 | Nested checklist encoding, partial update safety |
| Inventory Operations | `Integration/InventoryOperationsIntegrationTests.swift` | 6 | sellToBusiness, sellToProject (two-hop), reassignToProject, reassignToInventory — verifies item state, canonical sales, source tx updates, lineage edges |

### Shared Helpers

| File | Purpose |
|------|---------|
| `Helpers/TestFactories.swift` | `makeItem()`, `makeTransaction()`, `makeSpace()`, `makeProject()` with every field parameterized |
| `Helpers/RecordingBatch.swift` | Test double for `BatchWriting` — captures batch operations for assertion without touching Firestore |
| `Helpers/FirestoreTestHelper.swift` | Emulator auth sign-in, typed Firestore read/write, raw field reads, collection path helpers |

## Conventions

- **Framework:** Swift Testing (`@Test`, `@Suite`, `#expect`) — not XCTest
- **Naming:** `[Domain]CalculationTests`, `[Domain]ValidationTests`, `[Domain]CRUDIntegrationTests`
- **Factories:** Use shared `makeItem()` etc. from `TestFactories.swift` for integration tests. Existing unit tests have their own private factories (not yet migrated).
- **Integration tag:** All emulator tests use `.tags(.integration)` for filtering
