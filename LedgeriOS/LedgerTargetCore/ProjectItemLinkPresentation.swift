public enum ProjectItemLinkPresentationFailure: Error, Equatable, Sendable {
    case unavailableForAccountedItem
    case relationshipEvidenceIncomplete

    public var diagnosticCode: String {
        switch self {
        case .unavailableForAccountedItem:
            "project_item_link_unavailable_accounted"
        case .relationshipEvidenceIncomplete:
            "project_item_link_relationship_evidence_incomplete"
        }
    }
}

public struct ProjectItemAccountingSectionPresentation: Equatable, Sendable {
    public let kind: ProjectItemAccountingSectionKind
    public let title: String

    fileprivate init(kind: ProjectItemAccountingSectionKind) {
        self.kind = kind
        title = switch kind {
        case .unaccountedFor:
            "Unaccounted For Items"
        case .accountedFor:
            "Accounted For Items"
        }
    }
}

public enum ProjectItemLinkPayerChoice: CaseIterable, Hashable, Sendable {
    case clientPaid
    case businessPaid

    // Membership is canonical; CaseIterable declaration order is not UI order.
    public static let all = Set(allCases)

    public var label: String {
        switch self {
        case .clientPaid:
            "Client paid"
        case .businessPaid:
            "Business paid"
        }
    }
}

public enum ProjectItemLinkDismissalOutcome: Equatable, Sendable {
    case noAction
}

public struct ProjectItemLinkPresentationDescriptor: Equatable, Sendable {
    public let actionTitle: String
    public let question: String
    public let payerChoices: Set<ProjectItemLinkPayerChoice>

    fileprivate init() {
        actionTitle = "Link"
        question = "Who paid for this Item?"
        payerChoices = ProjectItemLinkPayerChoice.all
    }

    public func dismiss() -> ProjectItemLinkDismissalOutcome {
        .noAction
    }
}

public enum ProjectItemLinkPresentationProjector {
    public static func sections(
        from snapshot: ProjectItemAccountingSectionsSnapshot
    ) -> [ProjectItemAccountingSectionPresentation] {
        snapshot.sections.map {
            ProjectItemAccountingSectionPresentation(kind: $0.kind)
        }
    }

    public static func linkDescriptor(
        for row: ProjectItemAccountingRow
    ) throws -> ProjectItemLinkPresentationDescriptor {
        switch row.resolution {
        case .unaccountedFor:
            ProjectItemLinkPresentationDescriptor()
        case .accountedFor:
            throw ProjectItemLinkPresentationFailure.unavailableForAccountedItem
        case .relationshipEvidenceIncomplete:
            throw ProjectItemLinkPresentationFailure.relationshipEvidenceIncomplete
        }
    }
}
