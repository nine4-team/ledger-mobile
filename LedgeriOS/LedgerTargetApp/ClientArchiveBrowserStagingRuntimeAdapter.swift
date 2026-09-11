import LedgerTargetAppModel
import LedgerTargetPowerSync

enum ClientArchiveBrowserStagingRuntimeAdapter {
    static func adapt(
        _ runtime: LedgerOfflineClientRuntime
    ) -> ClientArchiveBrowserStagingRuntime {
        ClientArchiveBrowserStagingRuntime(
            archive: { try await runtime.archive($0) },
            watchOperation: { runtime.watchClientArchiveOperation($0) }
        )
    }
}
