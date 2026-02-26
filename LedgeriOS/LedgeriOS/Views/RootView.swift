import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.default, value: authManager.isAuthenticated)
    }
}

#Preview {
    RootView()
        .environment(AuthManager())
}
