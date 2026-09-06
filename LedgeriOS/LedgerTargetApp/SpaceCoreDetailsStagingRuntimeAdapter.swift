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
