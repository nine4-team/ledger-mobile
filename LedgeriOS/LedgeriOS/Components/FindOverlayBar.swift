import SwiftUI

/// Floating find-on-page bar, styled as a glass card overlay.
/// Triggered by Cmd+F. Shows match count, up/down navigation, and dismiss.
struct FindOverlayBar: View {
    @Environment(FindStateManager.self) private var findState
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var findState = findState

        HStack(spacing: Spacing.sm) {
            // Search field
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(BrandColors.textTertiary)

                TextField("Find on page…", text: $findState.searchText)
                    .font(Typography.body)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { findState.nextMatch() }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                if !findState.searchText.isEmpty {
                    Button {
                        findState.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(BrandColors.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))

            // Match count
            if !findState.debouncedQuery.isEmpty {
                Text(matchCountLabel)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            // Up / Down arrows
            HStack(spacing: 2) {
                Button { findState.previousMatch() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(findState.totalMatchCount == 0)

                Button { findState.nextMatch() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(findState.totalMatchCount == 0)
            }
            .foregroundStyle(findState.totalMatchCount == 0 ? BrandColors.textTertiary : BrandColors.textPrimary)

            // Dismiss
            Button { findState.deactivate() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .modifier(CardGlassModifier())
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.xs)
        .onAppear { isFocused = true }
        .onKeyPress(.escape) {
            findState.deactivate()
            return .handled
        }
    }

    private var matchCountLabel: String {
        let total = findState.totalMatchCount
        if total == 0 {
            return "No matches"
        }
        return "\(findState.currentMatchIndex + 1) of \(total)"
    }
}

#Preview {
    FindOverlayBar()
        .environment(FindStateManager())
}
