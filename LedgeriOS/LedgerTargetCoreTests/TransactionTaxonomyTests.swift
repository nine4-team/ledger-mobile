import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Transaction Taxonomy and Transfer Identity")
struct TransactionTaxonomyTests {
    @Test("Exactly three types preserve scope-owner and non-cash meaning")
    func exactTaxonomyAndScopeMeaning() throws {
        let fixture = try Self.fixture()
        #expect(LedgerTransactionType.allCases == [.purchase, .return, .transfer])

        let inventoryPurchase = try TransactionClassification(
            type: .purchase,
            scope: .businessInventory(accountId: fixture.accountId),
            role: .standalone
        )
        let inventoryReturn = try TransactionClassification(
            type: .return,
            scope: .businessInventory(accountId: fixture.accountId),
            role: .standalone
        )
        let projectPurchase = try TransactionClassification(
            type: .purchase,
            scope: fixture.sourceScope,
            role: .standalone
        )
        let projectReturn = try TransactionClassification(
            type: .return,
            scope: fixture.sourceScope,
            role: .standalone
        )
        let transferSource = try TransactionClassification(
            type: .transfer,
            scope: fixture.sourceScope,
            role: .transferSource
        )
        let transferDestination = try TransactionClassification(
            type: .transfer,
            scope: fixture.destinationScope,
            role: .transferDestination
        )

        #expect(inventoryPurchase.economicMeaning == .scopeOwnerPaid)
        #expect(projectPurchase.economicMeaning == .scopeOwnerPaid)
        #expect(inventoryReturn.economicMeaning == .scopeOwnerReceivedMoneyBack)
        #expect(projectReturn.economicMeaning == .scopeOwnerReceivedMoneyBack)
        #expect(transferSource.economicMeaning == .nonCashSameClientReallocation)
        #expect(transferDestination.economicMeaning == .nonCashSameClientReallocation)
        #expect(inventoryPurchase.scope.projectId == nil)
        #expect(inventoryPurchase.scope.clientId == nil)
        #expect(projectPurchase.scope.projectId == fixture.sourceProject.id)
        #expect(projectPurchase.scope.clientId == fixture.client.id)
    }

    @Test("A same-Client route binds one exact distinct Transfer pair")
    func validTransferRouteAndPair() throws {
        let fixture = try Self.fixture()
        let route = try ProjectTransferRoute(
            source: fixture.sourceProject,
            destination: fixture.destinationProject
        )
        let pair = try TransferPairIdentity(
            operationId: OperationID(validating: "operation-transfer-001"),
            route: route,
            sourceTransactionId: TransactionID(validating: "transaction-source-001"),
            destinationTransactionId: TransactionID(
                validating: "transaction-destination-001"
            )
        )

        #expect(route.source.accountId == fixture.accountId)
        #expect(route.destination.accountId == fixture.accountId)
        #expect(route.source.clientId == fixture.client.id)
        #expect(route.destination.clientId == fixture.client.id)
        #expect(route.source.projectId == fixture.sourceProject.id)
        #expect(route.destination.projectId == fixture.destinationProject.id)
        #expect(route.destinationLifecycle == .active)
        #expect(pair.route == route)
        #expect(pair.sourceTransactionId != pair.destinationTransactionId)
    }

