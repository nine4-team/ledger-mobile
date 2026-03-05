import Foundation

struct ActionMenuItem: Identifiable, @unchecked Sendable {
    let id: String
    let label: String
    var icon: String?
    var subactions: [ActionMenuSubitem]?
    var selectedSubactionKey: String?
    var isDestructive: Bool = false
    var isActionOnly: Bool = false
    var isSelected: Bool = false
    var onPress: (() -> Void)?
}

struct ActionMenuSubitem: Identifiable, @unchecked Sendable {
    let id: String
    let label: String
    var icon: String?
    var onPress: () -> Void
}
