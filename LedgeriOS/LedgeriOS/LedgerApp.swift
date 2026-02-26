import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct LedgerApp: App {
    @State private var authManager: AuthManager
    @State private var accountContext: AccountContext
    @State private var projectContext: ProjectContext

    init() {
        FirebaseApp.configure()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: FirebaseApp.app()!.options.clientID!
        )
        _authManager = State(initialValue: AuthManager())

        let syncTracker: SyncTracking = NoOpSyncTracker()

        let accountsService = AccountsService(syncTracker: syncTracker)
        let membersService = AccountMembersService(syncTracker: syncTracker)
        let projectService = ProjectService(syncTracker: syncTracker)
        let transactionsService = TransactionsService(syncTracker: syncTracker)
        let itemsService = ItemsService(syncTracker: syncTracker)
        let spacesService = SpacesService(syncTracker: syncTracker)
        let budgetCategoriesService = BudgetCategoriesService(syncTracker: syncTracker)
        let projectBudgetCategoriesService = ProjectBudgetCategoriesService(syncTracker: syncTracker)

        _accountContext = State(initialValue: AccountContext(
            accountsService: accountsService,
            membersService: membersService
        ))

        _projectContext = State(initialValue: ProjectContext(
            projectService: projectService,
            transactionsService: transactionsService,
            itemsService: itemsService,
            spacesService: spacesService,
            budgetCategoriesService: budgetCategoriesService,
            projectBudgetCategoriesService: projectBudgetCategoriesService
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .environment(accountContext)
                .environment(projectContext)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
