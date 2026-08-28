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
    var onUpdateCheckmarks: ((AttachmentRef, [ImageCheckmark]) -> Void)?

    @State private var zoomScale: CGFloat = 1.0
    @State private var currentIndex: Int = 0
    @State private var pdfDocument: PDFDocument?
    @State private var isPDFLoading = false
    @State private var isEditingCheckmarks = false
    @State private var localCheckmarksByURL: [String: [ImageCheckmark]] = [:]

    private var currentAttachment: AttachmentRef {
        allImages.indices.contains(currentIndex) ? allImages[currentIndex] : attachment
    }

    private var currentCheckmarks: [ImageCheckmark] {
        localCheckmarksByURL[currentAttachment.url] ?? currentAttachment.checkmarks ?? []
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if currentAttachment.kind == .pdf {
                pdfContent
            } else if onUpdateCheckmarks != nil {
                ImageCheckmarkEditor(
                    attachment: currentAttachment,
                    checkmarks: currentCheckmarks,
                    isEditing: isEditingCheckmarks,
                    onChange: updateCheckmarks
                )
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
                    if currentAttachment.kind == .image, onUpdateCheckmarks != nil {
                        editCheckmarksButton
                    }
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
            zoomScale = 1.0
            currentIndex = allImages.firstIndex(where: { $0.url == attachment.url }) ?? 0
        }
        .onChange(of: attachment.url) { _, newURL in
            zoomScale = 1.0
            isEditingCheckmarks = false
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

    private var editCheckmarksButton: some View {
        Button {
            isEditingCheckmarks.toggle()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isEditingCheckmarks ? "checkmark" : "checkmark.circle")
                Text(isEditingCheckmarks ? "Done" : "Check off")
            }
            .font(Typography.label)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .frame(height: 40)
            .background(.black.opacity(0.6))
            .clipShape(Capsule())
        }
        .accessibilityHint(isEditingCheckmarks
            ? "Finish placing checkmarks"
            : "Tap the image to place checkmarks; tap a checkmark to remove it")
    }

    private func updateCheckmarks(_ checkmarks: [ImageCheckmark]) {
        localCheckmarksByURL[currentAttachment.url] = checkmarks
        onUpdateCheckmarks?(currentAttachment, checkmarks)
    }

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

private struct ImageCheckmarkEditor: View {
    let attachment: AttachmentRef
    let checkmarks: [ImageCheckmark]
    let isEditing: Bool
    let onChange: ([ImageCheckmark]) -> Void

    @State private var image: PlatformImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    private let coordinateSpaceName = "image-checkmark-editor"

    var body: some View {
        GeometryReader { geometry in
            if let image {
                let imageRect = PinnedImageCalculations.aspectFitRect(
                    imageSize: image.size,
                    in: geometry.size
                )
                ZStack(alignment: .topLeading) {
                    platformImage(image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)

                    if isEditing {
                        Color.clear
                            .frame(width: imageRect.width, height: imageRect.height)
                            .contentShape(Rectangle())
                            .position(x: imageRect.midX, y: imageRect.midY)
                            .gesture(
                                SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                                    .onEnded { value in
                                        addCheckmark(at: value.location, imageRect: imageRect)
                                    }
                            )
                    }

                    ForEach(checkmarks) { mark in
                        Button {
                            guard isEditing else { return }
                            onChange(checkmarks.filter { $0.id != mark.id })
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 26, weight: .bold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .green)
                                .shadow(color: .black.opacity(0.65), radius: 2)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(isEditing)
                        .position(
                            PinnedImageCalculations.renderedPoint(
                                for: CGPoint(x: CGFloat(mark.x), y: CGFloat(mark.y)),
                                in: imageRect
                            )
                        )
                        .accessibilityLabel(isEditing ? "Remove checkmark" : "Checked item")
                    }
                }
                .coordinateSpace(name: coordinateSpaceName)
            } else if isLoading {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: attachment.url) { await loadImage() }
        .accessibilityLabel(isEditing ? "Checkmark editor" : "Pinned image with checkmarks")
    }

    @ViewBuilder
    private func platformImage(_ image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }

    private func addCheckmark(at point: CGPoint, imageRect: CGRect) {
        guard let normalizedPoint = PinnedImageCalculations.normalizedImagePoint(
            for: point,
            in: imageRect
        ) else { return }

        onChange(checkmarks + [
            ImageCheckmark(
                x: Double(normalizedPoint.x),
                y: Double(normalizedPoint.y)
            )
        ])
    }

    @MainActor
    private func loadImage() async {
        image = nil
        loadFailed = false
        isLoading = true
        defer { isLoading = false }

        if let cached = ImageCache.image(for: attachment.url) {
            image = cached
            return
        }

        guard let resolvedURL = await StorageURLResolver.resolve(attachment.url) else {
            loadFailed = true
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: resolvedURL)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                loadFailed = true
                return
            }
            guard let prepared = await PlatformImageDecoder.decode(data) else {
                loadFailed = true
                return
            }
            ImageCache.store(prepared.image, for: attachment.url, cost: data.count)
            image = prepared.image
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }
}
