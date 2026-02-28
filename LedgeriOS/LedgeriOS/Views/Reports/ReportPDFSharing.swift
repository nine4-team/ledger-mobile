import SwiftUI

enum ReportPDFSharing {

    @MainActor
    static func sharePDF<Content: View>(
        content: Content,
        fileName: String
    ) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale

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

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        rootVC.present(activityVC, animated: true)
    }
}
