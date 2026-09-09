import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Property Management report accounting eligibility")
struct PropertyManagementReportEligibilityTests {
    private let account = try! AccountID(validating: "account")
    private let project = try! ProjectID(validating: "project")

    @Test func unknownRelationshipCannotBecomeAReport() throws {
        #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
            try snapshot([item("unknown", accounting: nil)])
        }
        #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
            try snapshot([item("unknown", accounting: row("unknown", accounted: false, complete: false))])
        }
    }

    @Test func excludesUnaccountedItemsAndTheirValue() throws {
        let accounted = try item("eligible", accounting: row("eligible", accounted: true))
        let unaccounted = try item("excluded", accounting: row("excluded", accounted: false))
        let result = try snapshot([unaccounted, accounted])
        #expect(result.totals.itemCount == 1)
        #expect(result.totals.knownMarketValueSubtotal.minorUnits == 500)
        #expect(result.groups.flatMap(\.rows).map(\.itemId.rawValue) == ["eligible"])
        #expect(!String(decoding: try result.canonicalData(), as: UTF8.self).contains("excluded"))
        #expect(result.sourceSetHash != (try snapshot([accounted])).sourceSetHash)
        #expect(try snapshot([unaccounted, accounted]) == snapshot([accounted, unaccounted]))
    }

    @Test func rejectsMismatchedRelationship() throws {
        #expect(throws: PropertyManagementReportFailure.scopeMismatch) {
            try snapshot([item("item", accounting: row("different", accounted: true))])
        }
    }

    @Test func excludedItemCurrencyDoesNotAffectReport() throws {
        let excluded = try PropertyManagementReportItem(accountId: account, projectId: project,
            itemId: ItemID(validating: "excluded"), placementId: EntityID(validating: "placement-excluded"),
            spaceId: nil, name: "Excluded", sku: nil,
            marketValue: Money(minorUnits: 100, currency: CurrencyCode(validating: "EUR")), itemRevision: 1,
            accounting: row("excluded", accounted: false))
        let eligible = try item("eligible", accounting: row("eligible", accounted: true))
        let result = try snapshot([excluded, eligible])
        #expect(result.totals.itemCount == 1)
        #expect(result.totals.totalMarketValue?.minorUnits == 500)
    }

    private func row(_ id: String, accounted: Bool, complete: Bool = true) throws -> ProjectItemAccountingRow {
        let itemId = try ItemID(validating: id)
        let occurrences: [BillableItemAccountingOccurrence] = accounted ? [
            .init(id: try BillableItemOccurrenceID(validating: "charge-\(id)"), accountId: account,
                  projectId: project, itemId: itemId, polarity: .charge, phase: .availableToInvoice)
        ] : []
        return try .init(evidence: .init(accountId: account, projectId: project,
            clientId: ClientID(validating: "client"), itemId: itemId, billableOccurrences: occurrences),
            relationshipAbsenceIsAuthoritative: complete)
    }

    private func item(_ id: String, accounting: ProjectItemAccountingRow?) throws -> PropertyManagementReportItem {
        try .init(accountId: account, projectId: project, itemId: ItemID(validating: id),
            placementId: EntityID(validating: "placement-\(id)"), spaceId: nil, name: id, sku: nil,
            marketValue: Money(minorUnits: 500, currency: CurrencyCode(validating: "USD")),
            itemRevision: 1, accounting: accounting)
    }

    private func snapshot(_ items: [PropertyManagementReportItem]) throws -> PropertyManagementReportSnapshot {
        try .build(project: .init(accountId: account, projectId: project, name: "Home", address: nil, revision: 1),
            spaces: [], items: items, currency: CurrencyCode(validating: "USD"),
            provenance: .init(accountId: account, projectId: project, principalId: PrincipalID(validating: "principal"),
                visibilityScopeID: .make(bytes: Data("scope".utf8)), source: .authoritative,
                authorityVersion: .init(validating: "eligibility-test"), asOf: .init(validating: 1_800_000_000_000),
                readiness: .ready))
    }
}
