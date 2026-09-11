import LedgerTargetAppModel
import LedgerTargetPowerSync

enum ClientBrowsingStagingRuntimeAdapter {
    static func adapt(_ runtime: LedgerOfflineClientRuntime) -> ClientBrowsingStagingRuntime {
        ClientBrowsingStagingRuntime(
            watchClients: { runtime.watchClients() },
            watchClient: { request in runtime.watchClient(request) }
        )
    }
}
