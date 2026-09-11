#if os(macOS)
import Foundation
import Testing
import UniformTypeIdentifiers
import LedgerTargetAppModel

@Suite("Property report owned sharing contents")
struct PropertyManagementReportShareItemTests {
    @Test("Shared contents remain readable after scratch cleanup", arguments: ["pdf", "csv"])
    func independentContents(extension suffix: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("report.\(suffix)")
        let bytes = Data((suffix == "pdf" ? "%PDF-1.7\nsynthetic payload" : "Name\r\nReport test chair\r\n").utf8)
        try bytes.write(to: file)
        let provider = try PropertyManagementReportShareItem.make(fileURL: file)
        try FileManager.default.removeItem(at: file)
        #expect(provider.suggestedName == file.lastPathComponent)
        #expect(!provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        let type = suffix == "pdf" ? UTType.pdf : UTType.commaSeparatedText
        let loaded: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
        #expect(loaded == bytes)
        if suffix == "csv" {
            let text: Data = try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
                }
            }
            #expect(text == bytes)
        }
        // File-based destinations can still request a system-owned copy.
        let fileBytes: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw CocoaError(.fileReadUnknown) }
                    continuation.resume(returning: try Data(contentsOf: url))
                } catch { continuation.resume(throwing: error) }
            }
        }
        #expect(fileBytes == bytes)
    }
}
#endif
