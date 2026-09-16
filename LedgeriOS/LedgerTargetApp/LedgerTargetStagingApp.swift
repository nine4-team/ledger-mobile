import LedgerTargetCore
import LedgerTargetAppModel
import LedgerTargetPowerSync
import Observation
import SwiftUI

@main
struct LedgerTargetStagingApp: App {
    private let rootView: AnyView
    @State private var reportCleanupFailed = false

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-capture-batch") {
            rootView = AnyView(MediaCaptureBatchUITestFixture())
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-transaction-card") {
            rootView = AnyView(TransactionCardUITestFixture())
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-transaction-browser") {
            rootView = AnyView(TransactionBrowserUITestFixture(projectPayment:
                ProcessInfo.processInfo.arguments.contains("--project-payment")))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-transaction-audit") {
            rootView = AnyView(TransactionAuditPanelUITestFixture())
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-workspace-checklist") {
            rootView = AnyView(ActiveWorkspaceChecklistUITestFixtureView())
            return
        }
        #endif
        do {
            guard !TargetSupabaseConfiguration.isLocal
                || TargetSupabaseConfiguration.publishableKey.hasPrefix("sb_publishable_") else {
                throw LedgerEnvironmentValidationFailure.unsafeResourceIdentifier(.auth)
            }
            let dependencies = try TargetAppBootstrap.start(
                manifest: TargetStagingProjection.manifest,
                policy: TargetStagingProjection.policy
            ) { environment in
                TargetAppDependencies(environment: environment)
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-transaction-capture"),
               let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--capture-fixture-id=") }),
               let fixtureID = UUID(uuidString: String(argument.dropFirst("--capture-fixture-id=".count))) {
                rootView = AnyView(TransactionCaptureUITestFixture(environment: dependencies.environment, fixtureID: fixtureID))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-offline-entry") {
                rootView = AnyView(OfflineAccountEntryUITestFixture(environment: dependencies.environment))
                return
            }
            #endif
            rootView = AnyView(TargetStagingRootView(
                environment: dependencies.environment,
                failureCode: nil
            ))
        } catch let failure as LedgerEnvironmentValidationFailure {
            rootView = AnyView(TargetStagingRootView(
                environment: nil,
                failureCode: failure.diagnosticCode
            ))
        } catch {
            rootView = AnyView(TargetStagingRootView(
                environment: nil,
                failureCode: "target_startup_unknown_failure"
            ))
        }
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .task {
                    do { try await PropertyManagementReportDelivery.recoverStartupScratch() }
                    catch { reportCleanupFailed = true }
                }
                .alert("Report cleanup could not finish", isPresented: $reportCleanupFailed) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Some temporary report files could not be cleaned up. Ledger will retry before the next export. Original documents and saved exports are unchanged.")
                }
        }
    }
}
private struct TargetStagingRootView: View {
    let environment: ValidatedLedgerEnvironment?
    let failureCode: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("SUPABASE IMPLEMENTATION • NOT RELEASE READY")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red)
                .accessibilityIdentifier("target-staging-banner")

            Group {
                if let environment {
                    let diagnostics = environment.diagnostics
                      VStack(alignment: .leading, spacing: 16) {
                        LabeledContent("Environment", value: diagnostics.environment.rawValue)
                        DisclosureGroup("Build diagnostics") {
                            LabeledContent("Build profile", value: diagnostics.buildProfile.rawValue)
                            LabeledContent("Bundle", value: diagnostics.bundleIdentifier)
                            LabeledContent("Schema", value: diagnostics.contractVersions.schema)
                            LabeledContent("Query", value: diagnostics.contractVersions.query)
                            LabeledContent("Operation", value: diagnostics.contractVersions.operation)
                            LabeledContent("Sync", value: diagnostics.contractVersions.sync)
                            Text("Sign-in is configured for Ledger's Supabase project. Hosted database setup, live sync and offline startup are not complete. Do not use this build for real work.")
                        }

                        TargetOnlineAccountEntryView(environment: environment) { selection, entry, signedOut in
                            AnyView(OfflineProviderSpikeView(environment: environment, selection: selection, entry: entry, signedOut: signedOut))
                        }
                      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding()
                } else {
                    ContentUnavailableView(
                        "Target Startup Refused",
                        systemImage: "exclamationmark.shield",
                        description: Text(failureCode ?? "target_startup_unknown_failure")
                    )
                }
            }
        }
    }
}

