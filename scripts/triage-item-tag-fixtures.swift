#!/usr/bin/env swift
import Foundation
import ImageIO
import Vision

struct Manifest: Decodable {
    let images: [ManifestImage]
}

struct ManifestImage: Decodable {
    let itemId: String
    let itemName: String?
    let vendor: String
    let expectedSku: String?
    let projectName: String?
    let localPath: String
    let downloadStatus: String
}

struct TriageRow: Encodable {
    let bucket: String
    let vendor: String
    let expectedSku: String?
    let selectedSku: String?
    let selectedMatchesExpected: Bool
    let candidateContainsExpected: Bool
    let barcodeContainsExpected: Bool
    let tagEvidence: String
    let detectedBarcodes: [String]
    let detectedCandidates: [String]
    let detectedTextLines: [String]
    let textLineCount: Int
    let localPath: String
    let itemId: String
    let itemName: String?
    let projectName: String?
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let manifestArgument = arguments.first else {
    print("""
    Usage:
      swift scripts/triage-item-tag-fixtures.swift <manifest.json> [output-dir]

    Creates symlink buckets next to the manifest by default:
      triage/01-barcode-detected
      triage/02-expected-sku-found
      triage/03-text-with-candidates
      triage/04-text-no-candidates
      triage/05-no-text-no-barcode
      triage/06-download-missing
    """)
    exit(2)
}

let manifestURL = URL(fileURLWithPath: manifestArgument)
let manifestDirectory = manifestURL.deletingLastPathComponent()
let outputURL = arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
    ?? manifestDirectory.appendingPathComponent("triage", isDirectory: true)

let manifestData = try Data(contentsOf: manifestURL)
let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
let fileManager = FileManager.default

let buckets = [
    "01-barcode-detected",
    "02-expected-sku-found",
    "03-text-with-candidates",
    "04-text-no-candidates",
    "05-no-text-no-barcode",
    "06-download-missing",
]

try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
for bucket in buckets {
    try fileManager.createDirectory(at: outputURL.appendingPathComponent(bucket, isDirectory: true), withIntermediateDirectories: true)
}

var rows: [TriageRow] = []
var counts: [String: Int] = [:]

for (index, image) in manifest.images.enumerated() {
    let imageURL = manifestDirectory.appendingPathComponent(image.localPath)
    let exists = fileManager.fileExists(atPath: imageURL.path)
    guard image.downloadStatus == "downloaded", exists else {
        let bucket = "06-download-missing"
        counts[bucket, default: 0] += 1
        rows.append(TriageRow(
            bucket: bucket,
            vendor: image.vendor,
            expectedSku: image.expectedSku,
            selectedSku: nil,
            selectedMatchesExpected: false,
            candidateContainsExpected: false,
            barcodeContainsExpected: false,
            tagEvidence: "none",
            detectedBarcodes: [],
            detectedCandidates: [],
            detectedTextLines: [],
            textLineCount: 0,
            localPath: image.localPath,
            itemId: image.itemId,
            itemName: image.itemName,
            projectName: image.projectName
        ))
        continue
    }

    let result = analyzeImage(at: imageURL)
    let expected = normalizeSku(image.expectedSku ?? "")
    let selected = result.selectedSku
    let candidateContainsExpected = !expected.isEmpty && result.candidates.contains { normalizeSku($0) == expected }
    let barcodeContainsExpected = !expected.isEmpty && result.barcodes.contains { normalizeSku($0).contains(expected) }
    let foundExpected = !expected.isEmpty && (
        candidateContainsExpected ||
        result.textLines.contains { normalizeSku($0).contains(expected) }
    )

    let hasStrongCandidate = result.candidates.contains { candidate in
        isStrongCandidate(candidate, textLines: result.textLines)
    }

    let bucket: String
    if !result.barcodes.isEmpty {
        bucket = "01-barcode-detected"
    } else if foundExpected {
        bucket = "02-expected-sku-found"
    } else if hasStrongCandidate {
        bucket = "03-text-with-candidates"
    } else if !result.textLines.isEmpty {
        bucket = "04-text-no-candidates"
    } else {
        bucket = "05-no-text-no-barcode"
    }

    counts[bucket, default: 0] += 1
    let linkName = safeFileName("\(index + 1)-\(image.vendor)-\(image.expectedSku ?? "no-sku")-\(image.itemId)") + "." + imageURL.pathExtension
    let linkURL = outputURL.appendingPathComponent(bucket, isDirectory: true).appendingPathComponent(linkName)
    try? fileManager.removeItem(at: linkURL)
    try? fileManager.createSymbolicLink(at: linkURL, withDestinationURL: imageURL)

    rows.append(TriageRow(
        bucket: bucket,
        vendor: image.vendor,
        expectedSku: image.expectedSku,
        selectedSku: selected,
        selectedMatchesExpected: !expected.isEmpty && normalizeSku(selected ?? "") == expected,
        candidateContainsExpected: candidateContainsExpected,
        barcodeContainsExpected: barcodeContainsExpected,
        tagEvidence: tagEvidence(barcodes: result.barcodes, candidates: result.candidates),
        detectedBarcodes: result.barcodes,
        detectedCandidates: result.candidates,
        detectedTextLines: result.textLines,
        textLineCount: result.textLines.count,
        localPath: image.localPath,
        itemId: image.itemId,
        itemName: image.itemName,
        projectName: image.projectName
    ))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(rows).write(to: outputURL.appendingPathComponent("triage-report.json"))
try triageCSV(rows).write(to: outputURL.appendingPathComponent("triage-report.csv"), atomically: true, encoding: .utf8)

print("Triage complete: \(outputURL.path)")
for bucket in buckets {
    print("\(bucket): \(counts[bucket, default: 0])")
}

struct ImageAnalysis {
    let barcodes: [String]
    let textLines: [String]
    let candidates: [String]
    let selectedSku: String?
}

func analyzeImage(at url: URL) -> ImageAnalysis {
    let barcodeRequest = VNDetectBarcodesRequest()
    let textRequest = VNRecognizeTextRequest()
    textRequest.recognitionLevel = .accurate
    textRequest.usesLanguageCorrection = false

    let handler = VNImageRequestHandler(url: url, options: [:])
    do {
        try handler.perform([barcodeRequest, textRequest])
    } catch {
        return ImageAnalysis(barcodes: [], textLines: [], candidates: [], selectedSku: nil)
    }

    let barcodes = (barcodeRequest.results ?? [])
        .compactMap(\.payloadStringValue)
        .map(cleanCandidate)
        .compactMap { $0 }

    var textLines = recognizedTextLines(from: textRequest.results ?? [])
    for region in barcodeTextRegions(from: barcodeRequest.results ?? []) {
        textLines.append(contentsOf: recognizeText(in: region, url: url))
    }
    if let image = normalizedImage(at: url) {
        for region in barcodeTextRegions(from: barcodeRequest.results ?? []) {
            guard let crop = croppedUpscaledImage(from: image, region: region) else { continue }
            textLines.append(contentsOf: recognizeText(in: crop))
        }
    }

    let ranked = rankedCandidates(from: textLines, barcodes: barcodes)
    return ImageAnalysis(
        barcodes: barcodes,
        textLines: textLines,
        candidates: ranked.map(\.value),
        selectedSku: ranked.first { $0.score >= 70 }?.value
    )
}

func recognizeText(in region: CGRect, url: URL) -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.regionOfInterest = region

    let handler = VNImageRequestHandler(url: url, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return []
    }

    return recognizedTextLines(from: request.results ?? [])
}

func recognizeText(in image: CGImage) -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return []
    }

    return recognizedTextLines(from: request.results ?? [])
}

