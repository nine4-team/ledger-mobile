import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Direct "save to Files / save panel" flow — no share sheet, no AirDrop chrome.
/// Mirrors the shape of `ShareHelper.share(url:)` but uses the platform's
/// export/save affordance as the single destination.
enum PDFDownloadHelper {

    @MainActor
    static func download(url: URL) {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }

        // Walk to the topmost presented VC so present() doesn't silently fail.
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        topVC.present(picker, animated: true)
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
