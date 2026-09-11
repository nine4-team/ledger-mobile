import LedgerTargetAppModel
import LedgerTargetPowerSync

enum SpaceAssignmentDestinationStagingRuntimeAdapter {
    static func adapt(
        _ runtime: LedgerOfflineClientRuntime
    ) -> SpaceAssignmentDestinationStagingRuntime {
        SpaceAssignmentDestinationStagingRuntime(
            watch: { scope in
                runtime.watchSpaceAssignmentDestinations(scope: scope)
            }
        )
    }
}
