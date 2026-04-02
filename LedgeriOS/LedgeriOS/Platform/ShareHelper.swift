import SwiftUI

enum ShareHelper {

    /// Presents the platform share sheet for a file URL.
    /// Call from a context where no sheet is currently presented (e.g. an `onDismiss` callback).
    @MainActor
    static func share(url: URL) {
        #if canImport(UIKit)
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
        #elseif canImport(AppKit)
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = url.lastPathComponent
        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            try? FileManager.default.copyItem(at: url, to: destinationURL)
        }
        #endif
    }
}
