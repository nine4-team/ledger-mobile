import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

/// Direct "save to Files / save panel" flow — no share sheet, no AirDrop chrome.
/// Mirrors the shape of `ShareHelper.share(url:)` but uses the platform's
/// export/save affordance as the single destination.
enum PDFDownloadHelper {

    enum Failure: Error { case unavailablePresenter }

    /// Retain the caller's protected file until the native export completes.
    /// Revalidate before OS handoff (and after choosing a Mac destination).
    /// iOS receives the file when its export picker is presented. A later
    /// permission change cannot recall that external copy; keep the source
    /// until the picker completes even if the calling task is canceled.
    @MainActor
    static func downloadAndWait(url: URL, fileName: String,
        revalidate: @MainActor () async throws -> Void) async throws {
        try Task.checkCancellation()
        #if canImport(UIKit)
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).filter(\.isKeyWindow)
        guard windows.count == 1, var presenter = windows[0].rootViewController else { throw Failure.unavailablePresenter }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed, !presenter.isBeingPresented else {
            throw Failure.unavailablePresenter
        }
        try await revalidate()
        try Task.checkCancellation()
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        let session = PDFDownloadSession()
        picker.delegate = session
        picker.presentationController?.delegate = session
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.continuation = continuation
            presenter.present(picker, animated: true)
            picker.presentationController?.delegate = session
        }
        withExtendedLifetime(session) {}
        #else
        guard let destination = await selectDestination(fileName: fileName, contentType: .pdf) else { throw CancellationError() }
        try await revalidate()
        try Task.checkCancellation()
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        try Data(contentsOf: url).write(to: destination, options: .atomic)
        #endif
    }

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
        Task { @MainActor in
            guard let destinationURL = await selectDestination(fileName: url.lastPathComponent) else { return }
            try? FileManager.default.copyItem(at: url, to: destinationURL)
        }
        #endif
    }

    #if canImport(AppKit)
    /// Existing native save panel, with completion exposed for authorized
    /// exporters that must revalidate after the user chooses a destination.
    @MainActor
    static func selectDestination(fileName: String, contentType: UTType? = nil) async -> URL? {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = fileName
        if let contentType { savePanel.allowedContentTypes = [contentType] }
        return await withCheckedContinuation { continuation in
            savePanel.begin { response in
                continuation.resume(returning: response == .OK ? savePanel.url : nil)
            }
        }
    }
    #endif
}

#if canImport(UIKit)
@MainActor private final class PDFDownloadSession: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    var continuation: CheckedContinuation<Void, Error>?
    private func finish(_ error: Error? = nil) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls.isEmpty ? CancellationError() : nil)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(CancellationError()) }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish(CancellationError()) }
}
#endif
