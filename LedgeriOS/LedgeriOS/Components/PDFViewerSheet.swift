import SwiftUI
import PDFKit

/// Full-screen PDF viewer using PDFKit. Presented via fullScreenCover (iOS) or sheet (macOS).
struct PDFViewerPresentation: View {
    let fileName: String?
    let pdfDocument: PDFDocument?
    let isLoading: Bool
    @Binding var isPresented: Bool
    var onPinImage: (() -> Void)?
    var onShare: (() -> Void)?
    var shareURL: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PDFDocumentPresentation(document: pdfDocument, isLoading: isLoading)

            // Chrome overlay
            VStack {
                HStack {
                    closeButton
                    if onPinImage != nil {
                        pinButton
                    }
                    Spacer()
                    shareButton
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

                Spacer()

                if let fileName {
                    Text(fileName)
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .padding(.vertical, Spacing.sm)
                        .padding(.horizontal, Spacing.lg)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.7))
                }
            }
        }
        #if canImport(UIKit)
        .statusBarHidden()
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityValue(isLoading ? "Loading PDF" : pdfDocument.map { "\($0.pageCount) PDF pages" } ?? "Unable to load PDF")
    }

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityLabel("Close PDF")
    }

    private var pinButton: some View {
        Button {
            onPinImage?()
            isPresented = false
        } label: {
            Image(systemName: "pin")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityLabel("Pin PDF for reference")
    }

    @ViewBuilder
    private var shareButton: some View {
        if let onShare {
            Button(action: onShare) { shareIcon }.accessibilityLabel("Share PDF")
        } else if let shareURL {
            ShareLink(item: shareURL) { shareIcon }
        }
    }
    private var shareIcon: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.title3).fontWeight(.semibold).foregroundStyle(.white)
            .frame(width: 40, height: 40).background(.black.opacity(0.5)).clipShape(Circle())
    }
}

/// Shared existing PDF loading, rendering and failure presentation.
struct PDFDocumentPresentation: View {
    let document: PDFDocument?
    let isLoading: Bool

    var body: some View {
        if isLoading {
            ProgressView().tint(.white)
        } else if let document {
            PDFKitView(document: document)
                .accessibilityIdentifier("pdf-viewer-document")
        } else {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Unable to load PDF")
                    .font(Typography.small)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

#if canImport(FirebaseFirestore)
/// Legacy loading remains outside the shared PDF presentation.
struct PDFViewerSheet: View {
    let attachment: AttachmentRef
    @Binding var isPresented: Bool
    var onPinImage: ((AttachmentRef) -> Void)?
    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = true

    var body: some View {
        PDFViewerPresentation(fileName: attachment.fileName, pdfDocument: pdfDocument, isLoading: isLoading,
            isPresented: $isPresented, onPinImage: onPinImage.map { action in { action(attachment) } },
            shareURL: URL(string: attachment.url))
            .task {
                isLoading = true
                defer { isLoading = false }
                guard let resolved = await StorageURLResolver.resolve(attachment.url) else { return }
                do {
                    let (data, _) = try await URLSession.shared.data(from: resolved)
                    pdfDocument = PDFDocument(data: data)
                } catch { pdfDocument = nil }
            }
    }
}
#endif

// MARK: - PDFKit View

#if canImport(UIKit)
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.backgroundColor = .black
        pdfView.document = document
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
#elseif canImport(AppKit)
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = document
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
#endif
