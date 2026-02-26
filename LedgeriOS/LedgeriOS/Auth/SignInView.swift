import SwiftUI

struct SignInView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var onSwitchToSignUp: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Ledger")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(BrandColors.primary)

            Text("Sign in to your account")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                signIn()
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(BrandColors.primary)
                .foregroundStyle(.white)
                .cornerRadius(10)
            }
            .disabled(email.isEmpty || password.isEmpty || isLoading)

            dividerRow

            Button {
                signInWithGoogle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "g.circle.fill")
                        .font(.title2)
                    Text("Sign in with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .foregroundStyle(BrandColors.primary)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(BrandColors.primary.opacity(0.4), lineWidth: 1)
                )
            }
            .disabled(isLoading)

            Button {
                onSwitchToSignUp()
            } label: {
                Text("Create Account")
                    .foregroundStyle(BrandColors.primary)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var dividerRow: some View {
        HStack {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(.separator))
            Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(.separator))
        }
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func signInWithGoogle() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signInWithGoogle(presentingViewController: rootVC)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    SignInView(onSwitchToSignUp: {})
        .environment(AuthManager())
}