struct OfflineProviderSpikeView: View {
    let environment: ValidatedLedgerEnvironment
    let entry: SupabaseOnlineSignIn
    let signedOut: () -> Void
    @State private var model: OfflineClientSpikeModel

    init(environment: ValidatedLedgerEnvironment, selection: TargetWorkspaceSelection, entry: SupabaseOnlineSignIn, signedOut: @escaping () -> Void) {
        self.environment = environment
        self.entry = entry
        self.signedOut = signedOut
        let authorization = selection.authorization
        _model = State(initialValue: OfflineClientSpikeModel(authorization: authorization, prepareWorkspace: { runtime in
            if let admission = selection.offlineAdmission {
                try entry.requireOfflineAdmission(admission)
                try await runtime.requireMatchingDownloadedMembership(authorization)
                if let endpoint = TargetSupabaseConfiguration.powerSyncURL, entry.hasStoredSession {
                    try await entry.startWorkspaceSync(runtime, authorization: authorization, powerSyncURL: endpoint)
                }
            } else {
                guard let endpoint = TargetSupabaseConfiguration.powerSyncURL else {
                    throw SupabaseOnlineSignIn.Failure.syncNotConfigured
                }
                try await entry.startWorkspaceSync(runtime, authorization: authorization, powerSyncURL: endpoint)
                try await entry.rememberDownloadedWorkspace(authorization, account: selection.account, runtime: runtime)
            }
        }, finishRemoval: {
            try await entry.finishReportedWorkspaceRemoval(authorization)
        }))
    }

    var body: some View {
        WorkspaceAccessGate(access: model.access) {
        NavigationStack {
        ScrollView {
        VStack {
            workspaceContent
        }
        }
        .itemThumbnailViewport()
        .accessibilityIdentifier("target-workspace-scroll")
        }
        }
        .task { await model.start(validatedEnvironment: environment) }
        .onChange(of: model.access.isLocked) { _, locked in
            if locked { model.activeWorkspaceToSpaceChecklist.closeVendorDocumentReview() }
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        Section("Offline Client Creation") {
            TextField("Client name", text: $model.displayName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("target-client-name")

            Button("Create while offline") {
                Task { await model.createClient() }
            }
            .disabled(!model.canCreate)
            .accessibilityIdentifier("target-create-client")

            LabeledContent("Local database", value: model.databaseState)
            LabeledContent("Pending uploads", value: model.pendingUploadCount)
            if let lastCreatedName = model.lastCreatedName {
                LabeledContent("Local result", value: lastCreatedName)
            }
            if let diagnostic = model.diagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-client-diagnostic")
            }
        }
        SpaceAssignmentDestinationStagingExerciseView(model: model.spaceDestinations)
        SpaceBrowserStagingExerciseView(
            model: model.spaceBrowser,
            checklistToggle: model.spaceChecklistToggle,
            checklistEditor: model.spaceChecklistEditor,
            representedProjectId: model.projectBrowser.selectedProjectId,
            openProject: { projectId in
                Task { await model.openProjectSpaces(projectId) }
            },
            openBusinessInventory: {
                Task { await model.openBusinessInventorySpaces() }
            }
        )
        ActiveWorkspaceToSpaceChecklistStagingView(
            model: model.activeWorkspaceToSpaceChecklist,
            accountCurrency: model.projectSetup.accountCurrency,
            onSignOut: {
                try await model.signOut(entry: entry, environment: environment)
                signedOut()
            }, pendingWork: model.pendingWork, onEndSession: { request in
                try await model.signOut(entry: entry, environment: environment, request: request)
                signedOut()
            }
        )
        TransferDestinationSelectionStagingExerciseView(
            model: model.transferDestinations
        )
        ClientBrowsingStagingExerciseView(
            model: model.clientBrowser,
            archive: model.clientArchive
        )
        ProjectBrowsingStagingExerciseView(
            model: model.projectBrowser,
            archive: model.projectArchive,
            projectSetup: model.projectSetup
        )
        if let pendingWork = model.pendingWork {
            AccountPendingWorkStagingExerciseView(model: pendingWork)
        }
    }
}

@MainActor
@Observable
private final class OfflineClientSpikeModel {
    let access = WorkspaceAccessPresentation()
    var displayName = ""
    private(set) var databaseState = "Opening…"
    private(set) var pendingUploadCount = "—"
    private(set) var lastCreatedName: String?
    private(set) var diagnostic: String?

