#if os(macOS)
import Foundation
import UniformTypeIdentifiers

/// Share report contents, never a borrowed URL into the scratch directory.
/// AppKit services may retain the provider after reporting handoff completion.
public enum PropertyManagementReportShareItem {
    public static func make(fileURL: URL) throws -> NSItemProvider {
        let type: UTType
        switch fileURL.pathExtension.lowercased() {
        case "pdf": type = .pdf
        case "csv": type = .commaSeparatedText
        default: throw CocoaError(.fileReadUnsupportedScheme)
        }
        let bytes = try Data(contentsOf: fileURL)
        let provider = NSItemProvider()
        provider.suggestedName = fileURL.lastPathComponent
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(bytes, nil)
            return nil
        }
        if type == .commaSeparatedText {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                completion(bytes, nil)
                return nil
            }
        }
        return provider
    }
}
#endif
