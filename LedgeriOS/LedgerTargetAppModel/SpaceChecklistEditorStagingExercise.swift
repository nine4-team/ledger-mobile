import Foundation
import LedgerTargetCore
import Observation

public struct SpaceChecklistEditorItem: Equatable, Identifiable, Sendable {
    public let id: SpaceChecklistItemID
    public var text: String
    public var isChecked: Bool

    public init(id: SpaceChecklistItemID, text: String, isChecked: Bool) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}

public struct SpaceChecklistEditorChecklist: Equatable, Identifiable, Sendable {
    public let id: SpaceChecklistID
    public var name: String
    public var items: [SpaceChecklistEditorItem]

    public init(
        id: SpaceChecklistID,
        name: String,
        items: [SpaceChecklistEditorItem]
    ) {
        self.id = id
        self.name = name
        self.items = items
    }

    public var completedItemCount: Int { items.count(where: \.isChecked) }
}

@MainActor
@Observable
public final class SpaceChecklistEditorStagingExercise {
    public private(set) var isPresented = false
    public private(set) var isSaving = false
    public private(set) var checklists: [SpaceChecklistEditorChecklist] = []
    public private(set) var diagnostic: String?
    public private(set) var isReviewingRejectedDraft = false

    public var hasPreservedConflictDraft: Bool {
        submittedCollection != nil || coordinator.rejectedRecoveryCollection != nil
    }

    public var canOpen: Bool {
        !isPresented
            && !isSaving
            && !hasPreservedConflictDraft
            && coordinator.canSubmitCompleteDraft
            && editableUpdate != nil
    }

    public var canReviewPreservedConflict: Bool {
        !isPresented
            && !isSaving
            && hasPreservedConflictDraft
            && !coordinator.hasActiveSubmission
    }

    public var canSave: Bool {
        guard isPresented,
              !isReviewingRejectedDraft,
              !isSaving,
              coordinator.canSubmitCompleteDraft,
              let sourceUpdate = editorSourceUpdate,
              let target = try? materializedDraft(from: sourceUpdate).collection(),
              let source = Self.row(from: sourceUpdate)?.checklists,
              target != source else {
            return false
        }
        return true
    }

    public var canRetryAmbiguousAcceptance: Bool {
        isPresented && !isSaving && coordinator.canRetryAmbiguousAcceptance
    }

    public var canMutateDraft: Bool {
        isPresented
            && !isSaving
            && !isReviewingRejectedDraft
            && !coordinator.hasActiveSubmission
    }

    public var canCancel: Bool {
        isPresented && !isSaving && !coordinator.hasActiveSubmission
    }

    public var validationMessage: String? {
        guard isPresented, let sourceUpdate = editorSourceUpdate else { return nil }
        do {
            let target = try materializedDraft(from: sourceUpdate).collection()
            return target == Self.row(from: sourceUpdate)?.checklists
                ? "No checklist changes to save."
                : nil
        } catch SpaceChecklistRevisionFailure.invalidChecklistName {
            return "Checklist names are required."
        } catch SpaceChecklistRevisionFailure.invalidChecklistItemText {
            return "Checklist item text is required."
        } catch {
            return "This checklist draft cannot be saved."
        }
    }

    public var completedItemCount: Int {
        checklists.reduce(0) { $0 + $1.completedItemCount }
    }

    public var totalItemCount: Int {
        checklists.reduce(0) { $0 + $1.items.count }
    }

    private let coordinator: SpaceChecklistItemToggleStagingExercise
    private let makeChecklistId: @MainActor () throws -> SpaceChecklistID
    private let makeItemId: @MainActor () throws -> SpaceChecklistItemID
    private var selectedSpaceId: SpaceID?
    private var editableUpdate: SpaceCoreDetailsUpdate?
    private var editorSourceUpdate: SpaceCoreDetailsUpdate?
    private var submittedCollection: SpaceChecklistCollection?
    private var saveTask: Task<SpaceChecklistRevisionSubmissionOutcome, Never>?
    private var generation = UUID()