    @Test("Canonical classification, route, and pair evidence survives restart")
    func canonicalRestart() throws {
        let fixture = try Self.fixture()
        let route = try ProjectTransferRoute(
            source: fixture.sourceProject,
            destination: fixture.destinationProject
        )
        let restart = RestartFixture(
            classifications: [
                try TransactionClassification(
                    type: .purchase,
                    scope: .businessInventory(accountId: fixture.accountId),
                    role: .standalone
                ),
                try TransactionClassification(
                    type: .return,
                    scope: fixture.sourceScope,
                    role: .standalone
                ),
                try TransactionClassification(
                    type: .transfer,
                    scope: fixture.sourceScope,
                    role: .transferSource
                ),
                try TransactionClassification(
                    type: .transfer,
                    scope: fixture.destinationScope,
                    role: .transferDestination
                )
            ],
            pair: try TransferPairIdentity(
                operationId: OperationID(validating: "operation-transfer-restart"),
                route: route,
                sourceTransactionId: TransactionID(
                    validating: "transaction-source-restart"
                ),
                destinationTransactionId: TransactionID(
                    validating: "transaction-destination-restart"
                )
            )
        )

        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(
            RestartFixture.self,
            from: bytes
        )

        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.classifications.map(\.economicMeaning) == [
            .scopeOwnerPaid,
            .scopeOwnerReceivedMoneyBack,
            .nonCashSameClientReallocation,
            .nonCashSameClientReallocation
        ])
    }

    @Test("Invalid type, scope, role, route, and pair combinations fail")
    func invalidTaxonomyEvidence() throws {
        let fixture = try Self.fixture()
        let inventory = TransactionScope.businessInventory(accountId: fixture.accountId)

        #expect(Self.captureFailure {
            _ = try TransactionClassification(
                type: .transfer,
                scope: inventory,
                role: .transferSource
            )
        } == .transferRequiresProjectScope)
        #expect(Self.captureFailure {
            _ = try TransactionClassification(
                type: .purchase,
                scope: fixture.sourceScope,
                role: .transferSource
            )
        } == .incompatibleRecordRole)
        #expect(Self.captureFailure {
            _ = try TransactionClassification(
                type: .transfer,
                scope: fixture.sourceScope,
                role: .standalone
            )
        } == .incompatibleRecordRole)

        #expect(Self.captureFailure {
            _ = try TransactionScope(
                ownerKind: .businessInventory,
                accountId: fixture.accountId,
                projectId: fixture.sourceProject.id,
                clientId: fixture.client.id
            )
        } == .invalidTransactionScope)
        #expect(Self.captureFailure {
            _ = try TransactionScope(
                ownerKind: .project,
                accountId: fixture.accountId,
                projectId: fixture.sourceProject.id,
                clientId: nil
            )
        } == .invalidTransactionScope)
        #expect(Self.captureFailure {
            _ = try ProjectTransferRoute(
                source: inventory,
                destination: fixture.destinationScope,
                destinationLifecycle: .active
            )
        } == .transferRouteRequiresProjectScopes)

        let sameProject = try Self.project(
            id: fixture.sourceProject.id,
            accountId: fixture.accountId,
            client: fixture.client,
            lifecycle: .active
        )
        #expect(Self.captureFailure {
            _ = try ProjectTransferRoute(
                source: fixture.sourceProject,
                destination: sameProject
            )
        } == .transferRouteSameProject)

        let otherAccount = try AccountID(validating: "account-other")
        let otherAccountClient = try Self.client(
            id: "client-001",
            accountId: otherAccount,
            displayName: fixture.client.displayName
        )
        let crossAccountProject = try Self.project(
            id: ProjectID(validating: "project-other-account"),
            accountId: otherAccount,
            client: otherAccountClient,
            lifecycle: .active
        )
        #expect(Self.captureFailure {
            _ = try ProjectTransferRoute(
                source: fixture.sourceProject,
                destination: crossAccountProject
            )
        } == .transferRouteAccountMismatch)

        let sameNameOtherClient = try Self.client(
            id: "client-same-name-other-id",
            accountId: fixture.accountId,
            displayName: fixture.client.displayName
        )
        let crossClientProject = try Self.project(
            id: ProjectID(validating: "project-other-client"),
            accountId: fixture.accountId,
            client: sameNameOtherClient,
            lifecycle: .active
        )
        #expect(Self.captureFailure {
            _ = try ProjectTransferRoute(
                source: fixture.sourceProject,
                destination: crossClientProject
            )
        } == .transferRouteClientMismatch)

        let archivedDestination = try Self.project(
            id: fixture.destinationProject.id,
            accountId: fixture.accountId,
            client: fixture.client,
            lifecycle: .archived
        )
        #expect(Self.captureFailure {
            _ = try ProjectTransferRoute(
                source: fixture.sourceProject,
                destination: archivedDestination
            )
        } == .transferDestinationArchived)

        let route = try ProjectTransferRoute(
            source: fixture.sourceProject,
            destination: fixture.destinationProject
        )
        let repeatedTransactionId = try TransactionID(validating: "transaction-repeated")
        #expect(Self.captureFailure {
            _ = try TransferPairIdentity(
                operationId: OperationID(validating: "operation-repeated"),
                route: route,
                sourceTransactionId: repeatedTransactionId,
                destinationTransactionId: repeatedTransactionId
            )
        } == .duplicateTransferRecordIdentity)

        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                LedgerTransactionType.self,
                from: Data(#""sale""#.utf8)
            )
        } == .invalidEncodedTransactionType)
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransactionScopeOwnerKind.self,
                from: Data(#""warehouse""#.utf8)
            )
        } == .invalidEncodedScopeOwner)
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransactionRecordRole.self,
                from: Data(#""source""#.utf8)
            )
        } == .invalidEncodedRecordRole)
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransactionClassification.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedClassification)

        let invalidDecodedClassification = Data(
            #"{"role":"transferSource","scope":{"accountId":"account-main","ownerKind":"businessInventory"},"type":"transfer"}"#.utf8
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransactionClassification.self,
                from: invalidDecodedClassification
            )
        } == .transferRequiresProjectScope)

        let validRouteBytes = try OperationContractCodec.encode(route)
        let invalidRouteBytes = Data(
            String(decoding: validRouteBytes, as: UTF8.self)
                .replacingOccurrences(of: #""active""#, with: #""retired""#)
                .utf8
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                ProjectTransferRoute.self,
                from: invalidRouteBytes
            )
        } == .invalidEncodedTransferRoute)

        let pair = try TransferPairIdentity(
            operationId: OperationID(validating: "operation-decode-pair"),
            route: route,
            sourceTransactionId: TransactionID(validating: "transaction-source-decode"),
            destinationTransactionId: TransactionID(
                validating: "transaction-destination-decode"
            )
        )
        let validPairBytes = try OperationContractCodec.encode(pair)
        let invalidPairBytes = Data(
            String(decoding: validPairBytes, as: UTF8.self)
                .replacingOccurrences(
                    of: "transaction-destination-decode",
                    with: "transaction-source-decode"
                )
                .utf8
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferPairIdentity.self,
                from: invalidPairBytes
            )
        } == .duplicateTransferRecordIdentity)
        let invalidPairEncoding = Data(
            String(decoding: validPairBytes, as: UTF8.self)
                .replacingOccurrences(of: "operation-decode-pair", with: " ")
                .utf8
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransferPairIdentity.self,
                from: invalidPairEncoding
            )
        } == .invalidEncodedTransferPair)

        let diagnostics: [(TransactionTaxonomyFailure, String)] = [
            (.invalidEncodedTransactionType, "transaction_taxonomy_type_invalid"),
            (.invalidEncodedScopeOwner, "transaction_taxonomy_scope_owner_invalid"),
            (.invalidTransactionScope, "transaction_taxonomy_scope_invalid"),
            (.invalidEncodedRecordRole, "transaction_taxonomy_record_role_invalid"),
            (
                .invalidEncodedClassification,
                "transaction_taxonomy_classification_encoding_invalid"
            ),
            (.incompatibleRecordRole, "transaction_taxonomy_record_role_incompatible"),
            (
                .transferRequiresProjectScope,
                "transaction_taxonomy_transfer_project_scope_required"
            ),
            (
                .transferRouteRequiresProjectScopes,
                "transaction_taxonomy_route_project_scope_required"
            ),
            (.transferRouteAccountMismatch, "transaction_taxonomy_route_account_mismatch"),
            (.transferRouteClientMismatch, "transaction_taxonomy_route_client_mismatch"),
            (.transferRouteSameProject, "transaction_taxonomy_route_same_project"),
            (
                .transferDestinationArchived,
                "transaction_taxonomy_route_destination_archived"
            ),
            (.invalidEncodedTransferRoute, "transaction_taxonomy_route_encoding_invalid"),
            (
                .duplicateTransferRecordIdentity,
                "transaction_taxonomy_pair_record_duplicate"
            ),
            (.invalidEncodedTransferPair, "transaction_taxonomy_pair_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    private struct Fixture: Sendable {
        let accountId: AccountID
        let client: ClientSummary
        let sourceProject: ProjectSummary
        let destinationProject: ProjectSummary
        let sourceScope: TransactionScope
        let destinationScope: TransactionScope
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let classifications: [TransactionClassification]
        let pair: TransferPairIdentity
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-main")
        let client = try Self.client(
            id: "client-001",
            accountId: accountId,
            displayName: ClientDisplayName(validating: "1584 Design Client")
        )
        let sourceProject = try Self.project(
            id: ProjectID(validating: "project-source"),
            accountId: accountId,
            client: client,
            lifecycle: .active
        )
        let destinationProject = try Self.project(
            id: ProjectID(validating: "project-destination"),
            accountId: accountId,
            client: client,
            lifecycle: .active
        )
        return Fixture(
            accountId: accountId,
            client: client,
            sourceProject: sourceProject,
            destinationProject: destinationProject,
            sourceScope: .project(
                accountId: accountId,
                projectId: sourceProject.id,
                clientId: client.id
            ),
            destinationScope: .project(
                accountId: accountId,
                projectId: destinationProject.id,
                clientId: client.id
            )
        )
    }

    private static func client(
        id: String,
        accountId: AccountID,
        displayName: ClientDisplayName
    ) throws -> ClientSummary {
        try ClientSummary(
            id: ClientID(validating: id),
            accountId: accountId,
            displayName: displayName,
            lifecycle: .active,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
    }

    private static func project(
        id: ProjectID,
        accountId: AccountID,
        client: ClientSummary,
        lifecycle: DirectoryLifecycleState
    ) throws -> ProjectSummary {
        try ProjectSummary(
            id: id,
            accountId: accountId,
            clientId: client.id,
            client: client,
            displayName: ProjectDisplayName(validating: "Project \(id.rawValue)"),
            description: nil,
            lifecycle: lifecycle
        )
    }

    private static func captureFailure<Value>(
        _ body: () throws -> Value
    ) -> TransactionTaxonomyFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as TransactionTaxonomyFailure {
            return failure
        } catch {
            return nil
        }
    }
}