func recognizedTextLines(from observations: [VNRecognizedTextObservation]) -> [String] {
    observations.compactMap { observation in
        observation.topCandidates(1).first?.string
    }
}

func barcodeTextRegions(from observations: [VNBarcodeObservation]) -> [CGRect] {
    observations.map { observation in
        expandedRegion(around: observation.boundingBox)
    }
}

func expandedRegion(around box: CGRect) -> CGRect {
    let minX = max(0, box.minX - box.width * 1.4)
    let minY = max(0, box.minY - box.height * 1.8)
    let maxX = min(1, box.maxX + box.width * 1.4)
    let maxY = min(1, box.maxY + box.height * 6.0)
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

func normalizedImage(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 4096,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

func croppedUpscaledImage(from image: CGImage, region: CGRect) -> CGImage? {
    let cropRect = pixelRect(for: region, image: image)
    guard let cropped = image.cropping(to: cropRect) else { return nil }
    return upscale(cropped, minimumLongSide: 1800)
}

func pixelRect(for region: CGRect, image: CGImage) -> CGRect {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let rect = CGRect(
        x: region.minX * width,
        y: (1 - region.maxY) * height,
        width: region.width * width,
        height: region.height * height
    )
    return rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
}

func upscale(_ image: CGImage, minimumLongSide: CGFloat) -> CGImage? {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    guard width > 0, height > 0 else { return nil }
    let scale = max(1, minimumLongSide / max(width, height))
    let outputWidth = Int((width * scale).rounded(.up))
    let outputHeight = Int((height * scale).rounded(.up))
    guard let context = CGContext(
        data: nil,
        width: outputWidth,
        height: outputHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(outputWidth), height: CGFloat(outputHeight)))
    return context.makeImage()
}

func rankedCandidates(from lines: [String], barcodes: [String]) -> [ScoredCandidate] {
    var candidates: [ScoredCandidate] = []
    for (index, line) in lines.enumerated() {
        candidates.append(contentsOf: labeledCandidates(in: line).map {
            ScoredCandidate(
                value: $0,
                score: scoreWithBarcodeSupport(baseScore: 95, candidate: $0, barcodes: barcodes)
            )
        })
        if containsSkuLabel(line), lines.indices.contains(index + 1), let next = cleanCandidate(lines[index + 1]), isPlausibleSku(next, allowNumericOnly: true, allowPhoneNumberShape: true) {
            candidates.append(ScoredCandidate(
                value: next,
                score: scoreWithBarcodeSupport(baseScore: 88, candidate: next, barcodes: barcodes)
            ))
        }
        candidates.append(contentsOf: looseCandidates(in: line).map {
            ScoredCandidate(
                value: $0,
                score: scoreWithBarcodeSupport(baseScore: looseScore(for: $0), candidate: $0, barcodes: barcodes)
            )
        })
    }

    var bestByValue: [String: Int] = [:]
    for candidate in candidates {
        bestByValue[candidate.value] = max(bestByValue[candidate.value] ?? 0, candidate.score)
    }

    return bestByValue.map { ScoredCandidate(value: $0.key, score: $0.value) }.sorted {
        if $0.score == $1.score { return $0.value < $1.value }
        return $0.score > $1.score
    }
}

func labeledCandidates(in line: String) -> [String] {
    let pattern = #"(?i)\b(?:sku|style|model|item|item\s*#|item\s*no\.?|product|part|upc|ean|barcode)\b\s*(?:no\.?|number|#|:|-)?\s*([A-Z0-9][A-Z0-9._/-]{2,31})"#
    return regexMatches(pattern: pattern, in: line)
        .compactMap(cleanCandidate)
        .filter { isPlausibleSku($0, allowNumericOnly: true, allowPhoneNumberShape: true) }
}

func looseCandidates(in line: String) -> [String] {
    let pattern = #"\b[A-Z0-9][A-Z0-9._/-]{3,31}\b"#
    return regexMatches(pattern: pattern, in: line.uppercased())
        .compactMap(cleanCandidate)
        .filter { isPlausibleSku($0, allowNumericOnly: false) || isStandaloneNumericSku($0) }
}

func containsSkuLabel(_ line: String) -> Bool {
    line.range(
        of: #"(?i)\b(sku|style|model|item|item\s*#|item\s*no\.?|product|part|upc|ean|barcode)\b"#,
        options: .regularExpression
    ) != nil
}

func cleanCandidate(_ raw: String) -> String? {
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

func isPlausibleSku(
    _ candidate: String,
    allowNumericOnly: Bool,
    allowPhoneNumberShape: Bool = false
) -> Bool {
    guard (4...32).contains(candidate.count) else { return false }
    guard candidate.range(of: #"^[A-Z0-9][A-Z0-9.-]*[A-Z0-9]$"#, options: .regularExpression) != nil else { return false }
    guard candidate.contains(where: { $0.isNumber }) else { return false }
    if candidate.allSatisfy(\.isNumber) {
        return allowNumericOnly || isStandaloneNumericSku(candidate)
    }
    if looksLikeDate(candidate) || looksLikePrice(candidate) {
        return false
    }
    if !allowPhoneNumberShape && looksLikePhoneNumber(candidate) {
        return false
    }
    return true
}

func isStandardBarcodeLength(_ candidate: String) -> Bool {
    candidate.allSatisfy(\.isNumber) && [8, 12, 13, 14].contains(candidate.count)
}

func isStandaloneNumericSku(_ candidate: String) -> Bool {
    candidate.allSatisfy(\.isNumber) && (5...14).contains(candidate.count)
}

func isStrongCandidate(_ candidate: String, textLines: [String]) -> Bool {
    if isStandardBarcodeLength(candidate) { return true }
    return textLines.contains { line in
        containsSkuLabel(line) && line.localizedCaseInsensitiveContains(candidate)
    }
}

func looseScore(for candidate: String) -> Int {
    if isStandaloneNumericSku(candidate) { return 62 }
    if candidate.contains("-") || candidate.contains(".") { return 58 }
    return 48
}

func scoreWithBarcodeSupport(baseScore: Int, candidate: String, barcodes: [String]) -> Int {
    guard barcodes.contains(where: { barcodeSupports(candidate: candidate, barcode: $0) }) else { return baseScore }
    return max(baseScore + 15, 90)
}

func barcodeSupports(candidate: String, barcode: String) -> Bool {
    if barcode == candidate { return true }
    guard candidate.count >= 12 else { return false }
    return barcode.contains(candidate) || candidate.contains(barcode)
}

func tagEvidence(barcodes: [String], candidates: [String]) -> String {
    let hasBarcode = !barcodes.isEmpty
    let hasCandidate = !candidates.isEmpty
    if hasBarcode && hasCandidate { return "both" }
    if hasBarcode { return "barcode" }
    if hasCandidate { return "skuText" }
    return "none"
}

struct ScoredCandidate {
    let value: String
    let score: Int
}

func looksLikeDate(_ candidate: String) -> Bool {
    candidate.range(of: #"^\d{1,2}[-.]\d{2,4}$"#, options: .regularExpression) != nil ||
        candidate.range(of: #"^\d{1,2}[-.]\d{1,2}[-.]\d{2,4}$"#, options: .regularExpression) != nil
}

func looksLikePrice(_ candidate: String) -> Bool {
    candidate.range(of: #"^\d+[.]\d{2}$"#, options: .regularExpression) != nil
}

func looksLikePhoneNumber(_ candidate: String) -> Bool {
    let digits = candidate.filter(\.isNumber)
    return digits.count == 10 && candidate.contains("-")
}

func regexMatches(pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { match in
        let matchRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard let range = Range(matchRange, in: text) else { return nil }
        return String(text[range])
    }
}

func normalizeSku(_ value: String) -> String {
    value.filter { $0.isLetter || $0.isNumber }.lowercased()
}

func safeFileName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    return String(value.map { character in
        let text = String(character)
        return text.rangeOfCharacter(from: allowed) == nil ? "-" : text
    }.joined().prefix(140))
}

func csvValue(_ value: Any?) -> String {
    let text = value.map { String(describing: $0) } ?? ""
    return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
}

func triageCSV(_ rows: [TriageRow]) -> String {
    let headers = [
        "bucket", "vendor", "expectedSku", "selectedSku", "selectedMatchesExpected",
        "candidateContainsExpected", "barcodeContainsExpected", "tagEvidence",
        "detectedBarcodes", "detectedCandidates", "detectedTextLines",
        "textLineCount", "localPath", "itemId", "itemName", "projectName",
    ]
    let body = rows.map { row in
        [
            row.bucket,
            row.vendor,
            row.expectedSku ?? "",
            row.selectedSku ?? "",
            String(row.selectedMatchesExpected),
            String(row.candidateContainsExpected),
            String(row.barcodeContainsExpected),
            row.tagEvidence,
            row.detectedBarcodes.joined(separator: " | "),
            row.detectedCandidates.joined(separator: " | "),
            row.detectedTextLines.joined(separator: " | "),
            String(row.textLineCount),
            row.localPath,
            row.itemId,
            row.itemName ?? "",
            row.projectName ?? "",
        ].map(csvValue).joined(separator: ",")
    }
    return ([headers.joined(separator: ",")] + body).joined(separator: "\n") + "\n"
}
