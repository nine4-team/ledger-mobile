import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space Checklist Editing Presentation Contracts")
struct SpaceChecklistEditingPresentationTests {
    @Test("Only exact ready-complete current or retryable ready-complete cached evidence is editable")
    func exactAdmissionMatrix() throws {
        let project = try Self.row()
        let inventory = try Self.row(
            scope: .businessInventory,
            lifecycle: .archived
        )
        let current = try Self.presentation(.snapshot(Self.local([project])))
        let archivedInventory = try Self.presentation(.snapshot(Self.local([inventory])))
        let stale = try Self.presentation(.failed(
            failure: .retryable,
            cached: Self.local([project])
        ))

        #expect(current.state == .editableCurrent)
        #expect(archivedInventory.state == .editableCurrent)
        #expect(stale.state == .editableStale)
        #expect(try current.prepare().draft.collection() == project.checklists)
        #expect(try archivedInventory.prepare().draft.collection() == inventory.checklists)
        #expect(try stale.prepare().draft.collection() == project.checklists)

        let noneditable: [(SpaceCoreDetailsUpdateState, SpaceChecklistEditingPresentationState)] = try [
            (.waiting(.notRequested), .waiting(.notRequested)),
            (.waiting(.loading), .waiting(.loading)),
            (.waiting(.blocked), .waiting(.blocked)),
            (.snapshot(Self.local([project], complete: false)), .incomplete(.ready)),
            (.snapshot(Self.local([project], quality: .partial, complete: false)), .incomplete(.partial)),
            (.snapshot(Self.local([], quality: .partial, complete: false)), .incomplete(.partial)),
            (.snapshot(Self.local([project], quality: .stale, complete: false)), .incomplete(.stale)),
            (.snapshot(Self.local([], quality: .stale, complete: false)), .incomplete(.stale)),
            (.snapshot(Self.local([])), .authoritativeAbsence),
            (.snapshot(Self.local([], complete: false)), .incomplete(.ready)),
            (.failed(failure: .retryable, cached: nil), .incomplete(.loading)),
            (.failed(failure: .retryable, cached: Self.local([])), .incomplete(.ready)),
            (.failed(failure: .retryable, cached: Self.local([], complete: false)), .incomplete(.ready)),
            (.failed(failure: .retryable, cached: Self.local([project], complete: false)), .incomplete(.ready)),
            (.failed(
                failure: .retryable,
                cached: Self.local([project], quality: .partial, complete: false)
            ), .incomplete(.partial)),
            (.failed(
                failure: .retryable,
                cached: Self.local([], quality: .partial, complete: false)
            ), .incomplete(.partial)),
            (.failed(
                failure: .retryable,
                cached: Self.local([project], quality: .stale, complete: false)
            ), .incomplete(.stale)),
            (.failed(
                failure: .retryable,
                cached: Self.local([], quality: .stale, complete: false)
            ), .incomplete(.stale)),
            (.failed(failure: .unavailable, cached: nil), .unavailable),
            (.failed(failure: .requiredUpdate, cached: Self.local([project])), .requiredUpdate)
        ]
        for (source, expected) in noneditable {
            let projected = try Self.presentation(source)
            #expect(projected.state == expected)
            #expect(Self.failure { try projected.prepare() } == .sourceNotEditable)
        }
    }

    private enum FixtureUpdateState {
        case current
        case retryable
        case partial
        case stale
        case readyIncomplete
        case retryablePartial
        case unavailable
        case requiredUpdate
        case absence
    }

    private enum RestartValue {
        case presentation(SpaceChecklistEditingPresentation)
        case preparation(SpaceChecklistEditingPreparation)
        case draft(SpaceChecklistEditingDraft)

        func bytes() throws -> Data {
            switch self {
            case .presentation(let value): try OperationContractCodec.encode(value)
            case .preparation(let value): try OperationContractCodec.encode(value)
            case .draft(let value): try OperationContractCodec.encode(value)
            }
        }

        func roundTrip(_ bytes: Data) throws -> Data {
            switch self {
            case .presentation:
                try OperationContractCodec.encode(
                    OperationContractCodec.decode(
                        SpaceChecklistEditingPresentation.self,
                        from: bytes
                    )
                )
            case .preparation:
                try OperationContractCodec.encode(
                    OperationContractCodec.decode(
                        SpaceChecklistEditingPreparation.self,
                        from: bytes
                    )
                )
            case .draft:
                try OperationContractCodec.encode(
                    OperationContractCodec.decode(
                        SpaceChecklistEditingDraft.self,
                        from: bytes
                    )
                )
            }
        }
    }

    private enum Path {
        case key(String)
        case index(Int)
    }

    private static let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    private static let t1 = Date(timeIntervalSinceReferenceDate: 2_000)
    private static let t2 = Date(timeIntervalSinceReferenceDate: 3_000)
    private static let t3 = Date(timeIntervalSinceReferenceDate: 4_000)
    private static let t4 = Date(timeIntervalSinceReferenceDate: 5_000)

    private static func request(
        account: String = "account-one",
        space: String = "space-one"
    ) throws -> SpaceCoreDetailsRequest {
        try SpaceCoreDetailsRequest(
            accountId: AccountID(validating: account),
            spaceId: SpaceID(validating: space)
        )
    }

    private static func item(
        _ id: String,
        text: String,
        checked: Bool,
        order: UInt32
    ) throws -> SpaceChecklistItemState {
        SpaceChecklistItemState(
            id: try SpaceChecklistItemID(validating: id),
            text: try SpaceChecklistItemText(validating: text),
            isChecked: checked,
            presentationOrder: order
        )
    }

    private static func checklist(
        _ id: String,
        name: String,
        order: UInt32,
        items: [SpaceChecklistItemState]
    ) throws -> SpaceChecklistState {
        try SpaceChecklistState(
            id: SpaceChecklistID(validating: id),
            name: SpaceChecklistName(validating: name),
            presentationOrder: order,
            items: items
        )
    }

    private static func row(
        account: String = "account-one",
        space: String = "space-one",
        scope: SpaceCreationScope? = nil,
        name: String = "Living Room",
        notes: String? = "Current notes",
        lifecycle: DirectoryLifecycleState = .active,
        revision: UInt64 = 7,
        createdAt: Date = t0,
        updatedAt: Date = t2,
        checklistName: String = "Checklist A",
        checklistId: String = "checklist-a",
        itemText: String = "First",
        itemId: String = "item-a",
        itemChecked: Bool = false,
        checklistOrder: UInt32 = 5,
        itemOrder: UInt32 = 10,
        empty: Bool = false
    ) throws -> SpaceCoreDetailsSnapshot {
        let checklists: [SpaceChecklistState]
        if empty {
            checklists = []
        } else {
            checklists = try [
                checklist(
                    checklistId,
                    name: checklistName,
                    order: checklistOrder,
                    items: [
                        item(
                            itemId,
                            text: itemText,
                            checked: itemChecked,
                            order: itemOrder
                        ),
                        item("item-b", text: "Second", checked: true, order: 30)
                    ]
                ),
                checklist(
                    "checklist-secondary",
                    name: "Secondary",
                    order: checklistOrder == .max ? .max - 1 : 20,
                    items: [item("item-foreign", text: "Foreign", checked: false, order: 7)]
                )
            ]
        }
        return try SpaceCoreDetailsSnapshot(
            id: SpaceID(validating: space),
            accountId: AccountID(validating: account),
            scope: try scope ?? .project(ProjectID(validating: "project-one")),
            displayName: SpaceDisplayName(validating: name),
            notes: SpaceCreationNotes(notes),
            lifecycle: lifecycle,
            revision: revision,
            createdAt: createdAt,
            updatedAt: updatedAt,
            checklists: SpaceChecklistCollection(checklists: checklists)
        )
    }

