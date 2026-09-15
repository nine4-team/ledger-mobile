import SwiftUI

/// Inputs for the original gallery's image content. Loading and authorization
/// stay with the caller; this view owns only the original presentation.
struct GalleryImagePresentationContext {
    let index: Int
    let zoom: Binding<CGFloat>
    let onTap: () -> Void
}

struct ImageGalleryPresentation<ImageContent: View>: View {
    let imageIDs: [AnyHashable]
    var initialIndex: Int
    @Binding var isPresented: Bool
    var onPinImage: ((Int) -> Void)?
    var onSaveImage: ((Int) async throws -> Void)?
    var onShareImage: ((Int) -> Void)?
    var onCopyImage: ((Int) async throws -> Void)?
    var onRequestSave: ((Int) -> Void)?
    var shareURL: ((Int) -> URL?)?
    var caption: ((Int) -> String?)?
    var onSelectionChange: ((Int) -> Void)?
    var actionsDisabled: Bool
    var accessibilityPrefix: String
    var showsZoomLevel: Bool
    let imageContent: (GalleryImagePresentationContext) -> ImageContent
    @State private var currentIndex: Int = 0
    @State private var controlsVisible: Bool = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var currentZoom: CGFloat = 1.0
    @State private var saveAlertMessage: String?
    @State private var copiedIndex: Int?

    // Swipe-to-dismiss state
    @State private var dismissOffset: CGFloat = 0
    @State private var isDraggingToDismiss: Bool = false

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 5.0
    private let zoomStep: CGFloat = 0.5
    private let dismissThreshold: CGFloat = 300

    init(
        imageIDs: [AnyHashable],
        initialIndex: Int = 0,
        isPresented: Binding<Bool>,
        onPinImage: ((Int) -> Void)? = nil,
        onSaveImage: ((Int) async throws -> Void)? = nil,
        onShareImage: ((Int) -> Void)? = nil,
        onCopyImage: ((Int) async throws -> Void)? = nil,
        onRequestSave: ((Int) -> Void)? = nil,
        shareURL: ((Int) -> URL?)? = nil,
        caption: ((Int) -> String?)? = nil,
        onSelectionChange: ((Int) -> Void)? = nil,
        actionsDisabled: Bool = false,
        accessibilityPrefix: String = "gallery",
        showsZoomLevel: Bool = false,
        @ViewBuilder imageContent: @escaping (GalleryImagePresentationContext) -> ImageContent
    ) {
        self.imageIDs = imageIDs
        self.initialIndex = initialIndex
        self._isPresented = isPresented
        self.onPinImage = onPinImage
        self.onSaveImage = onSaveImage
        self.onShareImage = onShareImage
        self.onCopyImage = onCopyImage
        self.onRequestSave = onRequestSave
        self.shareURL = shareURL
        self.caption = caption
        self.onSelectionChange = onSelectionChange
        self.actionsDisabled = actionsDisabled
        self.accessibilityPrefix = accessibilityPrefix
        self.showsZoomLevel = showsZoomLevel
        self.imageContent = imageContent
        self._currentIndex = State(initialValue: Self.clampedIndex(initialIndex, total: imageIDs.count))
    }

    private var dismissProgress: CGFloat {
        MediaGalleryCalculations.dismissProgress(translation: dismissOffset, threshold: dismissThreshold)
    }

