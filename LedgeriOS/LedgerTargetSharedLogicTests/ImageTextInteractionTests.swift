import Foundation
import SwiftUI
import VisionKit
import CoreText
import XCTest

@MainActor
final class ImageTextInteractionTests: XCTestCase {
    func testSelectionAndReplacement() async throws {
        try XCTSkipUnless(ImageAnalyzer.isSupported, "Native image analysis is unavailable on this device")
        let context = try XCTUnwrap(CGContext(data: nil, width: 900, height: 250,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 250))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "LEDGER RECEIPT 12345",
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
                         NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]))
        context.textPosition = CGPoint(x: 30, y: 110)
        CTLineDraw(line, context)
        let pixels = try XCTUnwrap(context.makeImage())
        #if os(iOS)
        let image = UIImage(cgImage: pixels)
        let imageView = UIImageView()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 900, height: 250))
        scroll.addSubview(imageView)
        #else
        let image = NSImage(cgImage: pixels, size: CGSize(width: 900, height: 250))
        let imageView = NSImageView()
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 900, height: 250))
        scroll.documentView = imageView
        #endif
        let source = GalleryImageSource(identity: "text-first", image: image)
        let coordinator = ZoomableScrollView.Coordinator(parent: .init(source: source, zoomScale: .constant(1)))
        coordinator.imageView = imageView
        #if os(iOS)
        imageView.isUserInteractionEnabled = true
        imageView.addInteraction(coordinator.textInteraction)
        let interaction = coordinator.textInteraction
        #else
        let interaction = coordinator.textOverlay
        interaction.trackingImageView = imageView
        interaction.autoresizingMask = [.width, .height]
        interaction.frame = imageView.bounds
        imageView.addSubview(interaction)
        #endif
        coordinator.loadImage(source: source)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while interaction.analysis == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        let analysis = try XCTUnwrap(interaction.analysis)
        XCTAssertTrue(analysis.transcript.contains("LEDGER RECEIPT 12345"))
        coordinator.refitIfNeeded(in: CGSize(width: 450, height: 250))
        XCTAssertTrue(interaction.analysis === analysis, "Refitting must retain analysis of the same image")
        let text = interaction.text
        interaction.selectedRanges = [text.startIndex..<text.endIndex]
        XCTAssertTrue(interaction.selectedText.contains("LEDGER RECEIPT 12345"))
        coordinator.updateAnnotations([.init(id: "existing-marker", point: CGPoint(x: 0.5, y: 0.5))])
        let markerPoint = CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        #if os(iOS)
        XCTAssertFalse(coordinator.interaction(interaction, shouldBeginAt: markerPoint, for: .textSelection),
            "Existing annotation gets priority over text interaction")
        coordinator.parent.annotationSelectionEnabled = false
        XCTAssertTrue(coordinator.interaction(interaction, shouldBeginAt: markerPoint, for: .textSelection))
        #else
        let overlayPoint = imageView.convert(markerPoint, to: interaction)
        XCTAssertFalse(coordinator.overlayView(interaction, shouldBeginAt: overlayPoint, forAnalysisType: .textSelection),
            "Existing annotation gets priority over text interaction")
        coordinator.parent.annotationSelectionEnabled = false
        XCTAssertTrue(coordinator.overlayView(interaction, shouldBeginAt: overlayPoint, forAnalysisType: .textSelection))
        #endif
        coordinator.loadImage(source: GalleryImageSource(identity: "withdrawn"))
        XCTAssertTrue(interaction.analysis == nil && interaction.selectedText.isEmpty)
        XCTAssertNil(imageView.image)
        #if os(iOS)
        ZoomableScrollView.dismantleUIView(scroll, coordinator: coordinator)
        #else
        ZoomableScrollView.dismantleNSView(scroll, coordinator: coordinator)
        #endif
        XCTAssertNil(interaction.analysis)
    }
}
