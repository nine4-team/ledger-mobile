public struct TransactionTypeChoiceDescriptor: Equatable, Sendable {
    public let transactionType: LedgerTransactionType
    public let transactionTypeTitle: String
    public let scopeOwnerKind: TransactionScopeOwnerKind
    public let scopeOwnerTitle: String
    public let economicMeaning: TransactionEconomicMeaning

    fileprivate init(classification: TransactionClassification) {
        transactionType = classification.type
        transactionTypeTitle = switch classification.type {
        case .purchase: "Purchase"
        case .return: "Return"
        case .transfer: "Transfer"
        }
        scopeOwnerKind = classification.scope.ownerKind
        scopeOwnerTitle = switch classification.scope.ownerKind {
        case .project: "Client"
        case .businessInventory: "1584"
        }
        economicMeaning = classification.economicMeaning
    }
}

public enum TransactionTypeChoiceCatalog {
    public static func membership(
        for scopeOwnerKind: TransactionScopeOwnerKind
    ) -> Set<LedgerTransactionType> {
        switch scopeOwnerKind {
        case .project:
            [.purchase, .return, .transfer]
        case .businessInventory:
            [.purchase, .return]
        }
    }
}

public enum TransactionTypeChoicePresentationProjector {
    public static func descriptor(
        for classification: TransactionClassification
    ) -> TransactionTypeChoiceDescriptor {
        TransactionTypeChoiceDescriptor(classification: classification)
    }
}
