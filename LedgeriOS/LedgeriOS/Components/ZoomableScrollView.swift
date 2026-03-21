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

/// macOS fallback — simple async image viewer without UIScrollView zoom.
/// Resolves `gs://` Firebase Storage URLs before loading (AsyncImage can't handle them).
struct ZoomableScrollView: View {
    let url: URL?
    @Binding var zoomScale: CGFloat
    var onSingleTap: (() -> Void)?

    @State private var loadedImage: NSImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let loadedImage {
                Image(nsImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoomScale)
            } else if loadFailed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 36))
            } else {
                ProgressView()
            }
        }
        .onTapGesture {
            onSingleTap?()
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        loadedImage = nil
        loadFailed = false

        guard let url else {
            loadFailed = true
            return
        }

        // Resolve gs:// URLs to HTTPS via Firebase Storage SDK
        let loadableURL: URL
        if url.scheme == "gs" {
            guard let resolved = await StorageURLResolver.resolve(url.absoluteString) else {
                loadFailed = true
                return
            }
            loadableURL = resolved
        } else {
            loadableURL = url
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: loadableURL)
            guard !Task.isCancelled else { return }
            guard let image = NSImage(data: data) else {
                loadFailed = true
                return
            }
            loadedImage = image
        } catch {
            if !Task.isCancelled {
                loadFailed = true
            }
        }
    }
}
#endif
