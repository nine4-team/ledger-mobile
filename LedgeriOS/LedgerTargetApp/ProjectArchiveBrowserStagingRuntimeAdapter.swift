import LedgerTargetAppModel
import LedgerTargetPowerSync

enum ProjectArchiveBrowserStagingRuntimeAdapter {
    static func adapt(
        _ runtime: LedgerOfflineClientRuntime
    ) -> ProjectArchiveBrowserStagingRuntime {
        ProjectArchiveBrowserStagingRuntime(
            archive: { try await runtime.archive($0) },
            watchOperation: { runtime.watchOperation($0) }
        )
    }
}
