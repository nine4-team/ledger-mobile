import SwiftUI

/// Collapsible debug panel showing extraction stats, raw text, and copy-to-clipboard JSON.
struct ParseDebugReport: View {
    let rawText: String
    let stats: PdfTextExtractor.ExtractionStats
    let parseResultJson: String

    @State private var statsExpanded = false
    @State private var rawTextExpanded = false
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Debug Info")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            // Stats toggle
            Button {
                withAnimation { statsExpanded.toggle() }
            } label: {
                HStack {
                    Text(statsExpanded ? "Hide Stats" : "Show Stats")
                        .font(Typography.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(statsExpanded ? 90 : 0))
                        .font(.system(size: 10))
                }
                .foregroundStyle(BrandColors.primary)
            }

            if statsExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    statRow("Pages", value: "\(stats.pageCount)")
                    statRow("Characters", value: stats.charCount.formatted())
                    statRow("Lines", value: stats.lineCount.formatted())
                    statRow("Duration", value: "\(stats.durationMs)ms")
                }
                .padding(Spacing.sm)
                .background(BrandColors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            }

            // Raw text toggle
            Button {
                withAnimation { rawTextExpanded.toggle() }
            } label: {
                HStack {
                    Text(rawTextExpanded ? "Hide Raw Text" : "Show Raw Text")
                        .font(Typography.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(rawTextExpanded ? 90 : 0))
                        .font(.system(size: 10))
                }
                .foregroundStyle(BrandColors.primary)
            }

            if rawTextExpanded {
                ScrollView {
                    Text(rawText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(BrandColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.sm)
                }
                .frame(maxHeight: 200)
                .background(BrandColors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                )
            }

            // Copy debug JSON
            Button {
                copyDebugJson()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    Text(showCopied ? "Copied" : "Copy Debug JSON")
                }
                .font(Typography.caption)
                .foregroundStyle(BrandColors.primary)
            }
        }
    }

    // MARK: - Private

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(BrandColors.textPrimary)
        }
    }

    private func copyDebugJson() {
        let debugData: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "stats": [
                "pageCount": stats.pageCount,
                "charCount": stats.charCount,
                "lineCount": stats.lineCount,
                "durationMs": stats.durationMs,
            ],
            "parseResult": parseResultJson,
            "rawTextPreview": String(rawText.prefix(2000)),
            "rawTextLength": rawText.count,
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: debugData, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            UIPasteboard.general.string = jsonString
        }

        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
    }
}
