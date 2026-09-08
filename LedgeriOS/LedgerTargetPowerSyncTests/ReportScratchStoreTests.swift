import Darwin
import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetPowerSync

@Suite("Protected report scratch files")
struct ReportScratchStoreTests {
    private func root() throws -> URL {
        let path = try #require(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(path) }
        let parent = URL(fileURLWithPath: String(cString: path))
            .appendingPathComponent("scratch-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        return parent.appendingPathComponent(ReportScratchStore.directoryName)
    }
    private func reference() throws -> ProtectedArtifactSnapshotReference {
        try .init(snapshotID: .init(validating: String(repeating: "a", count: 32)),
                  snapshotHash: .make(bytes: Data("snapshot".utf8)),
                  visibilityScopeID: .make(bytes: Data("scope".utf8)),
                  profileVersion: .init(validating: "property-report-v1"),
                  authorityVersion: .init(validating: "authority-v1"))
    }

    @Test("Distinct files retain source reference and bytes until explicitly removed")
    func artifactsAndClose() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = try ReportScratchStore(rootDirectory: root)
        let bytes = Data("%PDF-first".utf8)
        let first = try await store.create(data: bytes, snapshotReference: reference())
        let second = try await store.create(data: Data("%PDF-second".utf8), snapshotReference: reference())
        #expect(first.url != second.url)
        #expect(first.snapshotReference == (try reference()))
        #expect(first.outputHash == (try .make(bytes: bytes)))
        #expect(try Data(contentsOf: first.url) == bytes)
        let attributes = try FileManager.default.attributesOfItem(atPath: first.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #if os(iOS)
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
        #endif
        await #expect(throws: ReportScratchFailure.artifactsPending) { try await store.close() }
        try await store.remove(first)
        #expect(FileManager.default.fileExists(atPath: second.url.path))
        try await store.remove(second)
        try await store.close()
        await #expect(throws: ReportScratchFailure.closed) {
            try await store.create(data: bytes, snapshotReference: reference())
        }
    }

    @Test("Partial write failure removes only its incomplete file")
    func partialWriteFailure() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = try ReportScratchStore(rootDirectory: root)
        let existing = try await store.create(data: Data("%PDF-existing".utf8), snapshotReference: reference())
        await #expect(throws: ReportScratchFailure.io(ENOSPC)) {
            try await store.create(data: Data("%PDF-incomplete".utf8), snapshotReference: reference()) { fd, data in
                _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, 3) }
                throw ReportScratchFailure.io(ENOSPC)
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: existing.url.deletingLastPathComponent().path)
            == [existing.url.lastPathComponent])
        #expect(try Data(contentsOf: existing.url) == Data("%PDF-existing".utf8))
        try await store.remove(existing)
        try await store.close()
    }

    @Test("Recovery retains other active stores and removes abandoned sessions")
    func recovery() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let active = try ReportScratchStore(rootDirectory: root)
        let activeFile = try await active.create(data: Data("%PDF-active".utf8), snapshotReference: reference())
        var abandoned: ReportScratchStore? = try ReportScratchStore(rootDirectory: root)
        let abandonedFile = try await abandoned!.create(data: Data("row,value\r\n".utf8), format: .csv, snapshotReference: reference())
        #expect(abandonedFile.url.pathExtension == "csv")
        let recovery = try ReportScratchStore(rootDirectory: root)
        try await recovery.recoverAbandonedSessions()
        #expect(FileManager.default.fileExists(atPath: activeFile.url.path))
        #expect(FileManager.default.fileExists(atPath: abandonedFile.url.path))
        abandoned = nil
        try await PropertyManagementReportDelivery.recoverStartupScratch(scratchRoot: root)
        #expect(!FileManager.default.fileExists(atPath: abandonedFile.url.path))
        #expect(FileManager.default.fileExists(atPath: activeFile.url.path))
        try await active.remove(activeFile)
        try await active.close()
        try await recovery.close()
    }

    @Test("Foreign artifacts and symlink replacements cannot delete outside evidence")
    func foreignAndSymlink() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = try ReportScratchStore(rootDirectory: root)
        let other = try ReportScratchStore(rootDirectory: root)
        let file = try await store.create(data: Data("%PDF-owned".utf8), snapshotReference: reference())
        await #expect(throws: ReportScratchFailure.foreignArtifact) { try await other.remove(file) }
        let evidence = root.deletingLastPathComponent().appendingPathComponent("original-evidence.pdf")
        try Data("original".utf8).write(to: evidence)
        try FileManager.default.removeItem(at: file.url)
        try FileManager.default.createSymbolicLink(at: file.url, withDestinationURL: evidence)
        await #expect(throws: ReportScratchFailure.unsafePath) { try await store.remove(file) }
        #expect(try Data(contentsOf: evidence) == Data("original".utf8))
        // Deliberately leave the tampered session: store must not follow its link.
        try await other.close()
    }

    @Test("Recovery rejects symlink sessions and unknown files without following them")
    func unsafeRecovery() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = try ReportScratchStore(rootDirectory: root)
        let evidence = root.deletingLastPathComponent().appendingPathComponent("saved-export.pdf")
        try Data("saved".utf8).write(to: evidence)
        let link = root.appendingPathComponent("session-" + UUID().uuidString.lowercased())
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: evidence.deletingLastPathComponent())
        await #expect(throws: ReportScratchFailure.unsafePath) { try await store.recoverAbandonedSessions() }
        #expect(try Data(contentsOf: evidence) == Data("saved".utf8))
        try FileManager.default.removeItem(at: link)
        let unknown = root.appendingPathComponent("user-export.pdf")
        try Data("user".utf8).write(to: unknown)
        await #expect(throws: ReportScratchFailure.unsafePath) { try await store.recoverAbandonedSessions() }
        #expect(try Data(contentsOf: unknown) == Data("user".utf8))
        try await store.close()
    }
}
