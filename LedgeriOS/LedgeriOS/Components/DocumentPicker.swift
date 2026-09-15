#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers

/// UIKit document picker wrapper for selecting PDF files.
/// Follows the same `UIViewControllerRepresentable` pattern as `CameraCapture`.
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.pdf]
    var onPickDocument: (Data, String) -> Void
    var onDismiss: () -> Void
    var onFailure: (Error) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPickDocument: onPickDocument, onDismiss: onDismiss, onFailure: onFailure)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPickDocument: (Data, String) -> Void
        let onDismiss: () -> Void
        let onFailure: (Error) -> Void

        init(onPickDocument: @escaping (Data, String) -> Void, onDismiss: @escaping () -> Void,
            onFailure: @escaping (Error) -> Void) {
            self.onPickDocument = onPickDocument
            self.onDismiss = onDismiss
            self.onFailure = onFailure
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onDismiss()
                return
            }

            Task { @MainActor in
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                    onPickDocument(data, url.lastPathComponent)
                } catch {
                    onFailure(error)
                    onDismiss()
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDismiss()
        }
    }
}
#endif
