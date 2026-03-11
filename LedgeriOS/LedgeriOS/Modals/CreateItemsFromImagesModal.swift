import SwiftUI

struct CreateItemsFromImagesModal: View {
    let transaction: Transaction
    let onCreated: ([ImageGroup]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: ImageGroupingState

    init(transaction: Transaction, onCreated: @escaping ([ImageGroup]) -> Void) {
        self.transaction = transaction
        self.onCreated = onCreated
        let allImages = (transaction.receiptImages ?? [])
            + (transaction.otherImages ?? [])
            + (transaction.transactionImages ?? [])
        self._state = State(initialValue: ImageGroupingState(allImages: allImages))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if !state.groups.isEmpty {
                        groupedSection
                    }

                    ungroupedSection
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxl)
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .background(BrandColors.background)
            .navigationTitle("Create Items from Images")
            .navBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Grouped Items

    private var groupedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("GROUPED ITEMS")
                .sectionLabelStyle()

            ForEach(state.groups) { group in
                groupCard(group)
            }
        }
    }

    private func groupCard(_ group: ImageGroup) -> some View {
        let index = state.groups.firstIndex(where: { $0.id == group.id })
        let label = "Item \((index ?? 0) + 1)"

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(label)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)

                Text("\(group.images.count) photo\(group.images.count == 1 ? "" : "s")")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                Spacer()

                Button {
                    withAnimation { state.ungroup(group) }
                } label: {
                    Text("Ungroup")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.destructive)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(group.images.enumerated()), id: \.offset) { _, attachment in
                        Color(BrandColors.surfaceTertiary)
                            .frame(width: 56, height: 56)
                            .overlay {
                                AsyncImage(url: URL(string: attachment.url)) { phase in
                                    if case .success(let image) = phase {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    }
                                }
                            }
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2))
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(BrandColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
    }

    // MARK: - Ungrouped Images

    private var ungroupedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PHOTOS")
                .sectionLabelStyle()

            if state.ungroupedImages.isEmpty {
                Text("All photos have been grouped.")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.xl)
            } else {
                SelectableImageGrid(
                    attachments: state.ungroupedImages,
                    selectedUrls: $state.selectedUrls
                )
            }
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        if state.canGroup {
            BulkSelectionBar(
                selectedCount: state.selectedUrls.count,
                totalCount: state.ungroupedImages.count,
                actionLabel: "Group as Item",
                onBulkActions: {
                    withAnimation { state.groupSelected() }
                },
                onClear: { state.clearSelection() }
            )
        } else if state.canCreate {
            HStack {
                Spacer()
                AppButton(
                    title: "Create \(state.groups.count) Item\(state.groups.count == 1 ? "" : "s")"
                ) {
                    onCreated(state.groups)
                    dismiss()
                }
                .fixedSize()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)
            .background(BrandColors.background)
        }
    }
}

#Preview {
    CreateItemsFromImagesModal(
        transaction: Transaction(
            receiptImages: (1...6).map { i in
                AttachmentRef(url: "https://picsum.photos/20\(i)", kind: .image)
            }
        ),
        onCreated: { _ in }
    )
}
