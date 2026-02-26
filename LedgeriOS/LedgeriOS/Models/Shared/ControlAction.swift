import Foundation

enum ControlActionAppearance {
    case standard
    case iconOnly
    case tile
}

struct ControlAction: Identifiable {
    let id: String
    let title: String
    var variant: AppButtonVariant = .secondary
    var icon: String?
    var isDisabled: Bool = false
    var isActive: Bool = false
    var appearance: ControlActionAppearance = .standard
    var accessibilityLabel: String?
    var action: () -> Void
}
