import LedgerTargetAppModel
import LedgerTargetPowerSync

enum AccountPendingWorkStagingRuntimeAdapter {
    static func adapt(
        _ runtime: LedgerOfflineClientRuntime
    ) -> AccountPendingWorkStagingRuntime {
        AccountPendingWorkStagingRuntime(
            pendingWorkSummary: { try await runtime.pendingWorkSummary() }
        )
    }
}
