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

    var body: some View {
        ImageGalleryPresentation(
            imageIDs: images.map { AnyHashable($0.url) },
            initialIndex: initialIndex,
            isPresented: $isPresented,
            onPinImage: onPinImage.map { action in { index in action(images[index]) } },
            onSaveImage: onSaveImage.map { action in { index in try await action(images[index]) } },
            shareURL: { URL(string: images[$0].url) },
            caption: { images[$0].fileName }
        ) { context in
            ZoomableScrollView(url: URL(string: images[context.index].url),
                zoomScale: context.zoom, onSingleTap: context.onTap)
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