    private var runtime: LedgerOfflineClientRuntime?
    private(set) var pendingWork: AccountPendingWorkStagingExercise?
    private var startInProgress = false
    private let accountId: AccountID
    private let principalId: PrincipalID
    private let authorization: WorkspaceMembershipAuthorization
    private let prepareWorkspace: @MainActor (LedgerOfflineClientRuntime) async throws -> Void
    private let finishRemoval: @MainActor () async throws -> Void
    private var removalCleanup: Task<Void, Never>?
    let clientBrowser: ClientBrowsingStagingExercise
    let clientArchive: ClientArchiveBrowserStagingExercise
    let projectBrowser: ProjectBrowsingStagingExercise
    let projectArchive: ProjectArchiveBrowserStagingExercise
    let projectSetup: ProjectSetupStagingExercise
    let spaceDestinations: SpaceAssignmentDestinationStagingExercise
    let spaceBrowser: SpaceBrowserStagingExercise
    let spaceChecklistToggle: SpaceChecklistItemToggleStagingExercise
    let spaceChecklistEditor: SpaceChecklistEditorStagingExercise
    let activeWorkspaceToSpaceChecklist: ActiveWorkspaceToSpaceChecklistStagingExercise
    let transferDestinations: TransferDestinationSelectionStagingExercise

    init(authorization: WorkspaceMembershipAuthorization,
         prepareWorkspace: @escaping @MainActor (LedgerOfflineClientRuntime) async throws -> Void,
         finishRemoval: @escaping @MainActor () async throws -> Void) {
        self.authorization = authorization
        self.prepareWorkspace = prepareWorkspace
        self.finishRemoval = finishRemoval
        let accountId = authorization.accountId
        let principalId = authorization.principalId
        let projectBrowser = ProjectBrowsingStagingExercise(accountId: accountId)
        let activeWorkspaceProjectBrowser = ProjectBrowsingStagingExercise(accountId: accountId)

        self.accountId = accountId
        self.principalId = principalId
        let clientBrowser = ClientBrowsingStagingExercise(accountId: accountId)
        self.clientBrowser = clientBrowser
        clientArchive = ClientArchiveBrowserStagingExercise(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: try! OperationContractVersion(
                validating: "client-archive-v1"
            ),
            browser: clientBrowser,
            makeIdentity: {
                try ClientArchiveSubmissionIdentity(
                    operationId: ClientArchiveOperationIdentity.make(
                        accountId: accountId,
                        uuid: UUID()
                    )
                )
            },
            now: Date.init
        )
        self.projectBrowser = projectBrowser
        projectArchive = ProjectArchiveBrowserStagingExercise(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: try! OperationContractVersion(
                validating: "project-archive-v1"
            ),
            browser: projectBrowser,
            makeIdentity: {
                try ProjectArchiveSubmissionIdentity(
                    operationId: ProjectArchiveOperationIdentity.make(
                        accountId: accountId,
                        uuid: UUID()
                    )
                )
            },
            now: Date.init
        )
        projectSetup = ProjectSetupStagingExercise(
            accountId: accountId,
            accountCurrency: try! CurrencyCode(validating: "USD"),
            actorPrincipalId: principalId,
            operationContractVersion: try! OperationContractVersion(
                validating: "project-create-v1"
            ),
            makeIdentity: {
                try ProjectSetupSubmissionIdentity(
                    projectId: ProjectID(
                        validating: "project-\(UUID().uuidString.lowercased())"
                    ),
                    operationId: OperationID(
                        validating: "operation-\(UUID().uuidString.lowercased())"
                    )
                )
            },
            now: Date.init
        )
        spaceDestinations = SpaceAssignmentDestinationStagingExercise(accountId: accountId)
        spaceBrowser = SpaceBrowserStagingExercise(accountId: accountId)
        func makeChecklistToggle() -> SpaceChecklistItemToggleStagingExercise {
            SpaceChecklistItemToggleStagingExercise(
                accountId: accountId,
                actorPrincipalId: principalId,
                operationContractVersion: try! OperationContractVersion(
                    validating: "space-checklist-revision-v1"
                ),
                makeIdentity: {
                    SpaceChecklistItemToggleSubmissionIdentity(
                        operationId: try SpaceChecklistRevisionOperationIdentity.make(
                            accountId: accountId,
                            uuid: UUID()
                        )
                    )
                },
                now: Date.init
            )
        }
        let checklistToggle = makeChecklistToggle()
        spaceChecklistToggle = checklistToggle
        activeWorkspaceToSpaceChecklist = ActiveWorkspaceToSpaceChecklistStagingExercise(
            accountId: accountId,
            projectBrowser: activeWorkspaceProjectBrowser,
            spaceBrowser: SpaceBrowserStagingExercise(accountId: accountId),
            checklistToggle: makeChecklistToggle()
        )
        spaceChecklistEditor = SpaceChecklistEditorStagingExercise(
            coordinator: checklistToggle,
            makeChecklistId: {
                try SpaceChecklistID(
                    validating: "checklist-\(UUID().uuidString.lowercased())"
                )
            },
            makeItemId: {
                try SpaceChecklistItemID(
                    validating: "checklist-item-\(UUID().uuidString.lowercased())"
                )
            }
        )
        transferDestinations = TransferDestinationSelectionStagingExercise(
            accountId: accountId
        )
    }

