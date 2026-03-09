import Foundation

/// Wayfair invoice text parser.
/// Direct port of `/Dev/ledger/src/utils/wayfairInvoiceParser.ts` (1,328 lines).
enum WayfairInvoiceParser {

    // MARK: - Types

    struct Attributes: Equatable {
        var color: String?
        var size: String?

        var isEmpty: Bool { color == nil && size == nil }
    }

    enum Section: String, Equatable {
        case shipped
        case toBeShipped = "to_be_shipped"
        case unknown
    }

    struct LineItem: Identifiable, Equatable {
        let id = UUID()
        var description: String
        var sku: String?
        var qty: Int
        var unitPrice: String?
        var subtotal: String?
        var shipping: String?
        var adjustment: String?
        var tax: String?
        var total: String
        var attributeLines: [String]?
        var attributes: Attributes?
        var shippedOn: String?
        var section: Section?
    }

    struct ParseResult: Equatable {
        var invoiceNumber: String?
        var orderDate: String?
        var invoiceLastUpdated: String?
        var orderTotal: String?
        var subtotal: String?
        var shippingDeliveryTotal: String?
        var taxTotal: String?
        var adjustmentsTotal: String?
        var calculatedSubtotal: String?
        var lineItems: [LineItem]
        var warnings: [String]
    }

    // MARK: - Constants

    private static let descriptionBufferLimit = 8

    private static let orderLevelAttributePrefixes = [
        "order ", "payment", "currency", "tax ", "taxable ", "tax-exempt",
        "tax exempt", "billing", "bill to", "ship to", "shipping address",
        "shipping country", "shipping state", "shipping city", "shipping method",
    ]

    private static let orderLevelAttributeExact: Set<String> = [
        "order country", "order state", "order city", "order postal code",
        "order zip", "order id", "order number", "order total", "payment type",
        "currency", "tax exempt", "tax exemption certificate",
    ]

    private static let continuationLeadingWords: Set<String> = [
        "and", "for", "with", "of", "set", "pair", "per",
        "by", "in", "on", "to", "the",
    ]

    private static let wayfairDoubleQuoteChars = "\"\u{201c}\u{201d}\u{201e}\u{2033}\u{2036}\u{ff02}"

    // MARK: - Vendor Detection

