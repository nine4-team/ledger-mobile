import LedgerTargetAppModel
import LedgerTargetPowerSync

enum ProjectBrowsingStagingRuntimeAdapter {
    static func adapt(_ runtime: LedgerOfflineClientRuntime) -> ProjectBrowsingStagingRuntime {
        ProjectBrowsingStagingRuntime(
            watchProjects: { runtime.watchProjects() },
            watchProject: { request in runtime.watchProject(request) }
        )
    }
}