    public init(
        coordinator: SpaceChecklistItemToggleStagingExercise,
        makeChecklistId: @escaping @MainActor () throws -> SpaceChecklistID,
        makeItemId: @escaping @MainActor () throws -> SpaceChecklistItemID
    ) {
        self.coordinator = coordinator
        self.makeChecklistId = makeChecklistId
        self.makeItemId = makeItemId
    }

    public func start() async {
        await reset(to: nil)
    }

    public func receiveDetailUpdate(
        _ update: SpaceCoreDetailsUpdate?,
        selectedSpaceId newSelection: SpaceID?
    ) async {
        if selectedSpaceId != newSelection {
            await reset(to: newSelection)
        }
        guard selectedSpaceId == newSelection else { return }

        editableUpdate = Self.editable(update)

        if submittedCollection == nil,
           coordinator.hasActiveSubmission,
           let projectedCollection = coordinator.optimisticCollection {
            submittedCollection = projectedCollection
            checklists = Self.project(projectedCollection)
        }

        guard submittedCollection != nil,
              !coordinator.hasActiveSubmission else { return }
        if coordinator.operationState == .applied,
           Self.row(from: editableUpdate)?.checklists == submittedCollection {
            clearDraft()
            diagnostic = nil
        } else if coordinator.operationState == .rejected
                    || coordinator.operationState == .superseded
                    || coordinator.operationState == .resolved {
            diagnostic = "Checklist changes were not applied. Review the preserved draft."
        }
    }

    public func open() {
        guard canOpen,
              let update = editableUpdate,
              let preparation = try? SpaceChecklistEditingPresentation(
                  projecting: update
              ).prepare() else { return }
        editorSourceUpdate = update
        checklists = Self.project(preparation.draft)
        submittedCollection = nil
        diagnostic = nil
        isReviewingRejectedDraft = false
        isPresented = true
    }

    public func reviewPreservedConflict() {
        guard canReviewPreservedConflict,
              let collection = coordinator.rejectedRecoveryCollection
                ?? submittedCollection else { return }
        editorSourceUpdate = editableUpdate
        checklists = Self.project(collection)
        diagnostic = nil
        isReviewingRejectedDraft = true
        isPresented = true
    }

    public func cancel() {
        guard canCancel else { return }
        if isReviewingRejectedDraft {
            isPresented = false
            isReviewingRejectedDraft = false
            editorSourceUpdate = nil
            checklists = []
            diagnostic = nil
            return
        }
        clearDraft()
    }

    public func renameChecklist(id: SpaceChecklistID, name: String) {
        guard canMutateDraft,
              let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        checklists[index].name = name
    }

    public func editItemText(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID,
        text: String
    ) {
        guard canMutateDraft,
              let checklistIndex = checklists.firstIndex(where: { $0.id == checklistId }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: {
                  $0.id == itemId
              }) else { return }
        checklists[checklistIndex].items[itemIndex].text = text
    }

    public func setItemChecked(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID,
        isChecked: Bool
    ) {
        guard canMutateDraft,
              let checklistIndex = checklists.firstIndex(where: { $0.id == checklistId }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: {
                  $0.id == itemId
              }) else { return }
        checklists[checklistIndex].items[itemIndex].isChecked = isChecked
    }

    public func addChecklist() {
        guard canMutateDraft else { return }
        do {
            let id = try makeChecklistId()
            guard !checklists.contains(where: { $0.id == id }) else {
                throw SpaceChecklistEditingFailure.checklistIdentityCollision
            }
            checklists.append(SpaceChecklistEditorChecklist(
                id: id,
                name: "New Checklist",
                items: []
            ))
            diagnostic = nil
        } catch {
            diagnostic = "space_checklist_editor_checklist_identity_invalid"
        }
    }

