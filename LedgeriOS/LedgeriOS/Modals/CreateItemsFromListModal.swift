import SwiftUI

/// Two-step modal for bulk item creation from pasted receipt text.
/// Step 1: Paste receipt text. Step 2: Preview parsed items + skipped lines, then create all.
struct CreateItemsFromListModal: View {
    let transaction: Transaction
    let onCreated: ([ReceiptListParser.ParsedItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var currentStep = 1
    @State private var parseResult: ReceiptListParser.ParseResult?

    var body: some View {
        Group {
            if currentStep == 1 {
                pasteStep
            } else {
                previewStep
            }
        }
    }

    // MARK: - Step 1: Paste

    private var pasteStep: some View {
        MultiStepFormSheet(
            title: "Create Items from List",
            description: "Paste receipt text with item lines (e.g. HomeGoods format)",
            currentStep: 1,
            totalSteps: 2,
            primaryAction: FormSheetAction(
                title: "Preview",
                isDisabled: inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                parseResult = ReceiptListParser.parseReceiptText(inputText)
                currentStep = 2
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            TextEditor(text: $inputText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(BrandColors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(Spacing.md)
                .frame(minHeight: 200)
                .background(BrandColors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                )
        }
    }

    // MARK: - Step 2: Preview

    private var previewStep: some View {
        MultiStepFormSheet(
            title: "Create Items from List",
            description: "\(parseResult?.items.count ?? 0) items parsed",
            currentStep: 2,
            totalSteps: 2,
            primaryAction: FormSheetAction(
                title: "Create All",
                isDisabled: parseResult?.items.isEmpty ?? true
            ) {
                if let items = parseResult?.items {
                    onCreated(items)
                }
                dismiss()
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = 1
            }
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let result = parseResult {
                    // Parsed items
                    ForEach(result.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)

                                if !item.sku.isEmpty {
                                    Text("SKU: \(item.sku)")
                                        .font(Typography.caption)
                                        .foregroundStyle(BrandColors.textTertiary)
                                }
                            }

                            Spacer()

                            Text(CurrencyFormatting.formatCentsWithDecimals(item.priceCents))
                                .font(Typography.body.weight(.semibold))
                                .foregroundStyle(BrandColors.textPrimary)
                        }
                        .padding(.vertical, Spacing.xs)
                    }

                    // Skipped lines
                    if !result.skippedLines.isEmpty {
                        DisclosureGroup("Skipped Lines (\(result.skippedLines.count))") {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                ForEach(Array(result.skippedLines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(Typography.caption)
                                        .foregroundStyle(BrandColors.textSecondary)
                                }
                            }
                            .padding(.top, Spacing.xs)
                        }
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    }
                }
            }
        }
    }
}

#Preview("Step 1") {
    CreateItemsFromListModal(
        transaction: Transaction(source: "HomeGoods"),
        onCreated: { _ in }
    )
}
