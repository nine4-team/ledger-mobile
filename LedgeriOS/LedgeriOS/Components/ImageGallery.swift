import SwiftUI
#if canImport(UIKit)
import Photos
import UIKit
#endif

struct ImageGallery: View {
    let images: [AttachmentRef]
    var initialIndex: Int = 0
    @Binding var isPresented: Bool
    var onPinImage: ((AttachmentRef) -> Void)?
    var onSaveImage: ((AttachmentRef) async throws -> Void)? = ImageSaveHelper.saveToDevice

    @State private var currentIndex: Int = 0
    @State private var controlsVisible: Bool = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var currentZoom: CGFloat = 1.0
    @State private var saveAlertMessage: String?

    // Swipe-to-dismiss state
    @State private var dismissOffset: CGFloat = 0
    @State private var isDraggingToDismiss: Bool = false

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 5.0
    private let zoomStep: CGFloat = 0.5
    private let dismissThreshold: CGFloat = 300

    init(
        images: [AttachmentRef],
        initialIndex: Int = 0,
        isPresented: Binding<Bool>,
        onPinImage: ((AttachmentRef) -> Void)? = nil,
        onSaveImage: ((AttachmentRef) async throws -> Void)? = ImageSaveHelper.saveToDevice
    ) {
        self.images = images
        self.initialIndex = initialIndex
        self._isPresented = isPresented
        self.onPinImage = onPinImage
        self.onSaveImage = onSaveImage
        self._currentIndex = State(initialValue: Self.clampedIndex(initialIndex, total: images.count))
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

            // Primary image actions stay visible while the image is open.
            VStack {
                HStack {
                    closeButton
                    if onPinImage != nil {
                        pinButton
                    }
                    Spacer()
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
            currentIndex = Self.clampedIndex(initialIndex, total: images.count)
            currentZoom = 1.0
            resetHideTimer()
        }
        .onChange(of: initialIndex) { _, newValue in
            currentIndex = Self.clampedIndex(newValue, total: images.count)
            currentZoom = 1.0
        }
        .onChange(of: images.count) { _, newValue in
            currentIndex = Self.clampedIndex(currentIndex, total: newValue)
            currentZoom = 1.0
        }
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
            ForEach(Array(images.enumerated()), id: \.offset) { index, attachment in
                ZoomableScrollView(
                    url: URL(string: attachment.url),
                    zoomScale: zoomBindingFor(index),
                    onSingleTap: { toggleControls() }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: currentIndex) { _, _ in
            currentZoom = 1.0
            resetHideTimer()
        }
        #else
        if images.indices.contains(currentIndex) {
            ZoomableScrollView(
                url: URL(string: images[currentIndex].url),
                zoomScale: zoomBindingFor(currentIndex),
                onSingleTap: { toggleControls() }
            )
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
            if images.count > 1 {
                HStack {
                    Button {
                        withAnimation {
                            currentIndex = MediaGalleryCalculations.previousIndex(current: currentIndex, total: images.count)
                        }
                        resetHideTimer()
                    } label: {
                        controlButtonLabel(systemName: "chevron.left")
                    }
                    Spacer()
                    Button {
                        withAnimation {
                            currentIndex = MediaGalleryCalculations.nextIndex(current: currentIndex, total: images.count)
                        }
                        resetHideTimer()
                    } label: {
                        controlButtonLabel(systemName: "chevron.right")
                    }
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
    }

    // MARK: - Pin Button

    private var pinButton: some View {
        Button {
            guard currentIndex < images.count else { return }
            onPinImage?(images[currentIndex])
            isPresented = false
        } label: {
            controlButtonLabel(systemName: "pin")
        }
        .accessibilityLabel("Pin image for reference")
    }

    // MARK: - Save Button

    @ViewBuilder
    private var saveButton: some View {
        if currentIndex < images.count, onSaveImage != nil {
            Button {
                saveCurrentImage()
            } label: {
                controlButtonLabel(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Save image to device")
        }
    }

    // MARK: - Share Button

    @ViewBuilder
    private var shareButton: some View {
        if currentIndex < images.count, let url = URL(string: images[currentIndex].url) {
            ShareLink(item: url) {
                controlButtonLabel(systemName: "square.and.arrow.up")
            }
        }
    }

    private func saveCurrentImage() {
        guard currentIndex < images.count, let onSaveImage else { return }
        let attachment = images[currentIndex]
        Task {
            do {
                try await onSaveImage(attachment)
                saveAlertMessage = "Image saved to Photos."
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

            if MediaGalleryCalculations.shouldShowResetZoom(currentZoom: currentZoom) {
                Button {
                    currentZoom = 1.0
                    resetHideTimer()
                } label: {
                    zoomButtonLabel(systemName: "arrow.counterclockwise")
                }
            }

            Button {
                currentZoom = MediaGalleryCalculations.nextZoom(current: currentZoom, step: zoomStep, max: maxZoom)
                resetHideTimer()
            } label: {
                zoomButtonLabel(systemName: "plus")
            }
            .disabled(!MediaGalleryCalculations.canZoomIn(currentZoom: currentZoom, maxZoom: maxZoom))
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
            if images.count > 1 {
                Text(MediaGalleryCalculations.imageCounterLabel(currentIndex: currentIndex, total: images.count))
                    .font(Typography.small)
                    .foregroundStyle(.white)
            }

            if let fileName = currentIndex < images.count ? images[currentIndex].fileName : nil {
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

enum ImageSaveError: LocalizedError {
    case unsupportedPlatform
    case missingURL
    case permissionDenied
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Saving images is not supported on this device."
        case .missingURL:
            return "This image is not available yet."
        case .permissionDenied:
            return "Ledger does not have permission to save to Photos."
        case .invalidImageData:
            return "This file could not be saved as an image."
        }
    }
}

enum ImageSaveHelper {
    static func saveToDevice(_ attachment: AttachmentRef) async throws {
        #if canImport(UIKit)
        guard let resolvedURL = await StorageURLResolver.resolve(attachment.url) else {
            throw ImageSaveError.missingURL
        }

        let (data, response) = try await URLSession.shared.data(from: resolvedURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw ImageSaveError.missingURL
        }

        guard UIImage(data: data) != nil else {
            throw ImageSaveError.invalidImageData
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ImageSaveError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
        #else
        throw ImageSaveError.unsupportedPlatform
        #endif
    }
}

// MARK: - Previews

#Preview("Single Image") {
    ImageGallery(
        images: [AttachmentRef(url: "https://picsum.photos/800/600", kind: .image)],
        isPresented: .constant(true)
    )
}

#Preview("Multiple Images") {
    ImageGallery(
        images: [
            AttachmentRef(url: "https://picsum.photos/800/600", kind: .image, fileName: "living-room.jpg"),
            AttachmentRef(url: "https://picsum.photos/600/800", kind: .image, fileName: "bedroom.jpg"),
            AttachmentRef(url: "https://picsum.photos/700/700", kind: .image),
        ],
        initialIndex: 1,
        isPresented: .constant(true)
    )
}
