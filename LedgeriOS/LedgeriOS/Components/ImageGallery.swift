import SwiftUI
import UIKit

struct ImageGallery: View {
    let images: [AttachmentRef]
    var initialIndex: Int = 0
    @Binding var isPresented: Bool

    @State private var currentIndex: Int = 0
    @State private var controlsVisible: Bool = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var currentZoom: CGFloat = 1.0

    // Swipe-to-dismiss state
    @State private var dismissOffset: CGFloat = 0
    @State private var isDraggingToDismiss: Bool = false

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 5.0
    private let zoomStep: CGFloat = 0.5
    private let dismissThreshold: CGFloat = 300

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

            // Close button — ALWAYS visible
            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                Spacer()
            }
        }
        .statusBarHidden()
        .gesture(dismissGesture)
        .onAppear {
            currentIndex = initialIndex
            resetHideTimer()
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
    }

    // MARK: - Pager

    private var pagerView: some View {
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
            // Top bar (share button only — close button is outside this overlay)
            VStack {
                HStack {
                    Spacer()
                    shareButton
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                Spacer()
            }

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

    // MARK: - Share Button

    @ViewBuilder
    private var shareButton: some View {
        if currentIndex < images.count, let url = URL(string: images[currentIndex].url) {
            ShareLink(item: url) {
                controlButtonLabel(systemName: "square.and.arrow.up")
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

// MARK: - ZoomableScrollView (UIScrollView wrapper)

private struct ZoomableScrollView: UIViewRepresentable {
    let url: URL?
    @Binding var zoomScale: CGFloat
    var onSingleTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        // Image view
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        // Loading indicator
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        scrollView.addSubview(spinner)
        context.coordinator.spinner = spinner

        // Error icon
        let errorConfig = UIImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        let errorImage = UIImage(systemName: "exclamationmark.triangle", withConfiguration: errorConfig)
        let errorView = UIImageView(image: errorImage)
        errorView.tintColor = .white.withAlphaComponent(0.5)
        errorView.isHidden = true
        scrollView.addSubview(errorView)
        context.coordinator.errorView = errorView

        // Double-tap gesture
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.doubleTapGesture = doubleTap

        // Single-tap gesture (requires double-tap to fail first)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        // Load initial image
        context.coordinator.loadImage(url: url)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self

        // If URL changed, reload
        if context.coordinator.currentURL != url {
            context.coordinator.loadImage(url: url)
        }

        // Sync zoom from SwiftUI → UIKit (from zoom buttons)
        if abs(scrollView.zoomScale - zoomScale) > 0.01 {
            scrollView.setZoomScale(zoomScale, animated: true)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableScrollView
        var imageView: UIImageView?
        var spinner: UIActivityIndicatorView?
        var errorView: UIImageView?
        var doubleTapGesture: UITapGestureRecognizer?
        var currentURL: URL?
        fileprivate var loadTask: Task<Void, Never>?

        init(parent: ZoomableScrollView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
            // Report zoom back to SwiftUI
            let scale = scrollView.zoomScale
            if abs(scale - parent.zoomScale) > 0.01 {
                DispatchQueue.main.async {
                    self.parent.zoomScale = scale
                }
            }
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            DispatchQueue.main.async {
                self.parent.zoomScale = scale
            }
        }

        // MARK: Image Centering

        private func centerImage(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let boundsSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize

            let horizontalInset = max(0, (boundsSize.width - contentSize.width) / 2)
            let verticalInset = max(0, (boundsSize.height - contentSize.height) / 2)

            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }

        // MARK: Double-Tap

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                // Zoom out to 1x
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom to 2.5x centered on tap point
                let tapPoint = recognizer.location(in: imageView)
                let targetScale: CGFloat = 2.5
                let zoomRect = zoomRectForScale(targetScale, center: tapPoint, in: scrollView)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        private func zoomRectForScale(_ scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            let origin = CGPoint(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2
            )
            return CGRect(origin: origin, size: size)
        }

        // MARK: Single-Tap

        @objc func handleSingleTap() {
            parent.onSingleTap?()
        }

        // MARK: Image Loading

        func loadImage(url: URL?) {
            loadTask?.cancel()
            currentURL = url
            imageView?.image = nil
            errorView?.isHidden = true

            guard let url else {
                errorView?.isHidden = false
                return
            }

            spinner?.startAnimating()

            loadTask = Task { [weak self] in
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard !Task.isCancelled else { return }
                    guard let image = UIImage(data: data) else {
                        await self?.showError()
                        return
                    }
                    await self?.displayImage(image)
                } catch {
                    if !Task.isCancelled {
                        await self?.showError()
                    }
                }
            }
        }

        @MainActor
        private func displayImage(_ image: UIImage) {
            guard let imageView, let scrollView = imageView.superview as? UIScrollView else { return }
            spinner?.stopAnimating()
            errorView?.isHidden = true

            imageView.image = image
            let imageSize = image.size
            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize

            // Reset zoom
            scrollView.zoomScale = 1.0

            // Fit image to screen
            let scrollBounds = scrollView.bounds
            guard scrollBounds.width > 0, scrollBounds.height > 0,
                  imageSize.width > 0, imageSize.height > 0 else { return }

            let widthScale = scrollBounds.width / imageSize.width
            let heightScale = scrollBounds.height / imageSize.height
            let fitScale = min(widthScale, heightScale)

            scrollView.minimumZoomScale = fitScale
            scrollView.maximumZoomScale = max(fitScale * 5, 5.0)
            scrollView.zoomScale = fitScale

            centerImage(in: scrollView)

            DispatchQueue.main.async {
                self.parent.zoomScale = 1.0
            }
        }

        @MainActor
        private func showError() {
            spinner?.stopAnimating()
            errorView?.isHidden = false
            layoutCenteredViews()
        }

        @MainActor
        private func layoutCenteredViews() {
            guard let scrollView = imageView?.superview as? UIScrollView else { return }
            let bounds = scrollView.bounds
            spinner?.center = CGPoint(x: bounds.midX, y: bounds.midY)
            errorView?.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
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