    static func isWayfairInvoice(_ text: String) -> Bool {
        let hasWayfair = text.range(of: "wayfair", options: .caseInsensitive) != nil
        let hasInvoiceNumber = text.range(of: #"Invoice\s*(?:Number|#)?\s*[:#]?\s*\d{6,}"#, options: .regularExpression) != nil
        return hasWayfair && hasInvoiceNumber
    }

    // MARK: - Main Parser

    static func parse(_ fullText: String) -> ParseResult {
        var warnings: [String] = []

        let invoiceNumber = extractFirstMatch(fullText, pattern: #"\bInvoice\s*(?:Number|#)?\s*[:#]?\s*(\d{6,})\b"#)
            ?? extractFirstMatch(fullText, pattern: #"\bInvoice\s*[:#]?\s*(\d{6,})\b"#)

        let orderDateRaw = extractFirstMatch(fullText, pattern: #"\bOrder\s*Date\s*[:#]?\s*([^\n\r]+)\b"#)
            ?? extractFirstMatch(fullText, pattern: #"\bOrder\s*Placed\s*[:#]?\s*([^\n\r]+)\b"#)
        let orderDate = orderDateRaw.flatMap { InvoiceDateParsing.parseDateToIso($0) }

        let orderTotalRaw = extractFirstMatch(fullText, pattern: #"\bOrder\s*Total\s*[:#]?\s*\$?\s*([\d,]+\.\d{2})\b"#)
        let subtotalRaw = extractFirstMatch(fullText, pattern: #"\bSubtotal\s*[:#]?\s*\$?\s*([\d,]+\.\d{2})\b"#)
        let shippingDeliveryRaw = extractFirstMatch(fullText, pattern: #"\bShipping(?:\s*(?:&|and)\s*Delivery)?\s*[:#]?\s*\$?\s*([\d,]+\.\d{2})\b"#)
            ?? extractFirstMatch(fullText, pattern: #"\bDelivery\s*[:#]?\s*\$?\s*([\d,]+\.\d{2})\b"#)
        let taxTotalRaw = extractFirstMatch(fullText, pattern: #"\bTax(?:\s*Total)?\s*[:#]?\s*\$?\s*([\d,]+\.\d{2})\b"#)
        let adjustmentsRaw = extractFirstMatch(fullText, pattern: #"\bAdjustments?\s*[:#]?\s*(\(?-?\$?\s*[\d,]+\.\d{2}\)?)"#)

        let orderTotal = orderTotalRaw.flatMap { InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString($0) }
        let subtotal = subtotalRaw.flatMap { InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString($0) }
        let shippingDeliveryTotal = shippingDeliveryRaw.flatMap { InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString($0) }
        let taxTotal = taxTotalRaw.flatMap { InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString($0) }
        let adjustmentsTotal = adjustmentsRaw.flatMap { InvoiceMoneyParsing.normalizeMoneyToTwoDecimalString($0) }

        var calculatedSubtotal: String?
        if let ot = orderTotal, let tt = taxTotal {
            let totalNum = InvoiceMoneyParsing.parseMoneyToNumber(ot) ?? 0
            let taxNum = InvoiceMoneyParsing.parseMoneyToNumber(tt) ?? 0
            calculatedSubtotal = String(format: "%.2f", totalNum - taxNum)
        }

        if invoiceNumber == nil { warnings.append("Could not confidently find an invoice number.") }
        if orderDate == nil { warnings.append("Could not confidently find an order date; defaulting to today is recommended.") }
        if orderTotal == nil { warnings.append("Could not confidently find an order total; totals reconciliation will be limited.") }

        let lines = normalizeLines(fullText)

        var currentSection: Section = .unknown
        var currentShippedOn: String?

        var bufferedDescriptionParts: [String] = []
        var pendingSku: String?
        var pendingAttributes = Attributes()
        var pendingAttributeLines: [String] = []
        var allowLooseContinuationForPreviousItem = false
        var awaitingPostMoneyContinuation = false
        var lastItemAwaitingSkuIndex: Int?
        var deferredPostMoneyLines: [String] = []
        var deferredPostMoneyItemIndex: Int?
        // Track items with dangling parentheses by their index
        var itemsWithDanglingParenthesis: Set<Int> = []

        var lineItems: [LineItem] = []

        func enqueueDescriptionFragment(_ fragment: String?) {
            guard let normalized = normalizeDescriptionFragment(fragment), !normalized.isEmpty else { return }
            allowLooseContinuationForPreviousItem = false
            awaitingPostMoneyContinuation = false
            bufferedDescriptionParts.append(normalized)
            if bufferedDescriptionParts.count > descriptionBufferLimit { bufferedDescriptionParts.removeFirst() }
        }

        func resetBuffers() {
            bufferedDescriptionParts = []
            pendingSku = nil
            pendingAttributes = Attributes()
            pendingAttributeLines = []
            allowLooseContinuationForPreviousItem = false
            awaitingPostMoneyContinuation = false
            lastItemAwaitingSkuIndex = nil
            deferredPostMoneyLines = []
            deferredPostMoneyItemIndex = nil
        }

        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespaces)

            // Section boundaries
            if let match = line.firstMatch(of: /(?i)\bShipped\s+On\s+(.+)\b/) {
                currentSection = .shipped
                currentShippedOn = InvoiceDateParsing.parseDateToIso(String(match.1))
                resetBuffers()
                continue
            }

            if line.range(of: #"\bItems\s+to\s+be\s+Shipped\b"#, options: .regularExpression) != nil
                || line.range(of: #"\bTo\s+be\s+Shipped\b"#, options: .regularExpression) != nil {
                currentSection = .toBeShipped
                currentShippedOn = nil
                resetBuffers()
                continue
            }

            // SKU detection
            if let standaloneSku = extractStandaloneSkuLine(line) {
                let previousIndex = lineItems.count - 1
                if previousIndex >= 0,
                   lastItemAwaitingSkuIndex == previousIndex,
                   lineItems[previousIndex].sku == nil {
                    // Attach deferred lines to previous item
                    if deferredPostMoneyItemIndex == previousIndex, !deferredPostMoneyLines.isEmpty {
                        let baseDesc = lineItems[previousIndex].description.trimmingCharacters(in: .whitespaces)
                        let joiner = baseDesc.hasSuffix("-") || baseDesc.hasSuffix("–") || baseDesc.hasSuffix("—") ? " " : " - "
                        lineItems[previousIndex].description = "\(baseDesc)\(joiner)\(deferredPostMoneyLines.joined(separator: " ").trimmingCharacters(in: .whitespaces))"
                        deferredPostMoneyLines = []
                        deferredPostMoneyItemIndex = nil
                    }
                    lineItems[previousIndex].sku = standaloneSku
                    lastItemAwaitingSkuIndex = nil
                    continue
                }

                if !bufferedDescriptionParts.isEmpty {
                    pendingSku = standaloneSku
                    allowLooseContinuationForPreviousItem = false
                    awaitingPostMoneyContinuation = false
                } else if previousIndex >= 0, lineItems[previousIndex].sku == nil {
                    lineItems[previousIndex].sku = standaloneSku
                    if lastItemAwaitingSkuIndex == previousIndex { lastItemAwaitingSkuIndex = nil }
                } else {
                    pendingSku = standaloneSku
                    allowLooseContinuationForPreviousItem = false
                    awaitingPostMoneyContinuation = false
                }
                continue
            }

            // Attribute detection
            if let attr = extractStandaloneAttributeLine(line) {
                let spillover = normalizeDescriptionFragment(attr.spillover)
                if isLikelyOrderLevelAttributeLabel(attr.label) {
                    bufferedDescriptionParts = []
                    pendingSku = nil
                    pendingAttributes = Attributes()
                    pendingAttributeLines = []
                    allowLooseContinuationForPreviousItem = false
                    awaitingPostMoneyContinuation = false
                    enqueueDescriptionFragment(spillover)
                    continue
                }

                let hasPendingDesc = bufferedDescriptionParts.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                let hasPendingSku = pendingSku != nil
                let hasPendingAttrState = !pendingAttributeLines.isEmpty || pendingAttributes.color != nil || pendingAttributes.size != nil
                let previousIndex = lineItems.count - 1

                if !hasPendingDesc, awaitingPostMoneyContinuation, previousIndex >= 0 {
                    appendStandaloneAttribute(to: &lineItems[previousIndex], attr: attr)
                    enqueueDescriptionFragment(spillover)
                    continue
                }

                if !hasPendingDesc, !hasPendingSku, !hasPendingAttrState, previousIndex >= 0 {
                    appendStandaloneAttribute(to: &lineItems[previousIndex], attr: attr)
                    enqueueDescriptionFragment(spillover)
                    continue
                }

                awaitingPostMoneyContinuation = false
                pendingAttributeLines.append(attr.rawLine)
                if let key = attr.key {
                    switch key {
                    case .color: pendingAttributes.color = attr.value
                    case .size: pendingAttributes.size = attr.value
                    }
                }
                enqueueDescriptionFragment(spillover)
                continue
            }

            // Table header detection
            if isLikelyTableHeaderLine(line) {
                let preserveContinuation = shouldPreserveContinuationOnReset(
                    allowLoose: allowLooseContinuationForPreviousItem,
                    awaitingPost: awaitingPostMoneyContinuation,
                    buffered: bufferedDescriptionParts,
                    sku: pendingSku,
                    attrs: pendingAttributes,
                    attrLines: pendingAttributeLines
                )
                let payload = stripLeadingMergedTableHeader(line)
                bufferedDescriptionParts = []
                pendingSku = nil
                pendingAttributes = Attributes()
                pendingAttributeLines = []
                if !preserveContinuation {
                    allowLooseContinuationForPreviousItem = false
                    awaitingPostMoneyContinuation = false
                }
                if let payload, !payload.isEmpty {
                    line = payload
                    // Fall through to process
                } else {
                    continue
                }
            }

            // Skip header/summary lines
            if line.range(of: #"\b(Order Total|Subtotal|Tax Total|Tax|Adjustments?|Invoice|Order Date)\b"#, options: .regularExpression) != nil
                || line.range(of: #"\b(Ship(?:ping)?|Handling|Payment|Bill(?:ing)?|Address)\b"#, options: .regularExpression) != nil {
                let preserveContinuation = shouldPreserveContinuationOnReset(
                    allowLoose: allowLooseContinuationForPreviousItem,
                    awaitingPost: awaitingPostMoneyContinuation,
                    buffered: bufferedDescriptionParts,
                    sku: pendingSku,
                    attrs: pendingAttributes,
                    attrLines: pendingAttributeLines
                )
                bufferedDescriptionParts = []
                pendingSku = nil
                pendingAttributes = Attributes()
                pendingAttributeLines = []
                if !preserveContinuation {
                    allowLooseContinuationForPreviousItem = false
                    awaitingPostMoneyContinuation = false
                }
                continue
            }

            let hasPendingDesc = bufferedDescriptionParts.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let previousIndex = lineItems.count - 1

            // Continuation checks
            let previousHasDangling = previousIndex >= 0 && itemsWithDanglingParenthesis.contains(previousIndex)
            let looksLikeParenTail = previousIndex >= 0 && previousHasDangling && isLikelyParentheticalContinuation(line)
            let looksLikeParenLead = previousIndex >= 0 && previousHasDangling
                && (allowLooseContinuationForPreviousItem || awaitingPostMoneyContinuation)
                && isLikelyParentheticalLead(line)
            let startsWithBullet = line.hasPrefix("-") || line.hasPrefix("–") || line.hasPrefix("•")
            let looksLikeSoftContinuation = previousIndex >= 0
                && (allowLooseContinuationForPreviousItem || awaitingPostMoneyContinuation)
                && isSoftLeadingWordContinuation(line)

            let canAppendToPrevious = !hasPendingDesc
                && pendingSku == nil
                && previousIndex >= 0
                && extractMoneyTokens(line).isEmpty
                && !isLikelyItemPositionIndicator(line)
                && (startsWithBullet || looksLikeParenTail || looksLikeParenLead || looksLikeSoftContinuation)

            if canAppendToPrevious, previousIndex >= 0 {
                let cleaned = startsWithBullet ? line.replacingOccurrences(of: #"^[-–•]\s*"#, with: "", options: .regularExpression) : line.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    let baseDesc = lineItems[previousIndex].description.trimmingCharacters(in: .whitespaces)
                    let joiner = (looksLikeParenTail || looksLikeParenLead)
                        ? " "
                        : (baseDesc.hasSuffix("-") || baseDesc.hasSuffix("–") || baseDesc.hasSuffix("—") ? " " : " - ")
                    lineItems[previousIndex].description = "\(baseDesc)\(joiner)\(cleaned)"
                    if previousIndex != lastItemAwaitingSkuIndex {
                        awaitingPostMoneyContinuation = false
                    }
                    if hasUnclosedParenthesis(lineItems[previousIndex].description) {
                        itemsWithDanglingParenthesis.insert(previousIndex)
                    } else {
                        itemsWithDanglingParenthesis.remove(previousIndex)
                        allowLooseContinuationForPreviousItem = false
                    }
                }
                continue
            }

            // Deferred post-money lines
            let shouldDefer = previousIndex >= 0
                && lastItemAwaitingSkuIndex == previousIndex
                && awaitingPostMoneyContinuation
                && extractMoneyTokens(line).isEmpty
                && !startsWithBullet
                && !looksLikeParenTail && !looksLikeParenLead && !looksLikeSoftContinuation
                && !isLikelyItemPositionIndicator(line)

            if shouldDefer {
                deferredPostMoneyLines.append(line.trimmingCharacters(in: .whitespaces))
                deferredPostMoneyItemIndex = previousIndex
                continue
            }

            // Dimension continuation
            if previousIndex >= 0,
               lineItems[previousIndex].attributeLines?.contains(where: { $0.hasPrefix("Size:") || $0.hasPrefix("size:") }) == true,
               extractMoneyTokens(line).isEmpty,
               isLikelyDimensionContinuation(line) {
                if let idx = lineItems[previousIndex].attributeLines?.firstIndex(where: { $0.range(of: "^Size:", options: .regularExpression) != nil }) {
                    let cleaned = line.trimmingCharacters(in: .whitespaces)
                    lineItems[previousIndex].attributeLines?[idx] += " \(cleaned)"
                    if lineItems[previousIndex].attributes?.size != nil {
                        lineItems[previousIndex].attributes?.size? += " \(cleaned)"
                    }
                }
                continue
            }

            // Leading SKU from money row
            if pendingSku == nil {
                let skuResult = extractLeadingSkuFromMoneyRow(line)
                if let sku = skuResult.sku {
                    pendingSku = sku
                    line = skuResult.lineWithoutSku
                }
            }

            // Pre-money description fragment
            let preMoney = extractDescriptionFragmentBeforeMoney(line)
            if let fragment = preMoney.fragment {
                allowLooseContinuationForPreviousItem = false
                awaitingPostMoneyContinuation = false
                bufferedDescriptionParts.append(fragment)
                if bufferedDescriptionParts.count > descriptionBufferLimit { bufferedDescriptionParts.removeFirst() }
                line = preMoney.remainder
            }

            // Try to parse as money row (line item)
            let bufferedText = bufferedDescriptionParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)

            // Handle unclosed parenthesis
            if !bufferedText.isEmpty, hasUnclosedParenthesis(bufferedText),
               line.firstMatch(of: /^\d+\)/) != nil, extractMoneyTokens(line).count >= 2 {
                if let closeMatch = line.firstMatch(of: /^(\d+\))/) {
                    bufferedDescriptionParts.append(String(closeMatch.1))
                }
            }

            let bufferedForParse = bufferedDescriptionParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let deferredText = deferredPostMoneyLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let descForParse = bufferedForParse.isEmpty ? deferredText : bufferedForParse

            if let parsed = parseLineItemFromLine(line, bufferedDescription: descForParse) {
                let usedDeferred = bufferedForParse.isEmpty && !deferredPostMoneyLines.isEmpty
                let extracted = extractInlineAttributesFromDescription(parsed.description)
                let skuSplit: (sku: String?, cleanedDescription: String)
                if let sku = pendingSku {
                    skuSplit = (sku, extracted.cleanedDescription)
                } else {
                    skuSplit = splitSkuPrefixFromDescription(extracted.cleanedDescription)
                }

                var mergedAttrs = Attributes(
                    color: extracted.attributes?.color ?? pendingAttributes.color,
                    size: extracted.attributes?.size ?? pendingAttributes.size
                )
                var allAttrLines = (pendingAttributeLines + (extracted.attributeLines ?? []))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                // Recovery: split Size spillover
                var recoveredDescription: String?
                if skuSplit.cleanedDescription.trimmingCharacters(in: .whitespaces).isEmpty, !allAttrLines.isEmpty {
                    for i in 0..<allAttrLines.count {
                        guard allAttrLines[i].range(of: "^Size\\s*:", options: .regularExpression) != nil else { continue }
                        guard let split = trySplitSizeAttributeLineWithSpillover(allAttrLines[i]) else { continue }
                        recoveredDescription = split.spillover
                        allAttrLines[i] = split.cleanedSizeLine
                        if mergedAttrs.size == nil { mergedAttrs.size = split.cleanedSizeValue }
                        break
                    }
                }

                let dedupedAttrLines = allAttrLines.isEmpty ? nil : Array(NSOrderedSet(array: allAttrLines)) as? [String]
                let finalDesc = (skuSplit.cleanedDescription.trimmingCharacters(in: .whitespaces).isEmpty
                    ? recoveredDescription ?? ""
                    : skuSplit.cleanedDescription).trimmingCharacters(in: .whitespaces)

                var newItem = LineItem(
                    description: finalDesc,
                    sku: skuSplit.sku,
                    qty: parsed.qty,
                    unitPrice: parsed.unitPrice,
                    subtotal: parsed.subtotal,
                    shipping: parsed.shipping,
                    adjustment: parsed.adjustment,
                    tax: parsed.tax,
                    total: parsed.total,
                    attributeLines: dedupedAttrLines,
                    attributes: mergedAttrs.isEmpty ? nil : mergedAttrs,
                    shippedOn: currentShippedOn,
                    section: currentSection
                )

                // Transfer recovered size to previous item
                if recoveredDescription != nil, let sizeLineIdx = newItem.attributeLines?.firstIndex(where: { $0.range(of: "^Size\\s*:", options: .regularExpression) != nil }) {
                    let prevIdx = lineItems.count - 1
                    let sizeLine = newItem.attributeLines![sizeLineIdx]
                    let previousAlreadyHasSize = prevIdx >= 0
                        && (lineItems[prevIdx].attributeLines?.contains(where: { $0.range(of: "^Size\\s*:", options: .regularExpression) != nil }) == true
                            || lineItems[prevIdx].attributes?.size != nil)

                    if prevIdx >= 0, !previousAlreadyHasSize, lineItems[prevIdx].section == currentSection {
                        let sizeValue = sizeLine.replacingOccurrences(of: #"^Size\s*:\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                        appendStandaloneAttribute(to: &lineItems[prevIdx], attr: ParsedAttribute(key: .size, value: sizeValue, rawLine: sizeLine, label: "Size"))
                        var nextAttrLines = newItem.attributeLines?.enumerated().filter { $0.offset != sizeLineIdx }.map(\.element)
                        if nextAttrLines?.isEmpty == true { nextAttrLines = nil }
                        newItem.attributeLines = nextAttrLines
                        if newItem.attributes?.size != nil {
                            newItem.attributes?.size = nil
                            if newItem.attributes?.isEmpty == true { newItem.attributes = nil }
                        }
                    }
                }

                lineItems.append(newItem)
                let newIndex = lineItems.count - 1
                lastItemAwaitingSkuIndex = newItem.sku == nil ? newIndex : nil
                let descSource = bufferedText.isEmpty ? parsed.description : bufferedText
                if hasUnclosedParenthesis(descSource) {
                    itemsWithDanglingParenthesis.insert(newIndex)
                }
                allowLooseContinuationForPreviousItem = true
                awaitingPostMoneyContinuation = true
                bufferedDescriptionParts = []
                pendingSku = nil
                pendingAttributes = Attributes()
                pendingAttributeLines = []
                if usedDeferred {
                    deferredPostMoneyLines = []
                    deferredPostMoneyItemIndex = nil
                }
                continue
            }

            // Buffer text that looks like a description line
            if line.range(of: #"^\$?\s*[\d,]+\.\d{2}\s*$"#, options: .regularExpression) == nil,
               line.range(of: #"^\d+$"#, options: .regularExpression) == nil {

                // Trailing SKU extraction
                if pendingSku == nil {
                    let trailing = extractTrailingSkuFromDescriptionLine(line)
                    if let sku = trailing.sku {
                        pendingSku = sku
                        line = trailing.cleanedLine
                        awaitingPostMoneyContinuation = false
                    }
                }

                // SKU prefix extraction
                if pendingSku == nil {
                    let split = splitSkuPrefixFromDescription(line)
                    if let sku = split.sku {
                        pendingSku = sku
                        allowLooseContinuationForPreviousItem = false
                        awaitingPostMoneyContinuation = false
                        bufferedDescriptionParts.append(split.cleanedDescription)
                        if bufferedDescriptionParts.count > descriptionBufferLimit { bufferedDescriptionParts.removeFirst() }
                        continue
                    }
                }

                // Inline attribute extraction
                let inline = extractInlineAttributesFromDescription(line)
                if let inlineAttrLines = inline.attributeLines {
                    awaitingPostMoneyContinuation = false
                    pendingAttributeLines.append(contentsOf: inlineAttrLines)
                }
                if let c = inline.attributes?.color { pendingAttributes.color = c }
                if let s = inline.attributes?.size { pendingAttributes.size = s }

                var descForBuffer = inline.cleanedDescription
                if pendingSku == nil, !descForBuffer.isEmpty {
                    let trailingAfterInline = extractTrailingSkuFromDescriptionLine(descForBuffer)
                    if let sku = trailingAfterInline.sku {
                        pendingSku = sku
                        descForBuffer = trailingAfterInline.cleanedLine
                        awaitingPostMoneyContinuation = false
                    }
                }

                if !descForBuffer.isEmpty {
                    allowLooseContinuationForPreviousItem = false
                    awaitingPostMoneyContinuation = false
                    bufferedDescriptionParts.append(descForBuffer)
                    if bufferedDescriptionParts.count > descriptionBufferLimit { bufferedDescriptionParts.removeFirst() }
                }
            }
        }

        if lineItems.isEmpty {
            warnings.append("No line items were detected. The PDF may be image-based or the template changed.")
        }

        // Validate totals
        let sumLineTotals = lineItems.reduce(0.0) { $0 + (InvoiceMoneyParsing.parseMoneyToNumber($1.total) ?? 0) }
        if let ot = orderTotal {
            let orderTotalNum = InvoiceMoneyParsing.parseMoneyToNumber(ot) ?? 0
            let diff = abs(sumLineTotals - orderTotalNum)
            if diff > 0.05 {
                warnings.append("Line totals ($\(String(format: "%.2f", sumLineTotals))) do not match order total ($\(String(format: "%.2f", orderTotalNum))). Difference: $\(String(format: "%.2f", diff)).")
            }
        }

        return ParseResult(
            invoiceNumber: invoiceNumber,
            orderDate: orderDate,
            orderTotal: orderTotal,
            subtotal: subtotal,
            shippingDeliveryTotal: shippingDeliveryTotal,
            taxTotal: taxTotal,
            adjustmentsTotal: adjustmentsTotal,
            calculatedSubtotal: calculatedSubtotal,
            lineItems: lineItems,
            warnings: warnings
        )
    }

    // MARK: - Helper Types

    enum AttributeKey: Equatable {
        case color, size
    }

    struct ParsedAttribute {
        var key: AttributeKey?
        var value: String
        var rawLine: String
        var label: String
        var spillover: String?
    }

    struct ParsedLineItem {
        var description: String
        var qty: Int
        var unitPrice: String?
        var subtotal: String?
        var shipping: String?
        var adjustment: String?
        var tax: String?
        var total: String
    }

    // MARK: - SKU Helpers

    private static func isLikelySkuToken(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        return t.range(of: #"^(?=.*[A-Za-z])(?=.*\d)[A-Za-z0-9-]{6,20}$"#, options: .regularExpression) != nil
    }

    private static func extractStandaloneSkuLine(_ line: String) -> String? {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, extractMoneyTokens(s).isEmpty else { return nil }

        // Labeled: "SKU: ABC123"
        if let match = s.firstMatch(of: /(?i)^(?:SKU|Item\s*(?:#|No\.?|Number|ID))\s*[:#]?\s*([A-Za-z0-9-]{4,30})\s*$/) {
            return String(match.1).trimmingCharacters(in: .whitespaces)
        }

        if isLikelySkuToken(s) { return s }
        return nil
    }

    private static func extractLeadingSkuFromMoneyRow(_ line: String) -> (lineWithoutSku: String, sku: String?) {
        let normalized = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, extractMoneyTokens(normalized).count >= 2 else { return (line, nil) }

        guard let match = normalized.firstMatch(of: /^([A-Za-z0-9-]{6,20})\s+(.+)$/) else { return (line, nil) }
        let candidate = String(match.1).trimmingCharacters(in: .whitespaces)
        guard isLikelySkuToken(candidate) else { return (line, nil) }

        let remainder = String(match.2).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty, extractMoneyTokens(remainder).count >= 2 else { return (line, nil) }
        return (remainder, candidate)
    }

    private static func splitSkuPrefixFromDescription(_ description: String) -> (sku: String?, cleanedDescription: String) {
        let s = description.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return (nil, s) }
        guard let match = s.firstMatch(of: /^([A-Za-z0-9-]{6,20})\s+(.+)$/) else { return (nil, s) }
        let possibleSku = String(match.1).trimmingCharacters(in: .whitespaces)
        guard isLikelySkuToken(possibleSku) else { return (nil, s) }
        return (possibleSku, String(match.2).trimmingCharacters(in: .whitespaces))
    }

    private static func extractTrailingSkuFromDescriptionLine(_ line: String) -> (cleanedLine: String, sku: String?) {
        let s = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, extractMoneyTokens(s).isEmpty else { return (s, nil) }
        let parts = s.components(separatedBy: " ").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return (s, nil) }
        let last = parts[parts.count - 1]
        guard isLikelySkuToken(last) else { return (s, nil) }
        return (parts.dropLast().joined(separator: " "), last)
    }

    // MARK: - Table Header Helpers

    private static func isLikelyTableHeaderLine(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }

        if s.range(of: #"^(?:Item|Unit Price|Qty|Subtotal|Adjustment|Tax|Total)$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if s.range(of: #"^Shipping\s*(?:and|&)\s*Delivery$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if s.range(of: #"^Delivery$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if s.range(of: "\\bUnit Price\\b", options: [.regularExpression, .caseInsensitive]) != nil
            && s.range(of: "\\bQty\\b", options: [.regularExpression, .caseInsensitive]) != nil
            && s.range(of: "\\bSubtotal\\b", options: [.regularExpression, .caseInsensitive]) != nil
            && s.range(of: "\\bTotal\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if s.range(of: "\\bShipping\\b", options: [.regularExpression, .caseInsensitive]) != nil
            && s.range(of: "\\bDelivery\\b", options: [.regularExpression, .caseInsensitive]) != nil
            && s.range(of: "\\bAdjustment\\b", options: [.regularExpression, .caseInsensitive]) != nil
            && s.range(of: "\\bTax\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    private static func stripLeadingMergedTableHeader(_ line: String) -> String? {
        var s = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        let headerPhrases = [
            "Shipping & Delivery", "Shipping and Delivery", "Unit Price",
            "Subtotal", "Adjustment", "Delivery", "Item", "Qty", "Tax", "Total",
        ]

        let scanWindow = String(s.prefix(80)).lowercased()
        let hitCount = headerPhrases.filter { scanWindow.contains($0.lowercased()) }.count
        guard hitCount >= 4 else { return nil }

        // Strip header labels from prefix
        var changed = false
        for _ in 0..<20 {
            let before = s
            let patterns = [
                "^Item\\s+", "^Unit Price\\s+", "^Qty\\s+", "^Subtotal\\s+",
                "^Shipping\\s*(?:and|&)\\s*Delivery\\s+", "^Delivery\\s+",
                "^Adjustment\\s+", "^Tax\\s+", "^Total\\s+",
            ]
            for p in patterns {
                s = s.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespaces)
            }
            if s != before { changed = true }
            if s == before { break }
        }
        if changed, !s.isEmpty { return s }

        // Fallback: cut after last header phrase
        let lower = line.lowercased()
        var cutIdx = -1
        var candidateCount = 0
        for phrase in headerPhrases {
            if let range = lower.range(of: phrase.lowercased()) {
                let idx = lower.distance(from: lower.startIndex, to: range.lowerBound)
                if idx < 80 {
                    candidateCount += 1
                    let endIdx = lower.distance(from: lower.startIndex, to: range.upperBound)
                    cutIdx = max(cutIdx, endIdx)
                }
            }
        }
        guard candidateCount >= 4, cutIdx > 0, cutIdx < line.count - 1 else { return nil }
        let payload = String(line.suffix(from: line.index(line.startIndex, offsetBy: cutIdx)))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return payload.isEmpty ? nil : payload
    }

    // MARK: - Attribute Helpers

    private static func extractStandaloneAttributeLine(_ line: String) -> ParsedAttribute? {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        let isSizeLine = s.range(of: "^Size\\s*:", options: [.regularExpression, .caseInsensitive]) != nil
        if !isSizeLine, !extractMoneyTokens(s).isEmpty { return nil }

        guard let match = s.firstMatch(of: /^([A-Za-z][A-Za-z0-9 \/&()-]{0,30})\s*:\s*(.+)$/) else { return nil }
        let key = String(match.1).trimmingCharacters(in: .whitespaces)
        let value = String(match.2).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        let normalizedKey = key.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let splitResult = splitAttributeSpillover(normalizedKey, value: value)
        let rawLine = "\(normalizedKey): \(splitResult.cleanedValue)"
        let lowerKey = normalizedKey.lowercased()

        if lowerKey == "color" {
            return ParsedAttribute(key: .color, value: splitResult.cleanedValue, rawLine: rawLine, label: normalizedKey, spillover: splitResult.spillover)
        }
        if lowerKey == "size" {
            return ParsedAttribute(key: .size, value: splitResult.cleanedValue, rawLine: rawLine, label: normalizedKey, spillover: splitResult.spillover)
        }
        return ParsedAttribute(key: nil, value: splitResult.cleanedValue, rawLine: rawLine, label: normalizedKey, spillover: splitResult.spillover)
    }

    private static func appendStandaloneAttribute(to item: inout LineItem, attr: ParsedAttribute) {
        var existing = item.attributeLines ?? []
        existing.append(attr.rawLine.trimmingCharacters(in: .whitespaces))
        item.attributeLines = Array(NSOrderedSet(array: existing.filter { !$0.isEmpty })) as? [String]

        if let key = attr.key {
            if item.attributes == nil { item.attributes = Attributes() }
            switch key {
            case .color: item.attributes?.color = attr.value
            case .size: item.attributes?.size = attr.value
            }
        }
    }

    private static func isLikelyOrderLevelAttributeLabel(_ label: String) -> Bool {
        let normalized = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return false }
        if orderLevelAttributeExact.contains(normalized) { return true }
        return orderLevelAttributePrefixes.contains { normalized.hasPrefix($0) }
    }

    private static func splitAttributeSpillover(_ label: String, value: String) -> (cleanedValue: String, spillover: String?) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces).lowercased()
        let trimmedValue = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !trimmedValue.isEmpty else { return (trimmedValue, nil) }

        guard trimmedLabel == "size" else { return (trimmedValue, nil) }

        let canonicalValue = normalizeQuotes(trimmedValue)

        // Look for trailing quoted descriptive segment (spillover from next item)
        let patterns = [
            #""\s*([^"]*[A-Za-z][^"]*)\s*"\s*$"#,
            #"\s"([^"]*[A-Za-z][^"]*)"\s*$"#,
            #""([^"]*[A-Za-z][^"]*)"\s*$"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: canonicalValue, range: NSRange(canonicalValue.startIndex..., in: canonicalValue)),
                  match.numberOfRanges > 1,
                  let candidateRange = Range(match.range(at: 1), in: canonicalValue),
                  let fullRange = Range(match.range, in: canonicalValue) else { continue }

            let base = String(trimmedValue[..<fullRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let candidate = stripOuterQuotes(String(canonicalValue[candidateRange]).trimmingCharacters(in: .whitespaces))

            if !base.isEmpty, looksLikeMeasurement(base), looksDescriptive(candidate) {
                return (base, candidate)
            }
        }

        // Fallback: quoted tail
        if let regex = try? NSRegularExpression(pattern: #"^(.*?)(?:\s+"([^"]+)"\s*)$"#),
           let match = regex.firstMatch(in: canonicalValue, range: NSRange(canonicalValue.startIndex..., in: canonicalValue)),
           match.numberOfRanges > 2,
           let baseRange = Range(match.range(at: 1), in: canonicalValue),
           let candidateRange = Range(match.range(at: 2), in: canonicalValue) {
            let base = String(trimmedValue[..<trimmedValue.index(trimmedValue.startIndex, offsetBy: String(canonicalValue[baseRange]).count)]).trimmingCharacters(in: .whitespaces)
            let candidate = stripOuterQuotes(String(canonicalValue[candidateRange]).trimmingCharacters(in: .whitespaces))
            if !base.isEmpty, looksLikeMeasurement(base), looksDescriptive(candidate) {
                return (base, candidate)
            }
        }

        return (trimmedValue, nil)
    }

    private static func trySplitSizeAttributeLineWithSpillover(_ line: String) -> (cleanedSizeLine: String, spillover: String, cleanedSizeValue: String)? {
        let s = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard let match = s.firstMatch(of: /(?i)^Size\s*:\s*(.+)$/) else { return nil }
        let sizeValue = String(match.1)

        let result = splitAttributeSpillover("Size", value: sizeValue)
        guard let spillover = normalizeDescriptionFragment(result.spillover), !spillover.isEmpty else { return nil }

        let cleanedSizeValue = result.cleanedValue.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !cleanedSizeValue.isEmpty else { return nil }

        return (cleanedSizeLine: "Size: \(cleanedSizeValue)", spillover: spillover, cleanedSizeValue: cleanedSizeValue)
    }

    private static func extractInlineAttributesFromDescription(_ description: String) -> (cleanedDescription: String, attributes: Attributes?, attributeLines: [String]?) {
        var s = description.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        var attributes = Attributes()
        var attrLines: [String] = []

        // Remove stray "Delivery" prefix
        s = s.replacingOccurrences(of: "^Delivery\\s+", with: "", options: [.regularExpression, .caseInsensitive])

        let pattern = #"\b(Fabric|Color|Size)\s*:\s*([^:]+?)(?=\s+(?:Fabric|Color|Size)\b|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return (s, nil, nil)
        }

        let range = NSRange(s.startIndex..., in: s)
        let matches = regex.matches(in: s, range: range)
        guard !matches.isEmpty else { return (s, nil, nil) }

        for match in matches {
            guard match.numberOfRanges > 2,
                  let labelRange = Range(match.range(at: 1), in: s),
                  let valueRange = Range(match.range(at: 2), in: s) else { continue }
            let label = String(s[labelRange]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(s[valueRange]).trimmingCharacters(in: .whitespaces)
            let value = rawValue.replacingOccurrences(of: "[,\\s]+$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            attrLines.append("\(label): \(value)")
            let lower = label.lowercased()
            if lower == "color" { attributes.color = value }
            else if lower == "size" { attributes.size = value }
        }

        // Remove inline attributes from description
        s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return (
            s,
            attributes.isEmpty ? nil : attributes,
            attrLines.isEmpty ? nil : Array(NSOrderedSet(array: attrLines)) as? [String]
        )
    }

    // MARK: - Description Helpers

    private static func normalizeDescriptionFragment(_ input: String?) -> String? {
        let s = (input ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let stripped = stripOuterQuotes(s)
        return stripped.isEmpty ? s : stripped
    }

    private static func extractDescriptionFragmentBeforeMoney(_ line: String) -> (fragment: String?, remainder: String) {
        guard !line.isEmpty else { return (nil, line) }
        let pattern = #"\$?\s*[\d,]+\.\d{2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let matchRange = Range(match.range, in: line),
              matchRange.lowerBound > line.startIndex else { return (nil, line) }

        let fragment = String(line[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let remainder = String(line[matchRange.lowerBound...]).trimmingCharacters(in: .whitespaces)
        guard !fragment.isEmpty, !remainder.isEmpty else { return (nil, line) }

        let normalized = fragment.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard normalized.range(of: "[A-Za-z]", options: .regularExpression) != nil else { return (nil, line) }

        let alphaTokens = normalized.components(separatedBy: " ").filter { $0.range(of: "[A-Za-z]", options: .regularExpression) != nil }
        if alphaTokens.count < 2 {
            if isLikelySkuToken(normalized) { return (nil, line) }
            if normalized.count < 6 { return (nil, line) }
        }

        return (normalized, remainder)
    }

    // MARK: - Quantity Extraction

    private static func extractQty(_ line: String) -> Int? {
        // 1) Explicit Qty label
        if let match = line.firstMatch(of: /(?i)\bQty\b\s*[:#]?\s*(\d{1,3})\b/) {
            let q = Int(match.1)!
            if q > 0 { return q }
        }

        // 2) Between money columns
        if let match = line.firstMatch(of: /\$?\s*[\d,]+\.\d{2}\s+(\d{1,3})\s+\$?\s*[\d,]+\.\d{2}/) {
            let q = Int(match.1)!
            if q > 0 { return q }
        }

        // 3) Qty before trailing money
        if let match = line.firstMatch(of: /^(.*)\b(\d{1,3})\b\s+\$?\s*[\d,]+\.\d{2}\s+\$?\s*[\d,]+\.\d{2}\s*$/) {
            let q = Int(match.2)!
            if q > 0 { return q }
        }

        return nil
    }

    // MARK: - Line Item Parsing

    private static func parseLineItemFromLine(_ line: String, bufferedDescription: String) -> ParsedLineItem? {
        let moneyTokens = extractMoneyTokens(line)
        guard moneyTokens.count >= 2 else { return nil }
        guard let qty = extractQty(line), qty > 0 else { return nil }

        let unitPrice = moneyTokens[0]
        let total = moneyTokens[moneyTokens.count - 1]
        let subtotal = moneyTokens.count >= 3 ? moneyTokens[1] : nil
        let tax = moneyTokens.count >= 4 ? moneyTokens[moneyTokens.count - 2] : nil

        var shipping: String?
        var adjustment: String?

        let middleBeforeTax: [String]
        if moneyTokens.count >= 6 {
            middleBeforeTax = Array(moneyTokens[2..<(moneyTokens.count - 2)])
        } else if moneyTokens.count == 5 {
            middleBeforeTax = Array(moneyTokens[2..<(moneyTokens.count - 2)])
        } else {
            middleBeforeTax = []
        }

        if !middleBeforeTax.isEmpty {
            if let negIdx = middleBeforeTax.firstIndex(where: { $0.hasPrefix("-") }) {
                adjustment = InvoiceMoneyParsing.absMoneyString(middleBeforeTax[negIdx])
                let remaining = middleBeforeTax.enumerated().filter { $0.offset != negIdx }.map(\.element)
                shipping = remaining.first
            } else if middleBeforeTax.count >= 2 {
                shipping = middleBeforeTax[0]
                adjustment = InvoiceMoneyParsing.absMoneyString(middleBeforeTax[1])
            } else {
                shipping = middleBeforeTax[0]
            }
        }

        let description: String
        if !bufferedDescription.trimmingCharacters(in: .whitespaces).isEmpty {
            description = bufferedDescription.trimmingCharacters(in: .whitespaces)
        } else {
            description = line.replacingOccurrences(of: #"\s+\$?\s*[\d,]+\.\d{2}.*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        guard !description.isEmpty else { return nil }

        return ParsedLineItem(
            description: description,
            qty: qty,
            unitPrice: unitPrice,
            subtotal: subtotal,
            shipping: shipping,
            adjustment: adjustment,
            tax: tax,
            total: total
        )
    }

    // MARK: - Continuation Helpers

    private static func shouldPreserveContinuationOnReset(
        allowLoose: Bool, awaitingPost: Bool,
        buffered: [String], sku: String?,
        attrs: Attributes, attrLines: [String]
    ) -> Bool {
        guard allowLoose || awaitingPost else { return false }
        if buffered.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { return false }
        if sku != nil { return false }
        if !attrLines.isEmpty { return false }
        if !attrs.isEmpty { return false }
        return true
    }

    private static func isSoftLeadingWordContinuation(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let cleaned = trimmed.replacingOccurrences(of: #"^[^A-Za-z0-9(]+"#, with: "", options: .regularExpression)
        guard !cleaned.isEmpty else { return false }
        let firstToken = cleaned.components(separatedBy: .whitespaces).first?.lowercased()
        guard let token = firstToken else { return false }
        if token.hasPrefix("(") { return true }
        return continuationLeadingWords.contains(token)
    }

    private static func isLikelyParentheticalLead(_ line: String) -> Bool {
        let s = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 120, s.contains("("), !s.contains(")"), !s.contains(":"), !s.contains("@") else { return false }
        guard s.range(of: #"^[A-Za-z][^:]*:\s*"#, options: .regularExpression) == nil else { return false }
        guard let parenIdx = s.firstIndex(of: "(") else { return false }
        let prefix = s[..<parenIdx].trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty else { return false }
        let prefixWords = prefix.components(separatedBy: " ").filter { !$0.isEmpty }
        guard prefixWords.count <= 4, prefix.count <= 30 else { return false }
        return true
    }

    private static func isLikelyParentheticalContinuation(_ line: String) -> Bool {
        let s = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 60, s.contains(")"), !s.contains(":"), !s.contains("@") else { return false }
        return s.range(of: #"^[A-Za-z0-9()\[\] ,./'&-]+$"#, options: .regularExpression) != nil
    }

    private static func isLikelyDimensionContinuation(_ line: String) -> Bool {
        let s = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        return s.range(of: #"^x\s+\d+(?:\.\d+)?(?:\s*(?:"|'|inch|inches|cm|mm|ft|feet|in|L|W|H|D))?\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isLikelyItemPositionIndicator(_ line: String) -> Bool {
        let s = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        return s.range(of: #"^\(?\d+\s+of\s+\d+\)?\.?$"#, options: .regularExpression) != nil
    }

    private static func hasUnclosedParenthesis(_ text: String?) -> Bool {
        guard let text else { return false }
        var balance = 0
        for char in text {
            if char == "(" { balance += 1 }
            else if char == ")" { if balance > 0 { balance -= 1 } }
        }
        return balance > 0
    }

    // MARK: - Quote Helpers

    private static func stripOuterQuotes(_ input: String) -> String {
        let quotePattern = "[\(wayfairDoubleQuoteChars)]"
        guard let regex = try? NSRegularExpression(pattern: "^\(quotePattern)+|\(quotePattern)+$") else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
    }

    private static func normalizeQuotes(_ input: String) -> String {
        let quotePattern = "[\(wayfairDoubleQuoteChars)]"
        guard let regex = try? NSRegularExpression(pattern: quotePattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "\"")
    }

    private static func looksLikeMeasurement(_ text: String) -> Bool {
        text.range(of: "[\\d]", options: .regularExpression) != nil
            || text.range(of: #"\b(?:cm|mm|inch|inches|ft|foot|feet|x)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func looksDescriptive(_ text: String) -> Bool {
        guard text.count >= 4, text.range(of: "[A-Za-z]", options: .regularExpression) != nil else { return false }
        if text.range(of: #"^\s*x\s+\d+(?:\.\d+)?(?:\s*(?:"|'|inch|inches|cm|mm|ft|feet|in|L|W|H|D))?\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        return true
    }
}
