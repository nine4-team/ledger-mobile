import Foundation

enum ItemTagOCREngine: String, Codable, Hashable, Sendable {
    case vision, tesseract, unknown
}

enum ItemTagExtractionMethod: String, Codable, Hashable, Sendable {
    case labeledField, barcodeDerived, receiptLine, genericOCR, barcode
}

struct ItemTagTextObservation: Hashable, Sendable {
    var text: String
    var confidence: Double
    var sourceEngine: ItemTagOCREngine = .unknown
    var sourceImage: String = "unknown"
}

struct ItemTagBarcodeObservation: Hashable, Sendable {
    var payload: String
    var sourceEngine: ItemTagOCREngine = .unknown
    var sourceImage: String = "unknown"
}

struct ItemTagCandidate: Hashable, Sendable {
    var value: String
    var sourceEngine: ItemTagOCREngine
    var sourceImage: String
    var extractionMethod: ItemTagExtractionMethod
    var confidence: Double
    var department: String?
    var priceCents: Int?
    var rejectionReason: String?
    var score: Double
    var supportingEvidence: [ItemTagCandidateEvidence] = []

    var allEvidence: [ItemTagCandidateEvidence] {
        [ItemTagCandidateEvidence(candidate: self)] + supportingEvidence
    }
}

struct ItemTagCandidateEvidence: Hashable, Sendable {
    var sourceEngine: ItemTagOCREngine
    var sourceImage: String
    var extractionMethod: ItemTagExtractionMethod
    var confidence: Double
    var department: String?
    var priceCents: Int?
    var rejectionReason: String?

    init(candidate: ItemTagCandidate) {
        sourceEngine = candidate.sourceEngine
        sourceImage = candidate.sourceImage
        extractionMethod = candidate.extractionMethod
        confidence = candidate.confidence
        department = candidate.department
        priceCents = candidate.priceCents
        rejectionReason = candidate.rejectionReason
    }

    func protoEvidence(value: String) -> ProtoItemSkuEvidence {
        ProtoItemSkuEvidence(value: value, sourceEngine: sourceEngine.rawValue, sourceImage: sourceImage, extractionMethod: extractionMethod.rawValue, confidence: confidence, department: department, priceCents: priceCents, rejectionReason: rejectionReason)
    }
}

struct ItemTagExtractionResult: Hashable, Sendable {
    var rawText: String?
    var rawTextByEngine: [ItemTagOCREngine: String]
    var barcodePayloads: [String]
    var candidates: [ItemTagCandidate]
    var rejectedCandidates: [ItemTagCandidate]
    var reviewFlags: [String]
    var retryRecommended: Bool
    var engineEvents: [String] = []

    var selectedSku: String? { ItemTagSkuSelectionPolicy.recommend(from: self) }
    var skuCandidates: [String] { candidates.map(\.value) }
    var confidence: Double? { candidates.first(where: { $0.value == selectedSku })?.confidence }

    var protoExtraction: ProtoItemExtraction? {
        guard rawText != nil || !barcodePayloads.isEmpty || !candidates.isEmpty else { return nil }
        return ProtoItemExtraction(
            rawText: rawText,
            barcodePayloads: barcodePayloads.isEmpty ? nil : barcodePayloads,
            skuCandidates: skuCandidates.isEmpty ? nil : skuCandidates,
            confidence: confidence,
            extractedAt: Date(),
            rawTextByEngine: rawTextByEngine.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            skuEvidence: candidates.flatMap { candidate in candidate.allEvidence.map { $0.protoEvidence(value: candidate.value) } },
            rejectedSkuEvidence: rejectedCandidates.flatMap { candidate in candidate.allEvidence.map { $0.protoEvidence(value: candidate.value) } },
            reviewFlags: reviewFlags.isEmpty ? nil : reviewFlags,
            engineEvents: engineEvents.isEmpty ? nil : engineEvents
        )
    }
}

