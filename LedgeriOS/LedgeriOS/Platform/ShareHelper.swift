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

enum PhotoPrintHelper {
    static func printPhotos(_ attachments: [AttachmentRef], jobName: String) async throws {
        let photos = attachments.filter {
            $0.kind == .image && !$0.url.isEmpty && $0.isUploading != true
        }
        guard !photos.isEmpty else { throw PhotoPrintError.noPhotos }

        let imageData = try await downloadPhotos(photos)
        let pdfData = try PhotoPrintPresentation.makePDF(from: imageData)
        try await PhotoPrintPresentation.presentPrintDialog(pdfData: pdfData, jobName: jobName)
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

}
