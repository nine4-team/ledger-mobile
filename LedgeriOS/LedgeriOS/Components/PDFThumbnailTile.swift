import SwiftUI

/// Styled tile for PDF attachments in the thumbnail grid.
/// Shows a document icon + truncated filename instead of an image preview.
struct PDFThumbnailTile: View {
    var fileName: String?

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 28))
                .foregroundStyle(BrandColors.primary)

            Text(fileName ?? "PDF")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xs)
    }
}

#Preview {
    PDFThumbnailTile(fileName: "invoice-2024.pdf")
        .frame(width: 100, height: 100)
        .background(BrandColors.surfaceTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2))
}
