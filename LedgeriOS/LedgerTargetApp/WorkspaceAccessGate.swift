import LedgerTargetAppModel
import SwiftUI

struct WorkspaceAccessGate<Content: View>: View {
    @Bindable var access: WorkspaceAccessPresentation
    @ViewBuilder let content: () -> Content

    var body: some View {
        if access.isLocked {
            Section {
                ContentUnavailableView(
                    "Account Access Removed",
                    systemImage: "lock.shield",
                    description: Text("Your access to this Account was removed. Unsynced work is kept securely on this device; it has not been discarded.")
                )
                .accessibilityIdentifier("target-workspace-access-removed")
            }
        } else {
            content()
        }
    }
}
