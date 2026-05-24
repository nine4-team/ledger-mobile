import Foundation

#if canImport(Vision)
import Vision
#endif

#if canImport(UIKit)
import UIKit
#endif

enum ItemTagExtractionService {
    static func extract(from imageDatas: [Data]) async -> ItemTagExtractionResult {
        await Task.detached(priority: .userInitiated) {
            var barcodePayloads: [String] = []
            var textObservations: [ItemTagTextObservation] = []

            for data in imageDatas {
                let imageResult = extract(from: data)
                barcodePayloads.append(contentsOf: imageResult.barcodePayloads)
                textObservations.append(contentsOf: imageResult.textObservations)
            }

            return ItemTagExtraction.extract(
                barcodePayloads: barcodePayloads,
                textObservations: textObservations
            )
        }.value
    }

    private static func extract(from data: Data) -> ImageExtractionPayload {
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
        var textObservations = textObservations(from: textRecognitionObservations)
        for region in barcodeTextRegions(from: barcodeObservations) {
            textObservations.append(contentsOf: recognizeText(in: region, data: data))
        }
        #if canImport(UIKit)
        if let image = normalizedImage(from: data) {
            for region in barcodeTextRegions(from: barcodeObservations) {
                guard let crop = croppedUpscaledImage(from: image, region: region) else { continue }
                textObservations.append(contentsOf: recognizeText(in: crop))
            }
        }
        #endif
        return ImageExtractionPayload(barcodePayloads: barcodePayloads, textObservations: textObservations)
        #else
        return ImageExtractionPayload(barcodePayloads: [], textObservations: [])
        #endif
    }

    #if canImport(Vision)
    private static func recognizeText(in region: CGRect, data: Data) -> [ItemTagTextObservation] {
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
        return textObservations(from: request.results ?? [])
    }

    private static func recognizeText(in image: CGImage) -> [ItemTagTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return textObservations(from: request.results ?? [])
    }

    private static func textObservations(from observations: [VNRecognizedTextObservation]) -> [ItemTagTextObservation] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return ItemTagTextObservation(
                text: candidate.string,
                confidence: Double(candidate.confidence)
            )
        }
    }

    private static func barcodeTextRegions(from observations: [VNBarcodeObservation]) -> [CGRect] {
        observations.map { observation in
            expandedRegion(around: observation.boundingBox)
        }
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
}