    public func addItem(to checklistId: SpaceChecklistID) {
        guard canMutateDraft,
              let checklistIndex = checklists.firstIndex(where: {
                  $0.id == checklistId
              }) else { return }
        do {
            let id = try makeItemId()
            guard !checklists[checklistIndex].items.contains(where: { $0.id == id }) else {
                throw SpaceChecklistEditingFailure.itemIdentityCollision
            }
            checklists[checklistIndex].items.append(SpaceChecklistEditorItem(
                id: id,
                text: "",
                isChecked: false
            ))
            diagnostic = nil
        } catch {
            diagnostic = "space_checklist_editor_item_identity_invalid"
        }
    }

    public func deleteChecklist(id: SpaceChecklistID) {
        guard canMutateDraft,
              checklists.contains(where: { $0.id == id }) else { return }
        checklists.removeAll(where: { $0.id == id })
    }

    public func deleteItem(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID
    ) {
        guard canMutateDraft,
              let checklistIndex = checklists.firstIndex(where: {
                  $0.id == checklistId
              }) else { return }
        checklists[checklistIndex].items.removeAll(where: { $0.id == itemId })
    }

    public func reorderItems(
        checklistId: SpaceChecklistID,
        itemIds: [SpaceChecklistItemID]
    ) {
        guard canMutateDraft,
              let checklistIndex = checklists.firstIndex(where: {
                  $0.id == checklistId
              }) else { return }
        let items = checklists[checklistIndex].items
        guard itemIds.count == items.count,
              Set(itemIds).count == itemIds.count,
              Set(itemIds) == Set(items.map(\.id)) else {
            diagnostic = "space_checklist_editor_item_order_invalid"
            return
        }
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        checklists[checklistIndex].items = itemIds.compactMap { byId[$0] }
        diagnostic = nil
    }

    public func save() async {
        guard canSave,
              let sourceUpdate = editorSourceUpdate,
              let draft = try? materializedDraft(from: sourceUpdate),
              let targetCollection = try? draft.collection() else { return }

        let activeGeneration = generation
        isSaving = true
        diagnostic = nil
        let task = Task {
            await coordinator.submitCompleteDraft(draft, from: sourceUpdate)
        }
        saveTask = task
        let outcome = await task.value
        guard generation == activeGeneration else { return }
        saveTask = nil
        isSaving = false

        switch outcome {
        case .acceptedLocally:
            submittedCollection = targetCollection
            isPresented = false
        case .acceptanceUncertain:
            diagnostic = "Local acceptance is uncertain; retry the exact operation."
        case .refused:
            diagnostic = coordinator.diagnostic ?? "Checklist changes could not be saved."
        }
    }

    public func retryAmbiguousAcceptance() async {
        guard isPresented,
              !isSaving,
              coordinator.canRetryAmbiguousAcceptance else { return }
        let activeGeneration = generation
        isSaving = true
        let task = Task { () -> SpaceChecklistRevisionSubmissionOutcome in
            await coordinator.retryAmbiguousAcceptance()
            return coordinator.optimisticCollection == nil
                ? .acceptanceUncertain
                : .acceptedLocally
        }
        saveTask = task
        let outcome = await task.value
        guard generation == activeGeneration else { return }
        saveTask = nil
        isSaving = false
        if outcome == .acceptedLocally {
            submittedCollection = coordinator.optimisticCollection
            isPresented = false
            diagnostic = nil
        } else {
            diagnostic = coordinator.diagnostic
        }
    }

    public func stop() async {
        await reset(to: nil)
    }

