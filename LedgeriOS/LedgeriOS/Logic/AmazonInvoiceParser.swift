import Foundation

/// Amazon invoice text parser.
/// Direct port of `/Dev/ledger/src/utils/amazonInvoiceParser.ts` (343 lines).
enum AmazonInvoiceParser {

    struct LineItem: Identifiable, Equatable {
        let id = UUID()
        var description: String
        var qty: Int
        var unitPrice: String?
        var total: String
        var shippedOn: String?
    }

    struct ParseResult: Equatable {
        var orderNumber: String?
        var orderPlacedDate: String?
        var grandTotal: String?
        var projectCode: String?
        var paymentMethod: String?
        var tax: String?
        var shipping: String?
        var lineItems: [LineItem]
        var warnings: [String]
    }

    // MARK: - Vendor Detection

    static func isAmazonInvoice(_ text: String) -> Bool {
        let hasOrderNumber = text.range(of: "Amazon\\.com order number:", options: .regularExpression) != nil
        let hasFinalDetails = text.range(of: "Final Details for Order #", options: .caseInsensitive) != nil
        let hasOrderPlacedAndAmazon = text.range(of: "Order Placed:", options: .caseInsensitive) != nil
            && text.range(of: "Amazon\\.com", options: .regularExpression) != nil
        return hasOrderNumber || hasFinalDetails || hasOrderPlacedAndAmazon
    }

    // MARK: - Parse

