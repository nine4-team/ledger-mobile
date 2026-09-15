import LedgerTargetAppModel
import LedgerTargetCore
import LedgerTargetPowerSync

enum CategoryManagementRuntimeAdapter {
    static func adapt(_ runtime: LedgerOfflineClientRuntime) -> CategoryManagementRuntime {
        CategoryManagementRuntime(watch: { runtime.watchBudgetCategories() }, submit: {
            try await runtime.submitCategoryChange($0, operationUUID: $1, capturedAt: $2)
        }, watchOperations: { runtime.watchCategoryOperations() })
    }
}

extension CategoryFormPresentation.Kind {
    var categoryKind: BudgetCategoryKind {
        switch self { case .general: .general; case .itemized: .itemized; case .fee: .fee }
    }

    init(_ kind: BudgetCategoryKind) {
        self = switch kind { case .general: .general; case .itemized: .itemized; case .fee: .fee }
    }
}
