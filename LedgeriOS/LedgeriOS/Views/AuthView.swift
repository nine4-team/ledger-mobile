import SwiftUI

struct AuthView: View {
    @State private var isSignUp = false

    var body: some View {
        Group {
            if isSignUp {
                SignUpView(onSwitchToSignIn: {
                    withAnimation { isSignUp = false }
                })
            } else {
                SignInView(onSwitchToSignUp: {
                    withAnimation { isSignUp = true }
                })
            }
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthManager())
}
