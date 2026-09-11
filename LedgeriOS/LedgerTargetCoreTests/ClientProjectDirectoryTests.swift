import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Client and Project Directory Read Contracts")
struct ClientProjectDirectoryTests {
    @Test("Account-scoped Client and Project snapshots use exact identity")
    func validDirectoryAndPort() async throws {
        let fixture = try Self.fixture()
        #expect(fixture.client.displayName.rawValue == "1584 Design Client")
        #expect(fixture.project.clientId == fixture.client.id)
        #expect(fixture.project.client == fixture.client)
        #expect(fixture.project.description == "Primary residence")
        #expect(fixture.clients.local.quality == .ready)
        #expect(fixture.clients.local.rows.count == 2)
        #expect(
            fixture.clients.local.rows[0].displayName ==
                fixture.clients.local.rows[1].displayName
        )
        #expect(fixture.clients.local.rows[0].id != fixture.clients.local.rows[1].id)
        #expect(fixture.projects.local.isCompleteForQuery)

        let port = FixtureDirectoryPort(
            clients: fixture.clients,
            projects: fixture.projects
        )
        var clientUpdates: [ClientListSnapshot] = []
        for try await update in port.watchClients(accountId: fixture.accountId) {
            clientUpdates.append(update)
        }
        var projectUpdates: [ProjectListSnapshot] = []
        for try await update in port.watchProjects(accountId: fixture.accountId) {
            projectUpdates.append(update)
        }
        #expect(clientUpdates == [fixture.clients])
        #expect(projectUpdates == [fixture.projects])
    }

    @Test("Ready, partial, and authoritative-empty evidence survives restart")
    func canonicalRestart() throws {
        let fixture = try Self.fixture()
        let partialClients = try ClientListSnapshot(
            accountId: fixture.accountId,
            local: ListLocalSnapshot(
                queryFingerprint: fixture.clients.local.queryFingerprint,
                rows: [fixture.client],
                visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: false,
                quality: .partial,
                localDataVersion: try LocalDataVersion(validating: "client-local-2"),
                asOf: Date(timeIntervalSince1970: 1_800_200_001)
            )
        )
        let authoritativeEmptyProjects = try ProjectListSnapshot(
            accountId: fixture.accountId,
            local: ListLocalSnapshot(
                queryFingerprint: fixture.projects.local.queryFingerprint,
                rows: [],
                visibleRowCountBeforeFiltering: 0,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: try LocalDataVersion(validating: "project-local-2"),
                asOf: Date(timeIntervalSince1970: 1_800_200_002)
            )
        )
        let restart = RestartFixture(
            clients: fixture.clients,
            projects: fixture.projects,
            partialClients: partialClients,
            authoritativeEmptyProjects: authoritativeEmptyProjects
        )

        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(
            RestartFixture.self,
            from: bytes
        )

        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(!restored.partialClients.local.isCompleteForQuery)
        #expect(restored.partialClients.local.quality == .partial)
        #expect(restored.authoritativeEmptyProjects.local.rows.isEmpty)
        #expect(restored.authoritativeEmptyProjects.local.isCompleteForQuery)
        #expect(restored.authoritativeEmptyProjects.local.quality == .ready)
    }

    @Test("Invalid names, times, Accounts, relationships, and duplicates fail")
    func invalidDirectoryEvidence() async throws {
        for name in ["", " ", "\n\t"] {
            #expect(Self.captureDirectoryFailure {
                _ = try ClientDisplayName(validating: name)
            } == .invalidClientDisplayName)
            #expect(Self.captureDirectoryFailure {
                _ = try ProjectDisplayName(validating: name)
            } == .invalidProjectDisplayName)
        }

        let fixture = try Self.fixture()
        #expect(Self.captureDirectoryFailure {
            _ = try ClientSummary(
                id: fixture.client.id,
                accountId: fixture.accountId,
                displayName: fixture.client.displayName,
                lifecycle: .active,
                createdAt: Date(timeIntervalSince1970: 2),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        } == .invalidClientAuditOrder)
        #expect(Self.captureDirectoryFailure {
            _ = try ClientSummary(
                id: fixture.client.id,
                accountId: fixture.accountId,
                displayName: fixture.client.displayName,
                lifecycle: .active,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidClientAuditOrder)

        let otherAccount = try AccountID(validating: "account-other")
        #expect(Self.captureDirectoryFailure {
            _ = try ProjectSummary(
                id: fixture.project.id,
                accountId: otherAccount,
                clientId: fixture.client.id,
                client: fixture.client,
                displayName: fixture.project.displayName,
                description: nil,
                lifecycle: .active
            )
        } == .accountScopeMismatch)
        #expect(Self.captureDirectoryFailure {
            _ = try ProjectSummary(
                id: fixture.project.id,
                accountId: fixture.accountId,
                clientId: try ClientID(validating: "client-other"),
                client: fixture.client,
                displayName: fixture.project.displayName,
                description: nil,
                lifecycle: .active
            )
        } == .clientRelationshipMismatch)

        let otherAccountClient = try ClientSummary(
            id: ClientID(validating: "client-other-account"),
            accountId: otherAccount,
            displayName: ClientDisplayName(validating: "Other Account Client"),
            lifecycle: .active,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        #expect(Self.captureDirectoryFailure {
            _ = try ClientListSnapshot(
                accountId: fixture.accountId,
                local: try ListLocalSnapshot(
                    queryFingerprint: fixture.clients.local.queryFingerprint,
                    rows: [otherAccountClient],
                    visibleRowCountBeforeFiltering: 1,
                    isCompleteForQuery: true,
                    quality: .ready,
                    localDataVersion: try LocalDataVersion(
                        validating: "client-local-cross-account"
                    ),
                    asOf: Date(timeIntervalSince1970: 1_800_200_003)
                )
            )
        } == .accountScopeMismatch)

        let otherAccountProject = try ProjectSummary(
            id: ProjectID(validating: "project-other-account"),
            accountId: otherAccount,
            clientId: otherAccountClient.id,
            client: otherAccountClient,
            displayName: ProjectDisplayName(validating: "Other Project"),
            description: nil,
            lifecycle: .active
        )
        #expect(Self.captureDirectoryFailure {
            _ = try ProjectListSnapshot(
                accountId: fixture.accountId,
                local: try ListLocalSnapshot(
                    queryFingerprint: fixture.projects.local.queryFingerprint,
                    rows: [otherAccountProject],
                    visibleRowCountBeforeFiltering: 1,
                    isCompleteForQuery: true,
                    quality: .ready,
                    localDataVersion: try LocalDataVersion(
                        validating: "project-local-cross-account"
                    ),
                    asOf: Date(timeIntervalSince1970: 1_800_200_004)
                )
            )
        } == .accountScopeMismatch)

        let validProjectBytes = try OperationContractCodec.encode(fixture.project)
        let mismatchedProjectBytes = Data(
            String(decoding: validProjectBytes, as: UTF8.self)
                .replacingOccurrences(
                    of: #""clientId":"client-001""#,
                    with: #""clientId":"client-other""#
                )
                .utf8
        )
        #expect(Self.captureDirectoryFailure {
            _ = try OperationContractCodec.decode(
                ProjectSummary.self,
                from: mismatchedProjectBytes
            )
        } == .clientRelationshipMismatch)

        #expect(Self.captureDirectoryFailure {
            _ = try ClientListSnapshot(
                accountId: fixture.accountId,
                local: try ListLocalSnapshot(
                    queryFingerprint: fixture.clients.local.queryFingerprint,
                    rows: [fixture.client, fixture.client],
                    visibleRowCountBeforeFiltering: 2,
                    isCompleteForQuery: true,
                    quality: .ready,
                    localDataVersion: try LocalDataVersion(validating: "client-local-duplicate"),
                    asOf: Date(timeIntervalSince1970: 1_800_200_010)
                )
            )
        } == .duplicateClientIdentity)
        #expect(Self.captureDirectoryFailure {
            _ = try ProjectListSnapshot(
                accountId: fixture.accountId,
                local: try ListLocalSnapshot(
                    queryFingerprint: fixture.projects.local.queryFingerprint,
                    rows: [fixture.project, fixture.project],
                    visibleRowCountBeforeFiltering: 2,
                    isCompleteForQuery: true,
                    quality: .ready,
                    localDataVersion: try LocalDataVersion(validating: "project-local-duplicate"),
                    asOf: Date(timeIntervalSince1970: 1_800_200_011)
                )
            )
        } == .duplicateProjectIdentity)

        let malformedClient = Data(
            #"{"accountId":"account-main","createdAt":1000,"displayName":" ","id":"client-001","lifecycle":"active","updatedAt":1000}"#.utf8
        )
        #expect(Self.captureDirectoryFailure {
            _ = try OperationContractCodec.decode(
                ClientSummary.self,
                from: malformedClient
            )
        } == .invalidClientDisplayName)

        let queryFailure = Self.captureListFailure {
            _ = try ListLocalSnapshot<ClientSummary>(
                queryFingerprint: fixture.clients.local.queryFingerprint,
                rows: [],
                visibleRowCountBeforeFiltering: 0,
                isCompleteForQuery: true,
                quality: .partial,
                localDataVersion: try LocalDataVersion(validating: "client-local-invalid"),
                asOf: Date(timeIntervalSince1970: 1_800_200_012)
            )
        }
        #expect(queryFailure == .incompleteAuthoritativeEmpty)

        let port = FixtureDirectoryPort(
            clients: fixture.clients,
            projects: fixture.projects
        )
        var portFailure: ClientProjectDirectoryFailure?
        do {
            for try await _ in port.watchClients(accountId: otherAccount) {}
        } catch let failure as ClientProjectDirectoryFailure {
            portFailure = failure
        }
        #expect(portFailure == .accountScopeMismatch)

        let diagnostics: [(ClientProjectDirectoryFailure, String)] = [
            (.invalidClientDisplayName, "client_directory_client_name_invalid"),
            (.invalidProjectDisplayName, "client_directory_project_name_invalid"),
            (.invalidClientAuditOrder, "client_directory_client_audit_order_invalid"),
            (.accountScopeMismatch, "client_directory_account_scope_mismatch"),
            (.clientRelationshipMismatch, "client_directory_relationship_mismatch"),
            (.duplicateClientIdentity, "client_directory_client_identity_duplicate"),
            (.duplicateProjectIdentity, "client_directory_project_identity_duplicate")
        ]
        for (failure, diagnosticCode) in diagnostics {
            #expect(failure.diagnosticCode == diagnosticCode)
        }
    }

    private struct DirectoryFixture: Sendable {
        let accountId: AccountID
        let client: ClientSummary
        let project: ProjectSummary
        let clients: ClientListSnapshot
        let projects: ProjectListSnapshot
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let clients: ClientListSnapshot
        let projects: ProjectListSnapshot
        let partialClients: ClientListSnapshot
        let authoritativeEmptyProjects: ProjectListSnapshot
    }

    private struct FixtureDirectoryPort: ClientProjectDirectoryQuerying {
        let clients: ClientListSnapshot
        let projects: ProjectListSnapshot

        func watchClients(
            accountId: AccountID
        ) -> AsyncThrowingStream<ClientListSnapshot, Error> {
            AsyncThrowingStream { continuation in
                guard accountId == clients.accountId else {
                    continuation.finish(
                        throwing: ClientProjectDirectoryFailure.accountScopeMismatch
                    )
                    return
                }
                continuation.yield(clients)
                continuation.finish()
            }
        }

        func watchProjects(
            accountId: AccountID
        ) -> AsyncThrowingStream<ProjectListSnapshot, Error> {
            AsyncThrowingStream { continuation in
                guard accountId == projects.accountId else {
                    continuation.finish(
                        throwing: ClientProjectDirectoryFailure.accountScopeMismatch
                    )
                    return
                }
                continuation.yield(projects)
                continuation.finish()
            }
        }
    }

    private static func fixture() throws -> DirectoryFixture {
        let accountId = try AccountID(validating: "account-main")
        let client = try ClientSummary(
            id: ClientID(validating: "client-001"),
            accountId: accountId,
            displayName: ClientDisplayName(validating: "1584 Design Client"),
            lifecycle: .active,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let sameNameClient = try ClientSummary(
            id: ClientID(validating: "client-002"),
            accountId: accountId,
            displayName: client.displayName,
            lifecycle: .archived,
            createdAt: Date(timeIntervalSince1970: 1_800_000_010),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_110)
        )
        let project = try ProjectSummary(
            id: ProjectID(validating: "project-001"),
            accountId: accountId,
            clientId: client.id,
            client: client,
            displayName: ProjectDisplayName(validating: "Walnut Residence"),
            description: "Primary residence",
            lifecycle: .active
        )
        let clients = try ClientListSnapshot(
            accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: try ListQueryFingerprint(
                    validating: String(repeating: "a", count: 64)
                ),
                rows: [client, sameNameClient],
                visibleRowCountBeforeFiltering: 2,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: try LocalDataVersion(validating: "client-local-1"),
                asOf: Date(timeIntervalSince1970: 1_800_200_000)
            )
        )
        let projects = try ProjectListSnapshot(
            accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: try ListQueryFingerprint(
                    validating: String(repeating: "b", count: 64)
                ),
                rows: [project],
                visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: try LocalDataVersion(validating: "project-local-1"),
                asOf: Date(timeIntervalSince1970: 1_800_200_000)
            )
        )
        return DirectoryFixture(
            accountId: accountId,
            client: client,
            project: project,
            clients: clients,
            projects: projects
        )
    }

    private static func captureDirectoryFailure<Value>(
        _ body: () throws -> Value
    ) -> ClientProjectDirectoryFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as ClientProjectDirectoryFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func captureListFailure<Value>(
        _ body: () throws -> Value
    ) -> ListQueryContractFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as ListQueryContractFailure {
            return failure
        } catch {
            return nil
        }
    }
}
