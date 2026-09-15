import SwiftUI

// Extracted from InvoiceRow: presentation accepts display values, never a
// Firebase model or a second calculation of frozen Invoice amounts.
enum InvoicePipelineFilter: String, CaseIterable {
    case all, created, sent, paid, canceled
    var label: String { rawValue.capitalized }
    var segmentOption: SegmentOption<InvoicePipelineFilter> { SegmentOption(id: self, label: label) }
}

struct BillingInvoiceSummaryPresentation: View {
    let title: String
    let amountText: String
    var date: Date? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
            }
            HStack(spacing: Spacing.sm) {
                Text(amountText)
                    .font(Typography.small.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
                if let date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BillingInvoiceStatusPresentation: View {
    let label: String
    let color: Color
    var isWorking = false
    var hasActions = false
    var body: some View {
        HStack(spacing: Spacing.xs) {
            if isWorking { ProgressView().controlSize(.small) }
            Text(label).font(Typography.caption.weight(.semibold))
            if hasActions {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.30), lineWidth: 1))
    }
}

enum CandidateAvailabilityFilter: String, CaseIterable {
    case available, created, sent, paid, all
    var label: String {
        switch self {
        case .available: "Available"
        case .created: "On Created Invoice"
        case .sent: "Sent"
        case .paid: "Paid"
        case .all: "All"
        }
    }
}

enum CandidateSourceFilter: String, CaseIterable {
    case all, fees, expenses, items
    var label: String {
        switch self {
        case .all: "All Sources"
        case .fees: "Fees"
        case .expenses: "Expenses"
        case .items: "Items"
        }
    }
    var segmentOption: SegmentOption<CandidateSourceFilter> { SegmentOption(id: self, label: label) }
}

struct BillingWorkspacePresentation<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md, content: content)
                .padding(Spacing.screenPadding)
                .frame(maxWidth: Dimensions.contentMaxWidth)
                .frame(maxWidth: .infinity)
        }
    }
}

// Moved unchanged from Billing; shared by original and canonical providers.
struct BillingReceivablesToolbar: View {
    @Binding var searchText: String
    let filtersAreActive: Bool
    var onFilter: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SearchField(text: $searchText, placeholder: "Search receivables...")
            Button(action: onFilter) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(filtersAreActive ? BrandColors.primary : BrandColors.textSecondary)
            }
            .buttonStyle(CircleBarButtonStyle())
            .background(BrandColors.surface, in: Circle())
            .overlay(Circle().stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth))
            .accessibilityLabel("Filter receivables")
        }
    }
}

struct BillingEmptyRow: View {
    let message: String
    init(_ message: String) { self.message = message }
    var body: some View {
        Text(message)
            .font(Typography.small)
            .foregroundStyle(BrandColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.md)
    }
}

struct BillingRowSurface<Content: View>: View {
    var padding: CGFloat = Spacing.md
    var isMuted = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .opacity(isMuted ? 0.58 : 1)
            .background((isMuted ? BrandColors.surface.opacity(0.62) : BrandColors.surface))
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
            .shadow(color: .black.opacity(isMuted ? 0.015 : 0.035), radius: isMuted ? 2 : 4, x: 0, y: 1)
    }
}

/// Original Billing candidate layout with provider-independent display values.
struct BillingCandidateRowPresentation: View {
    let title: String
    let metadata: String
    let amountText: String
    let statusLabel: String
    let statusColor: Color
    let invoiceName: String?

    var body: some View {
        BillingRowSurface {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: Spacing.xs) {
                        Text(metadata)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .lineLimit(1)
                        Badge(text: statusLabel, color: statusColor)
                        if let invoiceName, !invoiceName.isEmpty {
                            Text(invoiceName)
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: Spacing.md)
                Text(amountText)
                    .font(Typography.small.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }
        }
    }
}
