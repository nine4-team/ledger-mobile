import SwiftUI
import FirebaseFirestore

struct VendorDefaultsView: View {
    @Environment(AccountContext.self) private var accountContext

    @State private var vendors: [String] = []
    @State private var listener: ListenerRegistration?
    @State private var showingAddSheet = false
    @State private var newVendorName = ""

    private let service = VendorDefaultsService(syncTracker: NoOpSyncTracker())

    private var nonEmptyVendors: [(offset: Int, element: String)] {
        Array(vendors.enumerated().filter { !$0.element.isEmpty })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Add button
                Button {
                    newVendorName = ""
                    showingAddSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Vendor")
                    }
                    .font(Typography.button)
                    .foregroundStyle(BrandColors.primary)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.sm)

                if nonEmptyVendors.isEmpty {
                    Text("No vendors configured.")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                        .padding(.horizontal, Spacing.screenPadding)
                } else {
                    LazyVStack(spacing: Spacing.cardListGap) {
                        ForEach(nonEmptyVendors, id: \.offset) { index, vendor in
                            Card {
                                HStack {
                                    Text(vendor)
                                        .font(Typography.body)
                                        .foregroundStyle(BrandColors.textPrimary)

                                    Spacer()

                                    Button {
                                        removeVendor(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(BrandColors.destructive)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(BrandColors.background)
        .onAppear { startListening() }
        .onDisappear { listener?.remove() }
        .sheet(isPresented: $showingAddSheet) {
            AddVendorSheet(vendorName: $newVendorName) {
                addVendor(newVendorName)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Data

    private func startListening() {
        guard let accountId = accountContext.currentAccountId else { return }

        // Initialize defaults if needed
        Task { try? await service.initializeDefaults(accountId: accountId) }

        listener = service.subscribe(accountId: accountId) { defaults in
            self.vendors = defaults?.vendors ?? []
        }
    }

    private func addVendor(_ name: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Find first empty slot or append
        if let emptyIndex = vendors.firstIndex(of: "") {
            vendors[emptyIndex] = trimmed
        } else {
            vendors.append(trimmed)
        }
        try? service.save(accountId: accountId, vendors: vendors)
    }

    private func removeVendor(at index: Int) {
        guard let accountId = accountContext.currentAccountId else { return }
        guard index < vendors.count else { return }
        vendors[index] = ""
        try? service.save(accountId: accountId, vendors: vendors)
    }
}

// MARK: - Add Vendor Sheet

private struct AddVendorSheet: View {
    @Binding var vendorName: String
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasSubmitted = false

    var body: some View {
        FormSheet(
            title: "Add Vendor",
            primaryAction: FormSheetAction(
                title: "Add",
                action: handleAdd
            ),
            secondaryAction: FormSheetAction(
                title: "Cancel",
                action: { dismiss() }
            ),
            error: hasSubmitted && vendorName.trimmingCharacters(in: .whitespaces).isEmpty ? "Name is required" : nil
        ) {
            FormField(
                label: "Vendor Name",
                text: $vendorName,
                placeholder: "e.g. Home Depot",
                errorText: hasSubmitted && vendorName.trimmingCharacters(in: .whitespaces).isEmpty ? "Name is required" : nil
            )
        }
    }

    private func handleAdd() {
        hasSubmitted = true
        guard !vendorName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onAdd()
        dismiss()
    }
}
