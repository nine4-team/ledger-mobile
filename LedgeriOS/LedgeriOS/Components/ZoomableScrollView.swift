import Foundation
import SwiftUI
import VisionKit

// VisionKit recommends sharing the analyzer; results remain view-local and
// are discarded with the authorized displayed image, never persisted here.
private let galleryImageAnalyzer = ImageAnalyzer()

/// A non-destructive marker rendered by the native image zoom surface.
/// The point is normalized to the image bounds (0...1 on each axis).
struct ZoomableImageAnnotation: Equatable, Identifiable {
    let id: String
    let point: CGPoint
    var isHighlighted: Bool = false
    var quantityLabel: String?
    var accessibilityLabel: String = "Show checked item"
    var style: Style = .itemCheckmark

    enum Style {
        case itemCheckmark, noteReference

        var symbolName: String { self == .noteReference ? "record.circle" : "checkmark" }
    }
}

/// Matches the native viewer's note marker in non-interactive thumbnails.
struct ImageAnnotationSymbol: View {
    let annotation: ZoomableImageAnnotation

    var body: some View {
        Image(systemName: annotation.style.symbolName)
            .font(.system(size: 24, weight: .heavy))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                annotation.style == .noteReference
                    ? Color.red
                    : (annotation.isHighlighted ? .yellow : .green),
                .white
            )
            .shadow(color: .black.opacity(0.45), radius: 1)
            .accessibilityLabel(annotation.accessibilityLabel)
    }
}

#if canImport(UIKit)
import UIKit
typealias GalleryPlatformImage = UIImage
#else
import AppKit
typealias GalleryPlatformImage = NSImage
#endif

/// Presentation input, not permission to fetch an image. The target supplies
/// authorized pixels; legacy URL loading is in a separately compiled adapter.
struct GalleryImageSource {
    let identity: AnyHashable
    var image: GalleryPlatformImage? = nil
    var load: (@MainActor () async -> GalleryPlatformImage?)? = nil
}

#if canImport(UIKit)
import SwiftUI
import UIKit

private final class AccessibleAnnotationImageView: UIImageView {
    var annotationID = ""
    var onActivate: ((String) -> Void)?
    let quantityBadge = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        quantityBadge.textAlignment = .center
        quantityBadge.textColor = .white
        quantityBadge.backgroundColor = .systemGreen
        quantityBadge.clipsToBounds = true
        quantityBadge.isHidden = true
        addSubview(quantityBadge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        onActivate?(annotationID)
        return true
    }
}

/// Zoomable image viewer backed by UIScrollView. Supports pinch-to-zoom, double-tap zoom,
/// pan when zoomed, and async image loading with spinner/error states.
///
/// Shared by `ImageGallery` (full-screen viewer) and `PinnedImagePanel` (reference panel).
struct ZoomableScrollView: UIViewRepresentable {
    let source: GalleryImageSource
    @Binding var zoomScale: CGFloat
    var onSingleTap: (() -> Void)?
    var annotations: [ZoomableImageAnnotation] = []
    var annotationSelectionEnabled = true
    var onImageTap: ((CGPoint) -> Void)?
    var onAnnotationTap: ((String) -> Void)?
    var imageAccessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = LayoutScrollView()
        scrollView.onViewportLayout = { [weak coordinator = context.coordinator] size in
            coordinator?.refitIfNeeded(in: size)
        }
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
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Image"
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        if ImageAnalyzer.isSupported {
            imageView.isUserInteractionEnabled = true
            imageView.addInteraction(context.coordinator.textInteraction)
        }

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
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        // Don't load here — bounds are zero until the view is laid out.
        // updateUIView fires after layout with correct bounds, and its
        // currentImageIdentity != source.identity check will trigger the initial load.

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.imageView?.accessibilityIdentifier = imageAccessibilityIdentifier
        context.coordinator.imageView?.accessibilityValue = String(format: "%.1f× zoom", Double(zoomScale))

        // If image identity changed, reload
        if context.coordinator.currentImageIdentity != source.identity {
            context.coordinator.loadImage(source: source)
        }
        context.coordinator.updateAnnotations(annotations)