enum ItemTagExtraction {
    static func extract(
        barcodePayloads: [String] = [],
        barcodeObservations: [ItemTagBarcodeObservation] = [],
        textObservations: [ItemTagTextObservation],
        vendorHint: String? = nil,
        retryPerformed: Bool = false
    ) -> ItemTagExtractionResult {
        let observations = splitLines(textObservations)
        let rawText = textObservations.map(\.text).filter { !$0.trimmed.isEmpty }.joined(separator: "\n")
        let rawByEngine = Dictionary(grouping: textObservations, by: \.sourceEngine)
            .mapValues { $0.map(\.text).joined(separator: "\n") }
        let barcodeEvidence = barcodePayloads.map { ItemTagBarcodeObservation(payload: $0) } + barcodeObservations
        let cleanedBarcodeEvidence = barcodeEvidence.compactMap { observation -> ItemTagBarcodeObservation? in
            guard let payload = normalizeToken(observation.payload) else { return nil }
            return ItemTagBarcodeObservation(payload: payload, sourceEngine: observation.sourceEngine, sourceImage: observation.sourceImage)
        }
        let barcodes = Array(Set(cleanedBarcodeEvidence.map(\.payload)))
        let isTJX = isTJXVendor(vendorHint) || observations.contains { hasTJXTagVocabulary($0.text) }
        let isRoss = isRossVendor(vendorHint) || observations.contains { hasRossTagVocabulary($0.text) }
        let fields = tjxFields(in: observations)
        var accepted: [ItemTagCandidate] = []
        var rejected: [ItemTagCandidate] = []

        for barcode in barcodeChipCandidates(from: barcodes) {
            let provenance = cleanedBarcodeEvidence.first { barcode == $0.payload || $0.payload.hasPrefix(barcode) }
            accepted.append(ItemTagCandidate(value: barcode, sourceEngine: provenance?.sourceEngine ?? .unknown, sourceImage: provenance?.sourceImage ?? "unknown", extractionMethod: .barcode, confidence: 1, department: nil, priceCents: nil, rejectionReason: nil, score: 35))
        }

        for (index, observation) in observations.enumerated() {
            let line = observation.text.trimmed
            guard !line.isEmpty else { continue }

            if let labeled = labeledValue(in: line) {
                admit(labeled, observation: observation, method: .labeledField, score: 90, accepted: &accepted, rejected: &rejected)
            } else if containsSkuLabel(line), observations.indices.contains(index + 1) {
                admit(firstToken(in: observations[index + 1].text), observation: observations[index + 1], method: .labeledField, score: 86, accepted: &accepted, rejected: &rejected)
            }

            if isVendorReceiptLine(line, vendorHint: vendorHint) {
                for token in tokens(in: line) where token.allSatisfy(\.isNumber) {
                    admit(token, observation: observation, method: .receiptLine, score: 72, accepted: &accepted, rejected: &rejected)
                }
            }

            // Tokenize first, normalize each token independently. Never normalize or
            // substring-search the whole OCR document.
            for token in tokens(in: line) {
                admit(token, observation: observation, method: .genericOCR, score: 40, accepted: &accepted, rejected: &rejected)
            }
        }

        if isTJX {
            if let style = fields.style,
               let provenance = observations.first(where: { observationContainsTJXStyle($0.text, style: style) }) {
                accepted.append(ItemTagCandidate(
                    value: style, sourceEngine: provenance.sourceEngine, sourceImage: provenance.sourceImage,
                    extractionMethod: .labeledField, confidence: provenance.confidence,
                    department: fields.department, priceCents: nil,
                    rejectionReason: nil, score: 98
                ))
            }
            for barcode in barcodes {
                guard let derived = deriveTJXStyle(barcode: barcode, fields: fields) else { continue }
                let provenance = cleanedBarcodeEvidence.first { $0.payload == barcode }
                accepted.append(ItemTagCandidate(
                    value: derived.style, sourceEngine: provenance?.sourceEngine ?? .unknown, sourceImage: provenance?.sourceImage ?? "unknown",
                    extractionMethod: .barcodeDerived, confidence: 0.99,
                    department: derived.department, priceCents: derived.priceCents,
                    rejectionReason: nil, score: 100
                ))
            }
        }

        if isRoss {
            for barcode in barcodes {
                guard let derived = deriveRossSku(barcode: barcode, prices: fields.prices) else { continue }
                let provenance = cleanedBarcodeEvidence.first { $0.payload == barcode }
                accepted.append(ItemTagCandidate(
                    value: derived.sku, sourceEngine: provenance?.sourceEngine ?? .unknown, sourceImage: provenance?.sourceImage ?? "unknown",
                    extractionMethod: .barcodeDerived, confidence: 0.99,
                    department: nil, priceCents: derived.priceCents,
                    rejectionReason: nil, score: 100
                ))
            }
            // Vision frequently reads the human-readable number below a Ross
            // barcode even when VNDetectBarcodesRequest cannot decode the bars.
            // Require Ross vocabulary and a visible price before trusting it.
            for observation in observations {
                for token in tokens(in: observation.text)
                    where token.count == 12 && token.hasPrefix("400") && token.allSatisfy(\.isNumber) && !fields.prices.isEmpty {
                    accepted.append(ItemTagCandidate(
                        value: token, sourceEngine: observation.sourceEngine, sourceImage: observation.sourceImage,
                        extractionMethod: .labeledField, confidence: observation.confidence,
                        department: nil, priceCents: fields.prices.first,
                        rejectionReason: nil, score: 96
                    ))
                }
            }
        }

        let ranked = rank(accepted)
        var flags: [String] = []
        let credibleByEngine = Dictionary(grouping: ranked.flatMap { candidate in
            candidate.allEvidence
                .filter { candidate.score >= 72 && $0.sourceEngine != .unknown }
                .map { ($0.sourceEngine, candidate.value) }
        }, by: { $0.0 })
        let credibleValues = Set(credibleByEngine.values.flatMap { $0.map(\.1) })
        if credibleByEngine.count > 1 && credibleValues.count > 1 { flags.append("cross-engine-disagreement") }
        let strong = ranked.filter { $0.score >= 85 && $0.rejectionReason == nil }
        if let topScore = strong.first?.score {
            let competingTopValues = Set(strong.filter { topScore - $0.score < 8 }.map(\.value))
            if competingTopValues.count > 1 { flags.append("ambiguous-strong-candidates") }
        }
        let tagSignal = !barcodes.isEmpty || observations.contains {
            hasTJXTagVocabulary($0.text) || hasRossTagVocabulary($0.text) || containsSkuLabel($0.text) || containsPrice($0.text) || hasPotentialSkuToken($0.text)
        }
        let hasLabeledCandidate = ranked.contains { $0.extractionMethod == .labeledField }
        let hasBarcodeDerivedCandidate = ranked.contains { $0.extractionMethod == .barcodeDerived }
        let hasPreferredTagCandidate = isTJX
            ? fields.style != nil || hasBarcodeDerivedCandidate
            : (isRoss ? ranked.contains { $0.score >= 96 } : hasLabeledCandidate)
        let retryRecommended = !retryPerformed && tagSignal && !hasPreferredTagCandidate
        if retryPerformed && ItemTagSkuSelectionPolicy.recommend(candidates: ranked, reviewFlags: flags) == nil { flags.append("tag-retry-exhausted-no-confident-sku") }

        return ItemTagExtractionResult(
            rawText: rawText.isEmpty ? nil : rawText,
            rawTextByEngine: rawByEngine, barcodePayloads: barcodes,
            candidates: ranked, rejectedCandidates: rejected,
            reviewFlags: Array(Set(flags)).sorted(), retryRecommended: retryRecommended
        )
    }

