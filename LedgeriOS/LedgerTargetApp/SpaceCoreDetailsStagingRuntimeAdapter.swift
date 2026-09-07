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
            }
        )
    }
}
