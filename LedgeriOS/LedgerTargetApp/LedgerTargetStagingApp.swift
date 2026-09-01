import LedgerTargetCore
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
                diagnostics: dependencies.environment.diagnostics,
                failureCode: nil
            )
        } catch let failure as LedgerEnvironmentValidationFailure {
            rootView = TargetStagingRootView(
                diagnostics: nil,
                failureCode: failure.diagnosticCode
            )
        } catch {
            rootView = TargetStagingRootView(
                diagnostics: nil,
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
    let diagnostics: LedgerEnvironmentDiagnostics?
    let failureCode: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("STAGING • NO HOSTED SERVICES")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red)
                .accessibilityIdentifier("target-staging-banner")

            Group {
                if let diagnostics {
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
                            Text("This bootstrap shell validates isolation only. It cannot authenticate, sync, upload, migrate, or contact production.")
                        }
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
