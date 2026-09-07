import LedgerTargetAppModel
import LedgerTargetCore
import LedgerTargetPowerSync

struct SpaceCoreDetailsStagingRuntimeAdapter: SpaceCoreDetailsStagingRuntime {
    private let runtime: LedgerOfflineClientRuntime

    init(_ runtime: LedgerOfflineClientRuntime) {
        self.runtime = runtime
    }

    func watchSpaceCoreDetails(
        spaceId: SpaceID
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        runtime.watchSpaceCoreDetails(spaceId: spaceId)
    }
}

enum SpaceChecklistItemToggleStagingRuntimeAdapter {
    static func adapt(
        _ runtime: LedgerOfflineClientRuntime
    ) -> SpaceChecklistItemToggleStagingRuntime {
        SpaceChecklistItemToggleStagingRuntime(
            reviseChecklists: { try await runtime.reviseChecklists($0) },
            watchOperation: {
                runtime.watchSpaceChecklistRevisionOperation($0)
            },
            rejectedOperations: { try await runtime.rejectedOperations($0) },
            watchRejectedOperations: { runtime.watchRejectedOperations($0) }
        )
    }
}
