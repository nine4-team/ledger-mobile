import SwiftUI
import FirebaseAuth

struct AuthView: View {
    @Environment(AuthManager.self) private var authManager

    enum AuthMode: String, CaseIterable {
        case signIn = "Sign In"
        case createAccount = "Create Account"
    }

    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var isCreatingAccount: Bool { authMode == .createAccount }

    private var passwordsMatch: Bool {
        !confirmPassword.isEmpty && password == confirmPassword
    }

    private var canSubmitEmail: Bool {
        if isCreatingAccount {
            return !email.isEmpty && !password.isEmpty && passwordsMatch && !isLoading
        }
        return !email.isEmpty && !password.isEmpty && !isLoading
    }

    var body: some View {
        AdaptiveContentWidth(maxWidth: Dimensions.formMaxWidth) {
            VStack(spacing: Spacing.xl) {
                Spacer()

                Text("Ledger")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(BrandColors.primary)

                Text("For Interior Designers by Interior Designers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SegmentedControl(selection: $authMode, options: AuthMode.allCases.map {
                    SegmentOption(id: $0, label: $0.rawValue)
                })

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if let detail = authManager.errorDetail {
                    Text(detail)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.sm)
                        .background(Color.secondarySystemBackground)
                        .cornerRadius(Dimensions.inputRadius)
                }

                emailFields

                primaryButton

                dividerRow

                googleButton

                Spacer()
            }
            .padding(.horizontal, Spacing.xxl)
            .animation(.default, value: authMode)
        }
        .onChange(of: authMode) {
            errorMessage = nil
            confirmPassword = ""
        }
    }

    // MARK: - Email Fields

    private var emailFields: some View {
        VStack(spacing: Spacing.md) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .platformKeyboardType(.emailAddress)
                .autocorrectionDisabled()
                .platformTextInputAutocapitalization(.never)
                .padding()
                .background(Color.secondarySystemBackground)
                .cornerRadius(Dimensions.inputRadius)

            SecureField("Password", text: $password)
                .textContentType(isCreatingAccount ? .newPassword : .password)
                .padding()
                .background(Color.secondarySystemBackground)
                .cornerRadius(Dimensions.inputRadius)

            if isCreatingAccount {
                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(Dimensions.inputRadius)
            }

            if isCreatingAccount && !confirmPassword.isEmpty && !passwordsMatch {
                Text("Passwords do not match")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Buttons

    private var primaryButton: some View {
        Button {
            isCreatingAccount ? signUp() : signIn()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(isCreatingAccount ? "Create Account" : "Sign In")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(BrandColors.primary)
            .foregroundStyle(.white)
            .cornerRadius(Dimensions.buttonRadius)
        }
        .disabled(!canSubmitEmail)
    }

    private var dividerRow: some View {
        HStack {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.platformSeparator)
            Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.platformSeparator)
        }
    }

    private var googleButton: some View {
        Button {
            signInWithGoogle()
        } label: {
            HStack(spacing: Spacing.sm) {
                googleLogo
                    .frame(width: 20, height: 20)
                Text(isCreatingAccount ? "Sign up with Google" : "Sign in with Google")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.background)
            .foregroundStyle(.primary)
            .cornerRadius(Dimensions.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                    .stroke(Color.platformSeparator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    @ViewBuilder
    private var googleLogo: some View {
        #if canImport(UIKit)
        if let bundle = googleSignInBundle,
           let uiImage = UIImage(named: "google", in: bundle, compatibleWith: nil) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "g.circle.fill")
                .font(.title3)
                .foregroundStyle(BrandColors.primary)
        }
        #else
        Image(systemName: "g.circle.fill")
            .font(.title3)
            .foregroundStyle(BrandColors.primary)
        #endif
    }

    private var googleSignInBundle: Bundle? {
        guard let url = Bundle.main.url(forResource: "GoogleSignIn_GoogleSignIn", withExtension: "bundle") else { return nil }
        return Bundle(url: url)
    }

    // MARK: - Actions

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

    private func signUp() {
        guard passwordsMatch else {
            errorMessage = "Passwords do not match"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signUp(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signInWithGoogle()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthManager())
}
