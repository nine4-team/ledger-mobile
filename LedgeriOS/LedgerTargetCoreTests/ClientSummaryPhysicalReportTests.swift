import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("ClientSummaryPhysicalReport snapshot")
struct ClientSummaryPhysicalReportTests {
    @Test func stableOrderingAndIdentity() throws {
        let a = try fixture(indices: [2, 1]), b = try fixture(indices: [1, 2])
        #expect(a == b)
        #expect(a.items.map(\.itemId.rawValue) == ["item-1", "item-2"])
        #expect(a.isComplete)
        #expect(try ProtectedArtifactSHA256.make(bytes: a.canonicalContentData()) == a.reference.snapshotHash)
        let changedClient = try fixture(indices: [1, 2], clientRevision: 2)
        #expect(changedClient.sourceSetHash != a.sourceSetHash)
        let missingCategory = try fixture(indices: [1, 2], knownCategory: false)
        #expect(!missingCategory.isComplete)
        #expect(missingCategory.sourceSetHash != a.sourceSetHash)
        let json = String(decoding: try a.canonicalData(), as: UTF8.self)
        for forbidden in ["marketValue", "budget", "receipt", "totalSpent", "minorUnits"] {
            #expect(!json.contains(forbidden))
        }
    }

    @Test func rejectsBrokenRelationships() throws {
        let base = try fixture(indices: [1])
        #expect(throws: ClientSummaryPhysicalReportFailure.duplicateItem) {
            try ClientSummaryPhysicalReportSnapshot.build(project: base.project, client: base.client,
                spaces: base.spaces, items: base.items + base.items, provenance: base.provenance)
        }
        #expect(throws: ClientSummaryPhysicalReportFailure.missingSpace) {
            try ClientSummaryPhysicalReportSnapshot.build(project: base.project, client: base.client,
                spaces: [], items: base.items, provenance: base.provenance)
        }
        #expect(throws: ClientSummaryPhysicalReportFailure.invalidRevision) {
            try fixture(indices: [], clientRevision: 0)
        }
        let missingClient = try ClientSummaryPhysicalReportSnapshot.build(project: base.project,
            client: .unavailable(clientId: ClientID(validating: "client")), spaces: base.spaces,
            items: base.items, provenance: base.provenance)
        #expect(!missingClient.isComplete)
    }

    @Test func sameLabelDoesNotMergePhysicalIdentities() throws {
        let base = try fixture(indices: [1, 2])
        #expect(base.items.count == 2)
        #expect(base.items[0].name == base.items[1].name)
        let other = ClientSummaryPhysicalReportItem(accountId: base.project.accountId,
            projectId: base.project.projectId, itemId: try ItemID(validating: "item-3"),
            placementId: try EntityID(validating: "placement-3"), spaceId: nil, name: "Chair", sku: nil,
            category: .known(categoryId: try BudgetCategoryID(validating: "category"), name: "Conflicting name"), itemRevision: 1)
        #expect(throws: ClientSummaryPhysicalReportFailure.conflictingCategory) {
            try ClientSummaryPhysicalReportSnapshot.build(project: base.project, client: base.client,
                spaces: base.spaces, items: base.items + [other], provenance: base.provenance)
        }
    }

    @Test func rejectsBlankNamesAndEncodesExactRevisions() throws {
        let base = try fixture(indices: [1], clientRevision: 9_007_199_254_740_993)
        let json = String(decoding: try base.canonicalData(), as: UTF8.self)
        #expect(json.contains("\"revision\":\"9007199254740993\""))
        #expect(json.contains("\"itemRevision\":\"1\""))
        #expect(throws: (any Error).self) {
            try ClientSummaryPhysicalReportSnapshot.build(project: base.project,
                client: .known(clientId: ClientID(validating: "client"), name: "  ", revision: 1),
                spaces: base.spaces, items: base.items, provenance: base.provenance)
        }
        let item = base.items[0]
        let invalid = ClientSummaryPhysicalReportItem(accountId: item.accountId, projectId: item.projectId,
            itemId: item.itemId, placementId: item.placementId, spaceId: item.spaceId, name: item.name,
            sku: item.sku, category: .known(categoryId: try BudgetCategoryID(validating: "category"), name: " "),
            itemRevision: 9_007_199_254_740_993)
        #expect(String(decoding: try JSONEncoder().encode(invalid), as: UTF8.self).contains("\"itemRevision\":\"9007199254740993\""))
        #expect(throws: (any Error).self) {
            try ClientSummaryPhysicalReportSnapshot.build(project: base.project, client: base.client,
                spaces: base.spaces, items: [invalid], provenance: base.provenance)
        }
    }

    @Test func unknownAccountingRemainsIncompleteAndUnaccountedItemsAreExcluded() throws {
        let base = try fixture(indices: [1, 2])
        let item = base.items[0]
        func replacing(_ row: ProjectItemAccountingRow?) -> ClientSummaryPhysicalReportItem {
            .init(accountId: item.accountId, projectId: item.projectId, itemId: item.itemId,
                  placementId: item.placementId, spaceId: item.spaceId, name: item.name,
                  sku: item.sku, category: item.category, itemRevision: item.itemRevision, accounting: row)
        }
        func snapshot(_ row: ProjectItemAccountingRow?) throws -> ClientSummaryPhysicalReportSnapshot {
            try .build(project: base.project, client: base.client, spaces: base.spaces,
                       items: [replacing(row), base.items[1]], provenance: base.provenance)
        }
        #expect(try !snapshot(nil).isComplete)
        let absent = try ProjectItemAccountingEvidence(accountId: item.accountId, projectId: item.projectId,
            clientId: ClientID(validating: "client"), itemId: item.itemId, spaceId: item.spaceId)
        #expect(try !snapshot(.init(evidence: absent, relationshipAbsenceIsAuthoritative: false)).isComplete)
        let excluded = try snapshot(.init(evidence: absent, relationshipAbsenceIsAuthoritative: true))
        #expect(excluded.isComplete)
        #expect(excluded.items.map(\.itemId) == [base.items[1].itemId])
        #expect(!String(decoding: try excluded.canonicalData(), as: UTF8.self).contains("item-1"))
        let onlyEligible = try fixture(indices: [2])
        #expect(excluded.items == onlyEligible.items)
        #expect(excluded.sourceSetHash != onlyEligible.sourceSetHash)
        #expect(excluded.sourceSetHash != base.sourceSetHash)
    }

    @Test func rejectsForeignAndMismatchedAccountingEvidence() throws {
        let base = try fixture(indices: [1]), item = base.items[0]
        for field in ["account", "project", "client", "item", "space"] {
            let evidence = try ProjectItemAccountingEvidence(
                accountId: field == "account" ? AccountID(validating: "foreign") : item.accountId,
                projectId: field == "project" ? ProjectID(validating: "foreign") : item.projectId,
                clientId: ClientID(validating: field == "client" ? "foreign" : "client"),
                itemId: field == "item" ? ItemID(validating: "foreign") : item.itemId,
                spaceId: field == "space" ? nil : item.spaceId)
            let invalid = ClientSummaryPhysicalReportItem(accountId: item.accountId, projectId: item.projectId,
                itemId: item.itemId, placementId: item.placementId, spaceId: item.spaceId, name: item.name,
                sku: item.sku, category: item.category, itemRevision: 1,
                accounting: .init(evidence: evidence, relationshipAbsenceIsAuthoritative: true))
            #expect(throws: ClientSummaryPhysicalReportFailure.scopeMismatch) {
                try ClientSummaryPhysicalReportSnapshot.build(project: base.project, client: base.client,
                    spaces: base.spaces, items: [invalid], provenance: base.provenance)
            }
        }
    }

    private func fixture(indices: [Int], clientRevision: UInt64 = 1,
                         knownCategory: Bool = true) throws -> ClientSummaryPhysicalReportSnapshot {
        let account = try AccountID(validating: "account"), project = try ProjectID(validating: "project")
        let space = try SpaceID(validating: "space")
        return try .build(project: .init(accountId: account, projectId: project, name: "Home", address: nil, revision: 1),
            client: .known(clientId: ClientID(validating: "client"), name: "Client", revision: clientRevision),
            spaces: [.init(accountId: account, projectId: project, spaceId: space, name: "No Space", revision: 1)],
            items: indices.map { index in
                .init(accountId: account, projectId: project, itemId: try ItemID(validating: "item-\(index)"),
                    placementId: try EntityID(validating: "placement-\(index)"), spaceId: space, name: "Chair", sku: nil,
                    category: knownCategory ? .known(categoryId: try BudgetCategoryID(validating: "category"), name: "Furnishings") : .unavailable,
                    itemRevision: 1, accounting: .init(evidence: try ProjectItemAccountingEvidence(
                        accountId: account, projectId: project, clientId: ClientID(validating: "client"),
                        itemId: ItemID(validating: "item-\(index)"), spaceId: space,
                        billableOccurrences: [.init(id: BillableItemOccurrenceID(validating: "charge-\(index)"),
                            accountId: account, projectId: project, itemId: ItemID(validating: "item-\(index)"),
                            polarity: .charge, phase: .availableToInvoice)]), relationshipAbsenceIsAuthoritative: true))
            }, provenance: .init(accountId: account, projectId: project, principalId: PrincipalID(validating: "principal"),
                visibilityScopeID: .make(bytes: Data("scope".utf8)), localDataVersion: .init(validating: "v1"),
                authorityVersion: .init(validating: "authority1"), asOf: .init(validating: 1_800_000_000_000),
                readiness: .ready, lastSyncedAt: .init(validating: 1_800_000_000_000)))
    }
}
