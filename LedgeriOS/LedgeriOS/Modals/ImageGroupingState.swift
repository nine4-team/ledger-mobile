import Foundation

struct ImageGroup: Identifiable {
    let id = UUID()
    var images: [AttachmentRef]
}

@Observable
final class ImageGroupingState {
    let allImages: [AttachmentRef]
    var groups: [ImageGroup] = []
    var selectedUrls: Set<String> = []

    var ungroupedImages: [AttachmentRef] {
        let groupedUrls = Set(groups.flatMap { $0.images.map(\.url) })
        return allImages.filter { !groupedUrls.contains($0.url) }
    }

    var canGroup: Bool { !selectedUrls.isEmpty }
    var canCreate: Bool { !groups.isEmpty }

    init(allImages: [AttachmentRef]) {
        // Deduplicate by URL
        var seen = Set<String>()
        self.allImages = allImages.filter { seen.insert($0.url).inserted }
    }

    func toggleSelection(_ url: String) {
        if selectedUrls.contains(url) {
            selectedUrls.remove(url)
        } else {
            selectedUrls.insert(url)
        }
    }

    func clearSelection() {
        selectedUrls.removeAll()
    }

    func groupSelected() {
        let images = allImages.filter { selectedUrls.contains($0.url) }
        guard !images.isEmpty else { return }
        groups.append(ImageGroup(images: images))
        selectedUrls.removeAll()
    }

    func ungroup(_ group: ImageGroup) {
        groups.removeAll { $0.id == group.id }
    }
}
