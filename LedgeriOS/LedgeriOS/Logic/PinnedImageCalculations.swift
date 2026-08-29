import Foundation
import CoreGraphics

enum PinnedImageCalculations {

    /// Item IDs that have a linked checkmark in any of the supplied attachments.
    static func markedItemIds(in attachments: [AttachmentRef]) -> Set<String> {
        Set(attachments.flatMap { attachment in
            (attachment.checkmarks ?? []).compactMap(\.itemId)
        })
    }

    /// Places or moves an item's single linked checkmark. Any previous mark for
    /// the item is removed from every attachment before the replacement is added.
    static func placingCheckmark(
        for itemId: String,
        at normalizedPoint: CGPoint,
        in attachmentURL: String,
        attachments: [AttachmentRef],
        checkmarkId: String = UUID().uuidString
    ) -> [AttachmentRef] {
        attachments.map { attachment in
            var updated = attachment
            var marks = (attachment.checkmarks ?? []).filter { $0.itemId != itemId }
            if attachment.url == attachmentURL {
                marks.append(ImageCheckmark(
                    id: checkmarkId,
                    x: Double(normalizedPoint.x),
                    y: Double(normalizedPoint.y),
                    itemId: itemId
                ))
            }
            updated.checkmarks = marks.isEmpty ? nil : marks
            return updated
        }
    }

    /// Removes linked marks for items that no longer belong to the space while
    /// preserving legacy unassigned marks and marks for all other items.
    static func removingCheckmarks(
        for itemIds: Set<String>,
        from attachments: [AttachmentRef]
    ) -> [AttachmentRef] {
        guard !itemIds.isEmpty else { return attachments }
        return attachments.map { attachment in
            var updated = attachment
            let marks = (attachment.checkmarks ?? []).filter { mark in
                guard let itemId = mark.itemId else { return true }
                return !itemIds.contains(itemId)
            }
            updated.checkmarks = marks.isEmpty ? nil : marks
            return updated
        }
    }

    /// The image frame produced by aspect-fit inside a container.
    static func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }

        let scale = Swift.min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    /// Converts a tap in container coordinates into normalized image coordinates.
    static func normalizedImagePoint(for tapPoint: CGPoint, in imageRect: CGRect) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }

        return CGPoint(
            x: Swift.min(Swift.max((tapPoint.x - imageRect.minX) / imageRect.width, 0), 1),
            y: Swift.min(Swift.max((tapPoint.y - imageRect.minY) / imageRect.height, 0), 1)
        )
    }

    /// Converts normalized image coordinates back into container coordinates for rendering.
    static func renderedPoint(for normalizedPoint: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + normalizedPoint.x * imageRect.width,
            y: imageRect.minY + normalizedPoint.y * imageRect.height
        )
    }

    /// Clamp a panel height fraction to valid range.
    static func clampedFraction(_ fraction: CGFloat, min minVal: CGFloat = 0.20, max maxVal: CGFloat = 0.50) -> CGFloat {
        Swift.min(maxVal, Swift.max(minVal, fraction))
    }

    /// Compute new fraction after a drag gesture.
    static func fractionAfterDrag(
        startFraction: CGFloat,
        translationHeight: CGFloat,
        totalHeight: CGFloat,
        min minVal: CGFloat = 0.20,
        max maxVal: CGFloat = 0.50
    ) -> CGFloat {
        guard totalHeight > 0 else { return startFraction }
        let raw = startFraction + translationHeight / totalHeight
        return clampedFraction(raw, min: minVal, max: maxVal)
    }

    /// Whether an attachment can be pinned (image or PDF, and not mid-upload).
    static func canPin(_ attachment: AttachmentRef) -> Bool {
        (attachment.kind == .image || attachment.kind == .pdf) && !(attachment.isUploading ?? false)
    }
}
