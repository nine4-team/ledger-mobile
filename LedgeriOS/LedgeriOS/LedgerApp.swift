import SwiftUI
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

enum AppRuntime {
    static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["LEDGER_UNIT_TEST_HOST"] == "1"
    }
}

@main
struct LedgerApp: App {
    @State private var authManager: AuthManager
    @State private var accountContext: AccountContext
    @State private var projectContext: ProjectContext
    @State private var inventoryContext: InventoryContext
    @State private var mediaService = MediaService()
    @State private var networkMonitor = NetworkMonitor()
    @State private var mediaUploadQueue: MediaUploadQueue
    @State private var findStateManager = FindStateManager()
    @State private var inviteLinkRouter = InviteLinkRouter()

    init() {
        FirebaseApp.configure()
        PerformanceDiagnostics.shared.start()

        // Disk cache for images — FirebaseImage uses URLSession.shared which respects this.
        // L1 = ImageCache (NSCache, in-session). L2 = URLCache (disk, survives restarts).
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,   // 50 MB memory
            diskCapacity: 200 * 1024 * 1024      // 200 MB disk
        )


        // macOS + App Sandbox: use memory-only cache to avoid gRPC/persistence deadlocks.
        // Emulator config handles its own cache settings when active.
        #if os(macOS)
        let firestoreSettings = Firestore.firestore().settings
        firestoreSettings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = firestoreSettings
        print("[Firebase] macOS: configured Firestore with memory-only cache")
        #endif

        #if DEBUG
        FirebaseEmulatorConfig.configureIfEnabled()
        #endif

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: FirebaseApp.app()!.options.clientID!
        )

        #if os(macOS)
        if !AppRuntime.isUnitTestHost {
            _ = SparkleUpdateController.shared
        }
        #endif

        _authManager = State(initialValue: AuthManager())

        let accountsService = AccountsService()
        let membersService = AccountMembersService()
        let projectService = ProjectService()
        let transactionsService = TransactionsService()
        let itemsService = ItemsService()
        let protoItemsService = ProtoItemsService()
        let spacesService = SpacesService()
        let budgetCategoriesService = BudgetCategoriesService()
        let projectBudgetCategoriesService = ProjectBudgetCategoriesService()
        let invoicesService = InvoiceService()

        _accountContext = State(initialValue: AccountContext(
            accountsService: accountsService,
            membersService: membersService,
            itemsService: itemsService,
            protoItemsService: protoItemsService,
            transactionsService: transactionsService,
            spacesService: spacesService,
            budgetCategoriesService: budgetCategoriesService,
            projectService: projectService,
            invoicesService: invoicesService
        ))

        _projectContext = State(initialValue: ProjectContext(
            projectService: projectService,
            transactionsService: transactionsService,
            itemsService: itemsService,
            protoItemsService: protoItemsService,
            spacesService: spacesService,
            projectBudgetCategoriesService: projectBudgetCategoriesService
        ))

        _inventoryContext = State(initialValue: InventoryContext(
            itemsService: itemsService,
            protoItemsService: protoItemsService,
            transactionsService: transactionsService,
            spacesService: spacesService
        ))

        // Persistent media upload queue — survives app restarts.
        // Processes pending image uploads on launch and when connectivity is restored.
        let queue = MediaUploadQueue(mediaService: MediaService())
        _mediaUploadQueue = State(initialValue: queue)
    }

    @AppStorage("colorSchemePreference") private var colorSchemePreference = "system"

    private var resolvedColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup("Ledger", id: "main") {
            RootView()
                .environment(authManager)
                .environment(accountContext)
                .environment(projectContext)
                .environment(inventoryContext)
                .environment(mediaService)
                .environment(mediaUploadQueue)
                .environment(networkMonitor)
                .environment(findStateManager)
                .environment(inviteLinkRouter)
                .preferredColorScheme(resolvedColorScheme)
                #if DEBUG
                .overlay(alignment: .top) {
                    if FirebaseEmulatorConfig.isEnabled {
                        Text("EMULATOR")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.orange)
                            .clipShape(Capsule())
                            .padding(.top, 2)
                    }
                }
                #endif
                .onOpenURL { url in
                    if !GIDSignIn.sharedInstance.handle(url) {
                        _ = inviteLinkRouter.handle(url: url)
                    }
                }
                .task {
                    guard !AppRuntime.isUnitTestHost else { return }

                    networkMonitor.onConnectivityRestored = { [mediaUploadQueue] in
                        mediaUploadQueue.processQueue()
                    }
                    mediaUploadQueue.processQueue()
                }
        }
        .commands {
            LedgerCommands()
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        #endif
    }
}
