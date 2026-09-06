import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Client/Project PowerSync directory and browse", .serialized)
struct ClientProjectDirectoryPowerSyncQueryTests {
    @Test("Pending and authoritative rows drive selection, segments, and exact detail")
    func completeDirectoryBrowseFlow() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        try await Self.insertClient(
            database,
            id: "client-active",
            name: "Active Client",
            lifecycle: "active"
        )
        try await Self.insertClient(
            database,
            id: "client-archived",
            name: "Archived Client",
            lifecycle: "archived"
        )
        try await Self.insertProject(
            database,
            id: "project-active",
            clientId: "client-archived",
            name: "Active Project",
            lifecycle: "active"
        )
        try await Self.insertPendingClient(database)
        try await Self.insertPendingProject(database)

        let query = Self.query(database, complete: true)
        var clientIterator = query.watchClients(accountId: Self.accountId).makeAsyncIterator()
        let clients = try #require(try await clientIterator.next())
        #expect(clients.local.rows.map(\.id.rawValue) == [
            "client-active", "client-archived", "client-pending"
        ])
        #expect(clients.local.quality == .partial)
        #expect(!clients.local.isCompleteForQuery)

        let selection = try ProjectExistingClientSelectionSnapshot(directory: clients)
        #expect(selection.activeClients.map(\.id.rawValue) == [
            "client-active", "client-pending"
        ])
        #expect(try selection.selection(clientId: ClientID(validating: "client-active"))
            == ProjectClientSelectionInput(existing: ClientID(validating: "client-active")))

        var projectIterator = query.watchProjects(accountId: Self.accountId).makeAsyncIterator()
        let projects = try #require(try await projectIterator.next())
        #expect(projects.local.rows.map(\.id.rawValue) == [
            "project-active", "project-pending"
        ])
        #expect(projects.local.quality == .partial)
        let active = try ProjectDirectoryPresentationProjector.project(
            projects,
            segment: .active
        )
        let archived = try ProjectDirectoryPresentationProjector.project(
            projects,
            segment: .archived
        )
        #expect(active.rows.map(\.projectId.rawValue) == ["project-active"])
        #expect(active.rows.first?.clientLifecycle == .archived)
        #expect(archived.rows.map(\.projectId.rawValue) == ["project-pending"])

        let browsingSelection = try active.selection(
            projectId: ProjectID(validating: "project-active")
        )
        let detail = try browsingSelection.detailRequest(validating: active)
        #expect(detail.accountId == Self.accountId)
        let activeProjectId = try ProjectID(validating: "project-active")
        #expect(detail.projectId == activeProjectId)

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("A Project whose Client has not arrived is incomplete, never authoritative empty")
    func missingRelationshipStaysIncomplete() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        try await Self.insertProject(
            database,
            id: "project-before-client",
            clientId: "client-not-downloaded",
            name: "Waiting Project",
            lifecycle: "active"
        )

        let query = Self.query(database, complete: true)
        var iterator = query
            .watchProjects(accountId: Self.accountId)
            .makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())
        #expect(snapshot.local.rows.isEmpty)
        #expect(snapshot.local.visibleRowCountBeforeFiltering == 1)
        #expect(snapshot.local.quality == .partial)
        #expect(!snapshot.local.isCompleteForQuery)

        let presentation = try ProjectDirectoryPresentationProjector.project(
            snapshot,
            segment: .active
        )
        #expect(!presentation.isAuthoritativeEmpty)

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Project readback waits for its Client and never discards allocation optimism")
    func projectReadbackPreservesIncompleteAggregate() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        try await Self.insertPendingProject(
            database,
            projectId: "project-before-client",
            clientId: "client-late"
        )
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_pending_project_category_allocations (
              id, account_id, project_id, category_id,
              allocation_minor_units, allocation_currency, revision,
              created_at_ms, updated_at_ms, created_by_principal_id, operation_id
            ) VALUES (?, ?, ?, 'category-furnishings', 1000, 'USD', 1,
                      1788500000000, 1788500001000, ?, ?)
            """,
            parameters: [
                "operation-pending-project:category-furnishings",
                Self.accountId.rawValue,
                "project-before-client",
                Self.principalId.rawValue,
                "operation-pending-project"
            ]
        )
        try await Self.insertProject(
            database,
            id: "project-before-client",
            clientId: "client-late",
            name: "Waiting Project",
            lifecycle: "active"
        )

        let query = Self.query(database, complete: true)
        var iterator = query
            .watchProjects(accountId: Self.accountId)
            .makeAsyncIterator()
        let incomplete = try #require(try await iterator.next())
        #expect(incomplete.local.rows.isEmpty)
        #expect(incomplete.local.visibleRowCountBeforeFiltering == 1)
        #expect(try await Self.count("spike_pending_projects", database) == 1)
        #expect(
            try await Self.count(
                "spike_pending_project_category_allocations",
                database
            ) == 1
        )

        try await Self.insertClient(
            database,
            id: "client-late",
            name: "Late Client",
            lifecycle: "active"
        )
        let joined = try #require(try await iterator.next())
        #expect(joined.local.rows.map(\.id.rawValue) == ["project-before-client"])
        #expect(try await Self.count("spike_pending_projects", database) == 0)
        #expect(
            try await Self.count(
                "spike_pending_project_category_allocations",
                database
            ) == 1
        )

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Locally accepted rows stay visible as partial before membership downloads")
    func pendingRowsStayVisibleBeforeMembership() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertPendingClient(database)
        try await Self.insertPendingProject(database)

        let query = Self.query(database, complete: true)
        var clientIterator = query
            .watchClients(accountId: Self.accountId)
            .makeAsyncIterator()
        let clients = try #require(try await clientIterator.next())
        #expect(clients.local.rows.map(\.id.rawValue) == ["client-pending"])
        #expect(clients.local.quality == .partial)
        #expect(!clients.local.isCompleteForQuery)

        var projectIterator = query
            .watchProjects(accountId: Self.accountId)
            .makeAsyncIterator()
        let projects = try #require(try await projectIterator.next())
        #expect(projects.local.rows.map(\.id.rawValue) == ["project-pending"])
        #expect(projects.local.quality == .partial)
        #expect(!projects.local.isCompleteForQuery)

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Hidden authoritative readback cannot replace or reconcile optimism before membership")
    func authoritativeRowsStayHiddenBeforeMembership() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertPendingClient(database)
        try await Self.insertPendingProject(database)
        try await Self.insertClient(
            database,
            id: "client-pending",
            name: "Hidden Server Client",
            lifecycle: "active"
        )
        try await Self.insertProject(
            database,
            id: "project-pending",
            clientId: "client-pending",
            name: "Hidden Server Project",
            lifecycle: "active"
        )

        let query = Self.query(database, complete: true)
        var clientIterator = query
            .watchClients(accountId: Self.accountId)
            .makeAsyncIterator()
        let clients = try #require(try await clientIterator.next())
        #expect(clients.local.rows.map(\.displayName.rawValue) == ["Pending Client"])
        #expect(clients.local.quality == .partial)
        #expect(try await Self.count("spike_pending_clients", database) == 1)

        var projectIterator = query
            .watchProjects(accountId: Self.accountId)
            .makeAsyncIterator()
        let projects = try #require(try await projectIterator.next())
        #expect(projects.local.rows.map(\.displayName.rawValue) == ["Pending Project"])
        #expect(projects.local.quality == .partial)
        #expect(try await Self.count("spike_pending_projects", database) == 1)

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Exact detail navigation cannot expose hidden authority before membership")
    func exactDetailPreservesPendingValuesBeforeMembership() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertPendingClient(database)
        try await Self.insertPendingProject(database)
        try await Self.insertClient(
            database,
            id: "client-pending",
            name: "Hidden Server Client",
            lifecycle: "active"
        )
        try await Self.insertProject(
            database,
            id: "project-pending",
            clientId: "client-pending",
            name: "Hidden Server Project",
            lifecycle: "active"
        )
        try await database.close(deleteDatabase: false)

        let runtime = try await fixture.openRuntime()
        var clientDirectoryIterator = runtime.watchClients().makeAsyncIterator()
        let clients = try #require(try await clientDirectoryIterator.next())
        let pendingClient = try #require(clients.local.rows.first)
        #expect(pendingClient.displayName.rawValue == "Pending Client")

        let clientRequest = try ClientCoreDetailsRequest(
            accountId: Self.accountId,
            clientId: pendingClient.id
        )
        var clientDetailIterator = runtime.watchClient(clientRequest).makeAsyncIterator()
        _ = try await clientDetailIterator.next()
        let clientDetail = try #require(try await clientDetailIterator.next())
        guard case .snapshot(let clientSnapshot) = clientDetail.state else {
            Issue.record("Expected pending Client detail snapshot")
            try await runtime.close()
            fixture.removeDirectory()
            return
        }
        #expect(clientSnapshot.row?.client.displayName.rawValue == "Pending Client")
        #expect(clientSnapshot.local.quality == .partial)

        var projectDirectoryIterator = runtime.watchProjects().makeAsyncIterator()
        let projects = try #require(try await projectDirectoryIterator.next())
        let archived = try ProjectDirectoryPresentationProjector.project(
            projects,
            segment: .archived
        )
        let projectSelection = try archived.selection(
            projectId: ProjectID(validating: "project-pending")
        )
        let projectRequest = try projectSelection.detailRequest(validating: archived)
        var projectDetailIterator = runtime.watchProject(projectRequest).makeAsyncIterator()
        _ = try await projectDetailIterator.next()
        let projectDetail = try #require(try await projectDetailIterator.next())
        guard case .snapshot(let projectSnapshot) = projectDetail.state else {
            Issue.record("Expected pending Project detail snapshot")
            try await runtime.close()
            fixture.removeDirectory()
            return
        }
        #expect(projectSnapshot.row?.project.displayName.rawValue == "Pending Project")
        #expect(projectSnapshot.row?.project.client.displayName.rawValue == "Pending Client")
        #expect(projectSnapshot.local.quality == .partial)

        try await runtime.close()
        let reopened = try fixture.open()
        #expect(try await Self.count("spike_pending_clients", reopened) == 1)
        #expect(try await Self.count("spike_pending_projects", reopened) == 1)
        try await reopened.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Only the bound Principal's pending directory rows are visible")
    func pendingRowsArePrincipalScoped() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        let otherPrincipal = try PrincipalID(validating: "principal-other")
        try await Self.insertPendingClient(database)
        try await Self.insertPendingProject(database)
        try await Self.insertPendingClient(
            database,
            clientId: "client-other-pending",
            actor: otherPrincipal,
            name: "Other Pending Client",
            operationId: "operation-other-pending-client"
        )
        try await Self.insertPendingProject(
            database,
            projectId: "project-other-pending",
            clientId: "client-other-pending",
            actor: otherPrincipal,
            name: "Other Pending Project",
            operationId: "operation-other-pending-project"
        )

        let query = Self.query(database, complete: true)
        var clientIterator = query.watchClients(accountId: Self.accountId).makeAsyncIterator()
        let clients = try #require(try await clientIterator.next())
        #expect(clients.local.rows.map(\.id.rawValue) == ["client-pending"])

        var projectIterator = query.watchProjects(accountId: Self.accountId).makeAsyncIterator()
        let projects = try #require(try await projectIterator.next())
        #expect(projects.local.rows.map(\.id.rawValue) == ["project-pending"])

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Fresh runtime creates, selects, browses, and opens local detail without membership")
    func freshRuntimeOfflineBrowseFlow() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let runtime = try await fixture.openRuntime()
        _ = try await runtime.createClient(
            Self.clientCommand(accountId: Self.accountId, actor: Self.principalId)
        )

        var clientIterator = runtime.watchClients().makeAsyncIterator()
        let clients = try #require(try await clientIterator.next())
        let selection = try ProjectExistingClientSelectionSnapshot(directory: clients)
        #expect(selection.activeClients.map(\.id.rawValue) == ["client-runtime"])
        #expect(clients.local.quality == .partial)

        _ = try await runtime.createProject(
            Self.projectCommand(accountId: Self.accountId, actor: Self.principalId)
        )
        var projectIterator = runtime.watchProjects().makeAsyncIterator()
        let projects = try #require(try await projectIterator.next())
        let active = try ProjectDirectoryPresentationProjector.project(
            projects,
            segment: .active
        )
        let selected = try active.selection(
            projectId: ProjectID(validating: "project-runtime")
        )
        let request = try selected.detailRequest(validating: active)
        var detailIterator = runtime.watchProject(request).makeAsyncIterator()
        _ = try await detailIterator.next()
        let detail = try #require(try await detailIterator.next())
        guard case .snapshot(let snapshot) = detail.state else {
            Issue.record("Expected local Project detail snapshot")
            try await runtime.close()
            fixture.removeDirectory()
            return
        }
        #expect(snapshot.row?.project.id.rawValue == "project-runtime")
        #expect(snapshot.local.quality == .partial)

        try await runtime.close()
        fixture.removeDirectory()
    }

    @Test("Default runtime completeness never promotes local rows to ready")
    func defaultCompletenessIsUnproven() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        try await Self.insertClient(
            database,
            id: "client-active",
            name: "Active Client",
            lifecycle: "active"
        )
        let query = ClientProjectDirectoryPowerSyncQuery(
            database: database,
            principalId: Self.principalId,
            accountId: Self.accountId,
            now: { Self.observedAt }
        )

        var iterator = query.watchClients(accountId: Self.accountId).makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())
        #expect(snapshot.local.quality == .partial)
        #expect(!snapshot.local.isCompleteForQuery)

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Client and Project completeness transition independently without row changes")
    func completenessIsReactiveAndQuerySpecific() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        let clientProof = AsyncStream<Bool>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let projectProof = AsyncStream<Bool>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        clientProof.continuation.yield(false)
        projectProof.continuation.yield(false)
        let query = ClientProjectDirectoryPowerSyncQuery(
            database: database,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { stream, _ in
                switch stream {
                case .clients: clientProof.stream
                case .projects: projectProof.stream
                }
            },
            now: { Self.observedAt }
        )

        var clientIterator = query.watchClients(accountId: Self.accountId).makeAsyncIterator()
        let initialClients = try #require(try await clientIterator.next())
        #expect(initialClients.local.quality == .partial)
        clientProof.continuation.yield(true)
        let readyClients = try #require(try await clientIterator.next())
        #expect(readyClients.local.quality == .ready)
        #expect(readyClients.local.isCompleteForQuery)
        #expect(readyClients.local.rows.isEmpty)

        var projectIterator = query.watchProjects(accountId: Self.accountId).makeAsyncIterator()
        let initialProjects = try #require(try await projectIterator.next())
        #expect(initialProjects.local.quality == .partial)
        #expect(!initialProjects.local.isCompleteForQuery)
        projectProof.continuation.yield(true)
        let readyProjects = try #require(try await projectIterator.next())
        #expect(readyProjects.local.quality == .ready)
        #expect(readyProjects.local.isCompleteForQuery)

        clientProof.continuation.yield(false)
        let invalidatedClients = try #require(try await clientIterator.next())
        #expect(invalidatedClients.local.quality == .partial)
        #expect(!invalidatedClients.local.isCompleteForQuery)

        clientProof.continuation.finish()
        projectProof.continuation.finish()
        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Account binding and active membership prevent local cross-scope enumeration")
    func scopeAndMembershipIsolation() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        try await Self.insertClient(
            database,
            id: "client-primary",
            name: "Primary",
            lifecycle: "active"
        )
        try await Self.insertClient(
            database,
            id: "client-other",
            accountId: "account-other",
            name: "Other",
            lifecycle: "active"
        )

        let query = Self.query(database, complete: true)
        var iterator = query.watchClients(accountId: Self.accountId).makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())
        #expect(snapshot.local.rows.map(\.id.rawValue) == ["client-primary"])
        #expect(snapshot.local.quality == .ready)
        #expect(snapshot.local.isCompleteForQuery)

        let otherAccount = try AccountID(validating: "account-other")
        do {
            for try await _ in query.watchClients(accountId: otherAccount) {
                Issue.record("Mismatched Account must not produce directory rows")
            }
            Issue.record("Expected exact Account binding failure")
        } catch let failure as ClientProjectDirectoryFailure {
            #expect(failure == .accountScopeMismatch)
        }

        _ = try await database.execute(
            sql: "UPDATE spike_account_memberships SET state = 'revoked' WHERE id = ?",
            parameters: ["membership-primary"]
        )
        var revokedIterator = query.watchClients(accountId: Self.accountId).makeAsyncIterator()
        let revoked = try #require(try await revokedIterator.next())
        #expect(revoked.local.rows.isEmpty)
        #expect(revoked.local.quality == .partial)
        #expect(!revoked.local.isCompleteForQuery)

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Authoritative readback reconciles only matching overlays and changes content version")
    func authoritativeReadbackReconcilesExactOverlay() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        try await Self.insertPendingClient(database)

        let query = Self.query(database, complete: true)
        var iterator = query.watchClients(accountId: Self.accountId).makeAsyncIterator()
        let pending = try #require(try await iterator.next())
        #expect(pending.local.quality == .partial)

        try await Self.insertClient(
            database,
            id: "client-pending",
            name: "Pending Client",
            lifecycle: "active"
        )
        let authoritative = try #require(try await iterator.next())
        #expect(authoritative.local.rows.map(\.id.rawValue) == ["client-pending"])
        #expect(authoritative.local.localDataVersion != pending.local.localDataVersion)
        #expect(
            try await database.get(
                sql: "SELECT count(*) FROM spike_pending_clients WHERE id = ?",
                parameters: ["client-pending"]
            ) { try $0.getInt64(index: 0) } == 0
        )

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Pending directory state and content version survive an encrypted database restart")
    func pendingDirectorySurvivesRestart() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let firstDatabase = try fixture.open()
        try await Self.insertActiveMembership(firstDatabase)
        try await Self.insertPendingClient(firstDatabase)

        let beforeRestart = try await Self.firstClientSnapshot(firstDatabase)
        #expect(beforeRestart.local.rows.map(\.id.rawValue) == ["client-pending"])
        #expect(beforeRestart.local.quality == .partial)
        try await firstDatabase.close(deleteDatabase: false)

        let reopenedDatabase = try fixture.open()
        let afterRestart = try await Self.firstClientSnapshot(reopenedDatabase)
        #expect(afterRestart.local == beforeRestart.local)
        #expect(
            try await reopenedDatabase.get(
                sql: "SELECT count(*) FROM spike_pending_clients WHERE id = ?",
                parameters: ["client-pending"]
            ) { try $0.getInt64(index: 0) } == 1
        )

        try await reopenedDatabase.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Malformed Project data fails instead of masquerading as an incomplete relationship")
    func malformedProjectFailsClosed() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        try await Self.insertClient(
            database,
            id: "client-active",
            name: "Active Client",
            lifecycle: "active"
        )
        try await Self.insertProject(
            database,
            id: "project-invalid",
            clientId: "client-active",
            name: "Invalid Project",
            lifecycle: "unknown"
        )

        let query = Self.query(database, complete: true)
        do {
            for try await _ in query
                .watchProjects(accountId: Self.accountId) {
                Issue.record("Malformed Project must not produce a directory snapshot")
            }
            Issue.record("Expected malformed Project failure")
        } catch let failure as ClientProjectDirectoryPowerSyncFailure {
            #expect(failure == .malformedProjectRow)
        }

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Runtime rejects every cross-namespace mutation and detail read before persistence")
    func runtimeRejectsCrossNamespaceCalls() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let runtime = try await fixture.openRuntime()
        let otherAccount = try AccountID(validating: "account-other")
        let otherPrincipal = try PrincipalID(validating: "principal-other")

        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.createClient(
                Self.clientCommand(accountId: otherAccount, actor: Self.principalId)
            )
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.principalScopeMismatch) {
            try await runtime.createClient(
                Self.clientCommand(accountId: Self.accountId, actor: otherPrincipal)
            )
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.createProject(
                Self.projectCommand(accountId: otherAccount, actor: Self.principalId)
            )
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.principalScopeMismatch) {
            try await runtime.createProject(
                Self.projectCommand(accountId: Self.accountId, actor: otherPrincipal)
            )
        }

        do {
            for try await _ in runtime.watchClient(
                try ClientCoreDetailsRequest(
                    accountId: otherAccount,
                    clientId: ClientID(validating: "client-other")
                )
            ) {
                Issue.record("Cross-Account Client detail must yield no value")
            }
            Issue.record("Expected Client detail scope failure")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(failure == .accountScopeMismatch)
        }
        do {
            for try await _ in runtime.watchProject(
                try ProjectCoreDetailsRequest(
                    accountId: otherAccount,
                    projectId: ProjectID(validating: "project-other")
                )
            ) {
                Issue.record("Cross-Account Project detail must yield no value")
            }
            Issue.record("Expected Project detail scope failure")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(failure == .accountScopeMismatch)
        }

        #expect(try await runtime.pendingUploadCount() == 0)
        try await runtime.close()
        fixture.removeDirectory()
    }

    @Test(
        "Provider shutdown drains active directory watches before database close",
        .timeLimit(.minutes(1))
    )
    func providerShutdownDrainsBeforeDatabaseClose() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        let clientProof = AsyncStream<Bool>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let projectProof = AsyncStream<Bool>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        clientProof.continuation.yield(false)
        projectProof.continuation.yield(false)
        let query = ClientProjectDirectoryPowerSyncQuery(
            database: database,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { stream, _ in
                switch stream {
                case .clients: clientProof.stream
                case .projects: projectProof.stream
                }
            },
            now: { Self.observedAt }
        )

        var clientIterator = query.watchClients(accountId: Self.accountId).makeAsyncIterator()
        var projectIterator = query.watchProjects(accountId: Self.accountId).makeAsyncIterator()
        _ = try #require(try await clientIterator.next())
        _ = try #require(try await projectIterator.next())

        await query.cancelAndDrainWatches()
        var rejectedIterator = query.watchClients(accountId: Self.accountId).makeAsyncIterator()
        #expect(try await rejectedIterator.next() == nil)
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Cancelling a directory consumer stops further delivery")
    func cancellationStopsDelivery() async throws {
        let fixture = try DirectoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        let firstEmission = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let query = Self.query(database, complete: false)
        let observer = Task<Int, Never> {
            var count = 0
            do {
                for try await _ in query.watchClients(accountId: Self.accountId) {
                    count += 1
                    if count == 1 { firstEmission.continuation.yield(()) }
                }
            } catch {
                Issue.record("Cancellation must finish without a provider failure")
            }
            return count
        }
        var firstIterator = firstEmission.stream.makeAsyncIterator()
        _ = await firstIterator.next()
        observer.cancel()
        try await Self.insertClient(
            database,
            id: "client-after-cancel",
            name: "After Cancel",
            lifecycle: "active"
        )
        #expect(await observer.value == 1)
        firstEmission.continuation.finish()

        await query.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    private static let accountId = try! AccountID(validating: "account-primary")
    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let observedAt = Date(timeIntervalSince1970: 1_788_600_000)

    private static func query(
        _ database: any PowerSyncDatabaseProtocol,
        complete: Bool
    ) -> ClientProjectDirectoryPowerSyncQuery {
        ClientProjectDirectoryPowerSyncQuery(
            database: database,
            principalId: principalId,
            accountId: accountId,
            completenessObservation: { _, _ in
                AsyncStream { continuation in
                    continuation.yield(complete)
                    continuation.finish()
                }
            },
            now: { observedAt }
        )
    }

    private static func clientCommand(
        accountId: AccountID,
        actor: PrincipalID
    ) throws -> CreateClientCommand {
        try CreateClientCommand(
            operationId: OperationID(validating: "operation-runtime-client"),
            draft: ClientCreationDraft(
                accountId: accountId,
                actorPrincipalId: actor,
                operationContractVersion: OperationContractVersion(
                    validating: "client-create-v1"
                ),
                clientId: ClientID(validating: "client-runtime"),
                displayName: ClientDisplayName(validating: "Runtime Client"),
                capturedAt: observedAt
            )
        )
    }

    private static func projectCommand(
        accountId: AccountID,
        actor: PrincipalID
    ) throws -> CreateProjectCommand {
        try CreateProjectCommand(
            operationId: OperationID(validating: "operation-runtime-project"),
            draft: ProjectSetupDraft(
                accountId: accountId,
                actorPrincipalId: actor,
                operationContractVersion: OperationContractVersion(
                    validating: "project-create-v1"
                ),
                projectId: ProjectID(validating: "project-runtime"),
                clientSelection: ProjectClientSelectionInput(
                    existing: ClientID(validating: "client-runtime")
                ),
                displayName: ProjectDisplayName(validating: "Runtime Project"),
                description: nil,
                categoryAllocations: [],
                capturedAt: observedAt
            )
        )
    }

    private static func firstClientSnapshot(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> ClientListSnapshot {
        let query = Self.query(database, complete: true)
        var iterator = query
            .watchClients(accountId: accountId)
            .makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())
        await query.cancelAndDrainWatches()
        return snapshot
    }

    private static func insertActiveMembership(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_account_memberships (
              id, account_id, principal_id, role, state,
              can_manage_clients, can_manage_projects,
              can_manage_project_budgets, financial_access
            ) VALUES (?, ?, ?, 'owner', 'active', 1, 1, 1, 'full')
            """,
            parameters: [
                "membership-primary", accountId.rawValue, principalId.rawValue
            ]
        )
    }

    private static func insertClient(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        accountId: String = "account-primary",
        name: String,
        lifecycle: String
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_clients (
              id, account_id, display_name, lifecycle, revision,
              created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES (?, ?, ?, ?, 1, 1788500000000, 1788500001000, ?)
            """,
            parameters: [id, accountId, name, lifecycle, principalId.rawValue]
        )
    }

    private static func insertProject(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        clientId: String,
        name: String,
        lifecycle: String
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_projects (
              id, account_id, client_id, display_name, description, lifecycle,
              revision, created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES (?, ?, ?, ?, NULL, ?, 1, 1788500000000, 1788500001000, ?)
            """,
            parameters: [
                id, accountId.rawValue, clientId, name, lifecycle, principalId.rawValue
            ]
        )
    }

    private static func insertPendingClient(
        _ database: any PowerSyncDatabaseProtocol,
        clientId: String = "client-pending",
        actor: PrincipalID = principalId,
        name: String = "Pending Client",
        operationId: String = "operation-pending-client"
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_pending_clients (
              id, account_id, display_name, lifecycle, revision,
              created_at_ms, updated_at_ms, created_by_principal_id, operation_id
            ) VALUES (?, ?, ?, 'active', 1,
                      1788500000000, 1788500001000, ?, ?)
            """,
            parameters: [
                clientId, accountId.rawValue, name, actor.rawValue, operationId
            ]
        )
    }

    private static func insertPendingProject(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws {
        try await insertPendingProject(
            database,
            projectId: "project-pending",
            clientId: "client-pending"
        )
    }

    private static func insertPendingProject(
        _ database: any PowerSyncDatabaseProtocol,
        projectId: String,
        clientId: String,
        actor: PrincipalID = principalId,
        name: String = "Pending Project",
        operationId: String = "operation-pending-project"
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_pending_projects (
              id, account_id, client_id, display_name, description, lifecycle,
              revision, created_at_ms, updated_at_ms,
              created_by_principal_id, operation_id
            ) VALUES (?, ?, ?, ?, NULL, 'archived', 1,
                      1788500000000, 1788500001000, ?, ?)
            """,
            parameters: [
                projectId, accountId.rawValue, clientId, name,
                actor.rawValue, operationId
            ]
        )
    }

    private static func count(
        _ table: String,
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> Int64 {
        try await database.get(
            sql: "SELECT count(*) FROM \(table)",
            parameters: nil
        ) {
            try $0.getInt64(index: 0)
        }
    }
}

