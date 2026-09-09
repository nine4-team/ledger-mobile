import SwiftUI
import ImageIO
import LedgerTargetCore
import LedgerTargetAppModel

private struct ItemThumbnailViewportKey: EnvironmentKey {
    static let defaultValue = CGRect.zero
}

extension EnvironmentValues {
    var itemThumbnailViewport: CGRect {
        get { self[ItemThumbnailViewportKey.self] }
        set { self[ItemThumbnailViewportKey.self] = newValue }
    }
}

private struct ItemThumbnailViewport: ViewModifier {
    @State private var frame = CGRect.zero
    func body(content: Content) -> some View {
        content.environment(\.itemThumbnailViewport, frame)
            .background(GeometryReader { geometry in
                Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, value in frame = value }
            })
    }
}

extension View {
    /// Apply to the containing scroll viewport, not the full scroll content.
    func itemThumbnailViewport() -> some View { modifier(ItemThumbnailViewport()) }
}

struct DownloadedItemThumbnailView: View {
    let accountId: AccountID
    let itemId: ItemID
    let reader: any DownloadedItemImageReading
    @Environment(\.itemThumbnailViewport) private var viewport
    @State private var frame = CGRect.zero
    @State private var model = DownloadedItemImagesModel()
    @State private var rendered: CGImage?
    @State private var renderedFor: DownloadedItemImage?
    @State private var retry = UUID()

    private var visible: Bool { !viewport.isEmpty && !frame.isEmpty && viewport.intersects(frame) }
    private var selected: DownloadedItemImage? {
        guard visible, case .downloaded(let catalog) = model.state,
              catalog.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8),
              catalog.itemId.rawValue.utf8.elementsEqual(itemId.rawValue.utf8),
              catalog.isComplete else { return nil }
        return catalog.primaryImage
    }
    private struct Scope: Equatable {
        let account: [UInt8]
        let item: [UInt8]
        let visible: Bool
        let retry: UUID
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let selected, selected == renderedFor, let rendered {
                Image(decorative: rendered, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 108, height: 108).clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        // AppKit may omit the grouped element's value, so expose the actual
        // rendered state in its label as well.
        .accessibilityLabel(renderedFor != nil && renderedFor == selected
            ? "Item thumbnail, Downloaded" : "Item thumbnail, Unavailable")
        .accessibilityValue(renderedFor != nil && renderedFor == selected ? "Downloaded" : "Unavailable")
        .accessibilityIdentifier("target-item-thumbnail-\(itemId.rawValue)")
        .accessibilityAction(named: "Retry thumbnail") { retry = UUID() }
        .contextMenu { Button("Retry thumbnail") { retry = UUID() } }
        .background(GeometryReader { geometry in
            Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, value in frame = value }
        })
        .task(id: Scope(account: Array(accountId.rawValue.utf8),item: Array(itemId.rawValue.utf8),visible: visible,retry: retry)) {
            rendered = nil; renderedFor = nil; model.clear()
            guard visible else { return }
            await model.load(accountId: accountId,itemId: itemId,reader: reader)
        }
        .task(id: selected) {
            rendered = nil; renderedFor = nil
            guard let image = selected, image.thumbnail != nil else { return }
            do {
                guard let bytes = try await reader.loadDownloadedItemThumbnail(accountId: accountId,itemId: itemId,
                    image: image,allowDownload: true) else { return }
                try Task.checkCancellation()
                let decode = Task.detached(priority: .utility) { () -> CGImage? in
                    guard !Task.isCancelled else { return nil }
                    guard let source = CGImageSourceCreateWithData(bytes as CFData,
                        [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source,0,[
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 300
                    ] as CFDictionary)
                }
                let decoded = await withTaskCancellationHandler {
                    await decode.value
                } onCancel: { decode.cancel() }
                try Task.checkCancellation()
                guard selected == image, let decoded else { return }
                rendered = decoded; renderedFor = image
            } catch { }
        }
        .onDisappear { model.clear(); rendered = nil; renderedFor = nil }
    }
}
