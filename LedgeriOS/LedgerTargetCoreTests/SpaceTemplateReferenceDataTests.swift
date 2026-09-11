import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space Template Reference Read Contracts")
struct SpaceTemplateReferenceDataTests {
    @Test("Ordered templates preserve structure without carrying checked state")
    func exactStructureHasNoCheckedState() throws {
        let fixture = try Self.fixture()
        let rows = fixture.snapshot.local.rows

        #expect(rows.map(\.id.rawValue) == [
            "template-installation",
            "template-storage",
            "template-archived"
        ])
        #expect(rows.map(\.presentationOrder) == [1, 2, 3])
        #expect(rows.map(\.revision) == [11, 12, 13])
        #expect(rows[0].name.rawValue == "Installation Day")
        #expect(rows[0].notes == "Protect finished surfaces.")
        #expect(rows[0].checklists.map(\.id.rawValue) == [
            "checklist-arrival",
            "checklist-installation"
        ])
        #expect(rows[0].checklists.map(\.presentationOrder) == [1, 2])
        #expect(rows[0].checklists[0].items.isEmpty)
        #expect(rows[0].checklists[1].items.map(\.id.rawValue) == [
            "item-unpack",
            "item-hang"
        ])
        #expect(rows[0].checklists[1].items.map(\.presentationOrder) == [1, 2])
        #expect(rows[0].checklists[1].items.map(\.text.rawValue) == [
            "Unpack boxes",
            "Hang  artwork"
        ])
        #expect(rows[0].isSelectable)
        #expect(!rows[2].isSelectable)
        #expect(fixture.snapshot.selectableTemplates.map(\.id.rawValue) == [
            "template-installation",
            "template-storage"
        ])

        let bytes = try OperationContractCodec.encode(fixture.snapshot)
        let root = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        #expect(Set(root.keys) == Set(["accountId", "local"]))
        let local = try #require(root["local"] as? [String: Any])
        let encodedRows = try #require(local["rows"] as? [[String: Any]])
        let template = try #require(encodedRows.first)
        #expect(Set(template.keys) == Set([
            "id", "accountId", "name", "notes", "checklists", "lifecycle",
            "presentationOrder", "revision"
        ]))
        let checklists = try #require(template["checklists"] as? [[String: Any]])
        let checklist = try #require(checklists.last)
        #expect(Set(checklist.keys) == Set([
            "id", "name", "presentationOrder", "items"
        ]))
        let items = try #require(checklist["items"] as? [[String: Any]])
        let item = try #require(items.first)
        #expect(Set(item.keys) == Set(["id", "text", "presentationOrder"]))

        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "ischecked", "is_checked", "spaceid", "space_id", "projectid",
            "project_id", "firebase", "firestore", "supabase", "powersync",
            "https://", "file://", "bearer", "token", "secret", "serviceaccount",
            "service_account", "role", "capability", "sql"
        ] {
            #expect(!text.contains(forbidden))
        }

        let itemBytes = try OperationContractCodec.encode(
            rows[0].checklists[1].items[0]
        )
        let staleSourceBytes = Data(
            String(decoding: itemBytes, as: UTF8.self)
                .replacingOccurrences(
                    of: #""text":"Unpack boxes""#,
                    with: #""isChecked":true,"text":"Unpack boxes""#
                )
                .utf8
        )
        #expect(String(decoding: staleSourceBytes, as: UTF8.self).contains("isChecked"))
        let normalized = try OperationContractCodec.decode(
            SpaceTemplateChecklistItemDefinition.self,
            from: staleSourceBytes
        )
        let normalizedBytes = try OperationContractCodec.encode(normalized)
        #expect(!String(decoding: normalizedBytes, as: UTF8.self).contains("isChecked"))
    }

    @Test("Ready, partial, stale, and authoritative-empty evidence survives restart")
    func readinessSurvivesCanonicalRestart() throws {
        let fixture = try Self.fixture()
        let first = fixture.snapshot.local.rows[0]
        let partial = try Self.snapshot(
            accountId: fixture.accountId,
            rows: [first],
            quality: .partial,
            isComplete: false,
            fingerprintCharacter: "b",
            version: "space-template-partial",
            asOf: Self.t1
        )
        let stale = try Self.snapshot(
            accountId: fixture.accountId,
            rows: [first],
            quality: .stale,
            isComplete: false,
            fingerprintCharacter: "c",
            version: "space-template-stale",
            asOf: Self.t2
        )
        let authoritativeEmpty = try Self.snapshot(
            accountId: fixture.accountId,
            rows: [],
            quality: .ready,
            isComplete: true,
            fingerprintCharacter: "d",
            version: "space-template-empty",
            asOf: Self.t3
        )
        let restart = RestartFixture(
            ready: fixture.snapshot,
            partial: partial,
            stale: stale,
            authoritativeEmpty: authoritativeEmpty
        )

        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)

        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.ready.local.quality == .ready)
        #expect(restored.ready.local.isCompleteForQuery)
        #expect(restored.partial.local.quality == .partial)
        #expect(!restored.partial.local.isCompleteForQuery)
        #expect(restored.stale.local.quality == .stale)
        #expect(!restored.stale.local.isCompleteForQuery)
        #expect(restored.authoritativeEmpty.local.rows.isEmpty)
        #expect(restored.authoritativeEmpty.local.isCompleteForQuery)
        #expect(restored.authoritativeEmpty.selectableTemplates.isEmpty)
    }

    @Test("Invalid, cross-scope, duplicate, and malformed template evidence fails")
    func invalidTemplateEvidenceFailsClosed() throws {
        #expect(Self.referenceFailure {
            try SpaceTemplateName(validating: "  ")
        } == .invalidTemplateName)
        #expect(Self.referenceFailure {
            try SpaceTemplateChecklistName(validating: "\n")
        } == .invalidChecklistName)
        #expect(Self.referenceFailure {
            try SpaceTemplateChecklistItemText(validating: "\t")
        } == .invalidChecklistItemText)

        let accountId = try AccountID(validating: "account-space-template-invalid")
        let firstItem = try Self.item(id: "item-first", text: "First", order: 1)
        let secondItem = try Self.item(id: "item-second", text: "Second", order: 2)
        let duplicateItemIdentity = try Self.item(
            id: firstItem.id.rawValue,
            text: "Different",
            order: 3
        )
        #expect(Self.referenceFailure {
            try Self.checklist(
                id: "checklist-duplicate-item-id",
                name: "Duplicate item ID",
                order: 1,
                items: [firstItem, duplicateItemIdentity]
            )
        } == .duplicateChecklistItemIdentity)

        let duplicateItemOrder = try Self.item(
            id: "item-duplicate-order",
            text: "Different",
            order: firstItem.presentationOrder
        )
        #expect(Self.referenceFailure {
            try Self.checklist(
                id: "checklist-duplicate-item-order",
                name: "Duplicate item order",
                order: 1,
                items: [firstItem, duplicateItemOrder]
            )
        } == .duplicateChecklistItemPresentationOrder)

        let firstChecklist = try Self.checklist(
            id: "checklist-first",
            name: "First checklist",
            order: 1,
            items: [firstItem, secondItem]
        )
        let emptyChecklist = try Self.checklist(
            id: "checklist-empty",
            name: "Empty checklist",
            order: 2,
            items: []
        )
        #expect(emptyChecklist.items.isEmpty)
        let duplicateChecklistIdentity = try Self.checklist(
            id: firstChecklist.id.rawValue,
            name: "Different checklist",
            order: 3,
            items: []
        )
        #expect(Self.referenceFailure {
            try Self.template(
                id: "template-duplicate-checklist-id",
                accountId: accountId,
                name: "Duplicate checklist ID",
                checklists: [firstChecklist, duplicateChecklistIdentity],
                order: 1,
                revision: 1
            )
        } == .duplicateChecklistIdentity)

        let duplicateChecklistOrder = try Self.checklist(
            id: "checklist-duplicate-order",
            name: "Different checklist",
            order: firstChecklist.presentationOrder,
            items: []
        )
        #expect(Self.referenceFailure {
            try Self.template(
                id: "template-duplicate-checklist-order",
                accountId: accountId,
                name: "Duplicate checklist order",
                checklists: [firstChecklist, duplicateChecklistOrder],
                order: 1,
                revision: 1
            )
        } == .duplicateChecklistPresentationOrder)

        let firstTemplate = try Self.template(
            id: "template-first",
            accountId: accountId,
            name: "First template",
            checklists: [firstChecklist, emptyChecklist],
            order: 1,
            revision: 1
        )
        let otherAccount = try AccountID(validating: "account-other")
        let crossAccount = try Self.template(
            id: "template-cross-account",
            accountId: otherAccount,
            name: "Cross account",
            order: 2,
            revision: 1
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(accountId: accountId, rows: [crossAccount])
        } == .accountScopeMismatch)

        let duplicateTemplateIdentity = try Self.template(
            id: firstTemplate.id.rawValue,
            accountId: accountId,
            name: "Different template",
            order: 2,
            revision: 1
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: accountId,
                rows: [firstTemplate, duplicateTemplateIdentity]
            )
        } == .duplicateTemplateIdentity)

        let duplicateTemplateOrder = try Self.template(
            id: "template-duplicate-order",
            accountId: accountId,
            name: "Different template",
            order: firstTemplate.presentationOrder,
            revision: 1
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: accountId,
                rows: [firstTemplate, duplicateTemplateOrder]
            )
        } == .duplicateTemplatePresentationOrder)

        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: accountId,
                rows: [firstTemplate],
                visibleCount: 2
            )
        } == .visibleCountMismatch)
        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: accountId,
                rows: [firstTemplate],
                asOf: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidSnapshotAsOf)

        #expect(Self.listFailure {
            try ListLocalSnapshot<SpaceTemplateSnapshot>(
                queryFingerprint: Self.fingerprint("e"),
                rows: [],
                visibleRowCountBeforeFiltering: 0,
                isCompleteForQuery: true,
                quality: .partial,
                localDataVersion: LocalDataVersion(
                    validating: "space-template-invalid-local"
                ),
                asOf: Self.t3
            )
        } == .incompleteAuthoritativeEmpty)

        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                SpaceTemplateName.self,
                from: Data("123".utf8)
            )
        } == .invalidEncodedTemplateName)
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                SpaceTemplateChecklistName.self,
                from: Data("123".utf8)
            )
        } == .invalidEncodedChecklistName)
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                SpaceTemplateChecklistItemText.self,
                from: Data("123".utf8)
            )
        } == .invalidEncodedChecklistItemText)

        let itemBytes = try OperationContractCodec.encode(firstItem)
        let negativeItemOrder = Data(
            String(decoding: itemBytes, as: UTF8.self)
                .replacingOccurrences(of: #""presentationOrder":1"#, with: #""presentationOrder":-1"#)
                .utf8
        )
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                SpaceTemplateChecklistItemDefinition.self,
                from: negativeItemOrder
            )
        } == .invalidEncodedChecklistItem)

        let checklistBytes = try OperationContractCodec.encode(firstChecklist)
        let missingChecklistItems = Data(
            String(decoding: checklistBytes, as: UTF8.self)
                .replacingOccurrences(of: #""items":"#, with: #""missingItems":"#)
                .utf8
        )
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                SpaceTemplateChecklistDefinition.self,
                from: missingChecklistItems
            )
        } == .invalidEncodedChecklist)

        let templateBytes = try OperationContractCodec.encode(firstTemplate)
        let unknownLifecycle = Data(
            String(decoding: templateBytes, as: UTF8.self)
                .replacingOccurrences(of: #""lifecycle":"active""#, with: #""lifecycle":"unknown""#)
                .utf8
        )
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                SpaceTemplateSnapshot.self,
                from: unknownLifecycle
            )
        } == .invalidEncodedTemplate)
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                SpaceTemplateReferenceSnapshot.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedSnapshot)

        let diagnostics: [(SpaceTemplateReferenceFailure, String)] = [
            (.invalidTemplateName, "space_template_name_invalid"),
            (.invalidChecklistName, "space_template_checklist_name_invalid"),
            (.invalidChecklistItemText, "space_template_checklist_item_text_invalid"),
            (.accountScopeMismatch, "space_template_account_scope_mismatch"),
            (.duplicateTemplateIdentity, "space_template_identity_duplicate"),
            (.duplicateTemplatePresentationOrder, "space_template_order_duplicate"),
            (.duplicateChecklistIdentity, "space_template_checklist_identity_duplicate"),
            (.duplicateChecklistPresentationOrder, "space_template_checklist_order_duplicate"),
            (
                .duplicateChecklistItemIdentity,
                "space_template_checklist_item_identity_duplicate"
            ),
            (
                .duplicateChecklistItemPresentationOrder,
                "space_template_checklist_item_order_duplicate"
            ),
            (.visibleCountMismatch, "space_template_visible_count_mismatch"),
            (.invalidSnapshotAsOf, "space_template_as_of_invalid"),
            (.localReadFailed, "space_template_local_read_failed"),
            (.invalidEncodedTemplateName, "space_template_name_encoding_invalid"),
            (
                .invalidEncodedChecklistName,
                "space_template_checklist_name_encoding_invalid"
            ),
            (
                .invalidEncodedChecklistItemText,
                "space_template_checklist_item_text_encoding_invalid"
            ),
            (
                .invalidEncodedChecklistItem,
                "space_template_checklist_item_encoding_invalid"
            ),
            (.invalidEncodedChecklist, "space_template_checklist_encoding_invalid"),
            (.invalidEncodedTemplate, "space_template_encoding_invalid"),
            (.invalidEncodedSnapshot, "space_template_snapshot_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The query port streams only its exact Account snapshot")
    func queryPortIsAccountExactAndFailureSafe() async throws {
        let fixture = try Self.fixture()
        let port = FixtureSpaceTemplatePort(snapshot: fixture.snapshot)
        var received: [SpaceTemplateReferenceSnapshot] = []
        for try await snapshot in port.watchSpaceTemplates(accountId: fixture.accountId) {
            received.append(snapshot)
        }
        #expect(received == [fixture.snapshot])

        let otherAccount = try AccountID(validating: "account-other")
        var mismatchedRows: [SpaceTemplateReferenceSnapshot] = []
        var mismatchFailure: SpaceTemplateReferenceFailure?
        do {
            for try await snapshot in port.watchSpaceTemplates(accountId: otherAccount) {
                mismatchedRows.append(snapshot)
            }
        } catch let failure as SpaceTemplateReferenceFailure {
            mismatchFailure = failure
        }
        #expect(mismatchedRows.isEmpty)
        #expect(mismatchFailure == .accountScopeMismatch)

        let failing = FailingSpaceTemplatePort()
        var falseSnapshots: [SpaceTemplateReferenceSnapshot] = []
        var localFailure: SpaceTemplateReferenceFailure?
        do {
            for try await snapshot in failing.watchSpaceTemplates(
                accountId: fixture.accountId
            ) {
                falseSnapshots.append(snapshot)
            }
        } catch let failure as SpaceTemplateReferenceFailure {
            localFailure = failure
        }
        #expect(falseSnapshots.isEmpty)
        #expect(localFailure == .localReadFailed)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_910_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_910_001)
    private static let t2 = Date(timeIntervalSince1970: 1_800_910_002)
    private static let t3 = Date(timeIntervalSince1970: 1_800_910_003)

    private struct Fixture {
        let accountId: AccountID
        let snapshot: SpaceTemplateReferenceSnapshot
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let ready: SpaceTemplateReferenceSnapshot
        let partial: SpaceTemplateReferenceSnapshot
        let stale: SpaceTemplateReferenceSnapshot
        let authoritativeEmpty: SpaceTemplateReferenceSnapshot
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-space-templates")
        let installation = try checklist(
            id: "checklist-installation",
            name: "Installation tasks",
            order: 2,
            items: [
                try item(id: "item-hang", text: "Hang  artwork", order: 2),
                try item(id: "item-unpack", text: "Unpack boxes", order: 1)
            ]
        )
        let arrival = try checklist(
            id: "checklist-arrival",
            name: "Arrival",
            order: 1,
            items: []
        )
        let rows = [
            try template(
                id: "template-archived",
                accountId: accountId,
                name: "Old template",
                lifecycle: .archived,
                order: 3,
                revision: 13
            ),
            try template(
                id: "template-storage",
                accountId: accountId,
                name: "Storage",
                order: 2,
                revision: 12
            ),
            try template(
                id: "template-installation",
                accountId: accountId,
                name: "Installation Day",
                notes: "Protect finished surfaces.",
                checklists: [installation, arrival],
                order: 1,
                revision: 11
            )
        ]
        return Fixture(
            accountId: accountId,
            snapshot: try snapshot(accountId: accountId, rows: rows)
        )
    }

    private static func item(
        id: String,
        text: String,
        order: UInt32
    ) throws -> SpaceTemplateChecklistItemDefinition {
        SpaceTemplateChecklistItemDefinition(
            id: try SpaceTemplateChecklistItemID(validating: id),
            text: try SpaceTemplateChecklistItemText(validating: text),
            presentationOrder: order
        )
    }

    private static func checklist(
        id: String,
        name: String,
        order: UInt32,
        items: [SpaceTemplateChecklistItemDefinition]
    ) throws -> SpaceTemplateChecklistDefinition {
        try SpaceTemplateChecklistDefinition(
            id: SpaceTemplateChecklistID(validating: id),
            name: SpaceTemplateChecklistName(validating: name),
            presentationOrder: order,
            items: items
        )
    }

    private static func template(
        id: String,
        accountId: AccountID,
        name: String,
        notes: String? = nil,
        checklists: [SpaceTemplateChecklistDefinition] = [],
        lifecycle: DirectoryLifecycleState = .active,
        order: UInt32,
        revision: UInt64
    ) throws -> SpaceTemplateSnapshot {
        try SpaceTemplateSnapshot(
            id: SpaceTemplateID(validating: id),
            accountId: accountId,
            name: SpaceTemplateName(validating: name),
            notes: notes,
            checklists: checklists,
            lifecycle: lifecycle,
            presentationOrder: order,
            revision: revision
        )
    }

    private static func snapshot(
        accountId: AccountID,
        rows: [SpaceTemplateSnapshot],
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        isComplete: Bool = true,
        fingerprintCharacter: Character = "a",
        version: String = "space-template-ready",
        asOf: Date = t0
    ) throws -> SpaceTemplateReferenceSnapshot {
        try SpaceTemplateReferenceSnapshot(
            accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: fingerprint(fingerprintCharacter),
                rows: rows,
                visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
                isCompleteForQuery: isComplete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: asOf
            )
        )
    }

    private static func fingerprint(_ character: Character) throws -> ListQueryFingerprint {
        try ListQueryFingerprint(validating: String(repeating: character, count: 64))
    }

    private static func referenceFailure<T>(
        _ operation: () throws -> T
    ) -> SpaceTemplateReferenceFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as SpaceTemplateReferenceFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func listFailure<T>(
        _ operation: () throws -> T
    ) -> ListQueryContractFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ListQueryContractFailure {
            return failure
        } catch {
            return nil
        }
    }
}

private struct FixtureSpaceTemplatePort: SpaceTemplateQuerying {
    let snapshot: SpaceTemplateReferenceSnapshot

    func watchSpaceTemplates(
        accountId: AccountID
    ) -> AsyncThrowingStream<SpaceTemplateReferenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            guard accountId == snapshot.accountId else {
                continuation.finish(
                    throwing: SpaceTemplateReferenceFailure.accountScopeMismatch
                )
                return
            }
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}

private struct FailingSpaceTemplatePort: SpaceTemplateQuerying {
    func watchSpaceTemplates(
        accountId: AccountID
    ) -> AsyncThrowingStream<SpaceTemplateReferenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: SpaceTemplateReferenceFailure.localReadFailed
            )
        }
    }
}
