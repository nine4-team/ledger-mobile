import LedgerTargetCore
import LedgerTargetPowerSync
import SwiftUI

enum TargetSupabaseConfiguration {
    // Explicit local development uses the normal sign-in/workspace UI. No
    // endpoint override: credentials for a different host cannot redirect it.
    #if DEBUG && LEDGER_TARGET_LOCAL
    static let localKey = Bundle.main.object(forInfoDictionaryKey: "LedgerLocalPublishableKey") as? String
    static let isLocal = true
    #else
    static let localKey: String? = nil
    static let isLocal = false
    #endif
    static let environment: LedgerEnvironmentKind = isLocal ? .targetLocal : .targetStaging
    static let buildProfile: LedgerBuildProfile = isLocal ? .targetLocalDevelopment : .targetStaging
    // User-authorized Ledger project in PPM, not a separate dev project. Public
    // client configuration only; this does not deploy schema or migrate data.
    static let projectId = isLocal ? "ledger_target_supabase_local" : "ybwviepljilrkrjoahbl"
    static let url = URL(string: isLocal ? "http://127.0.0.1:54321" : "https://ybwviepljilrkrjoahbl.supabase.co")!
    static let publishableKey = isLocal ? (localKey ?? "") : "sb_publishable_oAx8Wobv1rd1OZ9m_nrE1A_bOuo1T-H"
    static let callback = URL(string: "apps.nine4.ledger.staging://auth-callback")!
    // Exact user-authorized Ledger instance; no caller-controlled host override.
    static let powerSyncURL: URL? = URL(string: isLocal
        ? "http://127.0.0.1:5590"
        : "https://6aa8966802481fb31b96942c.powersync.journeyapps.com")
}

/// Uses the original entry forms and explicit selection. Offline selection is
/// limited to working sets previously authorized and downloaded on this device.
struct TargetWorkspaceSelection {
    let authorization: WorkspaceMembershipAuthorization
    let account: AccountSummary
    let offlineAdmission: OfflineWorkspaceAdmission?
}

struct TargetOnlineAccountEntryView: View {
    let environment: ValidatedLedgerEnvironment
    let workspace: (TargetWorkspaceSelection, SupabaseOnlineSignIn, @escaping () -> Void) -> AnyView
    private let makeEntry: (() throws -> SupabaseOnlineSignIn)?
    @State private var entry: SupabaseOnlineSignIn?
    @State private var directory: AuthorizedAccountListSnapshot?
    @State private var selection: TargetWorkspaceSelection?
    @State private var downloaded: [OfflineWorkspaceAdmission]?
    @State private var hasDownloadedAccounts = false
    @State private var loading = true
    @State private var failure: String?
    @State private var confirmEmail = false

    init(environment: ValidatedLedgerEnvironment,
         makeEntry: (() throws -> SupabaseOnlineSignIn)? = nil,
         workspace: @escaping (TargetWorkspaceSelection, SupabaseOnlineSignIn, @escaping () -> Void) -> AnyView) {
        self.environment = environment
        self.makeEntry = makeEntry
        self.workspace = workspace
    }

    private struct Choice: Identifiable {
        let account: AccountSummary
        var id: AccountID { account.id }
    }