private final class DirectoryDatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    private let key: LedgerPowerSyncEncryptionKey
    private let environment: ValidatedLedgerEnvironment
    private let applicationSupportDirectory: URL

    init() throws {
        applicationSupportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ledger-directory-powersync-\(UUID().uuidString)",
            isDirectory: true
        )
        environment = try Self.makeEnvironment()
        let location = try LedgerWorkspaceRuntimeIsolation.resolve(
            validatedEnvironment: environment,
            principalId: PrincipalID(validating: "principal-owner"),
            accountId: AccountID(validating: "account-primary"),
            applicationSupportDirectory: applicationSupportDirectory
        )
        directoryURL = applicationSupportDirectory
        databaseURL = location.structuredDatabaseURL
        key = try LedgerPowerSyncEncryptionKey(
            hexadecimal: String(repeating: "4d", count: 32)
        )
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: databaseURL.path,
            encryptionKey: key
        )
    }

    func openRuntime() async throws -> LedgerOfflineClientRuntime {
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        dependencies.loadDatabaseKey = { [key] _, _ in key }
        dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x5e, count: 32) }
        dependencies.createDirectory = { directory in
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return try await LedgerPowerSyncLocalBootstrap.open(
            validatedEnvironment: environment,
            principalId: try PrincipalID(validating: "principal-owner"),
            accountId: try AccountID(validating: "account-primary"),
            applicationSupportDirectory: applicationSupportDirectory,
            dependencies: dependencies
        )
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func makeEnvironment() throws -> ValidatedLedgerEnvironment {
        let versions = LedgerContractVersions(
            schema: "schema-v1",
            query: "query-v1",
            operation: "operation-v1",
            sync: "sync-v1"
        )
        let resources = Dictionary(
            uniqueKeysWithValues: LedgerTargetComponent.allCases.map {
                ($0, "\($0.rawValue)-directory-fixture")
            }
        )
        let manifest = LedgerEnvironmentManifest(
            environment: .targetLocal,
            buildProfile: .targetLocalDevelopment,
            bundleIdentifier: "apps.nine4.ledger.target.local",
            displayName: "Ledger Target Local",
            localDataNamespacePrefix: "apps.nine4.ledger.target",
            contractVersions: versions,
            resources: LedgerTargetComponent.allCases.map { component in
                LedgerEnvironmentResource(
                    component: component,
                    environment: .targetLocal,
                    publicIdentifier: resources[component]!
                )
            }
        )
        return try LedgerEnvironmentValidator.validate(
            manifest,
            policy: LedgerEnvironmentPolicy(
                expectedEnvironment: .targetLocal,
                expectedBuildProfile: .targetLocalDevelopment,
                expectedBundleIdentifier: "apps.nine4.ledger.target.local",
                expectedContractVersions: versions,
                allowedResourceIdentifiers: resources.mapValues { [$0] },
                forbiddenResourceIdentifiers: [],
                forbiddenBundleIdentifiers: []
            )
        )
    }
}
