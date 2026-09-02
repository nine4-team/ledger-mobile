import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Account Discovery and Explicit Selection Contracts")
struct AccountDiscoveryAndSelectionTests {
    @Test("Zero, one, many, remembered order, and explicit choice remain distinct")
    func discoveryAndExplicitSelection() throws {
        let fixture = try Self.fixture()
        let empty = try Self.snapshot(accounts: [], version: "accounts-empty")
        #expect(empty.isAuthoritativeEmpty)

        let one = try Self.snapshot(accounts: [fixture.alphaA], version: "accounts-one")
        #expect(one.accounts == [fixture.alphaA])
        #expect(!one.isAuthoritativeEmpty)

        #expect(fixture.snapshot.accounts.map(\.id.rawValue) == [
            "account-alpha-a", "account-alpha-b", "account-beta"
        ])
        #expect(fixture.alphaA.displayName == fixture.alphaB.displayName)
        #expect(fixture.alphaA.id != fixture.alphaB.id)
        #expect(
            fixture.snapshot.orderedForPresentation(rememberedAccountId: fixture.beta.id)
                .map(\.id.rawValue) == [
                    "account-beta", "account-alpha-a", "account-alpha-b"
                ]
        )
        #expect(
            fixture.snapshot.orderedForPresentation(
                rememberedAccountId: try AccountID(validating: "account-no-longer-visible")
            ) == fixture.snapshot.accounts
        )

        let intent = try AccountSelectionPolicy.makeIntent(
            selecting: fixture.alphaB.id,
            from: fixture.snapshot,
            requestedAt: fixture.requestedAt
        )
        #expect(intent.environment == fixture.snapshot.environment)
        #expect(intent.principalId == fixture.snapshot.principalId)
        #expect(intent.accountId == fixture.alphaB.id)
        #expect(intent.sourceSnapshotFingerprint == fixture.snapshot.fingerprint)
        #expect(try AccountSelectionPolicy.validate(intent, against: fixture.snapshot) == fixture.alphaB)

        let partial = try Self.snapshot(
            accounts: [fixture.alphaA],
            isComplete: false,
            quality: .partial,
            version: "accounts-partial"
        )
        let stale = try Self.snapshot(
            accounts: fixture.snapshot.accounts,
            isComplete: true,
            quality: .stale,
            version: "accounts-stale"
        )
        #expect(
            AuthorizedAccountDiscoveryUpdate.waiting(.loading) !=
                .snapshot(empty)
        )
        #expect(
            AuthorizedAccountDiscoveryUpdate.snapshot(partial) !=
                .snapshot(stale)
        )
        #expect(
            AuthorizedAccountDiscoveryUpdate.failed(failure: .retryable, cached: stale) !=
                .snapshot(empty)
        )
    }

    @Test("Discovery and selection evidence survives byte-identical restart")
    func canonicalRestart() throws {
        let fixture = try Self.fixture()
        let partial = try Self.snapshot(
            accounts: [fixture.alphaA],
            isComplete: false,
            quality: .partial,
            version: "accounts-partial"
        )
        let stale = try Self.snapshot(
            accounts: fixture.snapshot.accounts,
            isComplete: true,
            quality: .stale,
            version: "accounts-stale"
        )
        let empty = try Self.snapshot(accounts: [], version: "accounts-empty")
        let intent = try AccountSelectionPolicy.makeIntent(
            selecting: fixture.beta.id,
            from: fixture.snapshot,
            requestedAt: fixture.requestedAt
        )
        let restart = RestartFixture(
            ready: fixture.snapshot,
            partial: partial,
            stale: stale,
            empty: empty,
            updates: [
                .waiting(.notRequested),
                .waiting(.loading),
                .snapshot(fixture.snapshot),
                .failed(failure: .retryable, cached: stale),
                .failed(failure: .unavailable, cached: nil)
            ],
            selection: intent
        )

        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)
        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.empty.isAuthoritativeEmpty)
        #expect(restored.partial.quality == .partial)
        #expect(restored.stale.quality == .stale)

        let encoded = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "supabase", "password", "token", "role", "financial",
            "invite", "logo", "endpoint", "firestore", "storagepath"
        ] {
            #expect(!encoded.contains(forbidden))
        }
    }

    @Test("Malformed, duplicate, rebound, changed, and unlisted evidence fails closed")
    func refusalAndDiagnostics() throws {
        for name in ["", " ", "\n", String(repeating: "x", count: 201)] {
            #expect(Self.captureFailure {
                _ = try AccountDisplayName(validating: name)
            } == .invalidDisplayName)
        }

        let fixture = try Self.fixture()
        #expect(Self.captureFailure {
            _ = try Self.snapshot(
                accounts: [fixture.alphaA, fixture.alphaA],
                version: "accounts-duplicate"
            )
        } == .duplicateAccountIdentity)
        #expect(Self.captureFailure {
            _ = try Self.snapshot(
                accounts: [fixture.alphaA],
                isComplete: false,
                quality: .ready,
                version: "accounts-bad-ready"
            )
        } == .invalidSnapshotReadiness)
        #expect(Self.captureFailure {
            _ = try Self.snapshot(
                accounts: [fixture.alphaA],
                isComplete: true,
                quality: .partial,
                version: "accounts-bad-partial"
            )
        } == .invalidSnapshotReadiness)
        #expect(Self.captureFailure {
            _ = try AuthorizedAccountListSnapshot(
                environment: .targetStaging,
                principalId: fixture.principalId,
                accounts: [fixture.alphaA],
                isComplete: true,
                quality: .ready,
                localDataVersion: try LocalDataVersion(validating: "accounts-time"),
                asOf: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidSnapshotAsOf)

        let unknown = try AccountID(validating: "account-unknown")
        #expect(Self.captureFailure {
            _ = try AccountSelectionPolicy.makeIntent(
                selecting: unknown,
                from: fixture.snapshot,
                requestedAt: fixture.requestedAt
            )
        } == .accountUnavailable)
        #expect(Self.captureFailure {
            _ = try AccountSelectionPolicy.makeIntent(
                selecting: fixture.alphaA.id,
                from: fixture.snapshot,
                requestedAt: fixture.snapshot.asOf.addingTimeInterval(-1)
            )
        } == .invalidRequestedAt)

        let intent = try AccountSelectionPolicy.makeIntent(
            selecting: fixture.alphaA.id,
            from: fixture.snapshot,
            requestedAt: fixture.requestedAt
        )
        let otherEnvironment = try Self.snapshot(
            environment: .targetLocal,
            accounts: fixture.snapshot.accounts,
            version: fixture.snapshot.localDataVersion.rawValue
        )
        #expect(Self.captureFailure {
            _ = try AccountSelectionPolicy.validate(intent, against: otherEnvironment)
        } == .scopeMismatch)
        let otherPrincipal = try Self.snapshot(
            principalId: PrincipalID(validating: "principal-other"),
            accounts: fixture.snapshot.accounts,
            version: fixture.snapshot.localDataVersion.rawValue
        )
        #expect(Self.captureFailure {
            _ = try AccountSelectionPolicy.validate(intent, against: otherPrincipal)
        } == .scopeMismatch)
        let changed = try Self.snapshot(
            accounts: fixture.snapshot.accounts,
            version: "accounts-newer"
        )
        #expect(Self.captureFailure {
            _ = try AccountSelectionPolicy.validate(intent, against: changed)
        } == .snapshotChanged)

        let snapshotBytes = try OperationContractCodec.encode(fixture.snapshot)
        let snapshotJSON = String(decoding: snapshotBytes, as: UTF8.self)
        let tamperedSnapshot = Data(
            snapshotJSON.replacingOccurrences(
                of: fixture.snapshot.fingerprint.rawValue,
                with: String(repeating: "0", count: 64)
            ).utf8
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                AuthorizedAccountListSnapshot.self,
                from: tamperedSnapshot
            )
        } == .snapshotFingerprintMismatch)

        let intentBytes = try OperationContractCodec.encode(intent)
        let intentJSON = String(decoding: intentBytes, as: UTF8.self)
        let tamperedIntent = Data(
            intentJSON.replacingOccurrences(
                of: intent.fingerprint.rawValue,
                with: String(repeating: "f", count: 64)
            ).utf8
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                WorkspaceSelectionIntent.self,
                from: tamperedIntent
            )
        } == .selectionFingerprintMismatch)
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                AuthorizedAccountDiscoveryUpdate.self,
                from: Data(#"{"kind":"unknown"}"#.utf8)
            )
        } == .invalidEncodedDiscoveryUpdate)

        let diagnosticCodes = Set([
            AccountDiscoverySelectionFailure.invalidDisplayName,
            .duplicateAccountIdentity,
            .invalidSnapshotAsOf,
            .invalidSnapshotReadiness,
            .snapshotFingerprintMismatch,
            .invalidRequestedAt,
            .accountUnavailable,
            .scopeMismatch,
            .snapshotChanged,
            .selectionFingerprintMismatch,
            .localReadFailed,
            .invalidEncodedDisplayName,
            .invalidEncodedAccountSummary,
            .invalidEncodedSnapshot,
            .invalidEncodedDiscoveryUpdate,
            .invalidEncodedSelectionIntent
        ].map(\.diagnosticCode))
        #expect(diagnosticCodes.count == 16)
    }

    @Test("The narrow query port streams only exact scoped discovery evidence")
    func referencePort() async throws {
        let fixture = try Self.fixture()
        let updates: [AuthorizedAccountDiscoveryUpdate] = [
            .waiting(.loading),
            .snapshot(fixture.snapshot)
        ]
        let port = FixtureAccountQueryPort(
            environment: fixture.snapshot.environment,
            principalId: fixture.principalId,
            updates: updates,
            failure: nil
        )

        var received: [AuthorizedAccountDiscoveryUpdate] = []
        for try await update in port.watchAuthorizedAccounts(
            environment: fixture.snapshot.environment,
            principalId: fixture.principalId
        ) {
            received.append(update)
        }
        #expect(received == updates)

        var wrongScopeValues: [AuthorizedAccountDiscoveryUpdate] = []
        do {
            for try await update in port.watchAuthorizedAccounts(
                environment: .targetLocal,
                principalId: fixture.principalId
            ) {
                wrongScopeValues.append(update)
            }
            Issue.record("Expected wrong-scope discovery to fail")
        } catch let failure as AccountDiscoverySelectionFailure {
            #expect(failure == .scopeMismatch)
        }
        #expect(wrongScopeValues.isEmpty)

        let failing = FixtureAccountQueryPort(
            environment: fixture.snapshot.environment,
            principalId: fixture.principalId,
            updates: [.snapshot(fixture.snapshot)],
            failure: .localReadFailed
        )
        var falseSnapshots: [AuthorizedAccountDiscoveryUpdate] = []
        do {
            for try await update in failing.watchAuthorizedAccounts(
                environment: fixture.snapshot.environment,
                principalId: fixture.principalId
            ) {
                falseSnapshots.append(update)
            }
            Issue.record("Expected local read failure")
        } catch let failure as AccountDiscoverySelectionFailure {
            #expect(failure == .localReadFailed)
        }
        #expect(falseSnapshots.isEmpty)
    }

    private static func fixture() throws -> Fixture {
        let alphaA = try account(id: "account-alpha-a", name: "Alpha Studio")
        let alphaB = try account(id: "account-alpha-b", name: "Alpha Studio")
        let beta = try account(id: "account-beta", name: "  Beta   Design  ")
        let snapshot = try Self.snapshot(
            accounts: [beta, alphaB, alphaA],
            version: "accounts-ready"
        )
        return Fixture(
            principalId: snapshot.principalId,
            alphaA: alphaA,
            alphaB: alphaB,
            beta: beta,
            snapshot: snapshot,
            requestedAt: snapshot.asOf.addingTimeInterval(1)
        )
    }

    private static func account(id: String, name: String) throws -> AccountSummary {
        AccountSummary(
            id: try AccountID(validating: id),
            displayName: try AccountDisplayName(validating: name)
        )
    }

    private static func snapshot(
        environment: LedgerEnvironmentKind = .targetStaging,
        principalId: PrincipalID? = nil,
        accounts: [AccountSummary],
        isComplete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String
    ) throws -> AuthorizedAccountListSnapshot {
        try AuthorizedAccountListSnapshot(
            environment: environment,
            principalId: principalId ?? PrincipalID(validating: "principal-account-tests"),
            accounts: accounts,
            isComplete: isComplete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: Date(timeIntervalSince1970: 1_800_800_000)
        )
    }

    private static func captureFailure(
        _ body: () throws -> Void
    ) -> AccountDiscoverySelectionFailure? {
        do {
            try body()
            return nil
        } catch let failure as AccountDiscoverySelectionFailure {
            return failure
        } catch {
            Issue.record("Unexpected failure: \(error)")
            return nil
        }
    }

    private struct Fixture {
        let principalId: PrincipalID
        let alphaA: AccountSummary
        let alphaB: AccountSummary
        let beta: AccountSummary
        let snapshot: AuthorizedAccountListSnapshot
        let requestedAt: Date
    }

    private struct RestartFixture: Codable, Equatable {
        let ready: AuthorizedAccountListSnapshot
        let partial: AuthorizedAccountListSnapshot
        let stale: AuthorizedAccountListSnapshot
        let empty: AuthorizedAccountListSnapshot
        let updates: [AuthorizedAccountDiscoveryUpdate]
        let selection: WorkspaceSelectionIntent
    }
}

private struct FixtureAccountQueryPort: AccountQuerying {
    let environment: LedgerEnvironmentKind
    let principalId: PrincipalID
    let updates: [AuthorizedAccountDiscoveryUpdate]
    let failure: AccountDiscoverySelectionFailure?

    func watchAuthorizedAccounts(
        environment requestedEnvironment: LedgerEnvironmentKind,
        principalId requestedPrincipalId: PrincipalID
    ) -> AsyncThrowingStream<AuthorizedAccountDiscoveryUpdate, Error> {
        AsyncThrowingStream { continuation in
            guard requestedEnvironment == environment,
                  requestedPrincipalId == principalId else {
                continuation.finish(throwing: AccountDiscoverySelectionFailure.scopeMismatch)
                return
            }
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            for update in updates {
                continuation.yield(update)
            }
            continuation.finish()
        }
    }
}

