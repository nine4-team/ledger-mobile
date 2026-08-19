import Foundation

#if canImport(Vision)
import Vision
import ImageIO
#endif

#if canImport(UIKit)
import UIKit
#endif

enum ItemTagExtractionService {
    enum ImageProfile: Hashable { case phonePhoto, longReceiptPhoto, cleanScan, pdfRender, tightCrop }
    enum EngineRoute: Hashable { case visionPrimary, tesseractPrimary }

    static func engineRoute(for profile: ImageProfile) -> EngineRoute {
        switch profile {
        case .phonePhoto, .longReceiptPhoto: .visionPrimary
        case .cleanScan, .pdfRender, .tightCrop: .tesseractPrimary
        }
    }

    static func extract(from imageDatas: [Data], vendorHint: String? = nil, profile: ImageProfile = .phonePhoto) async -> ItemTagExtractionResult {
        await Task.detached(priority: .userInitiated) {
            let route = engineRoute(for: profile)
            var barcodeObservations: [ItemTagBarcodeObservation] = []
            var textObservations: [ItemTagTextObservation] = []
            var fullImagePayloads: [(data: Data, sourceImage: String, focusRegions: [CGRect])] = []
            var engineEvents: [String] = []
            if route == .tesseractPrimary {
                engineEvents.append("tesseract-unavailable-in-capture-target:vision-fallback")
            }

            for (index, data) in imageDatas.enumerated() {
                let sourceImage = "image-\(index + 1)"
                let imageResult = extractFullImage(from: data, sourceImage: sourceImage)
                barcodeObservations.append(contentsOf: imageResult.barcodePayloads.map { ItemTagBarcodeObservation(payload: $0, sourceEngine: .vision, sourceImage: sourceImage) })
                textObservations.append(contentsOf: imageResult.textObservations)
                fullImagePayloads.append((data, sourceImage, imageResult.focusRegions))
            }

            var initial = ItemTagExtraction.extract(
                barcodePayloads: [],
                barcodeObservations: barcodeObservations,
                textObservations: textObservations,
                vendorHint: vendorHint
            )
            initial.engineEvents = engineEvents
            guard initial.retryRecommended else { return initial }

            var retryObservations: [ItemTagTextObservation] = []
            for payload in fullImagePayloads {
                let focused = recognizeFocusedRegions(
                    payload.focusRegions,
                    data: payload.data,
                    sourceImage: payload.sourceImage
                )
                retryObservations.append(contentsOf: focused.textObservations)
                barcodeObservations.append(contentsOf: focused.barcodePayloads.map {
                    ItemTagBarcodeObservation(payload: $0, sourceEngine: .vision, sourceImage: payload.sourceImage)
                })
            }
            engineEvents.append("tag-focused-orientation-retry:\(retryObservations.isEmpty ? "no-text" : "completed")")
            var retried = ItemTagExtraction.extract(
                barcodePayloads: [],
                barcodeObservations: barcodeObservations,
                textObservations: textObservations + retryObservations,
                vendorHint: vendorHint,
                retryPerformed: true
            )
            retried.engineEvents = engineEvents
            return retried
        }.value
    }

    private static func extractFullImage(from data: Data, sourceImage: String) -> ImageExtractionPayload {
        #if canImport(Vision)
        let barcodeRequest = VNDetectBarcodesRequest()
        let textRequest = configuredTextRequest()

        let handler = VNImageRequestHandler(data: data, options: [:])
        try? handler.perform([barcodeRequest, textRequest])

        let barcodeObservations = barcodeRequest.results ?? []
        let textRecognitionObservations = textRequest.results ?? []

        let barcodePayloads = barcodeObservations.compactMap(\.payloadStringValue)
        let textObservations = textObservations(from: textRecognitionObservations, sourceImage: sourceImage)
        let focusRegions = barcodeTextRegions(from: barcodeObservations) + potentialLabelRegions(from: textRecognitionObservations)
        return ImageExtractionPayload(barcodePayloads: barcodePayloads, textObservations: textObservations, focusRegions: focusRegions)
        #else
        return ImageExtractionPayload(barcodePayloads: [], textObservations: [], focusRegions: [])
        #endif
    }

    private static func recognizeFocusedRegions(_ regions: [CGRect], data: Data, sourceImage: String) -> ImageExtractionPayload {
        #if canImport(Vision)
        #if canImport(UIKit)
        var observations: [ItemTagTextObservation] = []
        var barcodePayloads: [String] = []
        if let image = normalizedImage(from: data) {
            for region in regions {
                guard let crop = croppedUpscaledImage(from: image, region: region) else { continue }
                let result = recognizeImage(crop, sourceImage: sourceImage)
                observations.append(contentsOf: result.textObservations)
                barcodePayloads.append(contentsOf: result.barcodePayloads)
            }
        }
        return ImageExtractionPayload(barcodePayloads: barcodePayloads, textObservations: observations, focusRegions: [])
        #else
        return ImageExtractionPayload(
            barcodePayloads: [],
            textObservations: regions.flatMap { recognizeText(in: $0, data: data, sourceImage: sourceImage) },
            focusRegions: []
        )
        #endif
        #else
        return ImageExtractionPayload(barcodePayloads: [], textObservations: [], focusRegions: [])
        #endif
    }