    private static func local(
        _ rows: [SpaceCoreDetailsSnapshot],
        request: SpaceCoreDetailsRequest? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "version-one",
        asOf: Date = t2
    ) throws -> SpaceCoreDetailsLocalSnapshot {
        let request = try request ?? Self.request(
            account: rows.first?.accountId.rawValue ?? "account-one",
            space: rows.first?.id.rawValue ?? "space-one"
        )
        return try SpaceCoreDetailsLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: asOf
        )
    }

    private static func presentation(
        _ state: SpaceCoreDetailsUpdateState,
        request: SpaceCoreDetailsRequest? = nil
    ) throws -> SpaceChecklistEditingPresentation {
        let request = try request ?? Self.request()
        return try SpaceChecklistEditingPresentation(
            projecting: SpaceCoreDetailsUpdate(request: request, state: state)
        )
    }

    private static func update(
        state: FixtureUpdateState = .current,
        account: String = "account-one",
        space: String = "space-one",
        scope: SpaceCreationScope? = nil,
        lifecycle: DirectoryLifecycleState = .active,
        revision: UInt64 = 7,
        version: String = "version-one",
        asOf: Date = t2,
        name: String = "Living Room",
        notes: String? = "Current notes",
        createdAt: Date = t0,
        updatedAt: Date = t2,
        checklistName: String = "Checklist A",
        checklistId: String = "checklist-a",
        itemText: String = "First",
        itemId: String = "item-a",
        itemChecked: Bool = false,
        checklistOrder: UInt32 = 5,
        itemOrder: UInt32 = 10,
        empty: Bool = false
    ) throws -> SpaceCoreDetailsUpdate {
        let request = try Self.request(account: account, space: space)
        let row = try Self.row(
            account: account,
            space: space,
            scope: scope,
            name: name,
            notes: notes,
            lifecycle: lifecycle,
            revision: revision,
            createdAt: createdAt,
            updatedAt: updatedAt,
            checklistName: checklistName,
            checklistId: checklistId,
            itemText: itemText,
            itemId: itemId,
            itemChecked: itemChecked,
            checklistOrder: checklistOrder,
            itemOrder: itemOrder,
            empty: empty
        )
        let source: SpaceCoreDetailsUpdateState
        switch state {
        case .current:
            source = .snapshot(try local([row], request: request, version: version, asOf: asOf))
        case .retryable:
            source = .failed(
                failure: .retryable,
                cached: try local([row], request: request, version: version, asOf: asOf)
            )
        case .partial:
            source = .snapshot(try local(
                [row], request: request, quality: .partial, complete: false,
                version: version, asOf: asOf
            ))
        case .stale:
            source = .snapshot(try local(
                [row], request: request, quality: .stale, complete: false,
                version: version, asOf: asOf
            ))
        case .readyIncomplete:
            source = .snapshot(try local(
                [row], request: request, complete: false, version: version, asOf: asOf
            ))
        case .retryablePartial:
            source = .failed(
                failure: .retryable,
                cached: try local(
                    [row], request: request, quality: .partial, complete: false,
                    version: version, asOf: asOf
                )
            )
        case .unavailable:
            source = .failed(failure: .unavailable, cached: nil)
        case .requiredUpdate:
            source = .failed(failure: .requiredUpdate, cached: try local(
                [row], request: request, version: version, asOf: asOf
            ))
        case .absence:
            source = .snapshot(try local(
                [], request: request, version: version, asOf: asOf
            ))
        }
        return try SpaceCoreDetailsUpdate(request: request, state: source)
    }

    private static func preparation(
        checklistOrder: UInt32 = 5,
        itemOrder: UInt32 = 10
    ) throws -> SpaceChecklistEditingPreparation {
        try SpaceChecklistEditingPresentation(
            projecting: update(checklistOrder: checklistOrder, itemOrder: itemOrder)
        ).prepare()
    }

    private static func emptyPreparation() throws -> SpaceChecklistEditingPreparation {
        let request = try Self.request()
        let row = try Self.row(empty: true)
        let update = try SpaceCoreDetailsUpdate(
            request: request,
            state: .snapshot(local([row], request: request))
        )
        return try SpaceChecklistEditingPresentation(projecting: update).prepare()
    }

    private static func command(
        _ draft: SpaceChecklistEditingDraft,
        validating update: SpaceCoreDetailsUpdate
    ) throws -> ReviseSpaceChecklistsCommand {
        try draft.command(
            validating: update,
            operationId: OperationID(validating: "operation-one"),
            actorPrincipalId: PrincipalID(validating: "actor-one"),
            operationContractVersion: OperationContractVersion(validating: "space-checklist-v1"),
            capturedAt: t3
        )
    }

    private static func failure<Value>(
        _ body: () throws -> Value
    ) -> SpaceChecklistEditingFailure? {
        do { _ = try body(); return nil }
        catch let failure as SpaceChecklistEditingFailure { return failure }
        catch { return nil }
    }

    private static func revisionFailure<Value>(
        _ body: () throws -> Value
    ) -> SpaceChecklistRevisionFailure? {
        do { _ = try body(); return nil }
        catch let failure as SpaceChecklistRevisionFailure { return failure }
        catch { return nil }
    }

    private static func decodeFailure<Value: Decodable>(
        _ type: Value.Type,
        _ bytes: Data
    ) -> SpaceChecklistEditingFailure? {
        do { _ = try OperationContractCodec.decode(type, from: bytes); return nil }
        catch let failure as SpaceChecklistEditingFailure { return failure }
        catch { return nil }
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { character in
            character.isNumber || ("a"..."f").contains(String(character))
        }
    }

    private static func mutate(
        _ data: Data,
        path: [Path],
        value: Any
    ) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data)
        object = try replacing(object, path: ArraySlice(path), value: value)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func replacing(
        _ object: Any,
        path: ArraySlice<Path>,
        value: Any
    ) throws -> Any {
        guard let step = path.first else { return value }
        let remainder = path.dropFirst()
        switch step {
        case .key(let key):
            var dictionary = object as! [String: Any]
            dictionary[key] = try replacing(dictionary[key]!, path: remainder, value: value)
            return dictionary
        case .index(let index):
            var array = object as! [Any]
            array[index] = try replacing(array[index], path: remainder, value: value)
            return array
        }
    }

    private static func addExtraKey(_ data: Data) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["unexpected"] = true
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func addExtraKey(_ data: Data, at path: [Path]) throws -> Data {
        try transform(data, path: path) {
            var object = $0 as! [String: Any]
            object["unexpected"] = true
            return object
        }
    }

    private static func removeKey(_ data: Data, key: String) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func removeKey(
        _ data: Data,
        at path: [Path],
        key: String
    ) throws -> Data {
        try transform(data, path: path) {
            var object = $0 as! [String: Any]
            object.removeValue(forKey: key)
            return object
        }
    }

    private static func transform(
        _ data: Data,
        path: [Path],
        body: (Any) throws -> Any
    ) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data)
        object = try transforming(object, path: ArraySlice(path), body: body)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func transforming(
        _ object: Any,
        path: ArraySlice<Path>,
        body: (Any) throws -> Any
    ) throws -> Any {
        guard let step = path.first else { return try body(object) }
        let remainder = path.dropFirst()
        switch step {
        case .key(let key):
            var dictionary = object as! [String: Any]
            dictionary[key] = try transforming(dictionary[key]!, path: remainder, body: body)
            return dictionary
        case .index(let index):
            var array = object as! [Any]
            array[index] = try transforming(array[index], path: remainder, body: body)
            return array
        }
    }

    private static func replacingNumber(
        _ data: Data,
        after marker: String,
        with replacement: String
    ) throws -> Data {
        var text = String(decoding: data, as: UTF8.self)
        guard let markerRange = text.range(of: marker) else { throw MutationFailure() }
        let valueStart = markerRange.upperBound
        var valueEnd = valueStart
        while valueEnd < text.endIndex, ![",", "}"].contains(text[valueEnd]) {
            valueEnd = text.index(after: valueEnd)
        }
        text.replaceSubrange(valueStart..<valueEnd, with: replacement)
        return Data(text.utf8)
    }

    private struct MutationFailure: Error {}

    @Test("Raw stable-identity edits preserve blank intermediate text and validate only on submission")
    func rawEditingAndIdentity() throws {
        let preparation = try Self.preparation()
        let firstChecklist = try SpaceChecklistID(validating: "checklist-a")
        let secondChecklist = try SpaceChecklistID(validating: "checklist-b")
        let firstItem = try SpaceChecklistItemID(validating: "item-a")
        let sameAcrossLists = try SpaceChecklistItemID(validating: "shared-item")

        var draft = preparation.draft
        draft = try draft.renamingChecklist(id: firstChecklist, name: "   ")
        draft = try draft.editingItemText(
            checklistId: firstChecklist,
            itemId: firstItem,
            text: "\n \t"
        )
        draft = try draft.appendingChecklist(id: secondChecklist, name: "   ")
        draft = try draft.appendingItem(
            checklistId: firstChecklist,
            id: sameAcrossLists,
            text: "  duplicate text  "
        )
        draft = try draft.appendingItem(
            checklistId: secondChecklist,
            id: sameAcrossLists,
            text: "duplicate text"
        )
        #expect(draft.checklists[0].name == "   ")
        #expect(draft.checklists[0].items[0].text == "\n \t")
        #expect(draft.checklists.first(where: { $0.id == secondChecklist })?.items[0].id == sameAcrossLists)
        #expect(Self.revisionFailure { try draft.collection() } == .invalidChecklistName)

        draft = try draft.renamingChecklist(id: firstChecklist, name: "  Punch List  ")
        draft = try draft.renamingChecklist(id: secondChecklist, name: "Punch List")
        draft = try draft.editingItemText(
            checklistId: firstChecklist,
            itemId: firstItem,
            text: "  Install   light  "
        )
        let collection = try draft.collection()
        #expect(collection.checklists.filter { $0.name.rawValue == "Punch List" }.count == 2)
        #expect(collection.checklists[0].items[0].text.rawValue == "Install   light")
        #expect(collection.checklists[0].items.last?.text.rawValue == "duplicate text")

        let longName = "MiXeD  Case " + String(repeating: "N", count: 8_192)
        let longText = "KeEp   Interior " + String(repeating: "T", count: 8_192)
        let validZeroItemChecklist = try preparation.draft
            .appendingChecklist(id: secondChecklist, name: "Zero Items")
        #expect(try validZeroItemChecklist.collection().checklists.last?.items.isEmpty == true)
        let unboundedText = try validZeroItemChecklist
            .renamingChecklist(id: secondChecklist, name: "  \(longName)  ")
            .appendingItem(
                checklistId: secondChecklist,
                id: sameAcrossLists,
                text: "  \(longText)  "
            )
        let unboundedCollection = try unboundedText.collection()
        #expect(unboundedCollection.checklists.last?.name.rawValue == longName)
        #expect(unboundedCollection.checklists.last?.items[0].text.rawValue == longText)
        #expect(unboundedCollection.checklists.count == preparation.draft.checklists.count + 1)

        let blankItem = try preparation.draft.editingItemText(
            checklistId: firstChecklist,
            itemId: firstItem,
            text: " \n "
        )
        #expect(Self.revisionFailure { try blankItem.collection() } == .invalidChecklistItemText)

        let removedItem = try draft.removingItem(
            checklistId: firstChecklist,
            itemId: sameAcrossLists
        )
        #expect(removedItem.checklists[0].items.count == 2)
        #expect(removedItem.checklists.first(where: { $0.id == secondChecklist })?.items.count == 1)
        #expect(try removedItem.removingChecklist(id: secondChecklist).checklists.count == 2)
        #expect(try draft.clearingChecklists().collection().checklists.isEmpty)

        #expect(Self.failure {
            try draft.appendingChecklist(id: firstChecklist, name: "Duplicate")
        } == .checklistIdentityCollision)
        #expect(Self.failure {
            try draft.appendingItem(
                checklistId: firstChecklist,
                id: firstItem,
                text: "Duplicate"
            )
        } == .itemIdentityCollision)
        #expect(Self.failure {
            try draft.renamingChecklist(
                id: SpaceChecklistID(validating: "unknown"),
                name: "Missing"
            )
        } == .checklistNotFound)
        #expect(Self.failure {
            try draft.editingItemText(
                checklistId: firstChecklist,
                itemId: SpaceChecklistItemID(validating: "unknown"),
                text: "Missing"
            )
        } == .itemNotFound)
    }

    @Test("Item reorder is an exact owning-list permutation and order tokens are deterministic")
    func orderTokensAndPermutation() throws {
        let checklistID = try SpaceChecklistID(validating: "checklist-a")
        let first = try SpaceChecklistItemID(validating: "item-a")
        let second = try SpaceChecklistItemID(validating: "item-b")
        let foreign = try SpaceChecklistItemID(validating: "item-foreign")
        let draft = try Self.preparation().draft
        let originalChecklistIDs = draft.checklists.map(\.id)
        let originalChecklistTokens = draft.checklists.map(\.presentationOrder)
        let originalItemIDs = draft.checklists.map { $0.items.map(\.id) }
        let originalItemTokens = draft.checklists.map { $0.items.map(\.presentationOrder) }

        let renamed = try draft.renamingChecklist(id: checklistID, name: "Renamed")
        #expect(renamed.checklists.map(\.id) == originalChecklistIDs)
        #expect(renamed.checklists.map(\.presentationOrder) == originalChecklistTokens)
        #expect(renamed.checklists[0].items == draft.checklists[0].items)
        #expect(renamed.checklists[1] == draft.checklists[1])
        let textEdited = try renamed.editingItemText(
            checklistId: checklistID,
            itemId: first,
            text: "Edited"
        )
        #expect(textEdited.checklists.map { $0.items.map(\.id) } == originalItemIDs)
        #expect(textEdited.checklists.map { $0.items.map(\.presentationOrder) } == originalItemTokens)
        #expect(textEdited.checklists[0].id == draft.checklists[0].id)
        #expect(textEdited.checklists[0].name == "Renamed")
        #expect(textEdited.checklists[0].presentationOrder == draft.checklists[0].presentationOrder)
        #expect(textEdited.checklists[0].items[0].id == first)
        #expect(textEdited.checklists[0].items[0].isChecked == draft.checklists[0].items[0].isChecked)
        #expect(textEdited.checklists[0].items[1] == draft.checklists[0].items[1])
        let checkEdited = try textEdited.settingItemChecked(
            checklistId: checklistID,
            itemId: first,
            isChecked: true
        )
        #expect(checkEdited.checklists[0].items[0].presentationOrder == 10)
        #expect(checkEdited.checklists[0].items[0].id == first)
        #expect(checkEdited.checklists[0].items[0].text == "Edited")
        #expect(checkEdited.checklists[0].items[1] == draft.checklists[0].items[1])
        let itemRemoved = try checkEdited.removingItem(checklistId: checklistID, itemId: first)
        #expect(itemRemoved.checklists[0].items.map(\.presentationOrder) == [30])
        #expect(itemRemoved.checklists[0].items[0].id == second)
        #expect(itemRemoved.checklists[0].id == checklistID)
        #expect(itemRemoved.checklists[0].name == "Renamed")
        #expect(itemRemoved.checklists[0].presentationOrder == draft.checklists[0].presentationOrder)
        #expect(itemRemoved.checklists[1] == draft.checklists[1])
        let checklistRemoved = try itemRemoved.removingChecklist(id: checklistID)
        #expect(checklistRemoved.checklists.count == 1)
        #expect(checklistRemoved.checklists[0] == draft.checklists[1])

        let reordered = try draft.reorderingItems(
            checklistId: checklistID,
            itemIds: [second, first]
        )
        #expect(reordered.checklists[0].items.map(\.id) == [second, first])
        #expect(reordered.checklists[0].items.map(\.presentationOrder) == [10, 30])
        #expect(reordered.checklists[0].items.map(\.text) == ["Second", "First"])
        #expect(reordered.checklists[0].items.map(\.isChecked) == [true, false])
        #expect(reordered.checklists[1] == draft.checklists[1])

        for invalid in [[first], [first, first], [first, foreign], [first, second, foreign]] {
            #expect(Self.failure {
                try draft.reorderingItems(checklistId: checklistID, itemIds: invalid)
            } == .invalidItemPermutation)
            #expect(draft == (try Self.preparation().draft))
        }
        #expect(Self.failure {
            try draft.reorderingItems(
                checklistId: SpaceChecklistID(validating: "unknown"),
                itemIds: []
            )
        } == .checklistNotFound)
        #expect(draft == (try Self.preparation().draft))

        let appended = try draft.appendingItem(
            checklistId: checklistID,
            id: SpaceChecklistItemID(validating: "item-c"),
            text: "Third"
        )
        #expect(appended.checklists[0].items.last?.presentationOrder == 31)
        let emptyAppended = try Self.emptyPreparation().draft
            .appendingChecklist(id: SpaceChecklistID(validating: "new-list"), name: "New")
            .appendingItem(
                checklistId: SpaceChecklistID(validating: "new-list"),
                id: SpaceChecklistItemID(validating: "new-item"),
                text: "New item"
            )
        #expect(emptyAppended.checklists[0].presentationOrder == 0)
        #expect(emptyAppended.checklists[0].items[0].presentationOrder == 0)

        let checklistOverflowDraft = try Self.preparation(checklistOrder: .max).draft
        #expect(Self.failure {
            try checklistOverflowDraft.appendingChecklist(
                id: SpaceChecklistID(validating: "overflow"),
                name: "Overflow"
            )
        } == .checklistOrderOverflow)
        #expect(checklistOverflowDraft == (try Self.preparation(checklistOrder: .max).draft))
        let itemOverflowDraft = try Self.preparation(itemOrder: .max).draft
        #expect(Self.failure {
            try itemOverflowDraft.appendingItem(
                checklistId: checklistID,
                id: SpaceChecklistItemID(validating: "overflow"),
                text: "Overflow"
            )
        } == .itemOrderOverflow)
        #expect(itemOverflowDraft == (try Self.preparation(itemOrder: .max).draft))
    }

    @Test("Unchanged and fully edited drafts derive exactly one complete revision command")
    func completeReplacementCommand() throws {
        let update = try Self.update()
        let preparation = try SpaceChecklistEditingPresentation(projecting: update).prepare()
        let unchanged = try preparation.draft.command(
            validating: update,
            operationId: OperationID(validating: "operation-unchanged"),
            actorPrincipalId: PrincipalID(validating: "actor-one"),
            operationContractVersion: OperationContractVersion(validating: "space-checklist-v1"),
            capturedAt: Self.t3
        )
        let startingCollection = try Self.row().checklists
        #expect(unchanged.draft.collection == startingCollection)
        #expect(unchanged.draft.expectedRevision == ExpectedSpaceRevision(7))
        #expect(unchanged.envelope.operationId.rawValue == "operation-unchanged")
        #expect(unchanged.envelope.preconditions.count == 1)

        let edited = try preparation.draft
            .renamingChecklist(
                id: SpaceChecklistID(validating: "checklist-a"),
                name: "  Final checklist  "
            )
            .settingItemChecked(
                checklistId: SpaceChecklistID(validating: "checklist-a"),
                itemId: SpaceChecklistItemID(validating: "item-a"),
                isChecked: true
            )
            .appendingItem(
                checklistId: SpaceChecklistID(validating: "checklist-a"),
                id: SpaceChecklistItemID(validating: "item-c"),
                text: "  Third item  "
            )
        let command = try edited.command(
            validating: update,
            operationId: OperationID(validating: "operation-edited"),
            actorPrincipalId: PrincipalID(validating: "actor-two"),
            operationContractVersion: OperationContractVersion(validating: "space-checklist-v1"),
            capturedAt: Self.t4
        )
        let expectedCollection = try SpaceChecklistCollection(checklists: [
            Self.checklist(
                "checklist-a",
                name: "Final checklist",
                order: 5,
                items: [
                    Self.item("item-a", text: "First", checked: true, order: 10),
                    Self.item("item-b", text: "Second", checked: true, order: 30),
                    Self.item("item-c", text: "Third item", checked: false, order: 31)
                ]
            ),
            Self.checklist(
                "checklist-secondary",
                name: "Secondary",
                order: 20,
                items: [
                    Self.item("item-foreign", text: "Foreign", checked: false, order: 7)
                ]
            )
        ])
        #expect(command.draft.collection == expectedCollection)
        #expect(command.draft.collection.checklists[0].name.rawValue == "Final checklist")
        #expect(command.draft.collection.checklists[0].items.map(\.text.rawValue) == [
            "First", "Second", "Third item"
        ])
        #expect(command.draft.collection.checklists[0].items.map(\.isChecked) == [true, true, false])
        #expect(command.draft.collection.checklists[0].items.map(\.id.rawValue) == [
            "item-a", "item-b", "item-c"
        ])
        #expect(command.draft.collection.checklists[0].items.map(\.presentationOrder) == [10, 30, 31])
        #expect(command.draft.collection.checklists[1].id.rawValue == "checklist-secondary")
        #expect(command.draft.collection.checklists[1].items.map(\.id.rawValue) == ["item-foreign"])
        #expect(command.draft.accountId.rawValue == "account-one")
        #expect(command.draft.spaceId.rawValue == "space-one")
        #expect(command.draft.actorPrincipalId.rawValue == "actor-two")
        #expect(command.draft.operationContractVersion.rawValue == "space-checklist-v1")
        #expect(command.draft.capturedAt == Self.t4)
        #expect(command.envelope.operationId.rawValue == "operation-edited")
        #expect(command.envelope.accountId == command.draft.accountId)
        #expect(command.envelope.actorPrincipalId == command.draft.actorPrincipalId)
        #expect(command.envelope.contractVersion == command.draft.operationContractVersion)
        #expect(command.envelope.clientCreatedAt == Self.t4)
        #expect(command.envelope.payload.spaceId == command.draft.spaceId)
        #expect(command.envelope.payload.collection == expectedCollection)
        #expect(command.subject.kind == .space)
        #expect(command.subject.id.rawValue == "space-one")
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: 7)
        ])
        #expect(Self.revisionFailure {
            try edited.command(
                validating: update,
                operationId: OperationID(validating: "operation-nonfinite"),
                actorPrincipalId: PrincipalID(validating: "actor-two"),
                operationContractVersion: OperationContractVersion(validating: "space-checklist-v1"),
                capturedAt: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidCapturedAt)
    }

    @Test("Command eligibility tolerates presentation refresh but rejects every semantic conflict")
    func semanticRevalidation() throws {
        let starting = try Self.update()
        let startingPresentation = try SpaceChecklistEditingPresentation(projecting: starting)
        let startingPreparation = try startingPresentation.prepare()
        let draft = startingPreparation.draft
        let refreshedCurrent = try Self.update(
            version: "later-version",
            asOf: Self.t4,
            name: "Refreshed display",
            notes: "Refreshed notes",
            createdAt: Self.t1,
            updatedAt: Self.t4
        )
        let refreshedStale = try Self.update(
            state: .retryable,
            version: "stale-version",
            asOf: Self.t4,
            name: "Refreshed display",
            notes: "Refreshed notes",
            createdAt: Self.t1,
            updatedAt: Self.t4
        )
        let refreshedPresentation = try SpaceChecklistEditingPresentation(projecting: refreshedCurrent)
        let refreshedPreparation = try refreshedPresentation.prepare()
        let refreshedStalePresentation = try SpaceChecklistEditingPresentation(
            projecting: refreshedStale
        )
        let stalePreparation = try refreshedStalePresentation.prepare()
        #expect(startingPresentation.evidenceFingerprint != refreshedPresentation.evidenceFingerprint)
        #expect(refreshedPresentation.evidenceFingerprint != refreshedStalePresentation.evidenceFingerprint)
        #expect(startingPreparation.semanticBaseFingerprint == refreshedPreparation.semanticBaseFingerprint)
        #expect(startingPreparation.semanticBaseFingerprint == stalePreparation.semanticBaseFingerprint)
        let rawEdited = try draft.renamingChecklist(
            id: SpaceChecklistID(validating: "checklist-a"),
            name: "Raw edit"
        )
        #expect(rawEdited.draftFingerprint != draft.draftFingerprint)
        #expect(rawEdited.semanticBaseFingerprint == draft.semanticBaseFingerprint)
        let semanticChange = try SpaceChecklistEditingPresentation(
            projecting: Self.update(revision: 8)
        ).prepare()
        #expect(semanticChange.semanticBaseFingerprint != startingPreparation.semanticBaseFingerprint)
        #expect(semanticChange.draft.semanticBaseFingerprint != draft.semanticBaseFingerprint)
        #expect(semanticChange.draft.draftFingerprint != draft.draftFingerprint)
        for digest in [
            startingPresentation.evidenceFingerprint.sha256,
            startingPreparation.semanticBaseFingerprint.sha256,
            draft.draftFingerprint.sha256
        ] {
            #expect(Self.isCanonicalSHA256(digest))
        }
        #expect(Set([
            startingPresentation.evidenceFingerprint.sha256,
            startingPreparation.semanticBaseFingerprint.sha256,
            draft.draftFingerprint.sha256
        ]).count == 3)
        for invalid in ["short", String(repeating: "A", count: 64), String(repeating: "g", count: 64)] {
            #expect(Self.failure {
                try SpaceChecklistEditingPresentationFingerprint(validating: invalid)
            } == .invalidPresentationFingerprint)
            #expect(Self.failure {
                try SpaceChecklistEditingSemanticBaseFingerprint(validating: invalid)
            } == .invalidSemanticBaseFingerprint)
            #expect(Self.failure {
                try SpaceChecklistEditingDraftFingerprint(validating: invalid)
            } == .invalidDraftFingerprint)
        }
        #expect(try Self.command(draft, validating: refreshedCurrent).draft.expectedRevision.rawValue == 7)
        #expect(try Self.command(draft, validating: refreshedStale).draft.expectedRevision.rawValue == 7)
        let staleDraft = stalePreparation.draft
        #expect(try Self.command(staleDraft, validating: refreshedCurrent).draft.expectedRevision.rawValue == 7)

        let conflicts = try [
            Self.update(account: "other-account"),
            Self.update(space: "other-space"),
            Self.update(scope: .businessInventory),
            Self.update(scope: .project(ProjectID(validating: "other-project"))),
            Self.update(lifecycle: .archived),
            Self.update(revision: 8),
            Self.update(checklistName: "Changed"),
            Self.update(checklistId: "changed-list"),
            Self.update(checklistOrder: 6),
            Self.update(itemText: "Changed"),
            Self.update(itemId: "changed-item"),
            Self.update(itemChecked: true),
            Self.update(itemOrder: 31),
            Self.update(itemOrder: 40),
            Self.update(empty: true)
        ]
        for conflict in conflicts {
            #expect(Self.failure {
                try Self.command(draft, validating: conflict)
            } == .semanticBaseMismatch)
        }
        let unsafe = try [
            Self.update(state: .partial),
            Self.update(state: .stale),
            Self.update(state: .readyIncomplete),
            Self.update(state: .retryablePartial),
            Self.update(state: .unavailable),
            Self.update(state: .requiredUpdate),
            Self.update(state: .absence)
        ]
        for update in unsafe {
            #expect(Self.failure {
                try Self.command(draft, validating: update)
            } == .sourceNotEditable)
        }
    }

    @Test("Canonical restart and independent every-field mutation fail at the owning layer")
    func restartAndEveryFieldTamper() throws {
        let presentation = try SpaceChecklistEditingPresentation(projecting: Self.update())
        let preparation = try presentation.prepare()
        let renamed = try preparation.draft.renamingChecklist(
            id: SpaceChecklistID(validating: "checklist-a"),
            name: " \n "
        )
        let blankDraft = try renamed
            .renamingChecklist(id: SpaceChecklistID(validating: "checklist-a"), name: " \n ")
            .editingItemText(
                checklistId: SpaceChecklistID(validating: "checklist-a"),
                itemId: SpaceChecklistItemID(validating: "item-a"),
                text: "\t"
            )
        let appendedChecklist = try blankDraft.appendingChecklist(
            id: SpaceChecklistID(validating: "restart-list"),
            name: ""
        )
        let appendedItem = try appendedChecklist.appendingItem(
            checklistId: SpaceChecklistID(validating: "restart-list"),
            id: SpaceChecklistItemID(validating: "restart-item"),
            text: " "
        )
        let checked = try appendedItem.settingItemChecked(
            checklistId: SpaceChecklistID(validating: "checklist-a"),
            itemId: SpaceChecklistItemID(validating: "item-a"),
            isChecked: true
        )
        let reordered = try checked.reorderingItems(
            checklistId: SpaceChecklistID(validating: "checklist-a"),
            itemIds: [
                SpaceChecklistItemID(validating: "item-b"),
                SpaceChecklistItemID(validating: "item-a")
            ]
        )
        let removedItem = try reordered.removingItem(
            checklistId: SpaceChecklistID(validating: "restart-list"),
            itemId: SpaceChecklistItemID(validating: "restart-item")
        )
        let removedChecklist = try removedItem.removingChecklist(
            id: SpaceChecklistID(validating: "restart-list")
        )
        let stalePresentation = try SpaceChecklistEditingPresentation(
            projecting: Self.update(state: .retryable)
        )
        let sourcePresentations: [SpaceChecklistEditingPresentation] = try [
            presentation,
            stalePresentation,
            SpaceChecklistEditingPresentation(projecting: Self.update(scope: .businessInventory)),
            SpaceChecklistEditingPresentation(projecting: Self.update(
                state: .retryable,
                scope: .businessInventory
            )),
            Self.presentation(.waiting(.notRequested)),
            Self.presentation(.waiting(.loading)),
            Self.presentation(.waiting(.blocked)),
            Self.presentation(.snapshot(Self.local([Self.row()], complete: false))),
            Self.presentation(.snapshot(Self.local(
                [Self.row()], quality: .partial, complete: false
            ))),
            Self.presentation(.snapshot(Self.local(
                [Self.row()], quality: .stale, complete: false
            ))),
            Self.presentation(.snapshot(Self.local([]))),
            Self.presentation(.failed(failure: .retryable, cached: nil)),
            Self.presentation(.failed(failure: .retryable, cached: Self.local(
                [Self.row()], quality: .partial, complete: false
            ))),
            Self.presentation(.failed(failure: .unavailable, cached: nil)),
            Self.presentation(.failed(failure: .requiredUpdate, cached: nil)),
            Self.presentation(.failed(failure: .requiredUpdate, cached: Self.local([Self.row()])))
        ]
        for sourcePresentation in sourcePresentations {
            let value = RestartValue.presentation(sourcePresentation)
            let bytes = try value.bytes()
            #expect(try value.roundTrip(bytes) == bytes)
        }

        let nilFailurePresentations = try [
            Self.presentation(.failed(failure: .retryable, cached: nil)),
            Self.presentation(.failed(failure: .unavailable, cached: nil)),
            Self.presentation(.failed(failure: .requiredUpdate, cached: nil))
        ]
        for nilFailurePresentation in nilFailurePresentations {
            let bytes = try OperationContractCodec.encode(nilFailurePresentation)
            let explicitNullCache = try Self.transform(
                bytes,
                path: [.key("update"), .key("state"), .key("failed")]
            ) {
                var payload = $0 as! [String: Any]
                payload["cached"] = NSNull()
                return payload
            }
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPresentation.self,
                explicitNullCache
            ) == .invalidEncodedPresentation)
        }

        let inventoryPresentation = try SpaceChecklistEditingPresentation(
            projecting: Self.update(scope: .businessInventory)
        )
        let inventoryBytes = try OperationContractCodec.encode(inventoryPresentation)
        let invalidInventoryScope = try Self.transform(
            inventoryBytes,
            path: [
                .key("update"), .key("state"), .key("snapshot"), .key("_0"),
                .key("local"), .key("rows"), .index(0), .key("scope")
            ]
        ) {
            var scope = $0 as! [String: Any]
            scope["projectId"] = "project-one"
            return scope
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            invalidInventoryScope
        ) == .invalidEncodedPresentation)
        for value in [
            .preparation(preparation),
            .draft(preparation.draft),
            .draft(renamed),
            .draft(blankDraft),
            .draft(appendedChecklist),
            .draft(appendedItem),
            .draft(checked),
            .draft(reordered),
            .draft(removedItem),
            .draft(removedChecklist),
            .draft(try removedChecklist.clearingChecklists())
        ] as [RestartValue] {
            let bytes = try value.bytes()
            #expect(try value.roundTrip(bytes) == bytes)
        }

        let presentationBytes = try OperationContractCodec.encode(presentation)
        let snapshot = [Path.key("update"), .key("state"), .key("snapshot"), .key("_0")]
        let local = snapshot + [.key("local")]
        let row = local + [.key("rows"), .index(0)]
        let checklist = row + [.key("checklists"), .key("checklists"), .index(0)]
        let item = checklist + [.key("items"), .index(0)]
        let presentationMutations: [([Path], Any, SpaceChecklistEditingFailure)] = [
            ([.key("evidenceFingerprint")], String(repeating: "0", count: 64), .presentationFingerprintMismatch),
            ([.key("state"), .key("editableCurrent")], false, .invalidEncodedPresentation),
            ([.key("update"), .key("request"), .key("accountId")], "other-account", .invalidEncodedPresentation),
            ([.key("update"), .key("request"), .key("spaceId")], "other-space", .invalidEncodedPresentation),
            ([.key("update"), .key("request"), .key("queryFingerprint")], String(repeating: "0", count: 64), .invalidEncodedPresentation),
            (snapshot + [.key("request"), .key("accountId")], "other-account", .invalidEncodedPresentation),
            (snapshot + [.key("request"), .key("spaceId")], "other-space", .invalidEncodedPresentation),
            (snapshot + [.key("request"), .key("queryFingerprint")], String(repeating: "0", count: 64), .invalidEncodedPresentation),
            (local + [.key("queryFingerprint")], String(repeating: "0", count: 64), .invalidEncodedPresentation),
            (local + [.key("visibleRowCountBeforeFiltering")], 0, .invalidEncodedPresentation),
            (local + [.key("isCompleteForQuery")], false, .presentationFingerprintMismatch),
            (local + [.key("quality")], "partial", .invalidEncodedPresentation),
            (local + [.key("localDataVersion")], "other-version", .presentationFingerprintMismatch),
            (local + [.key("asOf")], 123_456, .presentationFingerprintMismatch),
            (row + [.key("id")], "other-space", .invalidEncodedPresentation),
            (row + [.key("accountId")], "other-account", .invalidEncodedPresentation),
            (row + [.key("scope"), .key("projectId")], "other-project", .presentationFingerprintMismatch),
            (row + [.key("displayName")], "Changed", .presentationFingerprintMismatch),
            (row + [.key("notes"), .key("value")], "Changed", .presentationFingerprintMismatch),
            (row + [.key("lifecycle")], "archived", .presentationFingerprintMismatch),
            (row + [.key("revision")], 8, .presentationFingerprintMismatch),
            (row + [.key("createdAt")], 123_456, .presentationFingerprintMismatch),
            (row + [.key("updatedAt")], 123_457, .presentationFingerprintMismatch),
            (checklist + [.key("id")], "changed-list", .presentationFingerprintMismatch),
            (checklist + [.key("name")], "Changed", .presentationFingerprintMismatch),
            (checklist + [.key("presentationOrder")], 11, .presentationFingerprintMismatch),
            (item + [.key("id")], "changed-item", .presentationFingerprintMismatch),
            (item + [.key("text")], "Changed", .presentationFingerprintMismatch),
            (item + [.key("isChecked")], true, .presentationFingerprintMismatch),
            (item + [.key("presentationOrder")], 12, .presentationFingerprintMismatch)
        ]
        for (path, value, expected) in presentationMutations {
            let changed = try Self.mutate(presentationBytes, path: path, value: value)
            #expect(Self.decodeFailure(SpaceChecklistEditingPresentation.self, changed) == expected)
        }

        let preparationBytes = try OperationContractCodec.encode(preparation)
        let preparationMutations: [([Path], Any, SpaceChecklistEditingFailure)] = [
            ([.key("presentation"), .key("evidenceFingerprint")], String(repeating: "3", count: 64), .presentationFingerprintMismatch),
            ([.key("semanticBaseFingerprint")], String(repeating: "0", count: 64), .semanticBaseFingerprintMismatch),
            ([.key("draft"), .key("accountId")], "other-account", .draftFingerprintMismatch),
            ([.key("draft"), .key("spaceId")], "other-space", .draftFingerprintMismatch),
            ([.key("draft"), .key("semanticBaseFingerprint")], String(repeating: "1", count: 64), .draftFingerprintMismatch),
            ([.key("draft"), .key("checklists"), .index(0), .key("name")], "Changed", .draftFingerprintMismatch),
            ([.key("draft"), .key("draftFingerprint")], String(repeating: "2", count: 64), .draftFingerprintMismatch)
        ]
        for (path, value, expected) in preparationMutations {
            let changed = try Self.mutate(preparationBytes, path: path, value: value)
            #expect(Self.decodeFailure(SpaceChecklistEditingPreparation.self, changed) == expected)
        }

        let draftBytes = try OperationContractCodec.encode(preparation.draft)
        let draftMutations: [([Path], Any, SpaceChecklistEditingFailure)] = [
            ([.key("accountId")], "other-account", .draftFingerprintMismatch),
            ([.key("spaceId")], "other-space", .draftFingerprintMismatch),
            ([.key("semanticBaseFingerprint")], String(repeating: "0", count: 64), .draftFingerprintMismatch),
            ([.key("draftFingerprint")], String(repeating: "1", count: 64), .draftFingerprintMismatch),
            ([.key("checklists"), .index(0), .key("id")], "changed-list", .draftFingerprintMismatch),
            ([.key("checklists"), .index(0), .key("name")], "Changed", .draftFingerprintMismatch),
            ([.key("checklists"), .index(0), .key("presentationOrder")], 11, .draftFingerprintMismatch),
            ([.key("checklists"), .index(0), .key("items"), .index(0), .key("id")], "changed-item", .draftFingerprintMismatch),
            ([.key("checklists"), .index(0), .key("items"), .index(0), .key("text")], "Changed", .draftFingerprintMismatch),
            ([.key("checklists"), .index(0), .key("items"), .index(0), .key("isChecked")], true, .draftFingerprintMismatch),
            ([.key("checklists"), .index(0), .key("items"), .index(0), .key("presentationOrder")], 12, .draftFingerprintMismatch)
        ]
        for (path, value, expected) in draftMutations {
            let changed = try Self.mutate(draftBytes, path: path, value: value)
            #expect(Self.decodeFailure(SpaceChecklistEditingDraft.self, changed) == expected)
        }

        let malformedFingerprints = [
            "short",
            String(repeating: "A", count: 64),
            String(repeating: "g", count: 64)
        ]
        for malformed in malformedFingerprints {
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPresentation.self,
                try Self.mutate(
                    presentationBytes,
                    path: [.key("evidenceFingerprint")],
                    value: malformed
                )
            ) == .invalidPresentationFingerprint)
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPreparation.self,
                try Self.mutate(
                    preparationBytes,
                    path: [.key("semanticBaseFingerprint")],
                    value: malformed
                )
            ) == .invalidSemanticBaseFingerprint)
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPreparation.self,
                try Self.mutate(
                    preparationBytes,
                    path: [.key("presentation"), .key("evidenceFingerprint")],
                    value: malformed
                )
            ) == .invalidPresentationFingerprint)
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPreparation.self,
                try Self.mutate(
                    preparationBytes,
                    path: [.key("draft"), .key("semanticBaseFingerprint")],
                    value: malformed
                )
            ) == .invalidSemanticBaseFingerprint)
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPreparation.self,
                try Self.mutate(
                    preparationBytes,
                    path: [.key("draft"), .key("draftFingerprint")],
                    value: malformed
                )
            ) == .invalidDraftFingerprint)
            #expect(Self.decodeFailure(
                SpaceChecklistEditingDraft.self,
                try Self.mutate(
                    draftBytes,
                    path: [.key("semanticBaseFingerprint")],
                    value: malformed
                )
            ) == .invalidSemanticBaseFingerprint)
            #expect(Self.decodeFailure(
                SpaceChecklistEditingDraft.self,
                try Self.mutate(
                    draftBytes,
                    path: [.key("draftFingerprint")],
                    value: malformed
                )
            ) == .invalidDraftFingerprint)
        }

        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            try Self.addExtraKey(presentationBytes)
        ) == .invalidEncodedPresentation)
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPreparation.self,
            try Self.addExtraKey(preparationBytes)
        ) == .invalidEncodedPreparation)
        #expect(Self.decodeFailure(
            SpaceChecklistEditingDraft.self,
            try Self.addExtraKey(draftBytes)
        ) == .invalidEncodedDraft)

        let nestedPresentationContainers: [[Path]] = [
            [.key("update")],
            [.key("update"), .key("request")],
            [.key("update"), .key("state")],
            [.key("update"), .key("state"), .key("snapshot")],
            [.key("update"), .key("state"), .key("snapshot"), .key("_0")],
            [.key("update"), .key("state"), .key("snapshot"), .key("_0"), .key("request")],
            [.key("update"), .key("state"), .key("snapshot"), .key("_0"), .key("local")],
            [.key("update"), .key("state"), .key("snapshot"), .key("_0"), .key("local"), .key("rows"), .index(0)],
            [.key("update"), .key("state"), .key("snapshot"), .key("_0"), .key("local"), .key("rows"), .index(0), .key("scope")],
            [.key("update"), .key("state"), .key("snapshot"), .key("_0"), .key("local"), .key("rows"), .index(0), .key("notes")],
            [.key("update"), .key("state"), .key("snapshot"), .key("_0"), .key("local"), .key("rows"), .index(0), .key("checklists")],
            [.key("update"), .key("state"), .key("snapshot"), .key("_0"), .key("local"), .key("rows"), .index(0), .key("checklists"), .key("checklists"), .index(0)],
            [.key("update"), .key("state"), .key("snapshot"), .key("_0"), .key("local"), .key("rows"), .index(0), .key("checklists"), .key("checklists"), .index(0), .key("items"), .index(0)]
        ]
        for path in nestedPresentationContainers {
            let changed = try Self.addExtraKey(presentationBytes, at: path)
            #expect(Self.decodeFailure(SpaceChecklistEditingPresentation.self, changed) == .invalidEncodedPresentation)
        }
        for path in [
            [Path.key("checklists"), .index(0)],
            [.key("checklists"), .index(0), .key("items"), .index(0)]
        ] {
            let changed = try Self.addExtraKey(draftBytes, at: path)
            #expect(Self.decodeFailure(SpaceChecklistEditingDraft.self, changed) == .invalidEncodedDraft)
        }

        let snapshotRequiredKeys: [([Path], [String])] = [
            ([.key("update")], ["request", "state"]),
            ([.key("update"), .key("request")], ["accountId", "spaceId", "queryFingerprint"]),
            ([.key("update"), .key("state")], ["snapshot"]),
            (snapshot, ["request", "local"]),
            (snapshot + [.key("request")], ["accountId", "spaceId", "queryFingerprint"]),
            (local, [
                "queryFingerprint", "rows", "visibleRowCountBeforeFiltering",
                "isCompleteForQuery", "quality", "localDataVersion", "asOf"
            ]),
            (row, [
                "id", "accountId", "scope", "displayName", "notes", "lifecycle",
                "revision", "createdAt", "updatedAt", "checklists"
            ]),
            (row + [.key("scope")], ["kind", "projectId"]),
            (row + [.key("notes")], ["value"]),
            (row + [.key("checklists")], ["checklists"]),
            (checklist, ["id", "name", "presentationOrder", "items"]),
            (item, ["id", "text", "isChecked", "presentationOrder"])
        ]
        for (path, keys) in snapshotRequiredKeys {
            for key in keys {
                #expect(Self.decodeFailure(
                    SpaceChecklistEditingPresentation.self,
                    try Self.removeKey(presentationBytes, at: path, key: key)
                ) == .invalidEncodedPresentation)
            }
        }

        let draftRequiredKeys: [([Path], [String])] = [
            ([.key("checklists"), .index(0)], ["id", "name", "presentationOrder", "items"]),
            ([.key("checklists"), .index(0), .key("items"), .index(0)], [
                "id", "text", "isChecked", "presentationOrder"
            ])
        ]
        for (path, keys) in draftRequiredKeys {
            for key in keys {
                #expect(Self.decodeFailure(
                    SpaceChecklistEditingDraft.self,
                    try Self.removeKey(draftBytes, at: path, key: key)
                ) == .invalidEncodedDraft)
            }
        }

        for key in ["update", "state", "evidenceFingerprint"] {
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPresentation.self,
                try Self.removeKey(presentationBytes, key: key)
            ) == .invalidEncodedPresentation)
        }
        for key in ["presentation", "semanticBaseFingerprint", "draft"] {
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPreparation.self,
                try Self.removeKey(preparationBytes, key: key)
            ) == .invalidEncodedPreparation)
        }
        for key in ["accountId", "spaceId", "semanticBaseFingerprint", "checklists", "draftFingerprint"] {
            #expect(Self.decodeFailure(
                SpaceChecklistEditingDraft.self,
                try Self.removeKey(draftBytes, key: key)
            ) == .invalidEncodedDraft)
        }

        let reorderedSource = try Self.transform(
            presentationBytes,
            path: row + [.key("checklists"), .key("checklists")]
        ) { Array(($0 as! [Any]).reversed()) }
        #expect(Self.decodeFailure(SpaceChecklistEditingPresentation.self, reorderedSource) == .invalidEncodedPresentation)
        let removedSourceChecklist = try Self.transform(
            presentationBytes,
            path: row + [.key("checklists"), .key("checklists")]
        ) { Array(($0 as! [Any]).dropLast()) }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            removedSourceChecklist
        ) == .presentationFingerprintMismatch)
        let insertedSourceChecklist = try Self.transform(
            presentationBytes,
            path: row + [.key("checklists"), .key("checklists")]
        ) {
            let source = $0 as! [Any]
            return source + [source[0]]
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            insertedSourceChecklist
        ) == .invalidEncodedPresentation)
        let insertedUniqueSourceChecklist = try Self.transform(
            presentationBytes,
            path: row + [.key("checklists"), .key("checklists")]
        ) {
            let source = $0 as! [Any]
            var copy = source[0] as! [String: Any]
            copy["id"] = "inserted-source-list"
            copy["presentationOrder"] = 99
            return source + [copy]
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            insertedUniqueSourceChecklist
        ) == .presentationFingerprintMismatch)
        let reorderedSourceItems = try Self.transform(
            presentationBytes,
            path: checklist + [.key("items")]
        ) { Array(($0 as! [Any]).reversed()) }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            reorderedSourceItems
        ) == .invalidEncodedPresentation)
        let removedSourceItem = try Self.transform(
            presentationBytes,
            path: checklist + [.key("items")]
        ) { Array(($0 as! [Any]).dropLast()) }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            removedSourceItem
        ) == .presentationFingerprintMismatch)
        let insertedSourceItem = try Self.transform(
            presentationBytes,
            path: checklist + [.key("items")]
        ) {
            let source = $0 as! [Any]
            return source + [source[0]]
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            insertedSourceItem
        ) == .invalidEncodedPresentation)
        let insertedUniqueSourceItem = try Self.transform(
            presentationBytes,
            path: checklist + [.key("items")]
        ) {
            let source = $0 as! [Any]
            var copy = source[0] as! [String: Any]
            copy["id"] = "inserted-source-item"
            copy["presentationOrder"] = 99
            return source + [copy]
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            insertedUniqueSourceItem
        ) == .presentationFingerprintMismatch)
        let removedSourceRow = try Self.transform(
            presentationBytes,
            path: local + [.key("rows")]
        ) { Array(($0 as! [Any]).dropLast()) }
        #expect(Self.decodeFailure(SpaceChecklistEditingPresentation.self, removedSourceRow) == .invalidEncodedPresentation)
        let insertedSourceRow = try Self.transform(
            presentationBytes,
            path: local + [.key("rows")]
        ) {
            let source = $0 as! [Any]
            return source + [source[0]]
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            insertedSourceRow
        ) == .invalidEncodedPresentation)
        let reorderedDraftLists = try Self.transform(
            draftBytes,
            path: [.key("checklists")]
        ) { Array(($0 as! [Any]).reversed()) }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingDraft.self,
            reorderedDraftLists
        ) == .draftFingerprintMismatch)
        let removedDraftNode = try Self.transform(
            draftBytes,
            path: [.key("checklists")]
        ) { Array(($0 as! [Any]).dropLast()) }
        #expect(Self.decodeFailure(SpaceChecklistEditingDraft.self, removedDraftNode) == .draftFingerprintMismatch)
        let insertedDraftNode = try Self.transform(
            draftBytes,
            path: [.key("checklists")]
        ) {
            let source = $0 as! [Any]
            return source + [source[0]]
        }
        #expect(Self.decodeFailure(SpaceChecklistEditingDraft.self, insertedDraftNode) == .checklistIdentityCollision)
        let insertedUniqueDraftList = try Self.transform(
            draftBytes,
            path: [.key("checklists")]
        ) {
            let source = $0 as! [Any]
            var copy = source[0] as! [String: Any]
            copy["id"] = "inserted-list"
            copy["presentationOrder"] = 99
            return source + [copy]
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingDraft.self,
            insertedUniqueDraftList
        ) == .draftFingerprintMismatch)
        let rawItems = [Path.key("checklists"), .index(0), .key("items")]
        let reorderedDraftItems = try Self.transform(
            draftBytes,
            path: rawItems
        ) { Array(($0 as! [Any]).reversed()) }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingDraft.self,
            reorderedDraftItems
        ) == .draftFingerprintMismatch)
        let removedDraftItem = try Self.transform(
            draftBytes,
            path: rawItems
        ) { Array(($0 as! [Any]).dropLast()) }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingDraft.self,
            removedDraftItem
        ) == .draftFingerprintMismatch)
        let insertedDuplicateDraftItem = try Self.transform(
            draftBytes,
            path: rawItems
        ) {
            let source = $0 as! [Any]
            return source + [source[0]]
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingDraft.self,
            insertedDuplicateDraftItem
        ) == .itemIdentityCollision)
        let insertedUniqueDraftItem = try Self.transform(
            draftBytes,
            path: rawItems
        ) {
            let source = $0 as! [Any]
            var copy = source[0] as! [String: Any]
            copy["id"] = "inserted-item"
            copy["presentationOrder"] = 99
            return source + [copy]
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingDraft.self,
            insertedUniqueDraftItem
        ) == .draftFingerprintMismatch)

        let noncanonicalName = try Self.mutate(
            presentationBytes,
            path: [.key("update"), .key("state"), .key("snapshot"), .key("_0"), .key("local"), .key("rows"), .index(0), .key("checklists"), .key("checklists"), .index(0), .key("name")],
            value: " Checklist A "
        )
        #expect(Self.decodeFailure(SpaceChecklistEditingPresentation.self, noncanonicalName) == .invalidEncodedPresentation)
        let nonfiniteAsOf = try Self.replacingNumber(
            presentationBytes,
            after: "\"asOf\":",
            with: "1e999"
        )
        #expect(Self.decodeFailure(SpaceChecklistEditingPresentation.self, nonfiniteAsOf) == .invalidEncodedPresentation)
        for field in ["createdAt", "updatedAt"] {
            let nonfiniteTimestamp = try Self.replacingNumber(
                presentationBytes,
                after: "\"\(field)\":",
                with: "1e999"
            )
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPresentation.self,
                nonfiniteTimestamp
            ) == .invalidEncodedPresentation)
        }

        let retryable = try SpaceChecklistEditingPresentation(
            projecting: Self.update(state: .retryable)
        )
        let retryableBytes = try OperationContractCodec.encode(retryable)
        let failed = [Path.key("update"), .key("state"), .key("failed")]
        let cached = failed + [.key("cached")]
        let cachedLocal = cached + [.key("local")]
        let cachedRow = cachedLocal + [.key("rows"), .index(0)]
        let cachedChecklist = cachedRow + [
            .key("checklists"), .key("checklists"), .index(0)
        ]
        let cachedItem = cachedChecklist + [.key("items"), .index(0)]
        let cachedMutations: [([Path], Any, SpaceChecklistEditingFailure)] = [
            (cached + [.key("request"), .key("accountId")], "other-account", .invalidEncodedPresentation),
            (cached + [.key("request"), .key("spaceId")], "other-space", .invalidEncodedPresentation),
            (cached + [.key("request"), .key("queryFingerprint")], String(repeating: "0", count: 64), .invalidEncodedPresentation),
            (cachedLocal + [.key("queryFingerprint")], String(repeating: "0", count: 64), .invalidEncodedPresentation),
            (cachedLocal + [.key("visibleRowCountBeforeFiltering")], 0, .invalidEncodedPresentation),
            (cachedLocal + [.key("isCompleteForQuery")], false, .presentationFingerprintMismatch),
            (cachedLocal + [.key("quality")], "partial", .invalidEncodedPresentation),
            (cachedLocal + [.key("localDataVersion")], "cached-later-version", .presentationFingerprintMismatch),
            (cachedLocal + [.key("asOf")], 123_456, .presentationFingerprintMismatch),
            (cachedRow + [.key("id")], "other-space", .invalidEncodedPresentation),
            (cachedRow + [.key("accountId")], "other-account", .invalidEncodedPresentation),
            (cachedRow + [.key("scope"), .key("projectId")], "other-project", .presentationFingerprintMismatch),
            (cachedRow + [.key("displayName")], "Cached changed", .presentationFingerprintMismatch),
            (cachedRow + [.key("notes"), .key("value")], "Cached changed", .presentationFingerprintMismatch),
            (cachedRow + [.key("lifecycle")], "archived", .presentationFingerprintMismatch),
            (cachedRow + [.key("revision")], 8, .presentationFingerprintMismatch),
            (cachedRow + [.key("createdAt")], 123_456, .presentationFingerprintMismatch),
            (cachedRow + [.key("updatedAt")], 123_457, .presentationFingerprintMismatch),
            (cachedChecklist + [.key("id")], "cached-changed-list", .presentationFingerprintMismatch),
            (cachedChecklist + [.key("name")], "Cached changed", .presentationFingerprintMismatch),
            (cachedChecklist + [.key("presentationOrder")], 11, .presentationFingerprintMismatch),
            (cachedItem + [.key("id")], "cached-changed-item", .presentationFingerprintMismatch),
            (cachedItem + [.key("text")], "Cached changed", .presentationFingerprintMismatch),
            (cachedItem + [.key("isChecked")], true, .presentationFingerprintMismatch),
            (cachedItem + [.key("presentationOrder")], 12, .presentationFingerprintMismatch)
        ]
        for (path, value, expected) in cachedMutations {
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPresentation.self,
                try Self.mutate(retryableBytes, path: path, value: value)
            ) == expected)
        }

        let retryableContainers: [[Path]] = [
            failed,
            cached,
            cached + [.key("request")],
            cachedLocal,
            cachedRow,
            cachedRow + [.key("scope")],
            cachedRow + [.key("notes")],
            cachedRow + [.key("checklists")],
            cachedChecklist,
            cachedItem
        ]
        for path in retryableContainers {
            #expect(Self.decodeFailure(
                SpaceChecklistEditingPresentation.self,
                try Self.addExtraKey(retryableBytes, at: path)
            ) == .invalidEncodedPresentation)
        }
        let cachedRequiredKeys: [([Path], [String])] = [
            (failed, ["failure"]),
            (cached, ["request", "local"]),
            (cached + [.key("request")], ["accountId", "spaceId", "queryFingerprint"]),
            (cachedLocal, [
                "queryFingerprint", "rows", "visibleRowCountBeforeFiltering",
                "isCompleteForQuery", "quality", "localDataVersion", "asOf"
            ]),
            (cachedRow, [
                "id", "accountId", "scope", "displayName", "notes", "lifecycle",
                "revision", "createdAt", "updatedAt", "checklists"
            ]),
            (cachedRow + [.key("scope")], ["kind", "projectId"]),
            (cachedRow + [.key("notes")], ["value"]),
            (cachedRow + [.key("checklists")], ["checklists"]),
            (cachedChecklist, ["id", "name", "presentationOrder", "items"]),
            (cachedItem, ["id", "text", "isChecked", "presentationOrder"])
        ]
        for (path, keys) in cachedRequiredKeys {
            for key in keys {
                #expect(Self.decodeFailure(
                    SpaceChecklistEditingPresentation.self,
                    try Self.removeKey(retryableBytes, at: path, key: key)
                ) == .invalidEncodedPresentation)
            }
        }
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            try Self.removeKey(retryableBytes, at: failed, key: "cached")
        ) == .presentationFingerprintMismatch)
        let changedFailure = try Self.mutate(
            retryableBytes,
            path: failed + [.key("failure")],
            value: "requiredUpdate"
        )
        #expect(Self.decodeFailure(SpaceChecklistEditingPresentation.self, changedFailure) == .presentationFingerprintMismatch)
        let unavailableFailure = try Self.mutate(
            retryableBytes,
            path: failed + [.key("failure")],
            value: "unavailable"
        )
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            unavailableFailure
        ) == .invalidEncodedPresentation)
        let malformedFailure = try Self.mutate(
            retryableBytes,
            path: failed + [.key("failure")],
            value: "unknown"
        )
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            malformedFailure
        ) == .invalidEncodedPresentation)
        let removedCache = try Self.mutate(
            retryableBytes,
            path: failed + [.key("cached")],
            value: NSNull()
        )
        #expect(Self.decodeFailure(SpaceChecklistEditingPresentation.self, removedCache) == .invalidEncodedPresentation)

        let waiting = try SpaceChecklistEditingPresentation(
            projecting: SpaceCoreDetailsUpdate(
                request: Self.request(),
                state: .waiting(.loading)
            )
        )
        let waitingBytes = try OperationContractCodec.encode(waiting)
        let waitingPayload = [Path.key("update"), .key("state"), .key("waiting")]
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            try Self.addExtraKey(waitingBytes, at: waitingPayload)
        ) == .invalidEncodedPresentation)
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            try Self.removeKey(waitingBytes, at: waitingPayload, key: "_0")
        ) == .invalidEncodedPresentation)
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            try Self.mutate(waitingBytes, path: waitingPayload + [.key("_0")], value: "ready")
        ) == .invalidEncodedPresentation)
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            try Self.mutate(
                waitingBytes,
                path: [.key("update"), .key("state")],
                value: ["unknown": ["_0": "loading"]]
            )
        ) == .invalidEncodedPresentation)
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            try Self.addExtraKey(waitingBytes, at: [.key("update"), .key("state")])
        ) == .invalidEncodedPresentation)
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            try Self.addExtraKey(waitingBytes, at: [.key("state")])
        ) == .invalidEncodedPresentation)
        #expect(Self.decodeFailure(
            SpaceChecklistEditingPresentation.self,
            try Self.mutate(
                waitingBytes,
                path: [.key("state"), .key("waiting")],
                value: "blocked"
            )
        ) == .presentationFingerprintMismatch)

        let diagnostics: [(SpaceChecklistEditingFailure, String)] = [
            (.sourceNotEditable, "space_checklist_editing_source_not_editable"),
            (.checklistNotFound, "space_checklist_editing_checklist_not_found"),
            (.checklistIdentityCollision, "space_checklist_editing_checklist_identity_collision"),
            (.checklistOrderOverflow, "space_checklist_editing_checklist_order_overflow"),
            (.itemNotFound, "space_checklist_editing_item_not_found"),
            (.itemIdentityCollision, "space_checklist_editing_item_identity_collision"),
            (.itemOrderOverflow, "space_checklist_editing_item_order_overflow"),
            (.invalidItemPermutation, "space_checklist_editing_item_permutation_invalid"),
            (.semanticBaseMismatch, "space_checklist_editing_semantic_base_mismatch"),
            (.invalidPresentationFingerprint, "space_checklist_editing_presentation_fingerprint_invalid"),
            (.invalidSemanticBaseFingerprint, "space_checklist_editing_semantic_base_fingerprint_invalid"),
            (.invalidDraftFingerprint, "space_checklist_editing_draft_fingerprint_invalid"),
            (.presentationFingerprintMismatch, "space_checklist_editing_presentation_fingerprint_mismatch"),
            (.semanticBaseFingerprintMismatch, "space_checklist_editing_semantic_base_fingerprint_mismatch"),
            (.draftFingerprintMismatch, "space_checklist_editing_draft_fingerprint_mismatch"),
            (.invalidEncodedPresentation, "space_checklist_editing_presentation_encoding_invalid"),
            (.invalidEncodedPreparation, "space_checklist_editing_preparation_encoding_invalid"),
            (.invalidEncodedDraft, "space_checklist_editing_draft_encoding_invalid")
        ]
        #expect(Set(diagnostics.map(\.1)).count == diagnostics.count)
        for (failure, expected) in diagnostics {
            #expect(failure.diagnosticCode == expected)
            #expect(expected.utf8.count <= 72)
            #expect(expected.hasPrefix("space_checklist_editing_"))
            #expect(expected.allSatisfy { character in
                character.isNumber || ("a"..."z").contains(String(character)) || character == "_"
            })
            for forbidden in [
                "firebase", "supabase", "powersync", "provider", "url", "token",
                "secret", "credential", "authorization"
            ] {
                #expect(!expected.contains(forbidden))
            }
        }

        let derivedCommand = try Self.command(preparation.draft, validating: Self.update())
        let encodedBoundaryValues = try [
            presentationBytes,
            preparationBytes,
            draftBytes,
            OperationContractCodec.encode(derivedCommand)
        ].map { String(decoding: $0, as: UTF8.self).lowercased() }
        let forbiddenEncodedFields = [
            "providerurl", "url", "token", "secret", "credential", "authorization",
            "authoritativeresult", "result", "patch", "merge", "scopechange",
            "detailschange", "lifecyclechange", "templateid", "mediaid", "projectitemid",
            "review", "accounting", "repository", "persistence", "firebase", "supabase",
            "powersync"
        ]
        for encoded in encodedBoundaryValues {
            for forbidden in forbiddenEncodedFields {
                #expect(!encoded.contains("\"\(forbidden)\""))
            }
        }

        let implementationURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LedgerTargetCore")
            .appendingPathComponent("SpaceChecklistEditingPresentation.swift")
        let implementation = try String(contentsOf: implementationURL, encoding: .utf8)
        for forbiddenAPI in [
            "func reorderingChecklists", "func movingItem", "func movingChecklistItem",
            "crossChecklist", "Firebase", "Supabase", "PowerSync", "URLSession",
            "SwiftUI", "authorize(", "authorization", "persist(", "OperationPort",
            "authoritativeResult", "genericPatch", "applyTemplate", "saveTemplate",
            "ProjectItem", "InventoryItem", "Media", "Review", "Accounting",
            "Persistence", "RowLevelSecurity", "SyncStream"
        ] {
            #expect(!implementation.contains(forbiddenAPI))
        }
    }
}
