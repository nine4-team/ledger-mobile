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
        ClientBrowsingStagingExerciseView(model: model.clientBrowser)
        ProjectBrowsingStagingExerciseView(model: model.projectBrowser)
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

    private var runtime: LedgerOfflineClientRuntime?
    private var startInProgress = false
    private let accountId = try! AccountID(validating: "account-primary")
    private let principalId = try! PrincipalID(validating: "principal-owner")
    let clientBrowser = ClientBrowsingStagingExercise(
        accountId: try! AccountID(validating: "account-primary")
    )
    let projectBrowser = ProjectBrowsingStagingExercise(
        accountId: try! AccountID(validating: "account-primary")
    )
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
            await clientBrowser.start(
                runtime: ClientBrowsingStagingRuntimeAdapter.adapt(runtime)
            )
            await projectBrowser.start(
                runtime: ProjectBrowsingStagingRuntimeAdapter.adapt(runtime)
            )
            databaseState = "Encrypted (\(cipher))"
            pendingUploadCount = String(pendingCount)
            await waitForCancellation()
            await clientBrowser.stop()
            await projectBrowser.stop()
            projectSetup.stop()
            openedRuntime = nil
            try await runtime.close()
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
        await clientBrowser.stop()
        await projectBrowser.stop()
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