    var canCreate: Bool {
        runtime != nil && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start(validatedEnvironment: ValidatedLedgerEnvironment) async {
        guard runtime == nil, !startInProgress, !access.isLocked else { return }
        startInProgress = true
        defer {
            startInProgress = false
            access.stop()
        }
        var openedRuntime: LedgerOfflineClientRuntime?
        do {
            let runtime = try await LedgerPowerSyncLocalBootstrap.open(
                validatedEnvironment: validatedEnvironment,
                principalId: principalId,
                accountId: accountId
            )
            openedRuntime = runtime
            databaseState = "Opening authorized workspace…"
            // Subscribe before sync startup: denial can arrive while the first
            // download is still pending. Never drain from an SDK callback.
            let removals = runtime.watchAccessRemoval()
            let finishRemoval = self.finishRemoval
            removalCleanup = Task { [weak self] in
                for await _ in removals {
                    guard !Task.isCancelled else { return }
                    self?.access.showRemoval()
                    do { try await finishRemoval() }
                    catch {
                        self?.diagnostic = "Account access is locked, but removal cleanup could not finish. Pending work is retained."
                    }
                    return
                }
            }
            try await prepareWorkspace(runtime)
            let cipher = try await runtime.encryptionCipher()
            let pendingCount = try await runtime.pendingUploadCount()
            self.runtime = runtime
            pendingWork = AccountPendingWorkStagingExercise(
                expectedEnvironment: validatedEnvironment.manifest.environment,
                expectedPrincipalId: principalId,
                expectedAccountId: accountId,
                runtime: AccountPendingWorkStagingRuntimeAdapter.adapt(runtime)
            )
            await projectSetup.start(runtime: ProjectSetupStagingRuntimeAdapter.adapt(runtime))
            await spaceDestinations.open(
                scope: .businessInventory,
                runtime: SpaceAssignmentDestinationStagingRuntimeAdapter.adapt(runtime)
            )
            await spaceBrowser.start(
                scope: .businessInventory,
                runtime: SpaceBrowserStagingRuntimeAdapter.adapt(runtime)
            )
            await spaceChecklistToggle.start(
                runtime: SpaceChecklistItemToggleStagingRuntimeAdapter.adapt(runtime)
            )
            await activeWorkspaceToSpaceChecklist.start(
                runtime: ActiveWorkspaceToSpaceChecklistStagingRuntimeAdapter.adapt(runtime)
            )
            await spaceChecklistEditor.start()
            await clientBrowser.start(
                runtime: ClientBrowsingStagingRuntimeAdapter.adapt(runtime)
            )
            await clientArchive.start(
                runtime: ClientArchiveBrowserStagingRuntimeAdapter.adapt(runtime)
            )
            await projectBrowser.start(
                runtime: ProjectBrowsingStagingRuntimeAdapter.adapt(runtime)
            )
            await projectArchive.start(
                runtime: ProjectArchiveBrowserStagingRuntimeAdapter.adapt(runtime)
            )
            databaseState = "Encrypted (\(cipher))"
            pendingUploadCount = String(pendingCount)
            await waitForCancellation()
            let pendingWork = self.pendingWork
            self.pendingWork = nil
            await pendingWork?.stop()
            await projectArchive.stop()
            await clientArchive.stop()
            await clientBrowser.stop()
            await projectBrowser.stop()
            await projectSetup.stop()
            await spaceDestinations.stop()
            await spaceBrowser.stop()
            await spaceChecklistEditor.stop()
            await spaceChecklistToggle.stop()
            await activeWorkspaceToSpaceChecklist.stop()
            await transferDestinations.stop()
            openedRuntime = nil
            try await runtime.close()
            await stopRemovalCleanup()
            self.runtime = nil
            databaseState = "Closed"
        } catch is CancellationError {
            await closeAfterFailedStart(openedRuntime)
            databaseState = "Closed"
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure
            where failure.stage == .workspaceAccessRemoved {
            access.showRemoval()
            await closeAfterFailedStart(openedRuntime)
            databaseState = "Access removed"
            diagnostic = failure.diagnosticCode
        } catch SupabaseOnlineSignIn.Failure.syncNotConfigured {
            await closeAfterFailedStart(openedRuntime)
            databaseState = "Sync not configured"
            diagnostic = "The PowerSync service still needs setup. No downloaded data or pending work was deleted."
        } catch LedgerOfflineClientRuntimeFailure.workspaceMembershipNotReady {
            await closeAfterFailedStart(openedRuntime)
            databaseState = "Waiting for access data"
            diagnostic = "Account data must finish syncing or access reconciliation before this workspace can open. Existing data and pending work are retained."
        } catch {
            await closeAfterFailedStart(openedRuntime)
            databaseState = access.isLocked ? "Access removed" : "Unavailable"
            diagnostic = diagnostic ?? "local_runtime_failed"
        }
    }

    private func stopPresentation() async {
        let pendingWork = self.pendingWork
        self.pendingWork = nil
        await pendingWork?.stop()
        await projectArchive.stop()
        await clientArchive.stop()
        await clientBrowser.stop()
        await projectBrowser.stop()
        await projectSetup.stop()
        await spaceDestinations.stop()
        await spaceBrowser.stop()
        await spaceChecklistEditor.stop()
        await spaceChecklistToggle.stop()
        await activeWorkspaceToSpaceChecklist.stop()
        await transferDestinations.stop()
        displayName = ""
        lastCreatedName = nil
        pendingUploadCount = "—"
    }

    func signOut(entry: SupabaseOnlineSignIn, environment: ValidatedLedgerEnvironment,
                 request: SessionEndRequest? = nil) async throws {
        guard let runtime else { throw SupabaseOnlineSignIn.Failure.noSession }
        let ender = entry.sessionEnding(runtime: runtime, authorization: authorization,
            environment: environment) { [self] in
                await stopPresentation()
                try await PropertyManagementReportDelivery.recoverStartupScratch(requireNoActiveSessions: true)
            }
        if let request { try await ender.endSession(request) }
        else {
            let summary = try await ender.pendingWorkSummary()
            let clean = try SessionEndRequest(disposition: .ordinaryCleanLogout,
                expectedSummary: summary, requestedAt: Date())
            try await ender.endSession(clean)
        }
        await stopRemovalCleanup()
        self.runtime = nil
        databaseState = "Signed out"
    }

    private func closeAfterFailedStart(_ openedRuntime: LedgerOfflineClientRuntime?) async {
        await stopPresentation()
        if let openedRuntime {
            try? await openedRuntime.close()
        }
        await stopRemovalCleanup()
        runtime = nil
    }

    private func stopRemovalCleanup() async {
        let task = removalCleanup
        removalCleanup = nil
        task?.cancel()
        await task?.value
    }

    func openProjectSpaces(_ projectId: ProjectID) async {
        guard let runtime else { return }
        await spaceBrowser.start(
            scope: .project(projectId),
            runtime: SpaceBrowserStagingRuntimeAdapter.adapt(runtime)
        )
    }

    func openBusinessInventorySpaces() async {
        guard let runtime else { return }
        await spaceBrowser.start(
            scope: .businessInventory,
            runtime: SpaceBrowserStagingRuntimeAdapter.adapt(runtime)
        )
    }

    func createClient() async {
        guard let runtime else { return }
        diagnostic = nil
        do {
            let clientId = try ClientID(
                validating: "client-\(UUID().uuidString.lowercased())"
            )
            let command = try CreateClientCommand(
                operationId: OperationID(
                    validating: "operation-\(UUID().uuidString.lowercased())"
                ),
                draft: ClientCreationDraft(
                    accountId: accountId,
                    actorPrincipalId: principalId,
                    operationContractVersion: OperationContractVersion(
                        validating: "client-create-v1"
                    ),
                    clientId: clientId,
                    displayName: ClientDisplayName(validating: displayName),
                    capturedAt: Date()
                )
            )
            _ = try await runtime.createClient(command)
            pendingUploadCount = String(try await runtime.pendingUploadCount())

            let request = try ClientCoreDetailsRequest(
                accountId: accountId,
                clientId: clientId
            )
            for try await update in runtime.watchClient(request) {
                if case .snapshot(let snapshot) = update.state,
                   let client = snapshot.row?.client {
                    lastCreatedName = "\(client.displayName.rawValue) — queued locally"
                    break
                }
            }
            displayName = ""
        } catch let failure as ClientCreationFailure {
            diagnostic = failure.diagnosticCode
        } catch {
            diagnostic = "client_creation_local_failed"
        }
    }

    private func waitForCancellation() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
}

private enum TargetStagingProjection {
    static let versions = LedgerContractVersions(
        schema: "unprovisioned-1",
        query: "unprovisioned-1",
        operation: "unprovisioned-1",
        sync: "unprovisioned-1"
    )

    static let resources: [LedgerTargetComponent: String] = [
        .auth: TargetSupabaseConfiguration.projectId,
        .structuredData: TargetSupabaseConfiguration.projectId,
        .powerSync: TargetSupabaseConfiguration.isLocal ? "ledger_powersync_local" : "unprovisioned-powersync-staging",
        .storage: TargetSupabaseConfiguration.projectId,
        .mcp: "unprovisioned-mcp-staging",
        .telemetry: "unprovisioned-telemetry-staging",
        .externalRoutes: "unprovisioned-routes-staging",
        .updateFeed: "unprovisioned-updates-staging"
    ]

    static let manifest = LedgerEnvironmentManifest(
        environment: TargetSupabaseConfiguration.environment,
        buildProfile: TargetSupabaseConfiguration.buildProfile,
        bundleIdentifier: "apps.nine4.ledger.staging",
        displayName: TargetSupabaseConfiguration.isLocal ? "Ledger LOCAL" : "Ledger STAGING",
        localDataNamespacePrefix: TargetSupabaseConfiguration.isLocal ? "apps.nine4.ledger.target.local" : "apps.nine4.ledger.target",
        contractVersions: versions,
        resources: LedgerTargetComponent.allCases.map { component in
            LedgerEnvironmentResource(
                component: component,
                environment: TargetSupabaseConfiguration.environment,
                publicIdentifier: resources[component]!
            )
        }
    )

    static let policy = LedgerEnvironmentPolicy(
        expectedEnvironment: TargetSupabaseConfiguration.environment,
        expectedBuildProfile: TargetSupabaseConfiguration.buildProfile,
        expectedBundleIdentifier: "apps.nine4.ledger.staging",
        expectedContractVersions: versions,
        allowedResourceIdentifiers: resources.mapValues { [$0] },
        forbiddenResourceIdentifiers: [],
        forbiddenBundleIdentifiers: []
    )
}
