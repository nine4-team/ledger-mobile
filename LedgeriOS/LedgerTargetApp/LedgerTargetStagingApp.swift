import LedgerTargetCore
import LedgerTargetAppModel
import LedgerTargetPowerSync
import Observation
import SwiftUI

@main
struct LedgerTargetStagingApp: App {
    private let rootView: TargetStagingRootView

    init() {
        do {
            let dependencies = try TargetAppBootstrap.start(
                manifest: TargetStagingProjection.manifest,
                policy: TargetStagingProjection.policy
            ) { environment in
                TargetAppDependencies(environment: environment)
            }
            rootView = TargetStagingRootView(
                environment: dependencies.environment,
                failureCode: nil
            )
        } catch let failure as LedgerEnvironmentValidationFailure {
            rootView = TargetStagingRootView(
                environment: nil,
                failureCode: failure.diagnosticCode
            )
        } catch {
            rootView = TargetStagingRootView(
                environment: nil,
                failureCode: "target_startup_unknown_failure"
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }
}

private struct TargetStagingRootView: View {
    let environment: ValidatedLedgerEnvironment?
    let failureCode: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("LOCAL SPIKE • NO HOSTED SERVICES")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red)
                .accessibilityIdentifier("target-staging-banner")

            Group {
                if let environment {
                    let diagnostics = environment.diagnostics
                    List {
                        Section("Target Environment") {
                            LabeledContent("Environment", value: diagnostics.environment.rawValue)
                            LabeledContent("Build profile", value: diagnostics.buildProfile.rawValue)
                            LabeledContent("Bundle", value: diagnostics.bundleIdentifier)
                        }

                        Section("Contract Versions") {
                            LabeledContent("Schema", value: diagnostics.contractVersions.schema)
                            LabeledContent("Query", value: diagnostics.contractVersions.query)
                            LabeledContent("Operation", value: diagnostics.contractVersions.operation)
                            LabeledContent("Sync", value: diagnostics.contractVersions.sync)
                        }

                        Section("Provisioning") {
                            Text("This build uses encrypted PowerSync storage and an isolated local Supabase schema. Hosted sync and production access are disabled.")
                        }

                        OfflineProviderSpikeView(environment: environment)
                    }
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

private struct OfflineProviderSpikeView: View {
    let environment: ValidatedLedgerEnvironment
    @State private var model = OfflineClientSpikeModel()

    var body: some View {
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
        ProjectSetupStagingExerciseView(model: model.projectSetup)
        Section("Local Client & Project Browser") {
            LabeledContent("Client data", value: model.clientDirectoryStatus)
            LabeledContent("Project data", value: model.projectDirectoryStatus)
            LabeledContent("Selectable Clients", value: String(model.selectableClients.count))
            LabeledContent("Active Projects", value: String(model.activeProjects.count))
            ForEach(model.activeProjects, id: \.projectId) { row in
                Button {
                    Task { await model.openProject(row.projectId, segment: .active) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(row.projectDisplayName.rawValue)
                        Text(row.clientDisplayName.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Archived Projects", value: String(model.archivedProjects.count))
            ForEach(model.archivedProjects, id: \.projectId) { row in
                Button {
                    Task { await model.openProject(row.projectId, segment: .archived) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(row.projectDisplayName.rawValue)
                        Text(row.clientDisplayName.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let selectedProjectDetails = model.selectedProjectDetails {
                LabeledContent("Selected Project", value: selectedProjectDetails)
            }
            if let directoryDiagnostic = model.directoryDiagnostic {
                Text(directoryDiagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-directory-diagnostic")
            }
        }
        .task {
            await model.start(validatedEnvironment: environment)
        }
    }
}

@MainActor
@Observable
private final class OfflineClientSpikeModel {
    var displayName = ""
    private(set) var databaseState = "Opening…"
    private(set) var pendingUploadCount = "—"
    private(set) var lastCreatedName: String?
    private(set) var diagnostic: String?
    private(set) var selectableClients: [ClientSummary] = []
    private(set) var activeProjects: [ProjectDirectoryCoreRow] = []
    private(set) var archivedProjects: [ProjectDirectoryCoreRow] = []
    private(set) var selectedProjectDetails: String?
    private(set) var directoryDiagnostic: String?
    private(set) var clientDirectoryStatus = "loading"
    private(set) var projectDirectoryStatus = "loading"

    private var runtime: LedgerOfflineClientRuntime?
    private var startInProgress = false
    private var activeProjectDirectory: ProjectDirectoryPresentationSnapshot?
    private var archivedProjectDirectory: ProjectDirectoryPresentationSnapshot?
    private var projectDetailsTask: Task<Void, Never>?
    private let accountId = try! AccountID(validating: "account-primary")
    private let principalId = try! PrincipalID(validating: "principal-owner")
    let projectSetup = ProjectSetupStagingExercise(
        accountId: try! AccountID(validating: "account-primary"),
        actorPrincipalId: try! PrincipalID(validating: "principal-owner"),
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

    var canCreate: Bool {
        runtime != nil && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start(validatedEnvironment: ValidatedLedgerEnvironment) async {
        guard runtime == nil, !startInProgress else { return }
        startInProgress = true
        defer { startInProgress = false }
        var openedRuntime: LedgerOfflineClientRuntime?
        do {
            let runtime = try await LedgerPowerSyncLocalBootstrap.open(
                validatedEnvironment: validatedEnvironment,
                principalId: principalId,
                accountId: accountId
            )
            openedRuntime = runtime
            let cipher = try await runtime.encryptionCipher()
            let pendingCount = try await runtime.pendingUploadCount()
            self.runtime = runtime
            projectSetup.start(runtime: ProjectSetupStagingRuntimeAdapter.adapt(runtime))
            databaseState = "Encrypted (\(cipher))"
            pendingUploadCount = String(pendingCount)
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    await self?.watchClientDirectory(runtime)
                }
                group.addTask { [weak self] in
                    await self?.watchProjectDirectory(runtime)
                }
                await group.waitForAll()
            }
            projectDetailsTask?.cancel()
            projectSetup.stop()
            try await runtime.close()
            openedRuntime = nil
            self.runtime = nil
            databaseState = "Closed"
        } catch is CancellationError {
            await closeAfterFailedStart(openedRuntime)
            databaseState = "Closed"
        } catch {
            await closeAfterFailedStart(openedRuntime)
            databaseState = "Unavailable"
            diagnostic = "local_runtime_failed"
        }
    }

    private func closeAfterFailedStart(_ openedRuntime: LedgerOfflineClientRuntime?) async {
        projectDetailsTask?.cancel()
        projectSetup.stop()
        if let openedRuntime {
            try? await openedRuntime.close()
        }
        runtime = nil
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

    func openProject(_ projectId: ProjectID, segment: ProjectDirectorySegment) async {
        guard let runtime else { return }
        projectDetailsTask?.cancel()
        selectedProjectDetails = nil
        directoryDiagnostic = nil
        let presentation = segment == .active
            ? activeProjectDirectory
            : archivedProjectDirectory
        guard let presentation else {
            directoryDiagnostic = "project_directory_not_loaded"
            return
        }
        do {
            let selection = try presentation.selection(projectId: projectId)
            let request = try selection.detailRequest(validating: presentation)
            projectDetailsTask = Task { [weak self] in
                do {
                    for try await update in runtime.watchProject(request) {
                        let header = try ProjectDetailHeaderPresentationProjector.project(
                            update,
                            validating: request
                        )
                        if let content = header.state.content {
                            self?.selectedProjectDetails =
                                "\(content.projectDisplayName.rawValue) — \(content.clientDisplayName.rawValue)"
                            return
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self?.directoryDiagnostic = "project_detail_local_failed"
                }
            }
        } catch {
            directoryDiagnostic = "project_directory_selection_invalid"
        }
    }

    private func watchClientDirectory(_ runtime: LedgerOfflineClientRuntime) async {
        do {
            for try await directory in runtime.watchClients() {
                let selection = try ProjectExistingClientSelectionSnapshot(directory: directory)
                selectableClients = selection.activeClients
                clientDirectoryStatus = Self.directoryStatus(
                    quality: directory.local.quality,
                    isComplete: directory.local.isCompleteForQuery
                )
            }
        } catch is CancellationError {
            return
        } catch {
            directoryDiagnostic = "client_directory_local_failed"
        }
    }

    private func watchProjectDirectory(_ runtime: LedgerOfflineClientRuntime) async {
        do {
            for try await directory in runtime.watchProjects() {
                projectDirectoryStatus = Self.directoryStatus(
                    quality: directory.local.quality,
                    isComplete: directory.local.isCompleteForQuery
                )
                let active = try ProjectDirectoryPresentationProjector.project(
                    directory,
                    segment: .active
                )
                let archived = try ProjectDirectoryPresentationProjector.project(
                    directory,
                    segment: .archived
                )
                activeProjectDirectory = active
                archivedProjectDirectory = archived
                activeProjects = active.rows
                archivedProjects = archived.rows
            }
        } catch is CancellationError {
            return
        } catch {
            directoryDiagnostic = "project_directory_local_failed"
        }
    }

    private static func directoryStatus(
        quality: ListSnapshotQuality,
        isComplete: Bool
    ) -> String {
        "\(quality.rawValue) • \(isComplete ? "complete" : "incomplete")"
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
        .auth: "unprovisioned-auth-staging",
        .structuredData: "unprovisioned-supabase-staging",
        .powerSync: "unprovisioned-powersync-staging",
        .storage: "unprovisioned-storage-staging",
        .mcp: "unprovisioned-mcp-staging",
        .telemetry: "unprovisioned-telemetry-staging",
        .externalRoutes: "unprovisioned-routes-staging",
        .updateFeed: "unprovisioned-updates-staging"
    ]

    static let manifest = LedgerEnvironmentManifest(
        environment: .targetStaging,
        buildProfile: .targetStaging,
        bundleIdentifier: "apps.nine4.ledger.staging",
        displayName: "Ledger STAGING",
        localDataNamespacePrefix: "apps.nine4.ledger.target",
        contractVersions: versions,
        resources: LedgerTargetComponent.allCases.map { component in
            LedgerEnvironmentResource(
                component: component,
                environment: .targetStaging,
                publicIdentifier: resources[component]!
            )
        }
    )

    static let policy = LedgerEnvironmentPolicy(
        expectedEnvironment: .targetStaging,
        expectedBuildProfile: .targetStaging,
        expectedBundleIdentifier: "apps.nine4.ledger.staging",
        expectedContractVersions: versions,
        allowedResourceIdentifiers: resources.mapValues { [$0] },
        forbiddenResourceIdentifiers: [],
        forbiddenBundleIdentifiers: []
    )
}
