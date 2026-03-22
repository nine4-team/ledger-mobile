import SwiftUI
import PDFKit

/// Persistent reference panel that displays a pinned image or PDF with zoom/pan support.
/// Used inside `PinnedImageLayout` on detail screens so users can reference an attachment
/// while editing fields.
struct PinnedImagePanel: View {
    let attachment: AttachmentRef
    let allImages: [AttachmentRef]
    let onClose: () -> Void
    let onChangeImage: (AttachmentRef) -> Void

    @State private var zoomScale: CGFloat = 1.0
    @State private var currentIndex: Int = 0
    @State private var pdfDocument: PDFDocument?
    @State private var isPDFLoading = false

    private var currentAttachment: AttachmentRef {
        allImages.indices.contains(currentIndex) ? allImages[currentIndex] : attachment
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if currentAttachment.kind == .pdf {
                pdfContent
            } else {
                ZoomableScrollView(
                    url: URL(string: currentAttachment.url),
                    zoomScale: $zoomScale,
                    onSingleTap: nil
                )
            }

            // Close button — top trailing
            VStack {
                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                Spacer()
            }

            // Image counter — bottom center
            if allImages.count > 1 {
                VStack {
                    Spacer()
                    imageCounter
                        .padding(.bottom, Spacing.sm)
                }
            }
        }
        .onAppear {
            currentIndex = allImages.firstIndex(where: { $0.url == attachment.url }) ?? 0
        }
        .onChange(of: attachment.url) { _, newURL in
            zoomScale = 1.0
            currentIndex = allImages.firstIndex(where: { $0.url == newURL }) ?? 0
        }
        .onChange(of: currentAttachment.url) {
            if currentAttachment.kind == .pdf {
                Task { await loadPDF() }
            }
        }
        .task {
            if currentAttachment.kind == .pdf {
                await loadPDF()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(currentAttachment.kind == .pdf ? "Pinned reference document" : "Pinned reference image")
    }

    // MARK: - PDF Content

    @ViewBuilder
    private var pdfContent: some View {
        if isPDFLoading {
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
    }

    private func loadPDF() async {
        pdfDocument = nil
        isPDFLoading = true
        defer { isPDFLoading = false }

        guard let resolved = await StorageURLResolver.resolve(currentAttachment.url) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: resolved)
            if let doc = PDFDocument(data: data) {
                pdfDocument = doc
            }
        } catch {
            // loadError state handled by nil pdfDocument
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityLabel("Unpin image")
    }

    // MARK: - Image Counter

    private var imageCounter: some View {
        HStack(spacing: Spacing.md) {
            Button {
                let prev = MediaGalleryCalculations.previousIndex(current: currentIndex, total: allImages.count)
                currentIndex = prev
                zoomScale = 1.0
                onChangeImage(allImages[prev])
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            Text(MediaGalleryCalculations.imageCounterLabel(currentIndex: currentIndex, total: allImages.count))
                .font(Typography.small)
                .foregroundStyle(.white)

            Button {
                let next = MediaGalleryCalculations.nextIndex(current: currentIndex, total: allImages.count)
                currentIndex = next
                zoomScale = 1.0
                onChangeImage(allImages[next])
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.lg)
        .background(.black.opacity(0.7))
        .clipShape(Capsule())
    }
}
