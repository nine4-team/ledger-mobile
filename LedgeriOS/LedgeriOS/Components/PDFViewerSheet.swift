import SwiftUI
import PDFKit

/// Full-screen PDF viewer using PDFKit. Presented via fullScreenCover (iOS) or sheet (macOS).
struct PDFViewerSheet: View {
    let attachment: AttachmentRef
    @Binding var isPresented: Bool
    var onPinImage: ((AttachmentRef) -> Void)?

    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = true
    @State private var loadError = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let pdfDocument {
                PDFKitView(document: pdfDocument)
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

                if let fileName = attachment.fileName {
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
        .task {
            await loadPDF()
        }
    }

    private func loadPDF() async {
        isLoading = true
        defer { isLoading = false }

        guard let resolved = await StorageURLResolver.resolve(attachment.url) else {
            loadError = true
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: resolved)
            if let doc = PDFDocument(data: data) {
                pdfDocument = doc
            } else {
                loadError = true
            }
        } catch {
            loadError = true
        }
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
    }

    private var pinButton: some View {
        Button {
            onPinImage?(attachment)
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
        if let url = URL(string: attachment.url) {
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
    }
}

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
