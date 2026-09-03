import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Transaction Type Choice Presentation Contracts")
struct TransactionTypeChoicePresentationTests {
    @Test("Canonical membership is literal and unordered")
    func literalUnorderedMembership() {
        let allTypes: Set<LedgerTransactionType> = [.purchase, .return, .transfer]
        let inventoryTypes: Set<LedgerTransactionType> = [.purchase, .return]

        #expect(Set(LedgerTransactionType.allCases) == allTypes)
        #expect(LedgerTransactionType.allCases.count == 3)
        #expect(TransactionTypeChoiceCatalog.membership(for: .project) == allTypes)
        #expect(
            TransactionTypeChoiceCatalog.membership(for: .businessInventory)
                == inventoryTypes
        )
        #expect(
            !TransactionTypeChoiceCatalog.membership(for: .businessInventory)
                .contains(.transfer)
        )
    }

    @Test("Standalone Purchase and Return presentation is scope-relative")
    func standalonePresentation() throws {
        let fixture = try Self.fixture()
        let cases: [(
            classification: TransactionClassification,
            type: LedgerTransactionType,
            typeTitle: String,
            owner: TransactionScopeOwnerKind,
            ownerTitle: String,
            meaning: TransactionEconomicMeaning
        )] = [
            (
                try Self.classification(.purchase, fixture.inventoryScope, .standalone),
                .purchase,
                "Purchase",
                .businessInventory,
                "1584",
                .scopeOwnerPaid
            ),
            (
                try Self.classification(.return, fixture.inventoryScope, .standalone),
                .return,
                "Return",
                .businessInventory,
                "1584",
                .scopeOwnerReceivedMoneyBack
            ),
            (
                try Self.classification(.purchase, fixture.sourceScope, .standalone),
                .purchase,
                "Purchase",
                .project,
                "Client",
                .scopeOwnerPaid
            ),
            (
                try Self.classification(.return, fixture.sourceScope, .standalone),
                .return,
                "Return",
                .project,
                "Client",
                .scopeOwnerReceivedMoneyBack
            )
        ]

        for item in cases {
            let descriptor = TransactionTypeChoicePresentationProjector.descriptor(
                for: item.classification
            )
            #expect(descriptor.transactionType == item.type)
            #expect(descriptor.transactionTypeTitle == item.typeTitle)
            #expect(descriptor.scopeOwnerKind == item.owner)
            #expect(descriptor.scopeOwnerTitle == item.ownerTitle)
            #expect(descriptor.economicMeaning == item.meaning)
            #expect(descriptor.economicMeaning == item.classification.economicMeaning)
        }
    }

    @Test("Transfer source and destination have one role-neutral presentation")
    func transferRoleNeutrality() throws {
        let fixture = try Self.fixture()
        let source = try Self.classification(.transfer, fixture.sourceScope, .transferSource)
        let destination = try Self.classification(
            .transfer,
            fixture.destinationScope,
            .transferDestination
        )
        let sourceDescriptor = TransactionTypeChoicePresentationProjector.descriptor(for: source)
        let destinationDescriptor = TransactionTypeChoicePresentationProjector.descriptor(
            for: destination
        )

        #expect(source.scope != destination.scope)
        #expect(source.role != destination.role)
        #expect(sourceDescriptor == destinationDescriptor)
        #expect(sourceDescriptor.transactionType == .transfer)
        #expect(sourceDescriptor.transactionTypeTitle == "Transfer")
        #expect(sourceDescriptor.scopeOwnerKind == .project)
        #expect(sourceDescriptor.scopeOwnerTitle == "Client")
        #expect(sourceDescriptor.economicMeaning == .nonCashSameClientReallocation)
        #expect(Set(Mirror(reflecting: sourceDescriptor).children.compactMap(\.label)) == [
            "transactionType", "transactionTypeTitle", "scopeOwnerKind",
            "scopeOwnerTitle", "economicMeaning"
        ])
    }

    @Test("All six classification shapes restart without persisting presentation")
    func canonicalClassificationRestart() throws {
        let fixture = try Self.fixture()
        let classifications = try Self.allValidClassifications(fixture)
        var restoredDescriptors: [TransactionTypeChoiceDescriptor] = []

        for classification in classifications {
            let bytes = try OperationContractCodec.encode(classification)
            let object = try #require(
                JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            )
            #expect(Set(object.keys) == ["type", "scope", "role"])
            let scope = try #require(object["scope"] as? [String: Any])
            let expectedScopeKeys: Set<String> = classification.scope.ownerKind == .project
                ? ["ownerKind", "accountId", "projectId", "clientId"]
                : ["ownerKind", "accountId"]
            #expect(Set(scope.keys) == expectedScopeKeys)

            let restored = try OperationContractCodec.decode(
                TransactionClassification.self,
                from: bytes
            )
            #expect(restored == classification)
            #expect(try OperationContractCodec.encode(restored) == bytes)

            let originalDescriptor = TransactionTypeChoicePresentationProjector.descriptor(
                for: classification
            )
            let restoredDescriptor = TransactionTypeChoicePresentationProjector.descriptor(
                for: restored
            )
            #expect(restoredDescriptor == originalDescriptor)
            #expect(!Self.isEncodable(restoredDescriptor))
            restoredDescriptors.append(restoredDescriptor)

            let text = String(decoding: bytes, as: UTF8.self)
            for absentPresentationValue in [
                "Purchase", "Return", "Transfer", "Client", "1584",
                "scopeOwnerPaid", "scopeOwnerReceivedMoneyBack",
                "nonCashSameClientReallocation"
            ] {
                #expect(!text.contains(absentPresentationValue))
            }
        }

        #expect(classifications.count == 6)
        #expect(restoredDescriptors[4] == restoredDescriptors[5])
    }

    @Test("Invalid taxonomy evidence fails before presentation")
    func existingTaxonomyRejectionAndExactTitles() throws {
        let fixture = try Self.fixture()

        #expect(Self.decodeFailure(Data(#""sale""#.utf8), as: LedgerTransactionType.self)
            == .invalidEncodedTransactionType)
        #expect(Self.decodeFailure(
            Data(#""warehouse""#.utf8),
            as: TransactionScopeOwnerKind.self
        ) == .invalidEncodedScopeOwner)
        #expect(Self.decodeFailure(
            Data(#""incoming""#.utf8),
            as: TransactionRecordRole.self
        ) == .invalidEncodedRecordRole)

        let malformedScope = Data(
            #"{"accountId":"account-main","ownerKind":"project","projectId":"project-source"}"#.utf8
        )
        #expect(Self.decodeFailure(malformedScope, as: TransactionScope.self)
            == .invalidTransactionScope)
        #expect(Self.failure {
            try Self.classification(.purchase, fixture.sourceScope, .transferSource)
        } == .incompatibleRecordRole)
        #expect(Self.failure {
            try Self.classification(.transfer, fixture.sourceScope, .standalone)
        } == .incompatibleRecordRole)
        #expect(Self.failure {
            try Self.classification(.transfer, fixture.inventoryScope, .transferSource)
        } == .transferRequiresProjectScope)

        #expect(Self.decodeFailure(Data("{}".utf8), as: TransactionClassification.self)
            == .invalidEncodedClassification)
        let wrongAggregateFields = Data(
            #"{"kind":"purchase","owner":"project","recordRole":"standalone"}"#.utf8
        )
        #expect(Self.decodeFailure(
            wrongAggregateFields,
            as: TransactionClassification.self
        ) == .invalidEncodedClassification)
        #expect(Self.decodeFailure(
            Data("null".utf8),
            as: TransactionClassification.self
        ) == .invalidEncodedClassification)

        let displayTitles = Set(
            try Self.allValidClassifications(fixture).flatMap { classification in
                let descriptor = TransactionTypeChoicePresentationProjector.descriptor(
                    for: classification
                )
                return [descriptor.transactionTypeTitle, descriptor.scopeOwnerTitle]
            }
        )
        #expect(displayTitles == ["Purchase", "Return", "Transfer", "Client", "1584"])
        #expect(displayTitles.isDisjoint(with: [
            "Sale", "Payment to Business", "Fee", "Expense", "To Inventory",
            "Reimbursement", "Movement", "Incoming", "Outgoing", "Debit", "Credit",
            "Positive", "Negative", "Pending", "Complete", "Submit", "Delete"
        ]))
    }

    @Test("A test-only consumer composes validation, membership, and presentation")
    func testOnlyConsumer() throws {
        let fixture = try Self.fixture()
        let classifications = try Self.allValidClassifications(fixture)
        let results = try classifications.map {
            Self.consume(try OperationContractCodec.encode($0))
        }
        let descriptors = results.compactMap { result -> TransactionTypeChoiceDescriptor? in
            guard case let .descriptor(descriptor) = result else { return nil }
            return descriptor
        }

        #expect(descriptors.count == 6)
        #expect(Set(descriptors.map(\.transactionType)) == [.purchase, .return, .transfer])
        #expect(Set(descriptors.map(\.scopeOwnerKind)) == [.project, .businessInventory])
        #expect(Set(
            descriptors
                .filter { $0.scopeOwnerKind == .businessInventory }
                .map(\.transactionType)
        ) == [.purchase, .return])
        #expect(Set(
            descriptors
                .filter { $0.scopeOwnerKind == .project }
                .map(\.transactionType)
        ) == [.purchase, .return, .transfer])
        #expect(descriptors[4] == descriptors[5])
        #expect(Self.consume(Data("{}".utf8)) == .rejected(.invalidEncodedClassification))
    }

    private struct Fixture: Sendable {
        let accountId: AccountID
        let inventoryScope: TransactionScope
        let sourceScope: TransactionScope
        let destinationScope: TransactionScope
    }

    private enum ConsumerResult: Equatable {
        case descriptor(TransactionTypeChoiceDescriptor)
        case rejected(TransactionTaxonomyFailure)
        case unexpected
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-main")
        return Fixture(
            accountId: accountId,
            inventoryScope: .businessInventory(accountId: accountId),
            sourceScope: .project(
                accountId: accountId,
                projectId: try ProjectID(validating: "project-source"),
                clientId: try ClientID(validating: "client-main")
            ),
            destinationScope: .project(
                accountId: accountId,
                projectId: try ProjectID(validating: "project-destination"),
                clientId: try ClientID(validating: "client-main")
            )
        )
    }

    private static func classification(
        _ type: LedgerTransactionType,
        _ scope: TransactionScope,
        _ role: TransactionRecordRole
    ) throws -> TransactionClassification {
        try TransactionClassification(type: type, scope: scope, role: role)
    }

    private static func allValidClassifications(
        _ fixture: Fixture
    ) throws -> [TransactionClassification] {
        try [
            classification(.purchase, fixture.inventoryScope, .standalone),
            classification(.return, fixture.inventoryScope, .standalone),
            classification(.purchase, fixture.sourceScope, .standalone),
            classification(.return, fixture.sourceScope, .standalone),
            classification(.transfer, fixture.sourceScope, .transferSource),
            classification(.transfer, fixture.destinationScope, .transferDestination)
        ]
    }

    private static func failure<Value>(
        _ body: () throws -> Value
    ) -> TransactionTaxonomyFailure? {
        do { _ = try body(); return nil }
        catch let failure as TransactionTaxonomyFailure { return failure }
        catch { return nil }
    }

    private static func decodeFailure<Value: Decodable>(
        _ data: Data,
        as type: Value.Type
    ) -> TransactionTaxonomyFailure? {
        failure { try OperationContractCodec.decode(type, from: data) }
    }

    private static func isEncodable(_ value: Any) -> Bool {
        value is any Encodable
    }

    private static func consume(_ bytes: Data) -> ConsumerResult {
        do {
            let classification = try OperationContractCodec.decode(
                TransactionClassification.self,
                from: bytes
            )
            guard TransactionTypeChoiceCatalog.membership(
                for: classification.scope.ownerKind
            ).contains(classification.type) else {
                return .unexpected
            }
            return .descriptor(
                TransactionTypeChoicePresentationProjector.descriptor(for: classification)
            )
        } catch let failure as TransactionTaxonomyFailure {
            return .rejected(failure)
        } catch {
            return .unexpected
        }
    }
}
