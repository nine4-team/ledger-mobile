import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Payment batch SQL parameter boundary")
struct FirebaseClientPaymentImportParametersTests {
    @Test("Real batch produces exact operator parameters consumed by the database integration test")
    func exactParameters() throws {
        let batch = try Self.batch()
        let parameters = try FirebaseClientPaymentImportParameters.make(batch: batch, currency: CurrencyCode(validating: "USD"))
        #expect(parameters.count == 1)
        let actual = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters[0])) as? [String: String])
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let expected = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appending(path: "ClientPayment/import-parameters.json"))) as? [String: String])
        #expect(actual == expected)
        #expect(actual["p_amount"] == "9007199254740993")
        // Includes full path/scope/record metadata, line IDs and embedded NUL note,
        // not a lossy amount-only reconstruction or executable SQL.
        #expect(actual["p_source_bytes"]?.hasPrefix("\\x") == true)
    }

    @Test("Unresolved or overflowing batches cannot export a partial executable import")
    func unresolvedBatch() throws {
        let valid = try Self.batch()
        let overflow = FirebasePaymentBatchResult(entries: valid.entries, mappedTotalCents: nil)
        #expect(throws: FirebaseClientPaymentImportFailure.self) {
            try FirebaseClientPaymentImportParameters.make(batch: overflow, currency: CurrencyCode(validating: "USD"))
        }
        let rejected = FirebasePaymentBatchEntry(source: valid.entries[0].source, targetID: nil,
            conversion: nil, issues: [.unresolvedIdentityMapping])
        #expect(throws: FirebaseClientPaymentImportFailure.self) {
            try FirebaseClientPaymentImportParameters.make(batch: .init(entries: [rejected], mappedTotalCents: 0),
                currency: CurrencyCode(validating: "USD"))
        }
    }

    private static func batch() throws -> FirebasePaymentBatchResult {
        let account = "synthetic-export-fixture"
        let project = FirebaseSourceDocument(accountScopeID: account,
            documentPathSegments: ["accounts", account, "projects", "source-project"], entityCode: "projects",
            evidenceKind: .record, fields: .map([.init(key: "clientName", value: .string("Legacy label"))]), sourceRecordID: "project-source")
        let source = FirebaseSourceDocument(accountScopeID: account,
            documentPathSegments: ["accounts", account, "transactions", "source-payment-export-fixture"],
            entityCode: "transactions", evidenceKind: .record, fields: .map([
                .init(key: "amountCents", value: .integer("9007199254740993")),
                .init(key: "notes", value: .string("kept\0note")),
                .init(key: "projectId", value: .string("source-project")),
                .init(key: "settlementInvoiceId", value: .string("original-invoice")),
                .init(key: "settlementInvoiceLineIds", value: .array([.string("original-line")])),
                .init(key: "type", value: .string("paymentToBusiness"))
            ]), sourceRecordID: "payment-source-record")
        let scope = TransactionScope.project(accountId: try AccountID(validating: "account-primary"),
            projectId: try ProjectID(validating: "project-payment-export-fixture"), clientId: try ClientID(validating: "client-existing"))
        return FirebaseClientPaymentBatch.convert(transactions: [source], projects: [project], sourceAccountID: account,
            targetAccountID: scope.accountId, projectMappings: [.init(sourceProject: project, targetScope: scope)],
            identityMappings: [.init(sourcePath: source.documentPathSegments, targetID: try TransactionID(validating: "payment-export-fixture"))])
    }
}
