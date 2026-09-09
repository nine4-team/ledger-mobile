import SwiftUI

/// Presentation only: callers supply already-authorized, decoded pixels.
/// The document is sized to fit, so native magnification is the logical 1...5 scale.
struct DownloadedImageZoomSurface: View {
    let image: CGImage
    @Binding var zoomScale: CGFloat
    var onPage: ((Int) -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        #if os(iOS)
        DownloadedImageNativeSurface(image: image, zoomScale: $zoomScale,
            onPage: onPage, onDismiss: onDismiss)
        #else
        DownloadedImageNativeSurface(image: image, zoomScale: $zoomScale)
        #endif
    }
}

private func boundedImageZoom(_ value: CGFloat) -> CGFloat {
    value.isFinite ? min(5, max(1, value)) : 1
}

private func fittedImageSize(_ image: CGImage, in viewport: CGSize) -> CGSize {
    let scale = min(viewport.width / CGFloat(image.width), viewport.height / CGFloat(image.height))
    return CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
}

#if os(iOS)
import UIKit

private struct DownloadedImageNativeSurface: UIViewRepresentable {
    let image: CGImage
    @Binding var zoomScale: CGFloat
    let onPage: ((Int) -> Void)?
    let onDismiss: (() -> Void)?

    func makeUIView(context: Context) -> ImageScrollView { ImageScrollView() }
    func updateUIView(_ view: ImageScrollView, context: Context) {
        view.onPage = onPage
        view.onDismiss = onDismiss
        view.onZoom = { value, expected in
            guard zoomScale == expected else { return false }
            zoomScale = value
            return true
        }
        view.update(image: image, zoom: zoomScale)
    }
    static func dismantleUIView(_ view: ImageScrollView, coordinator: ()) {
        view.onZoom = nil; view.onPage = nil; view.onDismiss = nil
    }

    final class ImageScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let pixels = UIImageView()
        var source: CGImage?
        var viewport = CGSize.zero
        var onZoom: ((CGFloat, CGFloat) -> Bool)?
        var boundZoom: CGFloat = 1
        var reporting = false
        var arranging = false
        var onPage: ((Int) -> Void)?
        var onDismiss: (() -> Void)?
        private lazy var navigationPan = UIPanGestureRecognizer(target: self, action: #selector(navigate(_:)))
        private var draggingVertically = false

        init() {
            super.init(frame: .zero)
            delegate = self
            minimumZoomScale = 1
            maximumZoomScale = 5
            bouncesZoom = false
            contentInsetAdjustmentBehavior = .never
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            addSubview(pixels)
            pixels.isAccessibilityElement = true
            pixels.accessibilityIdentifier = "target-item-image-rendered"
            pixels.accessibilityLabel = "Item image"
            let gesture = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
            gesture.numberOfTapsRequired = 2
            addGestureRecognizer(gesture)
            navigationPan.maximumNumberOfTouches = 1
            navigationPan.delegate = self
            addGestureRecognizer(navigationPan)
            // At fit, this gesture owns paging/dismissal. When zoomed it
            // declines immediately, leaving the native scroll view's pan intact.
            panGestureRecognizer.require(toFail: navigationPan)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === navigationPan else {
                return super.gestureRecognizerShouldBegin(gestureRecognizer)
            }
            guard zoomScale <= 1.01 else { return false }
            let velocity = navigationPan.velocity(in: self)
            return abs(velocity.x) > abs(velocity.y) ? onPage != nil : onDismiss != nil
        }

        @objc private func navigate(_ gesture: UIPanGestureRecognizer) {
            let delta = gesture.translation(in: superview)
            switch gesture.state {
            case .began:
                let velocity = gesture.velocity(in: superview)
                draggingVertically = abs(velocity.y) >= abs(velocity.x)
            case .changed:
                if draggingVertically, onDismiss != nil {
                    transform = CGAffineTransform(translationX: 0, y: max(-300, min(300, delta.y)))
                    alpha = max(0.4, 1 - abs(delta.y) / 300)
                }
            case .ended, .cancelled, .failed:
                let completed = gesture.state == .ended && zoomScale <= 1.01
                UIView.animate(withDuration: 0.2) { self.transform = .identity; self.alpha = 1 }
                if completed {
                    if draggingVertically {
                        if abs(delta.y) > 90 { onDismiss?() }
                    } else if abs(delta.x) > 50 { onPage?(delta.x < 0 ? 1 : -1) }
                }
                draggingVertically = false
            default: break
            }
        }

        func update(image: CGImage, zoom: CGFloat) {
            // An unchanged SwiftUI echo must not undo a newer native gesture;
            // a changed binding must still win while a report is queued.
            let bindingChanged = zoom != boundZoom
            boundZoom = zoom
            if source !== image {
                source = image
                pixels.image = UIImage(cgImage: image)
                viewport = .zero
                setNeedsLayout()
            } else if bindingChanged,
                      abs(zoomScale - boundedImageZoom(zoom)) > 0.001 {
                setZoomScale(boundedImageZoom(zoom), animated: false)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard !arranging, let source, bounds.width > 0, bounds.height > 0 else { return }
            arranging = true
            defer { arranging = false }
            if viewport != bounds.size {
                viewport = bounds.size
                setZoomScale(1, animated: false)
                pixels.frame = CGRect(origin: .zero, size: fittedImageSize(source, in: viewport))
                contentSize = pixels.frame.size
                centerPixels()
                contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
                reportZoom()
            }
            centerPixels()
        }

        func centerPixels() {
            let x = max(0, (bounds.width - contentSize.width) / 2)
            let y = max(0, (bounds.height - contentSize.height) / 2)
            contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { pixels }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerPixels()
            reportZoom()
        }
        func reportZoom() {
            guard !reporting else { return }
            reporting = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reporting = false
                let value = boundedImageZoom(self.zoomScale)
                self.pixels.accessibilityValue = String(format: "%.1f× zoom", Double(value))
                if self.onZoom?(value, self.boundZoom) == true { self.boundZoom = value }
            }
        }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            if zoomScale > 1.01 {
                setZoomScale(1, animated: false)
            } else {
                let point = gesture.location(in: pixels)
                let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
                zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                width: size.width, height: size.height), animated: false)
            }
        }
    }
}
#elseif os(macOS)
import AppKit

