import Foundation

struct ItemTagTextObservation: Hashable, Sendable {
    var text: String
    var confidence: Double
}

struct ItemTagExtractionResult: Hashable, Sendable {
    var selectedSku: String?
    var rawText: String?
    var barcodePayloads: [String]
    var skuCandidates: [String]
    var confidence: Double?

    var protoExtraction: ProtoItemExtraction? {
        guard rawText != nil || !barcodePayloads.isEmpty || !skuCandidates.isEmpty || confidence != nil else { return nil }
        return ProtoItemExtraction(
            rawText: rawText,
            barcodePayloads: barcodePayloads.isEmpty ? nil : barcodePayloads,
            skuCandidates: skuCandidates.isEmpty ? nil : skuCandidates,
            confidence: confidence,
            extractedAt: Date()
        )
    }
}

enum ItemTagExtraction {
    static func extract(
        barcodePayloads: [String] = [],
        textObservations: [ItemTagTextObservation]
    ) -> ItemTagExtractionResult {
        let rawText = textObservations
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        let cleanedBarcodes = barcodePayloads.compactMap(cleanCandidate)
        var scored: [ScoredCandidate] = []
        for barcode in cleanedBarcodes {
            if isPlausibleSku(barcode, allowNumericOnly: true) {
                scored.append(ScoredCandidate(value: barcode, score: 60, confidence: 1.0, source: .barcode))
            }
        }

        let lines = textObservations.flatMap { observation in
            observation.text
                .components(separatedBy: .newlines)
                .map { ItemTagTextObservation(text: $0, confidence: observation.confidence) }
        }

        for (index, observation) in lines.enumerated() {
            let line = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let labeled = labeledCandidates(in: line)
            for candidate in labeled {
                scored.append(ScoredCandidate(
                    value: candidate,
                    score: scoreWithBarcodeSupport(baseScore: 95, candidate: candidate, barcodes: cleanedBarcodes),
                    confidence: observation.confidence,
                    source: .ocr
                ))
            }

            if containsSkuLabel(line),
               labeled.isEmpty,
               lines.indices.contains(index + 1),
               let nextCandidate = cleanCandidate(lines[index + 1].text),
               isPlausibleSku(nextCandidate, allowNumericOnly: true) {
                scored.append(ScoredCandidate(
                    value: nextCandidate,
                    score: scoreWithBarcodeSupport(baseScore: 88, candidate: nextCandidate, barcodes: cleanedBarcodes),
                    confidence: lines[index + 1].confidence,
                    source: .ocr
                ))
            }

            for candidate in looseCandidates(in: line) {
                scored.append(ScoredCandidate(
                    value: candidate,
                    score: scoreWithBarcodeSupport(baseScore: looseScore(for: candidate), candidate: candidate, barcodes: cleanedBarcodes),
                    confidence: observation.confidence,
                    source: .ocr
                ))
            }
        }

        let ranked = rankedCandidates(scored)
        let selected = ranked.first { $0.source == .ocr && $0.score >= 70 }
        return ItemTagExtractionResult(
            selectedSku: selected?.value,
            rawText: rawText.isEmpty ? nil : rawText,
            barcodePayloads: cleanedBarcodes,
            skuCandidates: ranked.map(\.value),
            confidence: selected?.confidence
        )
    }

    private static func labeledCandidates(in line: String) -> [String] {
        let pattern = #"(?i)\b(?:sku|style|model|item|item\s*#|item\s*no\.?|product|part|upc|ean|barcode)\b\s*(?:no\.?|number|#|:|-)?\s*([A-Z0-9][A-Z0-9._/-]{2,31})"#
        return regexMatches(pattern: pattern, in: line)
            .compactMap(cleanCandidate)
            .filter { isPlausibleSku($0, allowNumericOnly: true) }
    }

    private static func looseCandidates(in line: String) -> [String] {
        let pattern = #"\b[A-Z0-9][A-Z0-9._/-]{3,31}\b"#
        return regexMatches(pattern: pattern, in: line.uppercased())
            .compactMap(cleanCandidate)
            .filter { isPlausibleSku($0, allowNumericOnly: false) || isStandardBarcodeLength($0) }
    }

    private static func containsSkuLabel(_ line: String) -> Bool {
        line.range(
            of: #"(?i)\b(sku|style|model|item|item\s*#|item\s*no\.?|product|part|upc|ean|barcode)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func cleanCandidate(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#:;,.()[]{}"))
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "/", with: "-")

        let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func isPlausibleSku(_ candidate: String, allowNumericOnly: Bool) -> Bool {
        guard (4...32).contains(candidate.count) else { return false }
        guard candidate.range(of: #"^[A-Z0-9][A-Z0-9.-]*[A-Z0-9]$"#, options: .regularExpression) != nil else { return false }
        guard candidate.contains(where: { $0.isNumber }) else { return false }
        if candidate.allSatisfy(\.isNumber) {
            return allowNumericOnly || isStandardBarcodeLength(candidate)
        }
        if looksLikeDate(candidate) || looksLikePrice(candidate) || looksLikePhoneNumber(candidate) {
            return false
        }
        return true
    }

    private static func isStandardBarcodeLength(_ candidate: String) -> Bool {
        candidate.allSatisfy(\.isNumber) && [8, 12, 13, 14].contains(candidate.count)
    }

    private static func looksLikeDate(_ candidate: String) -> Bool {
        candidate.range(of: #"^\d{1,2}[-.]\d{1,2}[-.]\d{2,4}$"#, options: .regularExpression) != nil
    }

    private static func looksLikePrice(_ candidate: String) -> Bool {
        candidate.range(of: #"^\d+[.]\d{2}$"#, options: .regularExpression) != nil
    }

    private static func looksLikePhoneNumber(_ candidate: String) -> Bool {
        let digits = candidate.filter(\.isNumber)
        return digits.count == 10 && candidate.contains("-")
    }

    private static func looseScore(for candidate: String) -> Double {
        if isStandardBarcodeLength(candidate) { return 62 }
        if candidate.contains("-") || candidate.contains(".") { return 58 }
        return 48
    }

    private static func scoreWithBarcodeSupport(baseScore: Double, candidate: String, barcodes: [String]) -> Double {
        guard barcodes.contains(where: { barcode in
            barcode == candidate || barcode.contains(candidate) || candidate.contains(barcode)
        }) else { return baseScore }
        return max(baseScore + 15, 90)
    }

    private static func rankedCandidates(_ candidates: [ScoredCandidate]) -> [ScoredCandidate] {
        var bestByValue: [String: ScoredCandidate] = [:]
        for candidate in candidates {
            if let existing = bestByValue[candidate.value] {
                if candidate.score > existing.score {
                    bestByValue[candidate.value] = candidate
                }
            } else {
                bestByValue[candidate.value] = candidate
            }
        }
        return bestByValue.values.sorted {
            if $0.score == $1.score { return $0.value < $1.value }
            return $0.score > $1.score
        }
    }

    private static func regexMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let matchRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard let range = Range(matchRange, in: text) else { return nil }
            return String(text[range])
        }
    }
}

private struct ScoredCandidate: Hashable {
    var value: String
    var score: Double
    var confidence: Double
    var source: CandidateSource
}

private enum CandidateSource: Hashable {
    case ocr
    case barcode
}