        // Sync logical zoom from SwiftUI → UIKit. In SwiftUI state, 1.0 means
        // fitted-to-container; UIScrollView's actual scale may be below 1.0.
        let targetScale = MediaGalleryCalculations.platformZoomScale(
            logicalZoom: zoomScale,
            fitScale: scrollView.minimumZoomScale
        )
        if abs(scrollView.zoomScale - targetScale) > 0.01 {
            scrollView.setZoomScale(targetScale, animated: true)
        }
    }

    final class LayoutScrollView: UIScrollView {
        var onViewportLayout: ((CGSize) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onViewportLayout?(bounds.size)
        }
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        (scrollView as? LayoutScrollView)?.onViewportLayout = nil
        coordinator.loadTask?.cancel()
        coordinator.clearImageAnalysis()
        coordinator.currentLoadID = UUID()
        coordinator.imageView?.image = nil
        scrollView.delegate = nil
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate, ImageAnalysisInteractionDelegate {
        var parent: ZoomableScrollView
        var imageView: UIImageView?
        var spinner: UIActivityIndicatorView?
        var errorView: UIImageView?
        var doubleTapGesture: UITapGestureRecognizer?
        var currentImageIdentity: AnyHashable?
        var currentLoadID = UUID()
        var lastFitSize = CGSize.zero
        var isFitting = false
        var annotations: [ZoomableImageAnnotation] = []
        fileprivate var annotationViews: [String: AccessibleAnnotationImageView] = [:]
        fileprivate var loadTask: Task<Void, Never>?
        private var analysisTask: Task<Void, Never>?
        private var analysisLoadID: UUID?
        lazy var textInteraction: ImageAnalysisInteraction = {
            let interaction = ImageAnalysisInteraction(self)
            interaction.preferredInteractionTypes = .automaticTextOnly
            return interaction
        }()

        init(parent: ZoomableScrollView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
            analysisTask?.cancel()
        }

        func clearImageAnalysis() {
            analysisTask?.cancel()
            analysisTask = nil
            analysisLoadID = nil
            textInteraction.analysis = nil
        }

        private func analyzeDisplayedImage(_ image: UIImage) {
            guard ImageAnalyzer.isSupported, analysisLoadID != currentLoadID else { return }
            let loadID = currentLoadID
            analysisLoadID = loadID
            analysisTask = Task { @MainActor [weak self] in
                do {
                    let analysis = try await galleryImageAnalyzer.analyze(image, configuration: .init(.text))
                    guard !Task.isCancelled, let self, self.currentLoadID == loadID,
                          self.imageView?.image === image else { return }
                    self.textInteraction.analysis = analysis
                } catch { /* Unsupported or failed analysis leaves normal viewing intact. */ }
            }
        }

        func interaction(_ interaction: ImageAnalysisInteraction, shouldBeginAt point: CGPoint,
                         for interactionType: ImageAnalysisInteraction.InteractionTypes) -> Bool {
            guard let imageView, let scrollView = imageView.superview as? UIScrollView else { return false }
            return !parent.annotationSelectionEnabled ||
                nearestAnnotation(to: imageView.convert(point, to: scrollView), in: scrollView) == nil
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
            layoutAnnotationViews(in: scrollView)
            // Report zoom back to SwiftUI as a logical scale where 1.0 means fit.
            let scale = MediaGalleryCalculations.logicalZoomScale(
                platformZoom: scrollView.zoomScale,
                fitScale: scrollView.minimumZoomScale
            )
            if !isFitting, abs(scale - parent.zoomScale) > 0.01 {
                let loadID = currentLoadID
                DispatchQueue.main.async {
                    guard self.currentLoadID == loadID, self.imageView?.image != nil else { return }
                    self.parent.zoomScale = scale
                }
            }
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            let logicalScale = MediaGalleryCalculations.logicalZoomScale(
                platformZoom: scale,
                fitScale: scrollView.minimumZoomScale
            )
            DispatchQueue.main.async {
                self.parent.zoomScale = logicalScale
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
            guard !textInteraction.hasActiveTextSelection else { return }
            guard let scrollView = recognizer.view as? UIScrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                // Zoom out to 1x
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom to 2.5x relative to fit, centered on tap point
                let tapPoint = recognizer.location(in: imageView)
                let targetScale = MediaGalleryCalculations.platformZoomScale(
                    logicalZoom: 2.5,
                    fitScale: scrollView.minimumZoomScale
                )
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

        @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView,
                  let imageView,
                  imageView.image != nil else {
                parent.onSingleTap?()
                return
            }

            let tapInScrollView = recognizer.location(in: scrollView)
            if parent.annotationSelectionEnabled,
               let annotation = nearestAnnotation(to: tapInScrollView, in: scrollView) {
                parent.onAnnotationTap?(annotation.id)
                return
            }

            let tapInImage = recognizer.location(in: imageView)
            if textInteraction.hasActiveTextSelection || textInteraction.hasSupplementaryInterface(at: tapInImage) { return }
            guard imageView.bounds.contains(tapInImage),
                  imageView.bounds.width > 0,
                  imageView.bounds.height > 0 else {
                parent.onSingleTap?()
                return
            }
            if let onImageTap = parent.onImageTap,
               let normalizedPoint = PinnedImageCalculations.normalizedImagePoint(
                    for: tapInImage,
                    in: imageView.bounds
               ) {
                onImageTap(normalizedPoint)
            } else {
                parent.onSingleTap?()
            }
        }

        // MARK: Annotations

        @MainActor
        func updateAnnotations(_ annotations: [ZoomableImageAnnotation]) {
            self.annotations = annotations
            let currentIDs = Set(annotations.map(\.id))
            let removedIDs = annotationViews.keys.filter { !currentIDs.contains($0) }
            for id in removedIDs {
                annotationViews.removeValue(forKey: id)?.removeFromSuperview()
            }

            for annotation in annotations {
                let annotationView: AccessibleAnnotationImageView
                if let existing = annotationViews[annotation.id] {
                    annotationView = existing
                } else {
                    let configuration = UIImage.SymbolConfiguration(pointSize: 16, weight: .heavy)
                    annotationView = AccessibleAnnotationImageView(frame: .zero)
                    annotationView.image = UIImage(systemName: annotation.style.symbolName, withConfiguration: configuration)
                    annotationView.contentMode = .scaleAspectFit
                    annotationView.isAccessibilityElement = true
                    annotationView.accessibilityLabel = "Show checked item"
                    annotationView.accessibilityTraits = .button
                    annotationView.annotationID = annotation.id
                    annotationView.onActivate = { [weak self] id in
                        guard let self, self.parent.annotationSelectionEnabled else { return }
                        self.parent.onAnnotationTap?(id)
                    }
                    imageView?.addSubview(annotationView)
                    annotationViews[annotation.id] = annotationView
                }
                if annotation.style == .noteReference {
                    annotationView.image = UIImage(
                        systemName: annotation.style.symbolName,
                        withConfiguration: UIImage.SymbolConfiguration(paletteColors: [.systemRed, .white])
                    )
                    annotationView.tintColor = .systemRed
                } else {
                    annotationView.tintColor = annotation.isHighlighted ? .systemYellow : .systemGreen
                }
                annotationView.accessibilityLabel = annotation.accessibilityLabel
                annotationView.quantityBadge.text = annotation.quantityLabel
                annotationView.quantityBadge.isHidden = annotation.quantityLabel == nil
                annotationView.quantityBadge.backgroundColor = annotation.isHighlighted ? .systemYellow : .systemGreen
                annotationView.accessibilityLabel = annotation.accessibilityLabel
                annotationView.isAccessibilityElement = parent.annotationSelectionEnabled
            }

            if let scrollView = imageView?.superview as? UIScrollView {
                layoutAnnotationViews(in: scrollView)
            }
        }

        @MainActor
        private func layoutAnnotationViews(in scrollView: UIScrollView) {
            guard let imageView, scrollView.zoomScale > 0 else { return }
            let markerSize = 24 / scrollView.zoomScale
            for annotation in annotations {
                guard let annotationView = annotationViews[annotation.id] else { continue }
                annotationView.bounds = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)
                annotationView.center = PinnedImageCalculations.renderedPoint(
                    for: annotation.point,
                    in: imageView.bounds
                )
                let badgeHeight = 18 / scrollView.zoomScale
                annotationView.quantityBadge.font = .systemFont(
                    ofSize: 11 / scrollView.zoomScale,
                    weight: .bold
                )
                annotationView.quantityBadge.frame = CGRect(
                    x: markerSize * 0.68,
                    y: -1 / scrollView.zoomScale,
                    width: 22 / scrollView.zoomScale,
                    height: badgeHeight
                )
                annotationView.quantityBadge.layer.cornerRadius = badgeHeight / 2
            }
        }

        @MainActor
        private func nearestAnnotation(
            to tapPoint: CGPoint,
            in scrollView: UIScrollView
        ) -> ZoomableImageAnnotation? {
            guard let imageView else { return nil }
            let selectionRadius: CGFloat = 22
            let maximumSquaredDistance = selectionRadius * selectionRadius
            return annotations
                .compactMap { annotation -> (ZoomableImageAnnotation, CGFloat)? in
                    let imagePoint = PinnedImageCalculations.renderedPoint(
                        for: annotation.point,
                        in: imageView.bounds
                    )
                    let renderedPoint = imageView.convert(imagePoint, to: scrollView)
                    let dx = renderedPoint.x - tapPoint.x
                    let dy = renderedPoint.y - tapPoint.y
                    let distance = dx * dx + dy * dy
                    guard distance <= maximumSquaredDistance else { return nil }
                    return (annotation, distance)
                }
                .min { lhs, rhs in
                    if lhs.1 == rhs.1 { return lhs.0.id < rhs.0.id }
                    return lhs.1 < rhs.1
                }?
                .0
        }

        // MARK: Image Loading

        @MainActor
        func loadImage(source: GalleryImageSource) {
            loadTask?.cancel()
            clearImageAnalysis()
            currentImageIdentity = source.identity
            lastFitSize = .zero
            let loadID = UUID()
            currentLoadID = loadID
            spinner?.stopAnimating()
            imageView?.image = nil
            errorView?.isHidden = true
            if let image = source.image {
                displayImage(image)
                return
            }
            guard let load = source.load else { showError(); return }
            spinner?.startAnimating()
            loadTask = Task { @MainActor [weak self] in
                let image = await load()
                guard !Task.isCancelled, self?.currentLoadID == loadID else { return }
                if let image { self?.displayImage(image) }
                else { self?.showError() }
            }
        }

        @MainActor
        func refitIfNeeded(in viewport: CGSize) {
            guard viewport.width > 0, viewport.height > 0, viewport != lastFitSize,
                  let image = imageView?.image else { return }
            displayImage(image)
        }

        @MainActor
        private func displayImage(_ image: UIImage) {
            guard let imageView, let scrollView = imageView.superview as? UIScrollView else { return }
            isFitting = true
            defer { isFitting = false }
            spinner?.stopAnimating()
            errorView?.isHidden = true

            // Layout is independent of whether pixels arrive synchronously or from a URL.
            // Reset the old image transform before installing its unscaled frame.
            scrollView.minimumZoomScale = min(1, scrollView.minimumZoomScale)
            scrollView.setZoomScale(1, animated: false)
            imageView.image = image
            analyzeDisplayedImage(image)
            let imageSize = image.size
            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize

            // Fit image to screen
            let scrollBounds = scrollView.bounds
            guard scrollBounds.width > 0, scrollBounds.height > 0,
                  imageSize.width > 0, imageSize.height > 0 else { return }
            lastFitSize = scrollBounds.size

            let widthScale = scrollBounds.width / imageSize.width
            let heightScale = scrollBounds.height / imageSize.height
            let fitScale = min(widthScale, heightScale)

            scrollView.minimumZoomScale = fitScale
            scrollView.maximumZoomScale = max(fitScale * 5, 5.0)
            scrollView.zoomScale = fitScale

            centerImage(in: scrollView)
            layoutAnnotationViews(in: scrollView)

            let loadID = currentLoadID
            DispatchQueue.main.async {
                guard self.currentLoadID == loadID, self.imageView?.image != nil else { return }
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

}
#elseif canImport(AppKit)
import SwiftUI
import AppKit

private final class AccessibleAnnotationNSImageView: NSImageView {
    var annotationID = ""
    var onActivate: ((String) -> Void)?
    let quantityBadge = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        quantityBadge.alignment = .center
        quantityBadge.textColor = .white
        quantityBadge.isBordered = false
        quantityBadge.isEditable = false
        quantityBadge.drawsBackground = true
        quantityBadge.backgroundColor = .systemGreen
        quantityBadge.wantsLayer = true
        quantityBadge.isHidden = true
        addSubview(quantityBadge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?(annotationID)
        return true
    }
}

/// macOS zoomable image viewer backed by NSScrollView. Supports trackpad pinch-to-zoom,
/// double-click zoom, pan when zoomed, and async image loading with spinner/error states.
///
/// Mirrors the iOS `UIViewRepresentable` + `UIScrollView` architecture.
struct ZoomableScrollView: NSViewRepresentable {
    let source: GalleryImageSource
    @Binding var zoomScale: CGFloat
    var onSingleTap: (() -> Void)?
    var annotations: [ZoomableImageAnnotation] = []
    var annotationSelectionEnabled = true
    var onImageTap: ((CGPoint) -> Void)?
    var onAnnotationTap: ((String) -> Void)?
    var imageAccessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = LayoutScrollView()
        scrollView.onViewportLayout = { [weak coordinator = context.coordinator] size in
            coordinator?.refitIfNeeded(in: size)
        }
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
        if ImageAnalyzer.isSupported {
            let overlay = context.coordinator.textOverlay
            overlay.autoresizingMask = [.width, .height]
            overlay.frame = imageView.bounds
            overlay.trackingImageView = imageView
            imageView.addSubview(overlay)
        }

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
        let singleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleClick(_:)))
        singleClick.numberOfClicksRequired = 1
        singleClick.delaysPrimaryMouseButtonEvents = false
        scrollView.addGestureRecognizer(singleClick)

        // KVO on magnification to sync zoom back to SwiftUI
        context.coordinator.magnificationObservation = scrollView.observe(\.magnification, options: [.new]) { [weak coordinator = context.coordinator] scrollView, change in
            MainActor.assumeIsolated {
                guard let coordinator, !coordinator.isFitting, let newValue = change.newValue else { return }
                let logicalScale = MediaGalleryCalculations.logicalZoomScale(
                    platformZoom: newValue,
                    fitScale: scrollView.minMagnification
                )
                if !coordinator.isApplyingZoom,
                   abs(logicalScale - coordinator.parent.zoomScale) > 0.01 {
                    coordinator.parent.zoomScale = logicalScale
                }
                coordinator.layoutAnnotationViews(in: scrollView)
            }
        }

        // Load initial image
        context.coordinator.loadImage(source: source)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.imageView?.setAccessibilityIdentifier(imageAccessibilityIdentifier)
        context.coordinator.imageView?.setAccessibilityValue(String(format: "%.1f× zoom", Double(zoomScale)))

        // If image identity changed, reload
        if context.coordinator.currentImageIdentity != source.identity {
            context.coordinator.loadImage(source: source)
        }
        context.coordinator.updateAnnotations(annotations)

        // Sync logical zoom from SwiftUI → AppKit. In SwiftUI state, 1.0 means
        // fitted-to-container; NSScrollView's actual magnification may be below 1.0.
        let targetScale = MediaGalleryCalculations.platformZoomScale(
            logicalZoom: zoomScale,
            fitScale: scrollView.minMagnification
        )
        if abs(scrollView.magnification - targetScale) > 0.01 {
            // Animation samples are not new user zoom requests. Feeding them
            // back into the binding retargets Reset before it reaches fit.
            let coordinator = context.coordinator
            let animationID = UUID()
            coordinator.zoomAnimationID = animationID
            coordinator.isApplyingZoom = true
            NSAnimationContext.runAnimationGroup { _ in
                scrollView.animator().magnification = targetScale
            } completionHandler: { [weak coordinator] in
                MainActor.assumeIsolated {
                    guard let coordinator, coordinator.zoomAnimationID == animationID else { return }
                    coordinator.isApplyingZoom = false
                }
            }
        }
    }

    final class LayoutScrollView: NSScrollView {
        var onViewportLayout: ((CGSize) -> Void)?
        override func layout() {
            super.layout()
            onViewportLayout?(bounds.size)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        (scrollView as? LayoutScrollView)?.onViewportLayout = nil
        coordinator.loadTask?.cancel()
        coordinator.clearImageAnalysis()
        coordinator.currentLoadID = UUID()
        coordinator.imageView?.image = nil
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

    class Coordinator: NSObject, ImageAnalysisOverlayViewDelegate, @unchecked Sendable {
        var parent: ZoomableScrollView
        var imageView: NSImageView?
        var spinner: NSProgressIndicator?
        var errorView: NSImageView?
        var currentImageIdentity: AnyHashable?
        var currentLoadID = UUID()
        var lastFitSize = CGSize.zero
        var isFitting = false
        var magnificationObservation: NSKeyValueObservation?
        var isApplyingZoom = false
        var zoomAnimationID = UUID()
        var annotations: [ZoomableImageAnnotation] = []
        fileprivate var annotationViews: [String: AccessibleAnnotationNSImageView] = [:]
        fileprivate var loadTask: Task<Void, Never>?
        private var analysisTask: Task<Void, Never>?
        private var analysisLoadID: UUID?
        @MainActor lazy var textOverlay: ImageAnalysisOverlayView = {
            let overlay = ImageAnalysisOverlayView(self)
            overlay.preferredInteractionTypes = .automaticTextOnly
            return overlay
        }()

        init(parent: ZoomableScrollView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
            analysisTask?.cancel()
            magnificationObservation = nil
        }

        @MainActor func clearImageAnalysis() {
            analysisTask?.cancel()
            analysisTask = nil
            analysisLoadID = nil
            textOverlay.analysis = nil
        }

        @MainActor private func analyzeDisplayedImage(_ image: NSImage) {
            guard ImageAnalyzer.isSupported, analysisLoadID != currentLoadID else { return }
            let loadID = currentLoadID
            analysisLoadID = loadID
            analysisTask = Task { @MainActor [weak self] in
                do {
                    let analysis = try await galleryImageAnalyzer.analyze(image, orientation: .up, configuration: .init(.text))
                    guard !Task.isCancelled, let self, self.currentLoadID == loadID,
                          self.imageView?.image === image else { return }
                    self.textOverlay.analysis = analysis
                } catch { /* Unsupported or failed analysis leaves normal viewing intact. */ }
            }
        }

        @MainActor func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldBeginAt point: CGPoint,
                                   forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes) -> Bool {
            guard let imageView, let scrollView = imageView.enclosingScrollView else { return false }
            let annotation = nearestAnnotation(to: overlayView.convert(point, to: scrollView), in: scrollView)
            return (!parent.annotationSelectionEnabled || annotation == nil) &&
                (overlayView.hasInteractiveItem(at: point) || overlayView.hasActiveTextSelection)
        }

        // MARK: Double-Click

        @MainActor
        @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
            guard !textOverlay.hasActiveTextSelection else { return }
            guard let scrollView = recognizer.view as? NSScrollView else { return }

            if scrollView.magnification > scrollView.minMagnification + 0.01 {
                // Zoom out to fit
                parent.zoomScale = 1.0
            } else {
                // Zoom to 2.5x relative to fit, centered on click point
                let clickPoint = recognizer.location(in: scrollView)
                let targetScale = MediaGalleryCalculations.platformZoomScale(
                    logicalZoom: 2.5,
                    fitScale: scrollView.minMagnification
                )
                scrollView.setMagnification(targetScale, centeredAt: clickPoint)
            }
        }

        // MARK: Single-Click

        @MainActor
        @objc func handleSingleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let scrollView = recognizer.view as? NSScrollView,
                  let imageView,
                  imageView.image != nil else {
                parent.onSingleTap?()
                return
            }

            let tapInScrollView = recognizer.location(in: scrollView)
            if parent.annotationSelectionEnabled,
               let annotation = nearestAnnotation(to: tapInScrollView, in: scrollView) {
                parent.onAnnotationTap?(annotation.id)
                return
            }

            let tapInImage = recognizer.location(in: imageView)
            if textOverlay.hasActiveTextSelection || textOverlay.hasSupplementaryInterface(at: tapInImage) { return }
            guard imageView.bounds.contains(tapInImage),
                  imageView.bounds.width > 0,
                  imageView.bounds.height > 0 else {
                parent.onSingleTap?()
                return
            }
            let topLeftTap = CGPoint(
                x: tapInImage.x,
                y: imageView.bounds.height - tapInImage.y
            )
            if let onImageTap = parent.onImageTap,
               let normalizedPoint = PinnedImageCalculations.normalizedImagePoint(
                    for: topLeftTap,
                    in: imageView.bounds
               ) {
                onImageTap(normalizedPoint)
            } else {
                parent.onSingleTap?()
            }
        }

        // MARK: Annotations

        @MainActor
        func updateAnnotations(_ annotations: [ZoomableImageAnnotation]) {
            self.annotations = annotations
            let currentIDs = Set(annotations.map(\.id))
            let removedIDs = annotationViews.keys.filter { !currentIDs.contains($0) }
            for id in removedIDs {
                annotationViews.removeValue(forKey: id)?.removeFromSuperview()
            }

            for annotation in annotations {
                let annotationView: AccessibleAnnotationNSImageView
                if let existing = annotationViews[annotation.id] {
                    annotationView = existing
                } else {
                    let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .heavy)
                    let symbol = NSImage(systemSymbolName: annotation.style.symbolName, accessibilityDescription: annotation.accessibilityLabel)?
                        .withSymbolConfiguration(configuration)
                    annotationView = AccessibleAnnotationNSImageView(frame: .zero)
                    annotationView.image = symbol ?? NSImage()
                    annotationView.imageScaling = .scaleProportionallyUpOrDown
                    annotationView.setAccessibilityElement(true)
                    annotationView.setAccessibilityRole(.button)
                    annotationView.setAccessibilityLabel("Show checked item")
                    annotationView.annotationID = annotation.id
                    annotationView.onActivate = { [weak self] id in
                        guard let self, self.parent.annotationSelectionEnabled else { return }
                        self.parent.onAnnotationTap?(id)
                    }
                    imageView?.addSubview(annotationView)
                    annotationViews[annotation.id] = annotationView
                }
                if annotation.style == .noteReference {
                    annotationView.image = NSImage(systemSymbolName: annotation.style.symbolName, accessibilityDescription: annotation.accessibilityLabel)?
                        .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed, .white]))
                    annotationView.contentTintColor = nil
                } else {
                    annotationView.contentTintColor = annotation.isHighlighted ? .systemYellow : .systemGreen
                }
                annotationView.setAccessibilityLabel(annotation.accessibilityLabel)
                annotationView.quantityBadge.stringValue = annotation.quantityLabel ?? ""
                annotationView.quantityBadge.isHidden = annotation.quantityLabel == nil
                annotationView.quantityBadge.backgroundColor = annotation.isHighlighted ? .systemYellow : .systemGreen
                annotationView.setAccessibilityLabel(annotation.accessibilityLabel)
                annotationView.setAccessibilityElement(parent.annotationSelectionEnabled)
            }

            if let scrollView = imageView?.enclosingScrollView {
                layoutAnnotationViews(in: scrollView)
            }
        }

        @MainActor
        fileprivate func layoutAnnotationViews(in scrollView: NSScrollView) {
            guard let imageView, scrollView.magnification > 0 else { return }
            let markerSize = 24 / scrollView.magnification
            for annotation in annotations {
                guard let annotationView = annotationViews[annotation.id] else { continue }
                let topLeftPoint = PinnedImageCalculations.renderedPoint(
                    for: annotation.point,
                    in: imageView.bounds
                )
                annotationView.frame = CGRect(
                    x: topLeftPoint.x - markerSize / 2,
                    y: imageView.bounds.height - topLeftPoint.y - markerSize / 2,
                    width: markerSize,
                    height: markerSize
                )
                let badgeHeight = 18 / scrollView.magnification
                annotationView.quantityBadge.font = .systemFont(
                    ofSize: 11 / scrollView.magnification,
                    weight: .bold
                )
                annotationView.quantityBadge.frame = CGRect(
                    x: markerSize * 0.68,
                    y: markerSize - badgeHeight + (1 / scrollView.magnification),
                    width: 22 / scrollView.magnification,
                    height: badgeHeight
                )
                annotationView.quantityBadge.layer?.cornerRadius = badgeHeight / 2
            }
        }

        @MainActor
        private func nearestAnnotation(
            to tapPoint: CGPoint,
            in scrollView: NSScrollView
        ) -> ZoomableImageAnnotation? {
            guard let imageView else { return nil }
            let selectionRadius: CGFloat = 22
            let maximumSquaredDistance = selectionRadius * selectionRadius
            return annotations
                .compactMap { annotation -> (ZoomableImageAnnotation, CGFloat)? in
                    let topLeftPoint = PinnedImageCalculations.renderedPoint(
                        for: annotation.point,
                        in: imageView.bounds
                    )
                    let imagePoint = CGPoint(
                        x: topLeftPoint.x,
                        y: imageView.bounds.height - topLeftPoint.y
                    )
                    let renderedPoint = imageView.convert(imagePoint, to: scrollView)
                    let dx = renderedPoint.x - tapPoint.x
                    let dy = renderedPoint.y - tapPoint.y
                    let distance = dx * dx + dy * dy
                    guard distance <= maximumSquaredDistance else { return nil }
                    return (annotation, distance)
                }
                .min { lhs, rhs in
                    if lhs.1 == rhs.1 { return lhs.0.id < rhs.0.id }
                    return lhs.1 < rhs.1
                }?
                .0
        }

        // MARK: Image Loading

        @MainActor
        func loadImage(source: GalleryImageSource) {
            loadTask?.cancel()
            clearImageAnalysis()
            currentImageIdentity = source.identity
            lastFitSize = .zero
            let loadID = UUID()
            currentLoadID = loadID
            spinner?.stopAnimation(nil)
            imageView?.image = nil
            errorView?.isHidden = true
            if let image = source.image {
                displayImage(image)
                return
            }
            guard let load = source.load else { showError(); return }
            spinner?.startAnimation(nil)
            loadTask = Task { @MainActor [weak self] in
                let image = await load()
                guard !Task.isCancelled, self?.currentLoadID == loadID else { return }
                if let image { self?.displayImage(image) }
                else { self?.showError() }
            }
        }

        @MainActor
        func refitIfNeeded(in viewport: CGSize) {
            guard viewport.width > 0, viewport.height > 0, viewport != lastFitSize,
                  let image = imageView?.image else { return }
            displayImage(image)
        }

        @MainActor
        private func displayImage(_ image: NSImage) {
            guard let imageView, let scrollView = imageView.enclosingScrollView else { return }
            isFitting = true
            defer { isFitting = false }
            spinner?.stopAnimation(nil)
            errorView?.isHidden = true

            imageView.image = image
            analyzeDisplayedImage(image)
            let imageSize = image.size
            imageView.frame = CGRect(origin: .zero, size: imageSize)

            // Fit image to scroll view bounds
            let scrollBounds = scrollView.bounds
            guard scrollBounds.width > 0, scrollBounds.height > 0,
                  imageSize.width > 0, imageSize.height > 0 else { return }
            lastFitSize = scrollBounds.size

            let widthScale = scrollBounds.width / imageSize.width
            let heightScale = scrollBounds.height / imageSize.height
            let fitScale = min(widthScale, heightScale)

            // AppKit validates each bound immediately. A tiny image can need
            // a fit scale above the previous maximum; a later large image can
            // lower both bounds. Keep the intermediate range valid either way.
            let maximum = max(fitScale * 5, 5.0)
            scrollView.maxMagnification = max(scrollView.minMagnification, maximum)
            scrollView.minMagnification = fitScale
            scrollView.maxMagnification = maximum
            scrollView.magnification = fitScale

            let loadID = currentLoadID
            DispatchQueue.main.async {
                guard self.currentLoadID == loadID, self.imageView?.image != nil else { return }
                self.parent.zoomScale = 1.0
            }

            layoutAnnotationViews(in: scrollView)
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
