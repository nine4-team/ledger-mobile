import Foundation
import CoreGraphics

struct PhotoCheckProgress: Equatable {
    let checkedCount: Int
    let totalCount: Int

    var remainingCount: Int {
        max(totalCount - checkedCount, 0)
    }

    var percentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(checkedCount) / Double(totalCount) * 100
    }

    var isComplete: Bool {
        totalCount > 0 && remainingCount == 0
    }
}

struct PhotoCheckmarkPlacementSession: Equatable {
    let attachmentURL: String
    let itemName: String
    let assignments: [[String]]
    var points: [CGPoint] = []

    var totalItemCount: Int { assignments.reduce(0) { $0 + $1.count } }
    var nextLocationIndex: Int? { points.count < assignments.count ? points.count : nil }
    var isReadyToSave: Bool { !assignments.isEmpty && points.count == assignments.count }

    mutating func place(at point: CGPoint) {
        guard points.count < assignments.count else { return }
        points.append(point)
    }

    mutating func redo() {
        points.removeAll()
    }
}

enum PinnedImageCalculations {

    /// Item IDs that have a linked checkmark in any of the supplied attachments.
    static func markedItemIds(in attachments: [AttachmentRef]) -> Set<String> {
        Set(attachments.flatMap { attachment in
            (attachment.checkmarks ?? []).flatMap(\.linkedItemIds)
        })
    }

    /// Splits concrete item IDs across one or two photo locations. The default
    /// two-location split puts the extra item in the first location.
    static func placementAssignments(
        itemIds: [String],
        locationCount: Int,
        firstLocationCount: Int? = nil
    ) -> [[String]] {
        var seen: Set<String> = []
        let uniqueIds = itemIds.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !uniqueIds.isEmpty else { return [] }
        guard locationCount == 2, uniqueIds.count > 1 else { return [uniqueIds] }

        let defaultFirstCount = (uniqueIds.count + 1) / 2
        let resolvedFirstCount = min(
            max(firstLocationCount ?? defaultFirstCount, 1),
            uniqueIds.count - 1
        )
        return [
            Array(uniqueIds.prefix(resolvedFirstCount)),
            Array(uniqueIds.dropFirst(resolvedFirstCount)),
        ]
    }

    /// Progress for the items currently assigned to the space. Marks linked to
    /// moved/deleted items and legacy unassigned marks do not count toward it.
    static func photoCheckProgress(
        itemIds: Set<String>,
        attachments: [AttachmentRef]
    ) -> PhotoCheckProgress {
        let checkedItemIds = markedItemIds(in: attachments).intersection(itemIds)
        return PhotoCheckProgress(
            checkedCount: checkedItemIds.count,
            totalCount: itemIds.count
        )
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
            var marks = removingItemLinks([itemId], from: attachment.checkmarks ?? [])
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

    /// Atomically replaces every selected item's existing photo association and
    /// writes one marker for each completed placement assignment.
    static func placingCheckmarks(
        assignments: [[String]],
        at normalizedPoints: [CGPoint],
        in attachmentURL: String,
        attachments: [AttachmentRef],
        checkmarkIds: [String]? = nil
    ) -> [AttachmentRef] {
        guard assignments.count == normalizedPoints.count, !assignments.isEmpty else {
            return attachments
        }
        let selectedItemIds = Set(assignments.flatMap { $0 })
        return attachments.map { attachment in
            var updated = attachment
            var marks = removingItemLinks(selectedItemIds, from: attachment.checkmarks ?? [])
            if attachment.url == attachmentURL {
                for (index, assignment) in assignments.enumerated() where !assignment.isEmpty {
                    let markId = checkmarkIds?.indices.contains(index) == true
                        ? checkmarkIds![index]
                        : UUID().uuidString
                    marks.append(ImageCheckmark(
                        id: markId,
                        x: Double(normalizedPoints[index].x),
                        y: Double(normalizedPoints[index].y),
                        itemId: assignment.first,
                        itemIds: assignment.count > 1 ? assignment : nil
                    ))
                }
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
            let marks = removingItemLinks(itemIds, from: attachment.checkmarks ?? [])
            updated.checkmarks = marks.isEmpty ? nil : marks
            return updated
        }
    }

    private static func removingItemLinks(
        _ itemIds: Set<String>,
        from marks: [ImageCheckmark]
    ) -> [ImageCheckmark] {
        marks.compactMap { mark in
            let linkedIds = mark.linkedItemIds
            guard !linkedIds.isEmpty else { return mark }
            let remainingIds = linkedIds.filter { !itemIds.contains($0) }
            guard !remainingIds.isEmpty else { return nil }
            return mark.linking(remainingIds)
        }
    }

    /// Removes every photo checkmark while preserving the attachments themselves.
    static func clearingCheckmarks(from attachments: [AttachmentRef]) -> [AttachmentRef] {
        attachments.map { attachment in
            var updated = attachment
            updated.checkmarks = nil
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

    /// Applies the same center-based zoom and pan transform used by the photo editor.
    static func zoomedPoint(
        for point: CGPoint,
        imageRect: CGRect,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        CGPoint(
            x: imageRect.midX + (point.x - imageRect.midX) * scale + offset.width,
            y: imageRect.midY + (point.y - imageRect.midY) * scale + offset.height
        )
    }

    /// Reverses the photo editor's zoom and pan transform before normalizing a tap.
    static func unzoomedPoint(
        for point: CGPoint,
        imageRect: CGRect,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint? {
        guard scale > 0 else { return nil }
        return CGPoint(
            x: imageRect.midX + (point.x - imageRect.midX - offset.width) / scale,
            y: imageRect.midY + (point.y - imageRect.midY - offset.height) / scale
        )
    }

    /// Keeps the zoomed photo within reach while allowing free movement along an
    /// axis only when the scaled image is larger than its viewport.
    static func clampedPanOffset(
        _ offset: CGSize,
        imageRect: CGRect,
        containerSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let maxX = Swift.max(0, (imageRect.width * scale - containerSize.width) / 2)
        let maxY = Swift.max(0, (imageRect.height * scale - containerSize.height) / 2)
        return CGSize(
            width: Swift.min(Swift.max(offset.width, -maxX), maxX),
            height: Swift.min(Swift.max(offset.height, -maxY), maxY)
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
