import SwiftUI

enum ReportPDFSharing {

    @MainActor
    static func sharePDF<Content: View>(
        content: Content,
        fileName: String
    ) {
        let renderer = ImageRenderer(content: content)

        #if canImport(UIKit)
        renderer.scale = UIScreen.main.scale
        #elseif canImport(AppKit)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        #endif

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        renderer.render { size, renderContext in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(tempURL as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            renderContext(context)
            context.endPDFPage()
            context.closePDF()
        }

        guard FileManager.default.fileExists(atPath: tempURL.path) else { return }

        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        rootVC.present(activityVC, animated: true)
        #elseif canImport(AppKit)
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = fileName
        savePanel.allowedContentTypes = [.pdf]
        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            try? FileManager.default.copyItem(at: tempURL, to: destinationURL)
        }
        #endif
    }
}
