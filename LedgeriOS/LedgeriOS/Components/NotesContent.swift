import SwiftUI

/// Renders a transaction's or item's `notes` field as a stack of paragraphs.
///
/// The `notes` field is a single string but its contents are structured:
/// user-authored prose at the top, AI-authored audit entries (written by the
/// MCP server, prefixed with `[AI M/D/YYYY]`) at the bottom, each separated
/// by a blank line. This view splits on blank lines and renders each
/// paragraph as its own `Text`, with AI-tagged paragraphs styled smaller and
/// muted so user prose remains the primary focus.
struct NotesContent: View {
    let notes: String?
    var emptyText: String = "No notes"

    private var paragraphs: [String] {
        guard let notes, !notes.isEmpty else { return [] }
        return notes
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if paragraphs.isEmpty {
            Text(emptyText)
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    if NotesContent.isAiTagged(paragraph) {
                        SelectableNoteText(text: paragraph, style: .small)
                    } else {
                        SelectableNoteText(text: paragraph, style: .body)
                    }
                }
            }
        }
    }

    /// True if `paragraph` begins with the `[AI M/D/YYYY]` audit prefix the
    /// MCP server writes. Matches `util/notes.ts`.
    static func isAiTagged(_ paragraph: String) -> Bool {
        paragraph.range(of: #"^\[AI \d{1,2}/\d{1,2}/\d{4}\]"#, options: .regularExpression) != nil
    }
}
