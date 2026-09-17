import Foundation
import Testing
@testable import LedgerTargetCore

struct ReceiptLineEntryTests {
    @Test func existingExpenseDraftKeysAndImportedIdentitySurvive() throws {
        let bytes = Data(#"{"id":"11111111-2222-3333-4444-555555555555","sourceLineId":"imported-tax","description":"Printed tax refund","amountText":"90071992547409.93","effect":"decrease","quantityText":"-2"}"#.utf8)
        let input = try JSONDecoder().decode(ReceiptLineEntry.self, from: bytes)
        let line = try input.receiptLine(currency: .init(validating: "USD"))
        #expect(line.id.rawValue == "imported-tax")
        #expect(line.magnitude.minorUnits == 9_007_199_254_740_993)
        #expect(line.effect == .decrease && line.quantity == -2)
        #expect(try ReceiptLineEntry(line: line).receiptLine(currency: line.magnitude.currency) == line)
        let restored = try JSONDecoder().decode(ExpenseEntryRecovery.Line.self,
            from: JSONEncoder().encode(input))
        #expect(restored == input)
        let original = try #require(JSONSerialization.jsonObject(with: bytes) as? NSDictionary)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? NSDictionary)
        #expect(original == encoded)
    }
}
