import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Live Invoice wire contents")
struct LiveInvoiceWireSnapshotTests {
    private let json = #"{"accountId":"account","projectId":"project","clientId":"client","invoiceId":"invoice","revision":"1","status":"sent","name":"Phase 1","notes":"External delivery","currency":"USD","totalMinorUnits":"9007199254740993","lines":[{"kind":"expense","sourceId":"expense","sourceRevision":"2","amountMinorUnits":"9007199254740993","currency":"USD","categoryId":"category","description":"Vendor"}]}"#
    private func read(_ text: String) throws -> LiveInvoiceContents {
        try JSONDecoder().decode(LiveInvoiceWireSnapshot.self, from: Data(text.utf8)).contents(
            accountId: .init(validating: "account"), projectId: .init(validating: "project"),
            invoiceId: .init(validating: "invoice"))
    }
    @Test func preservesExactLiveFacts() throws {
        let result = try read(json)
        #expect(result.total.minorUnits == 9_007_199_254_740_993)
        #expect(result.status == .sent)
        #expect(result.lines[0].selection.expectedRevision == 2)
        #expect(result.lines[0].description == "Vendor")
        #expect(result.selection.scope.clientId?.rawValue == "client")
    }
    @Test func rejectsScopePaidMalformedAndInconsistentContents() throws {
        for (before, after) in [("\"account\"", "\"foreign\""), ("\"sent\"", "\"paid\""),
            ("\"sourceRevision\":\"2\"", "\"sourceRevision\":\"0\""),
            ("\"revision\":\"1\"", "\"revision\":\"01\""),
            ("\"totalMinorUnits\":\"9007199254740993\"", "\"totalMinorUnits\":\"1\""),
            ("\"kind\":\"expense\"", "\"kind\":\"unknown\"")] {
            #expect(throws: (any Error).self) { try read(json.replacingOccurrences(of: before, with: after)) }
        }
    }
}
