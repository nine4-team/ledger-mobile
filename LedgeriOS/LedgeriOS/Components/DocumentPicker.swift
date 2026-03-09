import SwiftUI
import UniformTypeIdentifiers

/// UIKit document picker wrapper for selecting PDF files.
/// Follows the same `UIViewControllerRepresentable` pattern as `CameraCapture`.
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.pdf]
    var onPickDocument: (Data, String) -> Void
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPickDocument: onPickDocument, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPickDocument: (Data, String) -> Void
        let onDismiss: () -> Void

        init(onPickDocument: @escaping (Data, String) -> Void, onDismiss: @escaping () -> Void) {
            self.onPickDocument = onPickDocument
            self.onDismiss = onDismiss
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onDismiss()
                return
            }

            // Security-scoped resource access for Files.app
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent
                onPickDocument(data, filename)
            } catch {
                onDismiss()
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDismiss()
        }
    }
}
