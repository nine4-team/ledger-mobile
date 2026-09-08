import Foundation
#if os(macOS)
import AppKit
import ApplicationServices
import PDFKit
#elseif os(iOS)
import UIKit
#endif

/// Native handoff only. The caller owns authorization, the exact report bytes,
/// and scratch-file cleanup AFTER this function completes. Cancellation of the
/// Swift task while native UI is open deliberately does not end this wait: the
/// OS or a selected sharing service may still be reading the file.
/// Once handed to a destination, its copy cannot be recalled on access changes.
@MainActor
enum PropertyManagementReportSystemDelivery {
    enum Action { case share, print }
    private static var presenting = false

    enum Failure: LocalizedError {
        case unavailablePresenter, alreadyPresenting, unreadableFile, printingUnavailable, presentationFailed
        var errorDescription: String? {
            switch self {
            case .unavailablePresenter: "Return to the report window and try again."
            case .alreadyPresenting: "Finish the current Share or Print action first."
            case .unreadableFile: "The report file could not be opened."
            case .printingUnavailable: "This report cannot be printed on this device."
            case .presentationFailed: "The system could not open the report delivery controls."
            }
        }
    }

    static func handoff(_ url: URL, action: Action) async throws {
        if Task.isCancelled { return }
        guard !presenting else { throw Failure.alreadyPresenting }
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else { throw Failure.unreadableFile }
        presenting = true
        defer { presenting = false }
        #if os(macOS)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let view = window.contentView,
              window.attachedSheet == nil else { throw Failure.unavailablePresenter }
        switch action {
        case .share:
            let session = MacShareSession()
            defer { withExtendedLifetime(session) {} }
            try await session.run(url: url, view: view)
        case .print:
            try printMacReport(url)
        }
        #elseif os(iOS)
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).filter(\.isKeyWindow)
        guard windows.count == 1, var presenter = windows[0].rootViewController else { throw Failure.unavailablePresenter }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed, !presenter.isBeingPresented else {
            throw Failure.unavailablePresenter
        }
        switch action {
        case .share:
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = anchor(in: presenter.view)
                popover.permittedArrowDirections = []
            }
            defer { withExtendedLifetime(activity) {} }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let completion = Completion(continuation)
                // Includes cancellation of the sheet/popover. Choosing a
                // destination is not completion of the destination's activity.
                activity.completionWithItemsHandler = { _, _, _, error in
                    Task { @MainActor in completion.finish(error: error) }
                }
                presenter.present(activity, animated: true)
            }
        case .print:
            guard UIPrintInteractionController.isPrintingAvailable, UIPrintInteractionController.canPrint(url) else {
                throw Failure.printingUnavailable
            }
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.jobName = url.deletingPathExtension().lastPathComponent
            info.outputType = .general
            controller.printInfo = info
            controller.printingItem = url
            defer { controller.printingItem = nil }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let completion = Completion(continuation)
                let handler: (UIPrintInteractionController, Bool, Error?) -> Void = { _, _, error in
                    Task { @MainActor in completion.finish(error: error) }
                }
                let shown: Bool
                if UIDevice.current.userInterfaceIdiom == .pad {
                    shown = controller.present(from: anchor(in: presenter.view), in: presenter.view,
                        animated: true, completionHandler: handler)
                } else {
                    shown = controller.present(animated: true, completionHandler: handler)
                }
                if !shown { completion.finish(error: Failure.presentationFailed) }
            }
        }
        #else
        throw Failure.unavailablePresenter
        #endif
    }

    #if os(iOS)
    private static func anchor(in view: UIView) -> CGRect {
        CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    }
    #endif

    @MainActor private final class Completion {
        private var continuation: CheckedContinuation<Void, Error>?
        init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
        func finish(error: Error? = nil) {
            guard let continuation else { return }
            self.continuation = nil
            if let error, !Self.isUserCancellation(error) { continuation.resume(throwing: error) }
            else { continuation.resume() }
        }
        private static func isUserCancellation(_ error: Error) -> Bool {
            let cocoa = error as NSError
            return cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSUserCancelledError
        }
    }

    #if os(macOS)
    @MainActor private final class MacShareSession: NSObject, @MainActor NSSharingServicePickerDelegate, NSSharingServiceDelegate {
        private var picker: NSSharingServicePicker?
        private var service: NSSharingService?
        private var completion: Completion?
        private var sourceView: NSView?

        func run(url: URL, view: NSView) async throws {
            sourceView = view
            let picker = NSSharingServicePicker(items: [url])
            self.picker = picker
            picker.delegate = self
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                completion = Completion(continuation)
                picker.show(relativeTo: CGRect(x: view.bounds.midX, y: view.bounds.maxY - 1, width: 1, height: 1),
                    of: view, preferredEdge: .minY)
            }
        }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                  delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
            service = sharingService
            return self
        }
        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            if let service { self.service = service }
            else if self.service == nil { finish() }
        }
        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish(error: error) }
        func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                            sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
            sourceView?.window
        }
        private func finish(error: Error? = nil) {
            let completion = self.completion
            self.completion = nil
            picker?.delegate = nil
            service?.delegate = nil
            picker = nil; service = nil; sourceView = nil
            completion?.finish(error: error)
        }
    }

    private static func printMacReport(_ url: URL) throws {
        guard let document = PDFDocument(url: url), document.pageCount > 0,
              let operation = document.printOperation(for: NSPrintInfo.shared.copy() as? NSPrintInfo,
                  scalingMode: .pageScaleToFit, autoRotate: true) else { throw Failure.printingUnavailable }
        // The report already occupies a SwiftUI sheet. Application-modal
        // printing avoids attaching another document-modal panel to that sheet.
        // AppKit runs its native event loop and returns only after completion;
        // retain the PDF and leave scratch cleanup to the caller after return.
        let success = withExtendedLifetime(document) { operation.run() }
        let status = PMSessionError(PMPrintSession(operation.printInfo.pmPrintSession()))
        if !success && status != noErr && status != OSStatus(kPMCancel) {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
    #endif
}