    var body: some View {
        ZStack {
            // Background — fades during swipe-to-dismiss
            Color.black
                .opacity(MediaGalleryCalculations.dismissOpacity(progress: dismissProgress))
                .ignoresSafeArea()

            // Pager with images
            pagerView
                .offset(y: dismissOffset)
                .scaleEffect(MediaGalleryCalculations.dismissScale(progress: dismissProgress))

            // Controls that auto-hide (share, zoom, nav, info)
            controlsOverlay
                .opacity(controlsVisible && !isDraggingToDismiss ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: controlsVisible)
                .animation(.easeInOut(duration: 0.15), value: isDraggingToDismiss)
                .allowsHitTesting(controlsVisible && !isDraggingToDismiss)
                .accessibilityHidden(!controlsVisible || isDraggingToDismiss)

            // Primary image actions stay visible while the image is open.
            VStack {
                HStack {
                    closeButton
                    if onPinImage != nil {
                        pinButton
                    }
                    Spacer()
                    if let onCopyImage {
                        Button {
                            let index = currentIndex
                            Task {
                                do { try await onCopyImage(index); copiedIndex = index }
                                catch is CancellationError { }
                                catch { saveAlertMessage = error.localizedDescription }
                            }
                        } label: { controlButtonLabel(systemName: copiedIndex == currentIndex ? "checkmark" : "doc.on.doc") }
                        .disabled(actionsDisabled)
                        .accessibilityLabel("Copy Image")
                        .accessibilityValue(copiedIndex == currentIndex ? "Copied" : "")
                        .accessibilityIdentifier(accessibilityPrefix + "-image-copy")
                    }
                    saveButton
                    shareButton
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                Spacer()
            }
        }
        #if canImport(UIKit)
        .statusBarHidden()
        #endif
        #if canImport(UIKit)
        .gesture(dismissGesture)
        #endif
        .onAppear {
            currentIndex = Self.clampedIndex(initialIndex, total: imageIDs.count)
            currentZoom = 1.0
            resetHideTimer()
        }
        .onChange(of: initialIndex) { _, newValue in
            currentIndex = Self.clampedIndex(newValue, total: imageIDs.count)
            currentZoom = 1.0
        }
        .onChange(of: imageIDs.count) { _, newValue in
            currentIndex = Self.clampedIndex(currentIndex, total: newValue)
            currentZoom = 1.0
        }
        .onChange(of: currentIndex) { _, index in
            copiedIndex = nil
            currentZoom = 1.0
            resetHideTimer()
            onSelectionChange?(index)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityPrefix + "-image-viewer")
        .accessibilityValue(controlsVisible ? "Image controls visible" : "Image controls hidden")
        .onDisappear {
            hideControlsTask?.cancel()
        }
        .alert("Image", isPresented: .init(
            get: { saveAlertMessage != nil },
            set: { if !$0 { saveAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveAlertMessage = nil }
        } message: {
            Text(saveAlertMessage ?? "")
        }
    }

    // MARK: - Pager

    @ViewBuilder
    private var pagerView: some View {
        #if canImport(UIKit)
        TabView(selection: $currentIndex) {
            ForEach(imageIDs.indices, id: \.self) { index in
                Group {
                    // Only the selected image owns a loader. Paging does not
                    // grant permission to prefetch every downloaded reference.
                    if index == currentIndex {
                        imageContent(GalleryImagePresentationContext(
                            index: index, zoom: zoomBindingFor(index), onTap: toggleControls))
                            .id(imageIDs[index])
                    } else { Color.clear }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        if imageIDs.indices.contains(currentIndex) {
            imageContent(GalleryImagePresentationContext(
                index: currentIndex, zoom: zoomBindingFor(currentIndex), onTap: toggleControls))
                .id(imageIDs[currentIndex])
        }
        #endif
    }

    private static func clampedIndex(_ index: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return min(max(index, 0), total - 1)
    }

    // MARK: - Swipe-to-Dismiss

    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only activate for vertical drags when not zoomed
                guard currentZoom <= 1.01 else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                isDraggingToDismiss = true
                dismissOffset = value.translation.height
            }
            .onEnded { value in
                guard isDraggingToDismiss else { return }
                isDraggingToDismiss = false

                if dismissProgress > 0.3 {
                    // Dismiss
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dismissOffset = value.translation.height > 0 ? 600 : -600
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        isPresented = false
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dismissOffset = 0
                    }
                }
            }
    }

    // MARK: - Zoom Binding

    private func zoomBindingFor(_ index: Int) -> Binding<CGFloat> {
        Binding(
            get: { index == currentIndex ? currentZoom : 1.0 },
            set: { newValue in
                if index == currentIndex {
                    currentZoom = newValue
                    resetHideTimer()
                }
            }
        )
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack {
            // Prev/Next navigation
            if imageIDs.count > 1 {
                HStack {
                    Button {
                        withAnimation {
                            currentIndex = MediaGalleryCalculations.previousIndex(current: currentIndex, total: imageIDs.count)
                        }
                        resetHideTimer()
                    } label: {
                        controlButtonLabel(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous")
                    .accessibilityIdentifier(accessibilityPrefix + "-images-previous")
                    Spacer()
                    Button {
                        withAnimation {
                            currentIndex = MediaGalleryCalculations.nextIndex(current: currentIndex, total: imageIDs.count)
                        }
                        resetHideTimer()
                    } label: {
                        controlButtonLabel(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Next")
                    .accessibilityIdentifier(accessibilityPrefix + "-images-next")
                }
                .padding(.horizontal, Spacing.md)
            }

            // Bottom area
            VStack {
                Spacer()

                zoomControls
                    .padding(.bottom, Spacing.sm)

                infoBar
            }
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            controlButtonLabel(systemName: "xmark")
        }
        .accessibilityLabel("Done")
        .accessibilityIdentifier(accessibilityPrefix + "-images-done")
    }

    // MARK: - Pin Button

    private var pinButton: some View {
        Button {
            guard currentIndex < imageIDs.count else { return }
            onPinImage?(currentIndex)
            isPresented = false
        } label: {
            controlButtonLabel(systemName: "pin")
        }
        .accessibilityLabel("Pin image for reference")
        .accessibilityIdentifier(accessibilityPrefix + "-image-pin")
    }

    // MARK: - Save Button

    @ViewBuilder
    private var saveButton: some View {
        if currentIndex < imageIDs.count, onSaveImage != nil || onRequestSave != nil {
            Button {
                if let onRequestSave { onRequestSave(currentIndex) }
                else { saveCurrentImage() }
            } label: {
                controlButtonLabel(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Save image to device")
            .accessibilityIdentifier(accessibilityPrefix + "-image-save")
            .disabled(actionsDisabled)
        }
    }

    // MARK: - Share Button

    @ViewBuilder
    private var shareButton: some View {
        if currentIndex < imageIDs.count {
            if let onShareImage {
                Button { onShareImage(currentIndex) } label: {
                    controlButtonLabel(systemName: "square.and.arrow.up")
                }
                .disabled(actionsDisabled)
                .accessibilityLabel("Share image")
                .accessibilityIdentifier(accessibilityPrefix + "-image-share")
            } else if let url = shareURL?(currentIndex) {
                ShareLink(item: url) { controlButtonLabel(systemName: "square.and.arrow.up") }
            }
        }
    }

    private func saveCurrentImage() {
        guard currentIndex < imageIDs.count, let onSaveImage else { return }
        let attachment = currentIndex
        Task {
            do {
                try await onSaveImage(attachment)
                #if os(macOS)
                saveAlertMessage = "Image saved."
                #else
                saveAlertMessage = "Image saved to Photos."
                #endif
            } catch is CancellationError {
                // Canceling a destination picker is not a failed save.
            } catch {
                saveAlertMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Zoom Controls

    private var zoomControls: some View {
        HStack(spacing: Spacing.md) {
            Button {
                currentZoom = MediaGalleryCalculations.previousZoom(current: currentZoom, step: zoomStep, min: minZoom)
                resetHideTimer()
            } label: {
                zoomButtonLabel(systemName: "minus")
            }
            .disabled(!MediaGalleryCalculations.canZoomOut(currentZoom: currentZoom, minZoom: minZoom))
            .accessibilityLabel("Zoom out")
            .accessibilityIdentifier(accessibilityPrefix + "-image-zoom-out")

            if showsZoomLevel {
                Text(String(format: "%.1f×", Double(currentZoom)))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier(accessibilityPrefix + "-image-zoom-level")
            }

            if MediaGalleryCalculations.shouldShowResetZoom(currentZoom: currentZoom) {
                Button {
                    currentZoom = 1.0
                    resetHideTimer()
                } label: {
                    zoomButtonLabel(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset zoom")
                .accessibilityIdentifier(accessibilityPrefix + "-image-zoom-reset")
            }

            Button {
                currentZoom = MediaGalleryCalculations.nextZoom(current: currentZoom, step: zoomStep, max: maxZoom)
                resetHideTimer()
            } label: {
                zoomButtonLabel(systemName: "plus")
            }
            .disabled(!MediaGalleryCalculations.canZoomIn(currentZoom: currentZoom, maxZoom: maxZoom))
            .accessibilityLabel("Zoom in")
            .accessibilityIdentifier(accessibilityPrefix + "-image-zoom-in")
        }
    }

    private func controlButtonLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(.black.opacity(0.5))
            .clipShape(Circle())
    }

    private func zoomButtonLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.black.opacity(0.5))
            .clipShape(Circle())
    }

    // MARK: - Info Bar

    private var infoBar: some View {
        VStack(spacing: 2) {
            if imageIDs.count > 1 {
                Text(MediaGalleryCalculations.imageCounterLabel(currentIndex: currentIndex, total: imageIDs.count))
                    .font(Typography.small)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier(accessibilityPrefix + "-images-counter")
            }

            if let fileName = currentIndex < imageIDs.count ? caption?(currentIndex) : nil {
                Text(fileName)
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.7))
    }

    // MARK: - Auto-Hide Controls

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            resetHideTimer()
        } else {
            hideControlsTask?.cancel()
        }
    }

    private func resetHideTimer() {
        controlsVisible = true
        hideControlsTask?.cancel()
        guard currentZoom <= 1.01 else { return }
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controlsVisible = false
                }
            }
        }
    }
}