private struct DownloadedImageNativeSurface: NSViewRepresentable {
    let image: CGImage
    @Binding var zoomScale: CGFloat

    func makeNSView(context: Context) -> ImageScrollView { ImageScrollView() }
    func updateNSView(_ view: ImageScrollView, context: Context) {
        view.onZoom = { value, expected in
            guard zoomScale == expected else { return false }
            zoomScale = value
            return true
        }
        view.update(image: image, zoom: zoomScale)
    }
    static func dismantleNSView(_ view: ImageScrollView, coordinator: ()) {
        view.onZoom = nil
        view.observation = nil
    }

    final class CenteringClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var result = super.constrainBoundsRect(proposedBounds)
            if let documentView {
                if documentView.frame.width < result.width {
                    result.origin.x = (documentView.frame.width - result.width) / 2
                }
                if documentView.frame.height < result.height {
                    result.origin.y = (documentView.frame.height - result.height) / 2
                }
            }
            return result
        }
    }

    final class ImageScrollView: NSScrollView {
        let pixels = NSImageView()
        var source: CGImage?
        var viewport = CGSize.zero
        var onZoom: ((CGFloat, CGFloat) -> Bool)?
        var boundZoom: CGFloat = 1
        var observation: NSKeyValueObservation?
        var reporting = false
        var arranging = false
        var lastDrag = CGPoint.zero

        init() {
            super.init(frame: .zero)
            contentView = CenteringClipView()
            drawsBackground = false
            contentView.drawsBackground = false
            allowsMagnification = true
            minMagnification = 1
            maxMagnification = 5
            hasHorizontalScroller = false
            hasVerticalScroller = false
            pixels.imageScaling = .scaleAxesIndependently
            pixels.setAccessibilityElement(true)
            pixels.setAccessibilityIdentifier("target-item-image-rendered")
            pixels.setAccessibilityLabel("Item image")
            documentView = pixels
            let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(doubleClick(_:)))
            doubleClick.numberOfClicksRequired = 2
            addGestureRecognizer(doubleClick)
            addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(pan(_:))))
            observation = observe(\.magnification, options: [.new]) { [weak self] _, _ in
                // AppKit magnification changes are main-thread events.
                MainActor.assumeIsolated { self?.reportZoom() }
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func update(image: CGImage, zoom: CGFloat) {
            // An unchanged SwiftUI echo must not undo a newer native gesture;
            // a changed binding must still win while a report is queued.
            let bindingChanged = zoom != boundZoom
            boundZoom = zoom
            if source !== image {
                source = image
                pixels.image = NSImage(cgImage: image, size: .zero)
                viewport = .zero
                needsLayout = true
            } else if bindingChanged, abs(magnification - boundedImageZoom(zoom)) > 0.001 {
                magnification = boundedImageZoom(zoom)
            }
        }
        override func layout() {
            super.layout()
            guard !arranging, let source, bounds.width > 0, bounds.height > 0,
                  viewport != bounds.size else { return }
            arranging = true
            defer { arranging = false }
            viewport = bounds.size
            magnification = 1
            pixels.frame = CGRect(origin: .zero, size: fittedImageSize(source, in: viewport))
            contentView.scroll(to: contentView.constrainBoundsRect(CGRect(origin: .zero, size: contentView.bounds.size)).origin)
            reflectScrolledClipView(contentView)
            reportZoom()
        }
        func reportZoom() {
            guard !reporting else { return }
            reporting = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reporting = false
                let value = boundedImageZoom(self.magnification)
                self.pixels.setAccessibilityValue(String(format: "%.1f× zoom", Double(value)))
                if self.onZoom?(value, self.boundZoom) == true { self.boundZoom = value }
            }
        }
        @objc func doubleClick(_ gesture: NSClickGestureRecognizer) {
            setMagnification(magnification > 1.01 ? 1 : 2.5,
                             centeredAt: gesture.location(in: contentView))
        }
        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            let translation = gesture.translation(in: self)
            if gesture.state == .began { lastDrag = .zero }
            defer { lastDrag = translation }
            guard magnification > 1.01 else { return }
            let proposed = contentView.bounds.offsetBy(
                dx: -(translation.x - lastDrag.x) / magnification,
                dy: -(translation.y - lastDrag.y) / magnification)
            contentView.scroll(to: contentView.constrainBoundsRect(proposed).origin)
            reflectScrolledClipView(contentView)
        }
    }
}
#endif
