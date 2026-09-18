import SwiftUI
import ImageIO
#if os(macOS)
import AppKit
import PDFKit
#elseif canImport(UIKit)
import UIKit
#endif

enum PhotoPrintError: LocalizedError {
    case noPhotos
    case unavailablePhoto
    case invalidPhoto
    case unableToCreateDocument
    case printingUnavailable

    var errorDescription: String? {
        switch self {
        case .noPhotos:
            return "There are no space photos available to print."
        case .unavailablePhoto:
            return "One or more space photos could not be downloaded."
        case .invalidPhoto:
            return "One or more space photos could not be prepared for printing."
        case .unableToCreateDocument:
            return "The photo print document could not be created."
        case .printingUnavailable:
            return "Printing is not available on this device."
        }
    }
}

// Existing print rendering/presentation, separated from Firebase URL loading.
enum PhotoPrintPresentation {
    static func makePDF(from imageData: [Data]) throws -> Data {
        guard !imageData.isEmpty else { throw PhotoPrintError.noPhotos }
        guard let output = CFDataCreateMutable(nil, 0),
              let consumer = CGDataConsumer(data: output) else {
            throw PhotoPrintError.unableToCreateDocument
        }

        var pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else {
            throw PhotoPrintError.unableToCreateDocument
        }

        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4_096,
        ] as CFDictionary

        for data in imageData {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
                throw PhotoPrintError.invalidPhoto
            }

            context.beginPDFPage(nil)
            let printableRect = pageRect.insetBy(dx: 36, dy: 36)
            let imageSize = CGSize(width: image.width, height: image.height)
            let scale = min(
                printableRect.width / imageSize.width,
                printableRect.height / imageSize.height
            )
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let drawRect = CGRect(
                x: printableRect.midX - drawSize.width / 2,
                y: printableRect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            context.interpolationQuality = .high
            context.draw(image, in: drawRect)
            context.endPDFPage()
        }

        context.closePDF()
        return output as Data
    }

    @MainActor
    static func presentPrintDialog(pdfData: Data, jobName: String) async throws {
        #if os(macOS)
        guard let document = PDFDocument(data: pdfData),
              let operation = document.printOperation(
                for: NSPrintInfo.shared,
                scalingMode: .pageScaleToFit,
                autoRotate: true
              ) else {
            throw PhotoPrintError.printingUnavailable
        }
        operation.jobTitle = jobName
        operation.run()
        #elseif canImport(UIKit)
        guard UIPrintInteractionController.isPrintingAvailable else {
            throw PhotoPrintError.printingUnavailable
        }
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = jobName
        printInfo.outputType = .photo

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = pdfData
        controller.present(animated: true)
        #else
        throw PhotoPrintError.printingUnavailable
        #endif
    }
}
