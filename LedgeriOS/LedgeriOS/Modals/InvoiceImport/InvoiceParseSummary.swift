import SwiftUI

/// Displays parsed header fields from an invoice (vendor-specific).
struct InvoiceParseSummary: View {
    let vendor: InvoiceVendor?
    let amazonResult: AmazonInvoiceParser.ParseResult?
    let wayfairResult: WayfairInvoiceParser.ParseResult?
    let itemCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Vendor badge
            if let vendor {
                Text(vendor.rawValue.capitalized)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 3)
                    .background(vendorColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if let amazonResult {
                amazonSummary(amazonResult)
            } else if let wayfairResult {
                wayfairSummary(wayfairResult)
            }

            // Warnings
            let warnings = (amazonResult?.warnings ?? wayfairResult?.warnings) ?? []
            if !warnings.isEmpty {
                warningsSection(warnings)
            }
        }
    }

    // MARK: - Amazon Summary

    @ViewBuilder
    private func amazonSummary(_ result: AmazonInvoiceParser.ParseResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            summaryRow("Order #", value: result.orderNumber)
            summaryRow("Date", value: result.orderPlacedDate)
            summaryRow("Grand Total", value: result.grandTotal.map { "$\($0)" })
            if let tax = result.tax { summaryRow("Tax", value: "$\(tax)") }
            if let shipping = result.shipping { summaryRow("Shipping", value: "$\(shipping)") }
            if let payment = result.paymentMethod { summaryRow("Payment", value: payment) }
            summaryRow("Items", value: "\(itemCount)")
        }
        .padding(Spacing.sm)
        .background(BrandColors.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
    }

    // MARK: - Wayfair Summary

    @ViewBuilder
    private func wayfairSummary(_ result: WayfairInvoiceParser.ParseResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            summaryRow("Invoice #", value: result.invoiceNumber)
            summaryRow("Date", value: result.orderDate)
            summaryRow("Subtotal", value: result.subtotal.map { "$\($0)" })
            if let shipping = result.shippingDeliveryTotal { summaryRow("Shipping", value: "$\(shipping)") }
            if let tax = result.taxTotal { summaryRow("Tax", value: "$\(tax)") }
            if let adjustments = result.adjustmentsTotal { summaryRow("Adjustments", value: "$\(adjustments)") }
            summaryRow("Order Total", value: result.orderTotal.map { "$\($0)" })
            summaryRow("Items", value: "\(itemCount)")
        }
        .padding(Spacing.sm)
        .background(BrandColors.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
    }

    // MARK: - Shared

    private func summaryRow(_ label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
            Spacer()
            Text(value ?? "—")
                .font(Typography.caption.weight(.medium))
                .foregroundStyle(BrandColors.textPrimary)
        }
    }

    private func warningsSection(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .padding(Spacing.sm)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
    }

    private var vendorColor: Color {
        switch vendor {
        case .amazon: Color.orange
        case .wayfair: Color.purple
        case nil: BrandColors.textTertiary
        }
    }
}
