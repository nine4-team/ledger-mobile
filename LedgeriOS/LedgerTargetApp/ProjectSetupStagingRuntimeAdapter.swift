import LedgerTargetAppModel
import LedgerTargetPowerSync

enum ProjectSetupStagingRuntimeAdapter {
    static func adapt(_ runtime: LedgerOfflineClientRuntime) -> ProjectSetupStagingRuntime {
        ProjectSetupStagingRuntime(
            watchClients: { runtime.watchClients() },
            watchBudgetCategories: { runtime.watchBudgetCategories() },
            create: { command in try await runtime.createProject(command) }
        )
    }
}
