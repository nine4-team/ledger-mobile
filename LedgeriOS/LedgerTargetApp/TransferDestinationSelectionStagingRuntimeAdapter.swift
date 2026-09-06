import LedgerTargetAppModel
import LedgerTargetPowerSync

enum TransferDestinationSelectionStagingRuntimeAdapter {
    static func adapt(
        _ runtime: LedgerOfflineClientRuntime
    ) -> TransferDestinationSelectionStagingRuntime {
        TransferDestinationSelectionStagingRuntime(
            watch: { source in
                runtime.watchTransferDestinations(source: source)
            }
        )
    }
}
