import LedgerTargetCore

package enum FirebaseInvoiceDisplayMetadata {
    package static func read(_ source: FirebaseSourceDocument) throws -> InvoiceDisplayMetadata? {
        guard case .map(let fields) = source.fields else { throw InvoiceDisplayMetadata.Failure.invalid }
        func value(_ key: String) -> FirebaseSourceValue? { fields.first { $0.key == key }?.value }
        func text(_ key: String) throws -> String? {
            switch value(key) {
            case nil, .null: return nil
            case .string(let text): return text
            default: throw InvoiceDisplayMetadata.Failure.invalid
            }
        }
        func milliseconds(_ key: String) throws -> String? {
            switch value(key) {
            case nil, .null: return nil
            case .timestamp(let secondsText, let nanos):
                guard let seconds = Int64(secondsText), (0..<1_000_000_000).contains(nanos) else { throw InvoiceDisplayMetadata.Failure.invalid }
                let product = seconds.multipliedReportingOverflow(by: 1000)
                let sum = product.partialValue.addingReportingOverflow(Int64(nanos / 1_000_000))
                guard !product.overflow && !sum.overflow else { throw InvoiceDisplayMetadata.Failure.invalid }
                // Original sub-millisecond precision remains in Invoice evidence.
                return String(sum.partialValue)
            default: throw InvoiceDisplayMetadata.Failure.invalid
            }
        }
        let result = try InvoiceDisplayMetadata(invoiceNumber: text("invoiceNumber"), notes: text("notes"),
            issuedAtMilliseconds: milliseconds("dateIssued"), sentAtMilliseconds: milliseconds("dateSent"),
            paidAtMilliseconds: milliseconds("datePaid"), canceledAtMilliseconds: milliseconds("dateCanceled"),
            voidedAtMilliseconds: milliseconds("dateVoided"))
        return result == (try InvoiceDisplayMetadata()) ? nil : result
    }
}