    static func parse(_ fullText: String) -> ParseResult {
        var warnings: [String] = []

        guard isAmazonInvoice(fullText) else {
            return ParseResult(lineItems: [], warnings: ["Not an Amazon invoice"])
        }

        // Header fields
        let orderNumber = extractFirstMatch(fullText, pattern: #"Amazon\.com order number:\s*([^\n\r]+)"#)
            ?? extractFirstMatch(fullText, pattern: #"Final Details for Order #([^\n\r]+)"#)

        let orderPlacedDateRaw = extractFirstMatch(fullText, pattern: #"Order Placed:\s*([^\n\r]+)"#)
        let orderPlacedDate = orderPlacedDateRaw.flatMap { InvoiceDateParsing.parseDateToIso($0) }

        let grandTotalRaw = extractFirstMatch(fullText, pattern: #"Grand Total:\s*\$?\s*([\d,]+\.\d{2})"#)
            ?? extractFirstMatch(fullText, pattern: #"Order Total:\s*\$?\s*([\d,]+\.\d{2})"#)
        let grandTotal = grandTotalRaw.flatMap { InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString($0) }

        let projectCode = extractFirstMatch(fullText, pattern: #"Project code:\s*([^\n\r]+)"#)?
            .trimmingCharacters(in: .whitespaces)

        let paymentMethodMatch = fullText.firstMatch(
            of: /(Visa|Mastercard|American Express|Discover)\s*\|\s*Last digits:\s*(\d{4})/
        )
        let paymentMethod = paymentMethodMatch.map { "\($0.1) | Last digits: \($0.2)" }

        let taxRaw = extractFirstMatch(fullText, pattern: #"Estimated Tax:\s*\$?\s*([\d,]+\.\d{2})"#)
        let tax = taxRaw.flatMap { InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString($0) }

        let shippingRaw = extractLastMatch(fullText, pattern: #"Shipping & Handling:\s*\$?\s*([\d,]+\.\d{2})"#)
        let shipping = shippingRaw.flatMap { InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString($0) }

        if orderNumber == nil { warnings.append("Could not confidently find an order number.") }
        if orderPlacedDate == nil { warnings.append("Could not confidently find an order date; defaulting to today is recommended.") }
        if grandTotal == nil { warnings.append("Missing order total") }

        let lines = normalizeLines(fullText)

        // Parse line items
        var lineItems: [LineItem] = []
        var currentShippedOn: String?
        var currentItemStart: Int?
        var currentDescriptionParts: [String] = []
        var currentQty: Int?
        var currentUnitPrice: String?
        var currentDescriptionLocked = false
        var isInAddressBlock = false

        let addressBlockStartPattern = /^(Shipping Address|Billing address):?/
        let addressBlockEndPattern = /^(Shipping Speed:|Item\(s\) Subtotal:|Total before tax:|Sales Tax:|Estimated Tax:|Total for This Shipment:|Payment information$|Credit Card transactions|Shipped on|-- \d+ of \d+ --$)/

        func finalizeCurrentItem() {
            guard currentItemStart != nil, let qty = currentQty, !currentDescriptionParts.isEmpty else { return }

            let description = currentDescriptionParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !description.isEmpty else { return }

            var unitPrice = currentUnitPrice

            // Find unit price if not already found
            if unitPrice == nil, let start = currentItemStart {
                for j in (start + 1)..<lines.count {
                    if lines[j].firstMatch(of: /^\d+\s+of:/) != nil || lines[j].range(of: "Shipped on", options: .caseInsensitive) != nil {
                        break
                    }
                    let moneyTokens = extractMoneyTokens(lines[j])
                    if !moneyTokens.isEmpty, !shouldIgnoreLine(lines[j]) {
                        let lineWithoutMoney = lines[j].replacingOccurrences(
                            of: #"\$?\d{1,3}(?:,\d{3})*\.\d{2}"#,
                            with: "",
                            options: .regularExpression
                        ).trimmingCharacters(in: .whitespaces)
                        if lineWithoutMoney.count < 15 {
                            unitPrice = moneyTokens[0]
                            break
                        }
                    }
                }
            }

            if let unitPrice {
                let unitPriceNum = InvoiceMoneyParsing.parseMoneyToNumber(unitPrice) ?? 0
                let totalNum = unitPriceNum * Double(qty)
                let total = InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString(String(totalNum)) ?? "0.00"
                lineItems.append(LineItem(
                    description: description,
                    qty: qty,
                    unitPrice: unitPrice,
                    total: total,
                    shippedOn: currentShippedOn
                ))
            } else {
                warnings.append("Could not find unit price for item: \(String(description.prefix(50)))")
            }

            // Reset
            currentItemStart = nil
            currentDescriptionParts = []
            currentQty = nil
            currentUnitPrice = nil
            currentDescriptionLocked = false
        }

        for i in 0..<lines.count {
            let line = lines[i]

            if line.firstMatch(of: addressBlockStartPattern) != nil {
                isInAddressBlock = true
                continue
            }

            if isInAddressBlock {
                if line.firstMatch(of: addressBlockEndPattern) != nil || line.firstMatch(of: /^(\d+)\s+of:\s*(.+)$/) != nil {
                    isInAddressBlock = false
                } else {
                    continue
                }
            }

            // Shipment boundary
            if let shippedOnMatch = line.firstMatch(of: /(?i)Shipped on\s+(.+)/) {
                finalizeCurrentItem()
                currentShippedOn = InvoiceDateParsing.parseDateToIso(String(shippedOnMatch.1))
                continue
            }

            // Item start: "N of: Description..."
            if let itemStart = line.firstMatch(of: /^(\d+)\s+of:\s*(.+)$/) {
                finalizeCurrentItem()

                currentQty = Int(itemStart.1)
                var descriptionPart = String(itemStart.2).trimmingCharacters(in: .whitespaces)
                currentUnitPrice = nil

                // Check if description ends with a price
                if let priceAtEnd = descriptionPart.firstMatch(of: /(\$?\d{1,3}(?:,\d{3})*\.\d{2})\s*$/) {
                    currentUnitPrice = InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString(String(priceAtEnd.1))
                    if let range = descriptionPart.range(of: String(priceAtEnd.0)) {
                        descriptionPart = String(descriptionPart[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    }
                }

                currentDescriptionParts = [descriptionPart]
                currentItemStart = i
                currentDescriptionLocked = false
                continue
            }

            // Accumulate description lines
            if currentItemStart != nil, !shouldIgnoreLine(line), !currentDescriptionLocked {
                let moneyTokens = extractMoneyTokens(line)
                let lineWithoutMoney = line.replacingOccurrences(
                    of: #"\$?\d{1,3}(?:,\d{3})*\.\d{2}"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespaces)

                // Line contains only a price → it's the price line
                if currentUnitPrice == nil, !moneyTokens.isEmpty, lineWithoutMoney.count < 15 {
                    currentUnitPrice = moneyTokens[0]
                    currentDescriptionLocked = true
                    continue
                }

                // Add to description if it looks like text
                if !line.isEmpty, line.firstMatch(of: /^\d+$/) == nil {
                    currentDescriptionParts.append(line)
                }
            }
        }

        // Finalize last item
        finalizeCurrentItem()

        if lineItems.isEmpty {
            warnings.append("No line items were detected. The PDF may be image-based or the template changed.")
        }

        // Validate totals
        if let grandTotal {
            let sumLineTotals = lineItems.reduce(0.0) { $0 + (InvoiceMoneyParsing.parseMoneyToNumber($1.total) ?? 0) }
            let taxNum = tax.flatMap { InvoiceMoneyParsing.parseMoneyToNumber($0) } ?? 0
            let shippingNum = shipping.flatMap { InvoiceMoneyParsing.parseMoneyToNumber($0) } ?? 0
            let calculatedTotal = sumLineTotals + taxNum + shippingNum
            let grandTotalNum = InvoiceMoneyParsing.parseMoneyToNumber(grandTotal) ?? 0
            let diff = abs(calculatedTotal - grandTotalNum)
            if diff > 0.05 {
                warnings.append("Calculated total ($\(String(format: "%.2f", calculatedTotal))) does not match order total ($\(String(format: "%.2f", grandTotalNum))) (diff $\(String(format: "%.2f", diff)))")
            }
        }

        return ParseResult(
            orderNumber: orderNumber,
            orderPlacedDate: orderPlacedDate,
            grandTotal: grandTotal,
            projectCode: projectCode,
            paymentMethod: paymentMethod,
            tax: tax,
            shipping: shipping,
            lineItems: lineItems,
            warnings: warnings
        )
    }

    // MARK: - Helpers

    nonisolated(unsafe) private static let ignorePatterns: [Regex<Substring>] = [
        /(?i)^Sold by:/,
        /(?i)^Condition:/,
        /(?i)^Business Price$/,
        /(?i)^Items Ordered Price$/,
        /(?i)^Shipping Address:/,
        /(?i)^Shipping Speed:/,
        /(?i)^Item\(s\) Subtotal:/,
        /(?i)^Shipping & Handling:/,
        /(?i)^Total before tax:/,
        /(?i)^(?:Sales Tax|Estimated Tax):/,
        /(?i)^Total for This Shipment:/,
        /(?i)^Payment information$/,
        /(?i)^Payment Method:/,
        /(?i)^Billing address$/,
        /(?i)^Credit Card transactions/,
        /^-- \d+ of \d+ --$/,
        /(?i)^Order Total:/,
        /(?i)^Grand Total:/,
    ]

    private static func shouldIgnoreLine(_ line: String) -> Bool {
        ignorePatterns.contains { line.firstMatch(of: $0) != nil }
    }
}

// MARK: - Shared Helpers

/// Shared text extraction helpers used by both Amazon and Wayfair parsers.
func extractFirstMatch(_ text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          match.numberOfRanges > 1,
          let captureRange = Range(match.range(at: 1), in: text) else { return nil }
    let result = String(text[captureRange]).trimmingCharacters(in: .whitespaces)
    return result.isEmpty ? nil : result
}

func extractLastMatch(_ text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, range: range)
    guard let lastMatch = matches.last,
          lastMatch.numberOfRanges > 1,
          let captureRange = Range(lastMatch.range(at: 1), in: text) else { return nil }
    let result = String(text[captureRange]).trimmingCharacters(in: .whitespaces)
    return result.isEmpty ? nil : result
}

func normalizeLines(_ text: String) -> [String] {
    text.components(separatedBy: .newlines)
        .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

func extractMoneyTokens(_ line: String) -> [String] {
    let pattern = #"\$?\d{1,3}(?:,\d{3})*\.\d{2}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(line.startIndex..., in: line)
    return regex.matches(in: line, range: range).compactMap { match in
        guard let matchRange = Range(match.range, in: line) else { return nil }
        return InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString(String(line[matchRange]))
    }.filter { !$0.isEmpty }
}