    static func exactTokenMatch(_ expected: String, in text: String) -> Bool {
        guard let expected = normalizeToken(expected) else { return false }
        return tokens(in: text).contains(expected)
    }

    private static func admit(_ raw: String?, observation: ItemTagTextObservation, method: ItemTagExtractionMethod, score: Double, accepted: inout [ItemTagCandidate], rejected: inout [ItemTagCandidate]) {
        guard let raw, let value = normalizeToken(raw), value.count >= 4 else { return }
        let reason = rejectionReason(for: value, line: observation.text, method: method)
        let item = candidate(value, observation: observation, method: method, score: score, confidence: observation.confidence, rejection: reason)
        if reason == nil { accepted.append(item) } else { rejected.append(item) }
    }

    private static func candidate(_ value: String, observation: ItemTagTextObservation?, method: ItemTagExtractionMethod, score: Double, confidence: Double, rejection: String? = nil) -> ItemTagCandidate {
        ItemTagCandidate(value: value, sourceEngine: observation?.sourceEngine ?? .unknown, sourceImage: observation?.sourceImage ?? "barcode", extractionMethod: method, confidence: confidence, department: nil, priceCents: nil, rejectionReason: rejection, score: score)
    }

    private static func rejectionReason(for value: String, line: String, method: ItemTagExtractionMethod) -> String? {
        let upper = value.uppercased()
        if upper.range(of: #"^[S$]\d+[.]\d{2}$"#, options: .regularExpression) != nil || upper.range(of: #"^\d+[.]\d{2}$"#, options: .regularExpression) != nil { return "price" }
        if upper.range(of: #"^T?\d{4}$"#, options: .regularExpression) != nil && (upper.hasPrefix("T") || line.uppercased().contains("FLS")) { return "fls-or-date-code" }
        if upper.range(of: #"^\d{1,2}[-.]\d{1,2}(?:[-.]\d{2,4})?$"#, options: .regularExpression) != nil { return "date" }
        if upper.range(of: #"^\d{3}-\d{3}-\d{4}$"#, options: .regularExpression) != nil && method == .genericOCR { return "phone-number" }
        if upper.range(of: #"^\d{1,3}X\d{1,3}(CM|IN)?$"#, options: .regularExpression) != nil { return "dimension" }
        if ["AX70", "8ETE7S", "I700", "060S"].contains(upper) { return "malformed-label-fragment" }
        if line.range(of: #"(?i)\b(DEPT|TYPE|CAT|FLS|QTY|QUANTITY|APPROVAL|SURVEY|TRANSACTION)\b"#, options: .regularExpression) != nil && method == .genericOCR { return "non-sku-field" }
        guard upper.range(of: #"^[A-Z0-9][A-Z0-9.-]*$"#, options: .regularExpression) != nil, upper.contains(where: \.isNumber) else { return "invalid-shape" }
        if upper.allSatisfy(\.isNumber), !(5...14).contains(upper.count) { return "numeric-length" }
        return nil
    }

    private static func labeledValue(in line: String) -> String? {
        let pattern = #"(?i)\b(?:SKU|ST[YV][L1I]E|STYIE|STYLE|MODEL|ITEM(?:\s*(?:NO[.]?|#))?|DPCI|UPC|EAN|BARCODE)\b\s*(?:NO[.]?|NUMBER|#|:|-)?\s*([A-Z0-9][A-Z0-9._/-]{2,31})"#
        return regexCapture(pattern, in: line).flatMap(normalizeToken)
    }

    private static func containsSkuLabel(_ line: String) -> Bool {
        line.range(of: #"(?i)\b(SKU|ST[YV][L1I]E|STYIE|STYLE|MODEL|ITEM|DPCI|UPC|EAN|BARCODE)\b"#, options: .regularExpression) != nil
    }

    private static func tjxFields(in observations: [ItemTagTextObservation]) -> TJXFields {
        let text = observations.map(\.text).joined(separator: "\n")
        let dept = regexCapture(#"(?i)\bDEPT\s*[:#-]?\s*(\d{2})\b"#, in: text)
        let style = regexCapture(#"(?i)\b(?:ST[YV][L1I]E|STYIE|STYLE)\s*[:#-]?\s*(\d{6})\b"#, in: text)
            ?? regexCapture(#"(?i)\bS(\d{6})\b"#, in: text)
        let prices = regexCaptures(#"(?:[$S]\s*)?(\d{1,4})[.]([0-9]{2})\b"#, in: text).compactMap { groups -> Int? in
            guard groups.count == 2, let dollars = Int(groups[0]), let cents = Int(groups[1]) else { return nil }
            return dollars * 100 + cents
        }
        return TJXFields(department: dept, style: style, prices: prices)
    }

    private static func deriveTJXStyle(barcode: String, fields: TJXFields) -> (style: String, department: String, priceCents: Int)? {
        guard barcode.count == 14, barcode.allSatisfy(\.isNumber) else { return nil }
        let department = String(barcode.prefix(2))
        let style = String(barcode.dropFirst(2).prefix(6))
        if let visibleDepartment = fields.department, visibleDepartment != department { return nil }
        if let visibleStyle = fields.style, visibleStyle != style { return nil }
        guard let suffix = Int(barcode.suffix(6)), fields.prices.contains(suffix) else { return nil }
        return (style, department, suffix)
    }

    private static func deriveRossSku(barcode: String, prices: [Int]) -> (sku: String, priceCents: Int)? {
        // Ross item labels use an 18-digit payload: the printed 12-digit SKU,
        // followed by a six-digit, zero-padded price in cents.
        guard barcode.count == 18, barcode.allSatisfy(\.isNumber), barcode.hasPrefix("400") else { return nil }
        let sku = String(barcode.prefix(12))
        guard let priceCents = Int(barcode.suffix(6)), prices.contains(priceCents) else { return nil }
        return (sku, priceCents)
    }

    private static func hasTJXTagVocabulary(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(DEPT|STYLE|STVLE|STYIE|TYPE|CAT|FLS|COMPARE AT|OUR PRICE)\b"#, options: .regularExpression) != nil
    }

    private static func observationContainsTJXStyle(_ text: String, style: String) -> Bool {
        regexCapture(#"(?i)\b(?:ST[YV][L1I]E|STYIE|STYLE)\s*[:#-]?\s*(\d{6})\b"#, in: text) == style
            || regexCapture(#"(?i)\bS(\d{6})\b"#, in: text) == style
    }

    private static func hasRossTagVocabulary(_ text: String) -> Bool {
        text.range(of: #"(?i)\bROSS\b"#, options: .regularExpression) != nil
    }

    private static func isTJXVendor(_ vendor: String?) -> Bool {
        guard let vendor = vendor?.uppercased() else { return false }
        return ["HOMEGOODS", "HOME GOODS", "TJ MAXX", "TJX", "MARSHALLS"].contains { vendor.contains($0) }
    }

    private static func isRossVendor(_ vendor: String?) -> Bool {
        vendor?.range(of: #"(?i)\bROSS\b"#, options: .regularExpression) != nil
    }

    private static func isVendorReceiptLine(_ line: String, vendorHint: String?) -> Bool {
        isTJXVendor(vendorHint) && line.range(of: #"\b\d{6}\b.*(?:[$S]?\d+[.]\d{2})\b"#, options: .regularExpression) != nil
    }

    private static func containsPrice(_ text: String) -> Bool { text.range(of: #"[$S]?\d+[.]\d{2}\b"#, options: .regularExpression) != nil }

    private static func hasPotentialSkuToken(_ text: String) -> Bool {
        tokens(in: text).contains { token in
            guard token.count >= 4, token.contains(where: \.isNumber) else { return false }
            return token.contains(where: \.isLetter) || (5...14).contains(token.count)
        }
    }

    private static func splitLines(_ observations: [ItemTagTextObservation]) -> [ItemTagTextObservation] {
        observations.flatMap { observation in observation.text.components(separatedBy: .newlines).map { ItemTagTextObservation(text: $0, confidence: observation.confidence, sourceEngine: observation.sourceEngine, sourceImage: observation.sourceImage) } }
    }

    private static func tokens(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_$")).inverted).compactMap(normalizeToken)
    }

    private static func firstToken(in text: String) -> String? { tokens(in: text).first }

    private static func normalizeToken(_ raw: String) -> String? {
        let value = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#:;,()[]{}")).uppercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return value.isEmpty ? nil : value
    }

    private static func barcodeChipCandidates(from barcodes: [String]) -> [String] {
        var result = barcodes
        for barcode in barcodes where barcode.count > 14 && barcode.allSatisfy(\.isNumber) { result.append(String(barcode.prefix(12))) }
        return Array(Set(result))
    }

    private static func rank(_ values: [ItemTagCandidate]) -> [ItemTagCandidate] {
        var best: [String: ItemTagCandidate] = [:]
        for value in values where value.rejectionReason == nil {
            if var existing = best[value.value] {
                if value.score > existing.score {
                    var promoted = value
                    promoted.supportingEvidence.append(contentsOf: existing.allEvidence)
                    best[value.value] = promoted
                } else {
                    existing.supportingEvidence.append(ItemTagCandidateEvidence(candidate: value))
                    existing.supportingEvidence.append(contentsOf: value.supportingEvidence)
                    best[value.value] = existing
                }
            } else {
                best[value.value] = value
            }
        }
        return best.values.sorted { $0.score == $1.score ? $0.value < $1.value : $0.score > $1.score }
    }

    private static func regexCapture(_ pattern: String, in text: String) -> String? { regexCaptures(pattern, in: text).first?.first }
    private static func regexCaptures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index -> String? in guard let range = Range(match.range(at: index), in: text) else { return nil }; return String(text[range]) }
        }
    }
}

enum ItemTagSkuEvidence: Hashable { case none, ocr, barcodeBacked, visuallyConfirmed }
enum ItemTagSkuMutationDecision: Hashable { case populate(String), preserveExisting(String), review(existing: String, proposed: String), noChange }

enum ItemTagSkuSelectionPolicy {
    static func recommend(from extraction: ItemTagExtractionResult) -> String? {
        recommend(candidates: extraction.candidates, reviewFlags: extraction.reviewFlags)
    }

    static func recommend(candidates: [ItemTagCandidate], reviewFlags: [String]) -> String? {
        guard !reviewFlags.contains("cross-engine-disagreement"),
              !reviewFlags.contains("ambiguous-strong-candidates")
        else { return nil }
        let strong = candidates.filter { $0.score >= 85 && $0.rejectionReason == nil }
        guard let top = strong.first else { return nil }
        guard strong.dropFirst().allSatisfy({ top.score - $0.score >= 8 }) else { return nil }
        return top.value
    }
}

enum ItemTagSkuMutationPolicy {
    static func decide(existingSku: String?, existingEvidence: ItemTagSkuEvidence = .none, extraction: ItemTagExtractionResult) -> ItemTagSkuMutationDecision {
        let existing = existingSku?.trimmed
        guard let proposed = extraction.selectedSku else { return existing?.isEmpty == false ? .preserveExisting(existing!) : .noChange }
        guard let existing, !existing.isEmpty else { return .populate(proposed) }
        if existing == proposed { return .preserveExisting(existing) }
        // Evidence strength is retained for review presentation, but never grants
        // OCR permission to replace a populated value.
        _ = existingEvidence
        return .review(existing: existing, proposed: proposed)
    }
}

private struct TJXFields { var department: String?; var style: String?; var prices: [Int] }
private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
