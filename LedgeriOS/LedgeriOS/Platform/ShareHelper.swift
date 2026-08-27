import SwiftUI
import ImageIO
#if os(macOS)
import AppKit
import PDFKit
#elseif canImport(UIKit)
import UIKit
#endif

enum ShareHelper {

    /// Presents the platform share sheet for a file URL.
    /// Call from a context where no sheet is currently presented (e.g. an `onDismiss` callback).
    @MainActor
    static func share(url: URL) {
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = url.lastPathComponent
        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            try? FileManager.default.copyItem(at: url, to: destinationURL)
        }
        #elseif canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }

        // Walk to the topmost presented VC so present() doesn't silently fail
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        topVC.present(activityVC, animated: true)
        #endif
    }
}

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

enum PhotoPrintHelper {
    static func printPhotos(_ attachments: [AttachmentRef], jobName: String) async throws {
        let photos = attachments.filter {
            $0.kind == .image && !$0.url.isEmpty && $0.isUploading != true
        }
        guard !photos.isEmpty else { throw PhotoPrintError.noPhotos }

        let imageData = try await downloadPhotos(photos)
        let pdfData = try makePDF(from: imageData)
        try await presentPrintDialog(pdfData: pdfData, jobName: jobName)
    }

    private static func downloadPhotos(_ photos: [AttachmentRef]) async throws -> [Data] {
        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, photo) in photos.enumerated() {
                group.addTask {
                    guard let url = await StorageURLResolver.resolve(photo.url) else {
                        throw PhotoPrintError.unavailablePhoto
                    }
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if let response = response as? HTTPURLResponse,
                       !(200...299).contains(response.statusCode) {
                        throw PhotoPrintError.unavailablePhoto
                    }
                    guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
                        throw PhotoPrintError.invalidPhoto
                    }
                    return (index, data)
                }
            }

            var downloaded = Array<Data?>(repeating: nil, count: photos.count)
            for try await (index, data) in group {
                downloaded[index] = data
            }
            return try downloaded.map {
                guard let data = $0 else { throw PhotoPrintError.unavailablePhoto }
                return data
            }
        }
    }

    private static func makePDF(from imageData: [Data]) throws -> Data {
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
    private static func presentPrintDialog(pdfData: Data, jobName: String) async throws {
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
