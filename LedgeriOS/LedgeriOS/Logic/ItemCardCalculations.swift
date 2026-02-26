import SwiftUI

enum ItemCardCalculations {

    struct BadgeItem {
        let text: String
        let color: Color
    }

    static func badgeItems(
        statusLabel: String?,
        budgetCategoryName: String?,
        indexLabel: String?
    ) -> [BadgeItem] {
        var badges: [BadgeItem] = []
        if let index = indexLabel, !index.isEmpty {
            badges.append(BadgeItem(text: index, color: BrandColors.textSecondary))
        }
        if let category = budgetCategoryName, !category.isEmpty {
            badges.append(BadgeItem(text: category, color: BrandColors.primary))
        }
        if let status = statusLabel, !status.isEmpty {
            badges.append(BadgeItem(text: status, color: BrandColors.primary))
        }
        return badges
    }

    static func metadataLines(
        name: String?,
        sku: String?,
        sourceLabel: String?,
        locationLabel: String?,
        priceLabel: String?,
        stackSkuAndSource: Bool
    ) -> [String] {
        var lines: [String] = []
        if let price = priceLabel, !price.isEmpty {
            lines.append(price)
        }
        if stackSkuAndSource {
            if let source = sourceLabel, !source.isEmpty {
                lines.append("Source: \(source)")
            }
            if let sku = sku, !sku.isEmpty {
                lines.append("SKU: \(sku)")
            }
        } else {
            let skuPart = sku ?? ""
            let sourcePart = sourceLabel ?? ""
            if !skuPart.isEmpty && !sourcePart.isEmpty {
                lines.append("SKU: \(skuPart) · Source: \(sourcePart)")
            } else if !skuPart.isEmpty {
                lines.append("SKU: \(skuPart)")
            } else if !sourcePart.isEmpty {
                lines.append("Source: \(sourcePart)")
            }
        }
        if let location = locationLabel, !location.isEmpty {
            lines.append("Location: \(location)")
        }
        return lines
    }

    static func thumbnailUrl(from urlString: String?) -> URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    static func isSelectionEnabled(
        externalSelected: Bool?,
        onSelectedChange: Bool
    ) -> Bool {
        externalSelected != nil || onSelectedChange
    }

    static func resolvedSelected(
        externalSelected: Bool?,
        internalSelected: Bool
    ) -> Bool {
        externalSelected ?? internalSelected
    }
}