    var body: some View {
        Group {
            if let selection, let entry {
                workspace(selection, entry) {
                    self.selection = nil
                    directory = nil
                    downloaded = nil
                    hasDownloadedAccounts = false
                    failure = nil
                }
            } else {
              ScrollView {
               VStack {
                if loading {
                ProgressView("Loading Accounts…")
            } else if let failure {
                ContentUnavailableView {
                    Label("Account access unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Retry") { Task { await loadAccounts() } }
                    Button("Use Downloaded Accounts") { showDownloadedAccounts() }
                    Button("Back to Sign In") { directory = nil; downloaded = nil; self.failure = nil }
                }
            } else if let downloaded, !downloaded.isEmpty {
                VStack(spacing: 0) {
                    AccountGatePresentation(accounts: downloaded.map { Choice(account: $0.account) },
                        isDiscovering: false, name: { $0.account.displayName.rawValue },
                        onSelect: { choice in selectDownloaded(choice.id) },
                        onCreate: {}, onSignOut: {}, canCreateAccount: false, canSignOut: false)
                    Text("Downloaded Accounts are available without internet.")
                        .font(.caption).foregroundStyle(.secondary).padding()
                    Button("Refresh Accounts Online") { Task { await loadAccounts() } }
                    Button("Sign In") { self.downloaded = nil }
                }
            } else if let directory {
                VStack(spacing: 0) {
                    AccountGatePresentation(accounts: directory.accounts.map(Choice.init),
                        isDiscovering: false, name: { $0.account.displayName.rawValue },
                        onSelect: { choice in Task { await select(choice.id, from: directory) } },
                        onCreate: {}, onSignOut: {}, canCreateAccount: false, canSignOut: false)
                    Text("Account creation and safe sign-out are not connected in this build.")
                        .font(.caption).foregroundStyle(.secondary).padding()
                }
            } else if let entry {
              VStack {
                AuthFormPresentation(onSignIn: { email, password in
                    try await entry.signIn(email: email, password: password)
                    await loadAccounts()
                }, onSignUp: { email, password in
                    switch try await entry.signUp(email: email, password: password) {
                    case .confirmEmail: confirmEmail = true
                    case .signedIn: await loadAccounts()
                    }
                }, onGoogleSignIn: {
                    try await entry.signInWithGoogle(redirectTo: TargetSupabaseConfiguration.callback)
                    await loadAccounts()
                })
                if hasDownloadedAccounts {
                    Button("Use Downloaded Accounts") { showDownloadedAccounts() }
                }
              }
            }
               }
              }
              .accessibilityIdentifier("target-account-entry-scroll")
            }
        }
        .task {
            guard entry == nil else { return }
            do {
                entry = try makeEntry?() ?? SupabaseOnlineSignIn(
                    supabaseURL: TargetSupabaseConfiguration.url,
                    publishableKey: TargetSupabaseConfiguration.publishableKey,
                    localDataNamespace: environment.manifest.localDataNamespacePrefix,
                    redirectTo: TargetSupabaseConfiguration.callback)
                try await recoverBeforeAccountEntry()
                if showDownloadedAccounts() { loading = false }
                else if entry?.hasStoredSession == true { await loadAccounts() }
                else { loading = false }
            } catch {
                failure = (error as? SupabaseOnlineSignIn.Failure) == .sessionRecoveryFailed
                    ? error.localizedDescription : "Ledger's sign-in configuration is unavailable."
                loading = false
            }
        }
        .alert("Check your email", isPresented: $confirmEmail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Confirm your email address, then return to sign in.")
        }
    }

    private func loadAccounts() async {
        guard let entry else { return }
        loading = true
        failure = nil
        defer { loading = false }
        do {
            try await recoverBeforeAccountEntry()
            directory = try await entry.accounts(environment: environment.manifest.environment).snapshot
            downloaded = nil
        }
        catch is CancellationError { return }
        catch SupabaseOnlineSignIn.Failure.noSession { directory = nil }
        catch SupabaseOnlineSignIn.Failure.sessionRecoveryFailed {
            directory = nil
            failure = SupabaseOnlineSignIn.Failure.sessionRecoveryFailed.localizedDescription
        }
        catch {
            directory = nil
            failure = "Could not load your Accounts. Retry or use available downloaded Accounts."
        }
    }

    private func recoverBeforeAccountEntry() async throws {
        guard let entry else { return }
        try await entry.recoverPendingSessionEnd(environment: environment) {
            try await PropertyManagementReportDelivery.recoverStartupScratch(requireNoActiveSessions: true)
            directory = nil
            downloaded = nil
            selection = nil
            hasDownloadedAccounts = false
        }
    }

    private func select(_ accountId: AccountID, from snapshot: AuthorizedAccountListSnapshot) async {
        guard let entry, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let intent = try AccountSelectionPolicy.makeIntent(selecting: accountId, from: snapshot, requestedAt: Date())
            let authorization = try await entry.authorize(intent)
            guard let account = snapshot.accounts.first(where: { $0.id == accountId }) else { return }
            selection = TargetWorkspaceSelection(authorization: authorization, account: account, offlineAdmission: nil)
        } catch is CancellationError { return }
        catch {
            directory = nil
            failure = "Ledger could not confirm access to this Account. Retry to refresh your Account list."
        }
    }

    @discardableResult private func showDownloadedAccounts() -> Bool {
        guard let entry else { return false }
        do {
            let available = try entry.downloadedWorkspaces(environment: environment.manifest.environment)
            hasDownloadedAccounts = !available.isEmpty
            guard !available.isEmpty else { return false }
            downloaded = available
            directory = nil
            failure = nil
            return true
        } catch {
            failure = "Downloaded Account access could not be verified. Local data and pending work have not been deleted."
            return false
        }
    }

    private func selectDownloaded(_ accountId: AccountID) {
        guard let entry, let admission = downloaded?.first(where: { $0.account.id == accountId }) else { return }
        do {
            try entry.requireOfflineAdmission(admission)
            selection = TargetWorkspaceSelection(authorization: admission.authorization,
                account: admission.account, offlineAdmission: admission)
        } catch {
            failure = "This downloaded Account cannot be opened. Local data and pending work are retained."
        }
    }
}
