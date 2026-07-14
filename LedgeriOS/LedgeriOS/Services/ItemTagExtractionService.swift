import Foundation

#if canImport(Vision)
import Vision
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
                retryObservations.append(contentsOf: recognizeFocusedRegions(
                    payload.focusRegions,
                    data: payload.data,
                    sourceImage: payload.sourceImage
                ))
            }
            engineEvents.append("tag-focused-retry:\(retryObservations.isEmpty ? "no-text" : "completed")")
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
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(data: data, options: [:])
        try? handler.perform([barcodeRequest, textRequest])

        let barcodeObservations = barcodeRequest.results ?? []
        let textRecognitionObservations = textRequest.results ?? []

        let barcodePayloads = barcodeObservations.compactMap(\.payloadStringValue)
        let textObservations = textObservations(from: textRecognitionObservations, sourceImage: sourceImage)
        let focusRegions = barcodeTextRegions(from: barcodeObservations) + tagTextRegions(from: textRecognitionObservations)
        return ImageExtractionPayload(barcodePayloads: barcodePayloads, textObservations: textObservations, focusRegions: focusRegions)
        #else
        return ImageExtractionPayload(barcodePayloads: [], textObservations: [], focusRegions: [])
        #endif
    }

    private static func recognizeFocusedRegions(_ regions: [CGRect], data: Data, sourceImage: String) -> [ItemTagTextObservation] {
        #if canImport(Vision)
        var observations = regions.flatMap { recognizeText(in: $0, data: data, sourceImage: sourceImage) }
        #if canImport(UIKit)
        if let image = normalizedImage(from: data) {
            for region in regions {
                guard let crop = croppedUpscaledImage(from: image, region: region) else { continue }
                observations.append(contentsOf: recognizeText(in: crop, sourceImage: sourceImage))
            }
        }
        #endif
        return observations
        #else
        return []
        #endif
    }

    #if canImport(Vision)
    private static func recognizeText(in region: CGRect, data: Data, sourceImage: String) -> [ItemTagTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.regionOfInterest = region

        let handler = VNImageRequestHandler(data: data, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return textObservations(from: request.results ?? [], sourceImage: sourceImage)
    }

    private static func recognizeText(in image: CGImage, sourceImage: String) -> [ItemTagTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return textObservations(from: request.results ?? [], sourceImage: sourceImage)
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

    private static func tagTextRegions(from observations: [VNRecognizedTextObservation]) -> [CGRect] {
        observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string,
                  text.range(of: #"(?i)\b(DEPT|STYLE|STVLE|STYIE|TYPE|CAT|FLS|COMPARE AT|OUR PRICE)\b|[$S]?\d+[.]\d{2}\b"#, options: .regularExpression) != nil
            else { return nil }
            return expandedTagRegion(around: observation.boundingBox)
        }
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
