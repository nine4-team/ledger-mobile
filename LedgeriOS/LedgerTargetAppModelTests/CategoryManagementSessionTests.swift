import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Category management shared form actions")
@MainActor
struct CategoryManagementSessionTests {
    private let account = try! AccountID(validating: "account")

    @Test func operationFeedbackDistinguishesLocalAcceptanceRejectionAndSync() throws {
        let session = CategoryManagementSession(accountId: account, runtime: runtime(Probe()))
        let command = try CategoryManagementCommand(operationId: OperationID(validating: "operation"),
            accountId: account, actorPrincipalId: PrincipalID(validating: "member"),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000), payload: create())
        func operation(_ state: OperationState, accountId: AccountID? = nil) throws -> OperationSnapshot {
            OperationSnapshot(operationId: command.envelope.operationId, accountId: accountId ?? account,
                contractVersion: command.envelope.contractVersion, fingerprint: try command.fingerprint,
                acceptedAt: command.envelope.clientCreatedAt, updatedAt: command.envelope.clientCreatedAt,
                state: state)
        }
        try session.receiveOperations([operation(.queued(attemptCount: 0, lastTransientError: nil))])
        #expect(session.syncMessage?.contains("waiting to sync") == true)
        let rejection = OperationRejection(error: .init(code: try ApplicationErrorCode(validating: "category_revision_conflict"),
            category: .conflict, retryDisposition: .afterUserCorrection), rejectedAt: command.envelope.clientCreatedAt)
        try session.receiveOperations([operation(.rejected(rejection))])
        #expect(session.syncMessage?.contains("could not sync") == true)
        session.invalidate()
        #expect(session.syncMessage == nil)
        let result = AppliedOperationResult(resultCode: try ApplicationResultCode(validating: "categories_updated"),
            serverReceivedAt: command.envelope.clientCreatedAt, completedAt: command.envelope.clientCreatedAt)
        try session.receiveOperations([operation(.applied(result))])
        #expect(session.syncMessage == "All category changes synced.")
        #expect(throws: CategoryManagementFailure.receiptMismatch) {
            try session.receiveOperations([operation(.applied(result), accountId: AccountID(validating: "foreign"))])
        }
        #expect(session.operations.isEmpty)
        #expect(session.syncMessage?.contains("status is unavailable") == true)
    }

    @Test func incompleteDirectoryAndForeignAccountCannotEnableSaving() async throws {
        let probe = Probe()
        let session = CategoryManagementSession(accountId: account, runtime: runtime(probe))
        #expect(!session.canSave)
        try session.receive(snapshot([], complete: false))
        await #expect(throws: CategoryManagementFailure.incompleteDirectory) {
            try await session.save(create())
        }
        #expect(await probe.calls.isEmpty)
        let foreign = CategoryManagementSession(accountId: try AccountID(validating: "other"), runtime: runtime(probe))
        #expect(throws: CategoryManagementFailure.wrongAccount) { try foreign.receive(snapshot([])) }
        #expect(foreign.snapshot == nil)
    }

    @Test func retryKeepsExactIdentityEvenWhenAcceptedProjectionArrivesBeforeResponse() async throws {
        let probe = Probe(failFirst: true)
        let session = CategoryManagementSession(accountId: account, runtime: runtime(probe))
        let initial = try snapshot([])
        try session.receive(initial)
        let payload = try create()
        await #expect(throws: InjectedFailure.self) { try await session.save(payload) }
        // An interrupted response does not imply that local acceptance failed.
        let accepted = try CategoryManagement.applying(payload, to: initial)
        try session.receive(snapshot(accepted))
        #expect(try await session.save(payload).localState == .queued)
        let calls = await probe.calls
        #expect(calls.count == 2)
        #expect(calls[0].uuid == calls[1].uuid)
        #expect(calls[0].date == calls[1].date)
        #expect(calls[0].payload == calls[1].payload)
        #expect(session.message == "Saved on this device; waiting to sync.")
    }

    @Test func changedInputUsesNewIdentityAndInvalidationPreventsFurtherWrites() async throws {
        let probe = Probe(failFirst: true)
        let session = CategoryManagementSession(accountId: account, runtime: runtime(probe))
        try session.receive(snapshot([]))
        await #expect(throws: InjectedFailure.self) { try await session.save(create()) }
        _ = try await session.save(create(name: "Updated name"))
        let calls = await probe.calls
        #expect(calls.count == 2)
        #expect(calls[0].uuid != calls[1].uuid)
        session.invalidate()
        #expect(session.categories.isEmpty)
        #expect(!session.canSave)
        await #expect(throws: CategoryManagementFailure.incompleteDirectory) {
            try await session.save(create())
        }
        #expect(await probe.calls.count == 2)
    }

    @Test func canonicallyEquivalentNameEditDoesNotReuseDifferentCommandBytes() async throws {
        let probe = Probe(failFirst: true)
        let session = CategoryManagementSession(accountId: account, runtime: runtime(probe))
        try session.receive(snapshot([]))
        let composed = try create(name: "Caf\u{00e9}")
        let decomposed = try create(name: "Cafe\u{0301}")
        #expect(composed == decomposed)
        await #expect(throws: InjectedFailure.self) { try await session.save(composed) }
        _ = try await session.save(decomposed)
        let calls = await probe.calls
        #expect(calls.count == 2)
        #expect(calls[0].uuid != calls[1].uuid)
        #expect(try OperationContractCodec.encode(calls[0].payload) != OperationContractCodec.encode(calls[1].payload))
        #expect(calls[1].payload.name?.rawValue.utf8.elementsEqual("Cafe\u{0301}".utf8) == true)
    }

    @Test func lifecycleTypeChangesAndReorderUseTheSamePayloadPath() async throws {
        let probe = Probe()
        let session = CategoryManagementSession(accountId: account, runtime: runtime(probe))
        var current = try snapshot([])
        let a = try create()
        let b = CategoryManagementPayload(action: .create, categoryId: try BudgetCategoryID(validating: "b"),
            name: try BudgetCategoryName(validating: "Art"), kind: .fee, excludesFromOverallBudget: false)
        for payload in [a, b] {
            try session.receive(current)
            _ = try await session.save(payload)
            current = try snapshot(CategoryManagement.applying(payload, to: current))
        }
        let row = try #require(current.local.rows.last)
        let edits: [CategoryManagementPayload] = [
            .init(action: .edit, categoryId: row.id, expectedRevision: 1,
                name: row.name, kind: .general, excludesFromOverallBudget: false),
            .init(action: .archive, categoryId: row.id, expectedRevision: 2),
            .init(action: .restore, categoryId: row.id, expectedRevision: 3),
            .init(action: .reorder, order: [
                .init(categoryId: row.id, expectedRevision: 4),
                .init(categoryId: try BudgetCategoryID(validating: "a"), expectedRevision: 1)])
        ]
        for payload in edits {
            try session.receive(current)
            _ = try await session.save(payload)
            current = try snapshot(CategoryManagement.applying(payload, to: current))
        }
        #expect(await probe.calls.map(\.payload.action) == [.create, .create, .edit, .archive, .restore, .reorder])
        #expect(current.local.rows.first?.id == row.id)
        #expect(current.local.rows.first?.kind == .general)
    }

    private func create(name: String = "Lighting") throws -> CategoryManagementPayload {
        .init(action: .create, categoryId: try BudgetCategoryID(validating: "a"),
            name: try BudgetCategoryName(validating: name), kind: .itemized, excludesFromOverallBudget: false)
    }
    private func runtime(_ probe: Probe) -> CategoryManagementRuntime {
        .init(watch: { AsyncThrowingStream { $0.finish() } }, submit: { try await probe.submit($0, $1, $2) })
    }
    private func snapshot(_ rows: [BudgetCategoryDefinitionSnapshot], complete: Bool = true) throws
        -> BudgetCategoryReferenceSnapshot {
        try BudgetCategoryReferenceSnapshot(accountId: account, local: ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(validating: String(repeating: "a", count: 64)),
            rows: rows, visibleRowCountBeforeFiltering: rows.count, isCompleteForQuery: complete,
            quality: complete ? .ready : .partial, localDataVersion: LocalDataVersion(validating: "test"),
            asOf: Date(timeIntervalSince1970: 1_800_000_000)))
    }
}

private struct InjectedFailure: Error {}
private actor Probe {
    struct Call: Sendable { let payload: CategoryManagementPayload; let uuid: UUID; let date: Date }
    private(set) var calls: [Call] = []
    let failFirst: Bool
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func submit(_ payload: CategoryManagementPayload, _ uuid: UUID, _ date: Date) throws -> OperationReceipt {
        calls.append(Call(payload: payload, uuid: uuid, date: date))
        if failFirst && calls.count == 1 { throw InjectedFailure() }
        return OperationReceipt(operationId: try OperationID(validating: uuid.uuidString), localState: .queued)
    }
}
