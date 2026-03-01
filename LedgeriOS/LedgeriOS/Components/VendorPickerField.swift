import SwiftUI
import FirebaseFirestore

/// Inline vendor/source picker that replaces a plain text FormField.
///
/// Shows a scrollable list of preset vendors (from VendorDefaults) with radio-button
/// selection, plus an "Other" option for free-text entry. Falls back to a plain
/// FormField when no vendor presets are configured.
struct VendorPickerField: View {
    @Binding var value: String
    var label: String = "Source"

    @Environment(AccountContext.self) private var accountContext

    @State private var vendors: [String] = []
    @State private var otherMode = false
    @State private var listener: ListenerRegistration?
    @FocusState private var otherFieldFocused: Bool

    private let service = VendorDefaultsService(syncTracker: NoOpSyncTracker())

    /// Filtered vendor list (no empty strings, deduplicated).
    private var displayVendors: [String] {
        var seen = Set<String>()
        return vendors.filter { v in
            let trimmed = v.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return false }
            seen.insert(trimmed)
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if displayVendors.isEmpty {
                // Fallback: no vendors configured — plain text input
                FormField(label: label, text: $value, placeholder: "e.g. Home Depot, Amazon")
            } else {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(BrandColors.textSecondary)

                Divider()

                ScrollView {
                    VStack(spacing: Spacing.xs) {
                        ForEach(displayVendors, id: \.self) { vendor in
                            vendorOption(vendor, isSelected: !otherMode && value == vendor) {
                                otherMode = false
                                otherFieldFocused = false
                                value = vendor
                            }
                        }

                        vendorOption("Other", isSelected: otherMode) {
                            otherMode = true
                            value = ""
                            otherFieldFocused = true
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .frame(maxHeight: 200)

                Divider()

                if otherMode {
                    TextField("e.g. Home Depot, Amazon", text: $value)
                        .font(Typography.input)
                        .padding(.horizontal, Spacing.md)
                        .frame(minHeight: 44)
                        .background(BrandColors.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                        )
                        .focused($otherFieldFocused)
                }
            }
        }
        .onAppear { startListening() }
        .onDisappear { listener?.remove() }
    }

    // MARK: - Vendor Option Row

    @ViewBuilder
    private func vendorOption(_ name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                // Radio circle
                Circle()
                    .strokeBorder(isSelected ? BrandColors.primary : BrandColors.border, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .overlay {
                        if isSelected {
                            Circle()
                                .fill(BrandColors.primary)
                                .frame(width: 10, height: 10)
                        }
                    }

                Text(name)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background(isSelected ? BrandColors.inputBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                    .stroke(isSelected ? BrandColors.primary : BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func startListening() {
        guard let accountId = accountContext.currentAccountId else { return }

        Task { try? await service.initializeDefaults(accountId: accountId) }

        listener = service.subscribe(accountId: accountId) { defaults in
            vendors = defaults?.vendors ?? []

            // Auto-enable "Other" mode if current value doesn't match any preset
            let available = displayVendors
            if !available.isEmpty && !value.isEmpty && !available.contains(value) {
                otherMode = true
            }
        }
    }
}

#Preview("With Vendors") {
    @Previewable @State var source = "Amazon"
    VendorPickerField(value: $source)
        .padding()
}

#Preview("Empty Value") {
    @Previewable @State var source = ""
    VendorPickerField(value: $source)
        .padding()
}
