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
    var isMatchingItems: Bool = false
    var pendingItemId: String?
    var pendingItemName: String?
    var onToggleItemMatching: (() -> Void)?
    var onCancelPendingItemMatch: (() -> Void)?
    var onPlaceItemCheckmark: ((AttachmentRef, String, CGPoint) -> Void)?
    var itemNameForId: ((String) -> String?)?
    var onMoveItemCheckmark: ((String) -> Void)?
    var onClearAllCheckmarks: (() -> Void)?

    @State private var zoomScale: CGFloat = 1.0
    @State private var currentIndex: Int = 0
    @State private var pdfDocument: PDFDocument?
    @State private var isPDFLoading = false
    @State private var localCheckmarksByURL: [String: [ImageCheckmark]] = [:]
    @State private var selectedCheckmark: ImageCheckmark?
    @State private var showClearAllConfirmation = false

    private var currentAttachment: AttachmentRef {
        allImages.indices.contains(currentIndex) ? allImages[currentIndex] : attachment
    }

    private var currentCheckmarks: [ImageCheckmark] {
        localCheckmarksByURL[currentAttachment.url] ?? currentAttachment.checkmarks ?? []
    }

    private var hasAnyCheckmarks: Bool {
        allImages.contains { image in
            !(localCheckmarksByURL[image.url] ?? image.checkmarks ?? []).isEmpty
        }
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
                    pendingItemId: pendingItemId,
                    onSelect: { selectedCheckmark = $0 },
                    onPlace: { itemId, point in
                        onPlaceItemCheckmark?(currentAttachment, itemId, point)
                    }
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
                    if currentAttachment.kind == .image, onToggleItemMatching != nil {
                        matchItemsButton
                        if isMatchingItems, hasAnyCheckmarks {
                            checkmarkActionsMenu
                        }
                    }
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                Spacer()
            }

            if isMatchingItems {
                VStack {
                    matchingInstruction
                        .padding(.top, 58)
                        .allowsHitTesting(pendingItemId != nil)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
            }

            if let selectedCheckmark {
                VStack {
                    Spacer()
                    checkmarkInspector(for: selectedCheckmark)
                        .padding(.bottom, allImages.count > 1 ? 58 : Spacing.sm)
                }
                .padding(.horizontal, Spacing.md)
            }

            // Image counter — bottom center
            if allImages.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        imageCounter
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
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
            currentIndex = allImages.firstIndex(where: { $0.url == newURL }) ?? 0
        }
        .onChange(of: currentAttachment.url) {
            selectedCheckmark = nil
            if currentAttachment.kind == .pdf {
                Task { await loadPDF() }
            }
        }
        .onChange(of: currentAttachment.checkmarks) { _, newCheckmarks in
            localCheckmarksByURL[currentAttachment.url] = newCheckmarks ?? []
        }
        .task {
            if currentAttachment.kind == .pdf {
                await loadPDF()
            }
        }
        .confirmationDialog(
            "Clear all photo checkmarks?",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear all checkmarks", role: .destructive) {
                for image in allImages {
                    localCheckmarksByURL[image.url] = []
                }
                selectedCheckmark = nil
                onClearAllCheckmarks?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every checkmark from this space's photos. Items and space completion will not change.")
        }
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

    private var matchItemsButton: some View {
        Button {
            onToggleItemMatching?()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isMatchingItems ? "checkmark" : "checkmark.circle")
                Text(isMatchingItems ? "Done" : "Match items")
            }
            .font(Typography.label)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .frame(height: 40)
            .background(.black.opacity(0.6))
            .clipShape(Capsule())
        }
        .accessibilityHint(isMatchingItems
            ? "Finish matching items to this photo"
            : "Show item matching controls")
    }

    private var checkmarkActionsMenu: some View {
        Menu {
            Button("Clear all checkmarks", role: .destructive) {
                showClearAllConfirmation = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.6))
                .clipShape(Circle())
        }
        .accessibilityLabel("Photo checkmark actions")
    }

    private var matchingInstruction: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: pendingItemId == nil ? "list.bullet" : "hand.tap")
                .foregroundStyle(.green)
            Text(pendingItemId == nil
                 ? "Choose Mark in photo on an item card"
                 : "Tap where \(pendingItemName ?? "the item") appears")
                .font(Typography.small)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
            if pendingItemId != nil {
                Button("Cancel") {
                    onCancelPendingItemMatch?()
                }
                .font(Typography.label)
                .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 44)
        .background(.black.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
    }

    private func updateCheckmarks(_ checkmarks: [ImageCheckmark]) {
        localCheckmarksByURL[currentAttachment.url] = checkmarks
        onUpdateCheckmarks?(currentAttachment, checkmarks)
    }

    private func checkmarkInspector(for mark: ImageCheckmark) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Marked item")
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text(mark.itemId.flatMap { itemNameForId?($0) } ?? "Unlinked checkmark")
                    .font(Typography.label)
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if let itemId = mark.itemId, itemNameForId?(itemId) != nil {
                Button("Move") {
                    selectedCheckmark = nil
                    onMoveItemCheckmark?(itemId)
                }
                .font(Typography.label)
                .foregroundStyle(.white)
            }

            Button("Remove", role: .destructive) {
                updateCheckmarks(currentCheckmarks.filter { $0.id != mark.id })
                selectedCheckmark = nil
            }
            .font(Typography.label)
            .foregroundStyle(.red)

            Button {
                selectedCheckmark = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Close checkmark details")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.black.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
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
    let pendingItemId: String?
    let onSelect: (ImageCheckmark) -> Void
    let onPlace: (String, CGPoint) -> Void

    @State private var image: PlatformImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @GestureState private var gestureMagnification: CGFloat = 1
    @GestureState private var gestureTranslation: CGSize = .zero

    private let coordinateSpaceName = "image-checkmark-editor"
    private let maximumZoomScale: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            if let image {
                let imageRect = PinnedImageCalculations.aspectFitRect(
                    imageSize: image.size,
                    in: geometry.size
                )
                let effectiveScale = clampedZoomScale(zoomScale * gestureMagnification)
                let proposedOffset = CGSize(
                    width: panOffset.width + gestureTranslation.width,
                    height: panOffset.height + gestureTranslation.height
                )
                let effectiveOffset = PinnedImageCalculations.clampedPanOffset(
                    proposedOffset,
                    imageRect: imageRect,
                    containerSize: geometry.size,
                    scale: effectiveScale
                )
                ZStack(alignment: .topLeading) {
                    platformImage(image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .scaleEffect(effectiveScale)
                        .offset(effectiveOffset)
                        .allowsHitTesting(false)

                    if let pendingItemId {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                                    .onEnded { value in
                                        placeCheckmark(
                                            for: pendingItemId,
                                            at: value.location,
                                            imageRect: imageRect,
                                            scale: effectiveScale,
                                            offset: effectiveOffset
                                        )
                                    }
                            )
                    }

                    ForEach(checkmarks) { mark in
                        Button {
                            onSelect(mark)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(.green)
                                .shadow(color: .black.opacity(0.65), radius: 2)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(
                            PinnedImageCalculations.zoomedPoint(
                                for: PinnedImageCalculations.renderedPoint(
                                    for: CGPoint(x: CGFloat(mark.x), y: CGFloat(mark.y)),
                                    in: imageRect
                                ),
                                imageRect: imageRect,
                                scale: effectiveScale,
                                offset: effectiveOffset
                            )
                        )
                        .accessibilityLabel("Show checked item")
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            zoomControls(
                                scale: effectiveScale,
                                imageRect: imageRect,
                                containerSize: geometry.size
                            )
                        }
                    }
                    .padding(Spacing.sm)
                }
                .coordinateSpace(name: coordinateSpaceName)
                .clipped()
                .simultaneousGesture(zoomGesture(imageRect: imageRect, containerSize: geometry.size))
                .simultaneousGesture(panGesture(imageRect: imageRect, containerSize: geometry.size))
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
        .onChange(of: attachment.url) {
            zoomScale = 1
            panOffset = .zero
        }
    }

    @ViewBuilder
    private func platformImage(_ image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }

    private func placeCheckmark(
        for itemId: String,
        at point: CGPoint,
        imageRect: CGRect,
        scale: CGFloat,
        offset: CGSize
    ) {
        guard let unzoomedPoint = PinnedImageCalculations.unzoomedPoint(
            for: point,
            imageRect: imageRect,
            scale: scale,
            offset: offset
        ) else { return }
        guard let normalizedPoint = PinnedImageCalculations.normalizedImagePoint(
            for: unzoomedPoint,
            in: imageRect
        ) else { return }
        onPlace(itemId, normalizedPoint)
    }

    private func clampedZoomScale(_ scale: CGFloat) -> CGFloat {
        Swift.min(maximumZoomScale, Swift.max(1, scale))
    }

    private func zoomGesture(imageRect: CGRect, containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($gestureMagnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let nextScale = clampedZoomScale(zoomScale * value)
                zoomScale = nextScale
                panOffset = PinnedImageCalculations.clampedPanOffset(
                    panOffset,
                    imageRect: imageRect,
                    containerSize: containerSize,
                    scale: nextScale
                )
            }
    }

    private func panGesture(imageRect: CGRect, containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($gestureTranslation) { value, state, _ in
                guard zoomScale * gestureMagnification > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard zoomScale > 1 else {
                    panOffset = .zero
                    return
                }
                let proposed = CGSize(
                    width: panOffset.width + value.translation.width,
                    height: panOffset.height + value.translation.height
                )
                panOffset = PinnedImageCalculations.clampedPanOffset(
                    proposed,
                    imageRect: imageRect,
                    containerSize: containerSize,
                    scale: zoomScale
                )
            }
    }

    private func zoomControls(scale: CGFloat, imageRect: CGRect, containerSize: CGSize) -> some View {
        HStack(spacing: 0) {
            Button {
                setZoom(scale - 0.75, imageRect: imageRect, containerSize: containerSize)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 40, height: 40)
            }
            .disabled(scale <= 1.01)
            .accessibilityLabel("Zoom out")

            Text("\(Int((scale * 100).rounded()))%")
                .font(Typography.caption)
                .frame(minWidth: 48)
                .accessibilityLabel("Zoom level")

            Button {
                setZoom(scale + 0.75, imageRect: imageRect, containerSize: containerSize)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 40, height: 40)
            }
            .disabled(scale >= maximumZoomScale - 0.01)
            .accessibilityLabel("Zoom in")
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.68))
        .clipShape(Capsule())
    }

    private func setZoom(_ requestedScale: CGFloat, imageRect: CGRect, containerSize: CGSize) {
        let nextScale = clampedZoomScale(requestedScale)
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = nextScale
            panOffset = nextScale == 1
                ? .zero
                : PinnedImageCalculations.clampedPanOffset(
                    panOffset,
                    imageRect: imageRect,
                    containerSize: containerSize,
                    scale: nextScale
                )
        }
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
