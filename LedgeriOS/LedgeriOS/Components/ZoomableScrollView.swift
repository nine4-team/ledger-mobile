#if canImport(UIKit)
import SwiftUI
import UIKit

/// Zoomable image viewer backed by UIScrollView. Supports pinch-to-zoom, double-tap zoom,
/// pan when zoomed, and async image loading with spinner/error states.
///
/// Shared by `ImageGallery` (full-screen viewer) and `PinnedImagePanel` (reference panel).
struct ZoomableScrollView: UIViewRepresentable {
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

        // Don't load here — bounds are zero until the view is laid out.
        // updateUIView fires after layout with correct bounds, and its
        // currentURL != url check will trigger the initial load.

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
            guard imageView != nil else { return }
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
                    // Resolve gs:// URLs to HTTPS download URLs
                    let loadableURL: URL
                    if url.scheme == "gs" {
                        guard let resolved = await StorageURLResolver.resolve(url.absoluteString) else {
                            self?.showError()
                            return
                        }
                        loadableURL = resolved
                    } else {
                        loadableURL = url
                    }

                    let (data, _) = try await URLSession.shared.data(from: loadableURL)
                    guard !Task.isCancelled else { return }
                    guard let image = UIImage(data: data) else {
                        self?.showError()
                        return
                    }
                    self?.displayImage(image)
                } catch {
                    if !Task.isCancelled {
                        self?.showError()
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
#elseif canImport(AppKit)
import SwiftUI
import AppKit

/// macOS zoomable image viewer backed by NSScrollView. Supports trackpad pinch-to-zoom,
/// double-click zoom, pan when zoomed, and async image loading with spinner/error states.
///
/// Mirrors the iOS `UIViewRepresentable` + `UIScrollView` architecture.
struct ZoomableScrollView: NSViewRepresentable {
    let url: URL?
    @Binding var zoomScale: CGFloat
    var onSingleTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        // Enable native trackpad pinch-to-zoom
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1.0
        scrollView.maxMagnification = 5.0

        // Use a centering clip view
        let clipView = CenteringClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        // Image view as document view
        let imageView = NSImageView()
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        scrollView.documentView = imageView
        context.coordinator.imageView = imageView

        // Loading spinner
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        scrollView.addSubview(spinner)
        context.coordinator.spinner = spinner

        // Error icon
        let errorConfig = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        let errorImage = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")?
            .withSymbolConfiguration(errorConfig)
        let errorView = NSImageView(image: errorImage ?? NSImage())
        errorView.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        errorView.isHidden = true
        scrollView.addSubview(errorView)
        context.coordinator.errorView = errorView

        // Double-click gesture for zoom toggle
        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        scrollView.addGestureRecognizer(doubleClick)

        // Single-click gesture
        // Note: NSGestureRecognizer doesn't support failure requirements like UIKit.
        // Single-click will also fire on double-click, which is acceptable — it toggles
        // controls visibility while double-click handles zoom.
        let singleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleClick))
        singleClick.numberOfClicksRequired = 1
        singleClick.delaysPrimaryMouseButtonEvents = false
        scrollView.addGestureRecognizer(singleClick)

        // KVO on magnification to sync zoom back to SwiftUI
        context.coordinator.magnificationObservation = scrollView.observe(\.magnification, options: [.new]) { [weak coordinator = context.coordinator] scrollView, change in
            guard let coordinator, let newValue = change.newValue else { return }
            if abs(newValue - coordinator.parent.zoomScale) > 0.01 {
                DispatchQueue.main.async {
                    coordinator.parent.zoomScale = newValue
                }
            }
        }

        // Load initial image
        context.coordinator.loadImage(url: url)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        // If URL changed, reload
        if context.coordinator.currentURL != url {
            context.coordinator.loadImage(url: url)
        }

        // Sync zoom from SwiftUI → AppKit (from zoom buttons)
        if abs(scrollView.magnification - zoomScale) > 0.01 {
            scrollView.animator().magnification = zoomScale
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        coordinator.magnificationObservation = nil
    }

    // MARK: - Centering Clip View

    /// Custom NSClipView that centers the document view when it's smaller than the scroll view.
    class CenteringClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var constrained = super.constrainBoundsRect(proposedBounds)
            guard let documentView else { return constrained }

            let docFrame = documentView.frame
            if docFrame.width < constrained.width {
                constrained.origin.x = (docFrame.width - constrained.width) / 2
            }
            if docFrame.height < constrained.height {
                constrained.origin.y = (docFrame.height - constrained.height) / 2
            }
            return constrained
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var parent: ZoomableScrollView
        var imageView: NSImageView?
        var spinner: NSProgressIndicator?
        var errorView: NSImageView?
        var currentURL: URL?
        var magnificationObservation: NSKeyValueObservation?
        fileprivate var loadTask: Task<Void, Never>?

        init(parent: ZoomableScrollView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
            magnificationObservation = nil
        }

        // MARK: Double-Click

        @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let scrollView = recognizer.view as? NSScrollView else { return }

            if scrollView.magnification > scrollView.minMagnification + 0.01 {
                // Zoom out to fit
                scrollView.animator().magnification = scrollView.minMagnification
            } else {
                // Zoom to 2.5x centered on click point
                let clickPoint = recognizer.location(in: scrollView)
                let targetScale: CGFloat = 2.5
                scrollView.setMagnification(targetScale, centeredAt: clickPoint)
            }
        }

        // MARK: Single-Click

        @objc func handleSingleClick() {
            parent.onSingleTap?()
        }

        // MARK: Image Loading

        @MainActor
        func loadImage(url: URL?) {
            loadTask?.cancel()
            currentURL = url
            imageView?.image = nil
            errorView?.isHidden = true

            guard let url else {
                errorView?.isHidden = false
                return
            }

            spinner?.startAnimation(nil)

            loadTask = Task { [weak self] in
                do {
                    // Resolve gs:// URLs to HTTPS download URLs
                    let loadableURL: URL
                    if url.scheme == "gs" {
                        guard let resolved = await StorageURLResolver.resolve(url.absoluteString) else {
                            self?.showError()
                            return
                        }
                        loadableURL = resolved
                    } else {
                        loadableURL = url
                    }

                    let (data, _) = try await URLSession.shared.data(from: loadableURL)
                    guard !Task.isCancelled else { return }
                    guard let image = NSImage(data: data) else {
                        self?.showError()
                        return
                    }
                    self?.displayImage(image)
                } catch {
                    if !Task.isCancelled {
                        self?.showError()
                    }
                }
            }
        }

        @MainActor
        private func displayImage(_ image: NSImage) {
            guard let imageView, let scrollView = imageView.enclosingScrollView else { return }
            spinner?.stopAnimation(nil)
            errorView?.isHidden = true

            imageView.image = image
            let imageSize = image.size
            imageView.frame = CGRect(origin: .zero, size: imageSize)

            // Fit image to scroll view bounds
            let scrollBounds = scrollView.bounds
            guard scrollBounds.width > 0, scrollBounds.height > 0,
                  imageSize.width > 0, imageSize.height > 0 else { return }

            let widthScale = scrollBounds.width / imageSize.width
            let heightScale = scrollBounds.height / imageSize.height
            let fitScale = min(widthScale, heightScale)

            scrollView.minMagnification = fitScale
            scrollView.maxMagnification = max(fitScale * 5, 5.0)
            scrollView.magnification = fitScale

            DispatchQueue.main.async {
                self.parent.zoomScale = fitScale
            }

            layoutOverlays()
        }

        @MainActor
        private func showError() {
            spinner?.stopAnimation(nil)
            errorView?.isHidden = false
            layoutOverlays()
        }

        @MainActor
        private func layoutOverlays() {
            guard let scrollView = imageView?.enclosingScrollView else { return }
            let bounds = scrollView.bounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            spinner?.frame = CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)
            errorView?.frame = CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36)
        }
    }
}
#endif