    private func materializedDraft(
        from update: SpaceCoreDetailsUpdate
    ) throws -> SpaceChecklistEditingDraft {
        let preparation = try SpaceChecklistEditingPresentation(projecting: update).prepare()
        var draft = preparation.draft
        let desiredChecklistIds = Set(checklists.map(\.id))
        for existing in draft.checklists where !desiredChecklistIds.contains(existing.id) {
            draft = try draft.removingChecklist(id: existing.id)
        }

        for checklist in checklists {
            if draft.checklists.contains(where: { $0.id == checklist.id }) {
                draft = try draft.renamingChecklist(id: checklist.id, name: checklist.name)
            } else {
                draft = try draft.appendingChecklist(id: checklist.id, name: checklist.name)
            }

            let desiredItemIds = Set(checklist.items.map(\.id))
            let representedItems = draft.checklists
                .first(where: { $0.id == checklist.id })?.items ?? []
            for existing in representedItems where !desiredItemIds.contains(existing.id) {
                draft = try draft.removingItem(
                    checklistId: checklist.id,
                    itemId: existing.id
                )
            }

            for item in checklist.items {
                let itemExists = draft.checklists
                    .first(where: { $0.id == checklist.id })?
                    .items.contains(where: { $0.id == item.id }) == true
                if itemExists {
                    draft = try draft.editingItemText(
                        checklistId: checklist.id,
                        itemId: item.id,
                        text: item.text
                    )
                    draft = try draft.settingItemChecked(
                        checklistId: checklist.id,
                        itemId: item.id,
                        isChecked: item.isChecked
                    )
                } else {
                    draft = try draft.appendingItem(
                        checklistId: checklist.id,
                        id: item.id,
                        text: item.text,
                        isChecked: item.isChecked
                    )
                }
            }
            draft = try draft.reorderingItems(
                checklistId: checklist.id,
                itemIds: checklist.items.map(\.id)
            )
        }
        return draft
    }

    private func reset(to newSelection: SpaceID?) async {
        generation = UUID()
        let oldTask = saveTask
        saveTask = nil
        oldTask?.cancel()
        _ = await oldTask?.value
        selectedSpaceId = newSelection
        editableUpdate = nil
        clearDraft()
        isSaving = false
    }

    private func clearDraft() {
        isPresented = false
        checklists = []
        editorSourceUpdate = nil
        submittedCollection = nil
        diagnostic = nil
        isReviewingRejectedDraft = false
    }
}

private extension SpaceChecklistEditorStagingExercise {
    static func editable(
        _ update: SpaceCoreDetailsUpdate?
    ) -> SpaceCoreDetailsUpdate? {
        guard let update,
              let presentation = try? SpaceChecklistEditingPresentation(projecting: update),
              presentation.state == .editableCurrent
                || presentation.state == .editableStale,
              row(from: update)?.lifecycle == .active else { return nil }
        return update
    }

    static func row(from update: SpaceCoreDetailsUpdate?) -> SpaceCoreDetailsSnapshot? {
        guard let update else { return nil }
        switch update.state {
        case .snapshot(let snapshot):
            return snapshot.row
        case .failed(.retryable, let cached):
            return cached?.row
        case .waiting, .failed:
            return nil
        }
    }

    static func project(
        _ draft: SpaceChecklistEditingDraft
    ) -> [SpaceChecklistEditorChecklist] {
        draft.checklists.map { checklist in
            SpaceChecklistEditorChecklist(
                id: checklist.id,
                name: checklist.name,
                items: checklist.items.map {
                    SpaceChecklistEditorItem(
                        id: $0.id,
                        text: $0.text,
                        isChecked: $0.isChecked
                    )
                }
            )
        }
    }

    static func project(
        _ collection: SpaceChecklistCollection
    ) -> [SpaceChecklistEditorChecklist] {
        collection.checklists.map { checklist in
            SpaceChecklistEditorChecklist(
                id: checklist.id,
                name: checklist.name.rawValue,
                items: checklist.items.map {
                    SpaceChecklistEditorItem(
                        id: $0.id,
                        text: $0.text.rawValue,
                        isChecked: $0.isChecked
                    )
                }
            )
        }
    }
}
