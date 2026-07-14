import SwiftUI
import FirebaseFirestore

/// Picker-button for vendor/source selection.
///
/// Displays as a tappable row (like transaction/space pickers) showing the current
/// vendor value with a chevron. Tapping sets `showPicker` to true — the parent view
/// must attach `.adaptivePresentation(isPresented:style:.picker)` with a
/// `VendorPickerModal` at the top level of its body.
///
/// Falls back to a plain FormField when no vendor presets are configured.
struct VendorPickerField: View {
    @Binding var value: String
    var label: String = "Source"
    @Binding var showPicker: Bool
    var fixedOptions: [String] = []
    var excludedOptions: Set<String> = []

    @Environment(AccountContext.self) private var accountContext

    @State private var vendors: [String] = VendorDefaultsService.defaultVendors
    @State private var listener: ListenerRegistration?

    private let service = VendorDefaultsService()

    /// Filtered vendor list (no empty strings, deduplicated).
    private var displayVendors: [String] {
        VendorDefaultsService.displayVendorOptions(
            fixedOptions: fixedOptions,
            vendors: vendors,
            excluding: excludedOptions
        )
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

                Button { showPicker = true } label: {
                    HStack {
                        Text(value.isEmpty ? "Select Source" : value)
                            .foregroundStyle(value.isEmpty ? BrandColors.textSecondary : BrandColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    .font(Typography.input)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                            .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { startListening() }
        .onDisappear { listener?.remove() }
    }

    // MARK: - Data

    private func startListening() {
        guard let accountId = accountContext.currentAccountId else {
            print("🔴 [VendorPicker] No accountId — skipping vendor load")
            return
        }

        print("🟢 [VendorPicker] startListening for account: \(accountId)")

        Task { try? await service.initializeDefaults(accountId: accountId) }

        listener = service.subscribe(accountId: accountId) { defaults in
            print("🟡 [VendorPicker] Listener fired — defaults: \(defaults == nil ? "nil" : "exists"), vendors: \(defaults?.vendors.count ?? -1)")
            if let loaded = defaults?.vendors, !loaded.isEmpty {
                vendors = loaded
            }
        }
    }
}

// MARK: - Vendor Picker Modal

/// Sheet modal presenting vendor radio options + "Other" free-text entry.
/// Loads its own vendor data from Firestore.
struct VendorPickerModal: View {
    let selectedValue: String
    var fixedOptions: [String] = []
    var excludedOptions: Set<String> = []
    let onSelect: (String) -> Void

    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    @State private var vendors: [String] = VendorDefaultsService.defaultVendors
    @State private var listener: ListenerRegistration?
    @State private var otherMode: Bool
    @State private var otherText: String
    @FocusState private var otherFieldFocused: Bool

    private let service = VendorDefaultsService()

    init(
        selectedValue: String,
        fixedOptions: [String] = [],
        excludedOptions: Set<String> = [],
        onSelect: @escaping (String) -> Void
    ) {
        self.selectedValue = selectedValue
        self.fixedOptions = fixedOptions
        self.excludedOptions = excludedOptions
        self.onSelect = onSelect
        // Other mode will be resolved once vendors load
        _otherMode = State(initialValue: false)
        _otherText = State(initialValue: "")
    }

    /// Filtered vendor list (no empty strings, deduplicated).
    private var displayVendors: [String] {
        VendorDefaultsService.displayVendorOptions(
            fixedOptions: fixedOptions,
            vendors: vendors,
            excluding: excludedOptions
        )
    }

    var body: some View {
        FormSheet(
            title: "Select Source",
            primaryAction: FormSheetAction(title: "Done") {
                if otherMode {
                    onSelect(otherText)
                }
                dismiss()
            },
            secondaryAction: FormSheetAction(title: "Clear") {
                onSelect("")
                dismiss()
            }
        ) {
            ScrollViewReader { proxy in
                VStack(spacing: Spacing.xs) {
                    ForEach(displayVendors, id: \.self) { vendor in
                        vendorOption(vendor, isSelected: !otherMode && selectedValue == vendor) {
                            otherMode = false
                            otherFieldFocused = false
                            onSelect(vendor)
                        }
                    }

                    vendorOption("Other", isSelected: otherMode) {
                        otherMode = true
                        otherText = ""
                    }

                    if otherMode {
                        TextField("e.g. Home Depot, Amazon", text: $otherText)
                            .font(Typography.input)
                            .padding(.horizontal, Spacing.md)
                            .frame(minHeight: 44)
                            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                            )
                            .focused($otherFieldFocused)
                            .padding(.top, Spacing.xs)
                            .id("otherTextField")
                            .onAppear {
                                otherFieldFocused = true
                                withAnimation {
                                    proxy.scrollTo("otherTextField", anchor: .bottom)
                                }
                            }
                    }
                }
            }
        }
        .onAppear { startListening() }
        .onDisappear { listener?.remove() }
    }

    @ViewBuilder
    private func vendorOption(_ name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(Color.clear)
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

        listener = service.subscribe(accountId: accountId) { defaults in
            if let loaded = defaults?.vendors, !loaded.isEmpty {
                vendors = loaded
            }

            // Auto-enable "Other" mode if current value doesn't match any preset
            let available = displayVendors
            if !available.isEmpty && !selectedValue.isEmpty && !available.contains(selectedValue) {
                otherMode = true
                otherText = selectedValue
            }
        }
    }
}

// MARK: - Inline Vendor Picker

/// Vendor radio list displayed inline (no extra tap/modal).
/// Loads vendor presets from Firestore, shows radio options + "Other" free-text.
struct InlineVendorPicker: View {
    @Binding var selectedValue: String
    @Binding var otherMode: Bool
    @Binding var otherText: String
    @Binding var saveOtherAsPreset: Bool
    var otherFocused: FocusState<Bool>.Binding
    var fixedOptions: [String] = []
    var excludedOptions: Set<String> = []

    @Environment(AccountContext.self) private var accountContext

    @State private var vendors: [String] = VendorDefaultsService.defaultVendors
    @State private var listener: ListenerRegistration?

    private let service = VendorDefaultsService()

    private var displayVendors: [String] {
        VendorDefaultsService.displayVendorOptions(
            fixedOptions: fixedOptions,
            vendors: vendors,
            excluding: excludedOptions
        )
    }

    private var cleanedOtherText: String {
        VendorDefaultsService.cleanedVendorName(otherText)
    }

    private var typedValueAlreadyExists: Bool {
        let normalized = VendorDefaultsService.normalizedVendorName(otherText)
        guard !normalized.isEmpty else { return false }
        return displayVendors.contains {
            VendorDefaultsService.normalizedVendorName($0) == normalized
        }
    }

    private var shouldShowSavePresetToggle: Bool {
        otherMode && !cleanedOtherText.isEmpty && !typedValueAlreadyExists
    }

    private let otherEntryBlockId = "otherVendorEntryBlock"

    var body: some View {
        Group {
            if displayVendors.isEmpty {
                FormField(label: "Source / Vendor", text: $selectedValue, placeholder: "e.g. Home Depot, Amazon")
            } else {
                ScrollViewReader { proxy in
                    VStack(spacing: Spacing.xs) {
                        ForEach(displayVendors, id: \.self) { vendor in
                            vendorOption(vendor, isSelected: !otherMode && selectedValue == vendor) {
                                otherMode = false
                                otherFocused.wrappedValue = false
                                selectedValue = vendor
                                saveOtherAsPreset = false
                            }
                        }

                        vendorOption("Other", isSelected: otherMode) {
                            otherMode = true
                            selectedValue = ""
                            otherText = ""
                            saveOtherAsPreset = false
                        }

                        if otherMode {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                TextField("e.g. Home Depot, Amazon", text: $otherText)
                                    .font(Typography.input)
                                    .padding(.horizontal, Spacing.md)
                                    .frame(minHeight: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                            .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                                    )
                                    .focused(otherFocused)
                                    .onAppear {
                                        otherFocused.wrappedValue = true
                                        scrollOtherEntryIntoView(proxy)
                                    }
                                    .onChange(of: otherText) { _, _ in
                                        if typedValueAlreadyExists {
                                            saveOtherAsPreset = false
                                        }
                                    }

                                if shouldShowSavePresetToggle {
                                    FormToggle(
                                        label: "Save \"\(cleanedOtherText)\" for next time",
                                        isOn: $saveOtherAsPreset
                                    )
                                }
                            }
                            .id(otherEntryBlockId)
                            .padding(.top, Spacing.xs)
                            .onChange(of: otherFocused.wrappedValue) { _, isFocused in
                                if isFocused {
                                    scrollOtherEntryIntoView(proxy)
                                }
                            }
                            .onChange(of: shouldShowSavePresetToggle) { _, shouldShow in
                                if !shouldShow {
                                    saveOtherAsPreset = false
                                } else if otherFocused.wrappedValue {
                                    scrollOtherEntryIntoView(proxy)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { startListening() }
        .onDisappear { listener?.remove() }
    }

    private func scrollOtherEntryIntoView(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(otherEntryBlockId, anchor: .bottom)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation {
                proxy.scrollTo(otherEntryBlockId, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func vendorOption(_ name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                    .stroke(isSelected ? BrandColors.primary : BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func startListening() {
        guard let accountId = accountContext.currentAccountId else { return }

        Task { try? await service.initializeDefaults(accountId: accountId) }

        listener = service.subscribe(accountId: accountId) { defaults in
            if let loaded = defaults?.vendors, !loaded.isEmpty {
                vendors = loaded
            }

            // Auto-enable "Other" mode if current value doesn't match any preset
            let available = displayVendors
            if !available.isEmpty && !selectedValue.isEmpty && !available.contains(selectedValue) {
                otherMode = true
                otherText = selectedValue
            }
        }
    }
}

#Preview("With Vendors") {
    @Previewable @State var source = "Amazon"
    @Previewable @State var showPicker = false
    VendorPickerField(value: $source, showPicker: $showPicker)
        .padding()
}

#Preview("Empty Value") {
    @Previewable @State var source = ""
    @Previewable @State var showPicker = false
    VendorPickerField(value: $source, showPicker: $showPicker)
        .padding()
}
