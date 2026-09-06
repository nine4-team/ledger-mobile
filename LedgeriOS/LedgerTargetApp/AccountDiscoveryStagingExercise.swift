import LedgerTargetCore
import Observation
import SwiftUI

/// Build-only exercise for the backend-neutral AccountQuerying boundary. The
/// staging root does not instantiate this view until workspace activation is a
/// separately approved slice.
struct AccountDiscoveryStagingExercise: View {
    @State private var model: AccountDiscoveryStagingModel

    init(
        query: any AccountQuerying,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID
    ) {
        _model = State(initialValue: AccountDiscoveryStagingModel(
            query: query,
            environment: environment,
            principalId: principalId
        ))
    }

    var body: some View {
        Section("Local Account Discovery") {
            LabeledContent("State", value: model.stateLabel)

            if model.accounts.isEmpty {
                Text(model.emptyStateLabel)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.accounts, id: \.id) { account in
                    Button {
                        model.select(account.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(account.displayName.rawValue)
                            Text(account.id.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("target-account-\(account.id.rawValue)")
                }
            }

            if let selectedAccountId = model.selectedAccountId {
                LabeledContent("Local selection intent", value: selectedAccountId.rawValue)
                Text("Selection is local evidence, not current server authorization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let diagnosticCode = model.diagnosticCode {
                Text(diagnosticCode)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-account-discovery-diagnostic")
            }
        }
        .task { model.start() }
        .onDisappear { model.stop() }
    }
}

@MainActor
@Observable
private final class AccountDiscoveryStagingModel {
    private(set) var update: AuthorizedAccountDiscoveryUpdate = .waiting(.notRequested)
    private(set) var selectionIntent: WorkspaceSelectionIntent?
    private(set) var diagnosticCode: String?

    private let query: any AccountQuerying
    private let environment: LedgerEnvironmentKind
    private let principalId: PrincipalID
    private var observationTask: Task<Void, Never>?

    init(
        query: any AccountQuerying,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID
    ) {
        self.query = query
        self.environment = environment
        self.principalId = principalId
    }

    var accounts: [AccountSummary] {
        currentSnapshot?.accounts ?? []
    }

    var selectedAccountId: AccountID? {
        selectionIntent?.accountId
    }

    var stateLabel: String {
        switch update {
        case .waiting(.notRequested): "not-requested"
        case .waiting(.loading): "loading"
        case .snapshot(let snapshot): snapshot.quality.rawValue
        case .failed(let failure, _): "failed-\(failure.rawValue)"
        }
    }

    var emptyStateLabel: String {
        switch update {
        case .snapshot(let snapshot) where snapshot.isAuthoritativeEmpty:
            "No authorized Accounts"
        case .snapshot:
            "No complete local Account result yet"
        case .failed:
            "Account discovery unavailable"
        case .waiting:
            "Waiting for local Account data"
        }
    }

    func start() {
        guard observationTask == nil else { return }
        update = .waiting(.loading)
        observationTask = Task {
            do {
                for try await next in query.watchAuthorizedAccounts(
                    environment: environment,
                    principalId: principalId
                ) {
                    update = next
                    discardSelectionIfSnapshotChanged()
                }
            } catch {
                update = .failed(failure: .retryable, cached: currentSnapshot)
                diagnosticCode = "account_discovery_staging_unavailable"
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    func select(_ accountId: AccountID) {
        guard let snapshot = currentSnapshot else {
            diagnosticCode = "account_discovery_snapshot_unavailable"
            return
        }
        do {
            selectionIntent = try AccountSelectionPolicy.makeIntent(
                selecting: accountId,
                from: snapshot,
                requestedAt: max(Date(), snapshot.asOf)
            )
            diagnosticCode = nil
        } catch let failure as AccountDiscoverySelectionFailure {
            selectionIntent = nil
            diagnosticCode = failure.diagnosticCode
        } catch {
            selectionIntent = nil
            diagnosticCode = "account_discovery_selection_unavailable"
        }
    }

    private var currentSnapshot: AuthorizedAccountListSnapshot? {
        switch update {
        case .snapshot(let snapshot): snapshot
        case .failed(_, let cached): cached
        case .waiting: nil
        }
    }

    private func discardSelectionIfSnapshotChanged() {
        guard let selectionIntent,
              let snapshot = currentSnapshot else {
            self.selectionIntent = nil
            return
        }
        do {
            _ = try AccountSelectionPolicy.validate(selectionIntent, against: snapshot)
        } catch {
            self.selectionIntent = nil
        }
    }
}
