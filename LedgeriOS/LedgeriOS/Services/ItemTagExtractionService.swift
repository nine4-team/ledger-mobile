import Foundation

#if canImport(Vision)
import Vision
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
    #endif
}

private struct ImageExtractionPayload {
    var barcodePayloads: [String]
    var textObservations: [ItemTagTextObservation]
}
