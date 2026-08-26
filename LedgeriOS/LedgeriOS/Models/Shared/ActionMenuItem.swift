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
    /// Optional filter-specific summary shown at the trailing edge of a submenu row.
    var selectionSummary: String?
    /// Overrides ActionMenuSheet's legacy inference for whether Clear is visible.
    var isFilterActive: Bool?
    var onPress: (() -> Void)?
}

struct ActionMenuSubitem: Identifiable, @unchecked Sendable {
    let id: String
    let label: String
    var icon: String?
    var onPress: () -> Void
}