    #if canImport(Vision)
    private static func recognizeText(in region: CGRect, data: Data, sourceImage: String) -> [ItemTagTextObservation] {
        let request = configuredTextRequest()
        request.regionOfInterest = region

        let handler = VNImageRequestHandler(data: data, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return textObservations(from: request.results ?? [], sourceImage: sourceImage)
    }

    private static func recognizeImage(_ image: CGImage, sourceImage: String) -> ImageExtractionPayload {
        var observations: [ItemTagTextObservation] = []
        var barcodePayloads: [String] = []
        for orientation in [CGImagePropertyOrientation.up, .down, .left, .right] {
            let request = configuredTextRequest()
            let barcodeRequest = VNDetectBarcodesRequest()
            let textHandler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            guard (try? textHandler.perform([request])) != nil else { continue }
            observations.append(contentsOf: textObservations(from: request.results ?? [], sourceImage: sourceImage))
            let barcodeHandler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try? barcodeHandler.perform([barcodeRequest])
            barcodePayloads.append(contentsOf: (barcodeRequest.results ?? []).compactMap(\.payloadStringValue))
        }
        return ImageExtractionPayload(barcodePayloads: barcodePayloads, textObservations: observations, focusRegions: [])
    }

    private static func textObservations(from observations: [VNRecognizedTextObservation], sourceImage: String) -> [ItemTagTextObservation] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return ItemTagTextObservation(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                sourceEngine: .vision,
                sourceImage: sourceImage
            )
        }
    }

    private static func barcodeTextRegions(from observations: [VNBarcodeObservation]) -> [CGRect] {
        observations.map { observation in
            expandedRegion(around: observation.boundingBox)
        }
    }

    private static func potentialLabelRegions(from observations: [VNRecognizedTextObservation]) -> [CGRect] {
        Array(observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string,
                  isPotentialLabelText(text)
            else { return nil }
            return expandedTagRegion(around: observation.boundingBox)
        }.prefix(4))
    }

    private static func isPotentialLabelText(_ text: String) -> Bool {
        if text.range(of: #"(?i)\b(SKU|STYLE|STVLE|STYIE|MODEL|ITEM|DPCI|UPC|EAN|BARCODE|NO|NUMBER|PRICE)\b"#, options: .regularExpression) != nil {
            return true
        }
        return text
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_/")).inverted)
            .contains { token in
                let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.count >= 4, value.contains(where: \.isNumber) else { return false }
                return value.contains(where: \.isLetter) || (5...18).contains(value.count)
            }
    }

    private static func configuredTextRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.customWords = ["SKU", "STYLE", "MODEL", "ITEM", "DPCI", "UPC", "EAN", "BARCODE"]
        return request
    }

    private static func expandedTagRegion(around box: CGRect) -> CGRect {
        let minX = max(0, box.minX - max(box.width * 1.5, 0.18))
        let minY = max(0, box.minY - max(box.height * 5, 0.16))
        let maxX = min(1, box.maxX + max(box.width * 1.5, 0.18))
        let maxY = min(1, box.maxY + max(box.height * 5, 0.16))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func expandedRegion(around box: CGRect) -> CGRect {
        let minX = max(0, box.minX - box.width * 1.4)
        let minY = max(0, box.minY - box.height * 1.8)
        let maxX = min(1, box.maxX + box.width * 1.4)
        let maxY = min(1, box.maxY + box.height * 6.0)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    #if canImport(UIKit)
    private static func normalizedImage(from data: Data) -> CGImage? {
        guard let image = UIImage(data: data) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return rendered.cgImage
    }

    private static func croppedUpscaledImage(from image: CGImage, region: CGRect) -> CGImage? {
        let cropRect = pixelRect(for: region, image: image)
        guard let cropped = image.cropping(to: cropRect) else { return nil }
        return upscale(cropped, minimumLongSide: 1800)
    }

    private static func pixelRect(for region: CGRect, image: CGImage) -> CGRect {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let x = region.minX * width
        let y = (1 - region.maxY) * height
        let rect = CGRect(
            x: x,
            y: y,
            width: region.width * width,
            height: region.height * height
        )
        return rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func upscale(_ image: CGImage, minimumLongSide: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return nil }
        let scale = max(1, minimumLongSide / max(width, height))
        let outputSize = CGSize(width: width * scale, height: height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let rendered = renderer.image { context in
            context.cgContext.interpolationQuality = .high
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: outputSize))
        }
        return rendered.cgImage
    }
    #endif
    #endif
}

private struct ImageExtractionPayload {
    var barcodePayloads: [String]
    var textObservations: [ItemTagTextObservation]
    var focusRegions: [CGRect]
}
