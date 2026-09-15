import Darwin
import Foundation
import LedgerTargetCore

public enum ReportScratchFailure: Error, Equatable, Sendable {
    case unsafePath
    case io(Int32)
    case operationFailed(String, Int, Int32)
    case protectionUnavailable(Int32)
    case closed
    case foreignArtifact
    case artifactsPending
    case emptyContent
}

public enum ReportScratchFormat: String, Sendable { case pdf, csv }

/// A temporary owned file, not authorization to disclose its contents.
public struct ReportScratchArtifact: Sendable {
    public let url: URL
    public let snapshotReference: ProtectedArtifactSnapshotReference
    public let outputHash: ProtectedArtifactSHA256
    fileprivate let owner: UUID
    fileprivate let name: String
    fileprivate let inode: ino_t
}

/// Call remove only after handoff completion, cancellation or failure. Deallocation
/// releases the session lock but preserves files for explicit startup recovery.
public actor ReportScratchStore {
    public static let directoryName = "ledger-report-scratch-v1"
    private let owner = UUID()
    private let rootURL: URL
    private let sessionName: String
    private var rootFD: Int32
    private var sessionFD: Int32
    private var artifacts: [String: ino_t] = [:]

    public init(rootDirectory suppliedRoot: URL? = nil) throws {
        let rootDirectory: URL
        if let suppliedRoot { rootDirectory = suppliedRoot }
        else {
            // Foundation may abbreviate /private/var back to /var even after
            // resolvingSymlinksInPath. Canonicalize only the trusted OS temp
            // parent, never caller-supplied roots or owned scratch descendants.
            guard let path = realpath(FileManager.default.temporaryDirectory.path, nil) else { throw Self.ioError() }
            defer { free(path) }
            rootDirectory = URL(fileURLWithPath: String(cString: path)).appendingPathComponent(Self.directoryName)
        }
        guard rootDirectory.isFileURL, rootDirectory.lastPathComponent == Self.directoryName else {
            throw ReportScratchFailure.unsafePath
        }
        let root = try Self.openRoot(rootDirectory)
        do {
            try Self.lock(root)
            defer { flock(root, LOCK_UN) }
            let name = "session-" + UUID().uuidString.lowercased()
            guard mkdirat(root, name, 0o700) == 0 else { throw Self.ioError() }
            let session = openat(root, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard session >= 0 else { throw Self.ioError() }
            do {
                try Self.lock(session)
                try Self.protect(session)
            } catch {
                Darwin.close(session)
                unlinkat(root, name, AT_REMOVEDIR)
                throw error
            }
            rootURL = rootDirectory
            sessionName = name
            rootFD = root
            sessionFD = session
        } catch { Darwin.close(root); throw error }
    }

    deinit {
        if sessionFD >= 0 { Darwin.close(sessionFD) }
        if rootFD >= 0 { Darwin.close(rootFD) }
    }

    public func create(data: Data, format: ReportScratchFormat = .pdf, snapshotReference: ProtectedArtifactSnapshotReference, nameHint: String? = nil) throws -> ReportScratchArtifact {
        try create(data: data, format: format, snapshotReference: snapshotReference, nameHint: nameHint, writeBytes: Self.writeBytes)
    }

    // Internal seam exercises partial-write cleanup without changing process limits.
    func create(data: Data, format: ReportScratchFormat = .pdf, snapshotReference: ProtectedArtifactSnapshotReference,
                nameHint: String? = nil, writeBytes: @Sendable (Int32, Data) throws -> Void) throws -> ReportScratchArtifact {
        guard sessionFD >= 0 else { throw ReportScratchFailure.closed }
        guard !data.isEmpty else { throw ReportScratchFailure.emptyContent }
        let prefix = nameHint.map { hint in
            String(hint.unicodeScalars.prefix(60).map { scalar -> Character in
                Self.isNameCharacter(scalar) ? Character(String(scalar)) : "-"
            })
        }.flatMap { $0.isEmpty ? nil : $0 + "--" } ?? ""
        let name = prefix + UUID().uuidString.lowercased() + "." + format.rawValue
        let fd = openat(sessionFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Self.ioError() }
        var complete = false
        defer {
            Darwin.close(fd)
            if !complete { unlinkat(sessionFD, name, 0) }
        }
        try Self.protect(fd)
        try writeBytes(fd, data)
        guard fsync(fd) == 0 else { throw Self.ioError() }
        let info = try Self.info(fd, directory: false)
        let artifact = ReportScratchArtifact(
            url: rootURL.appendingPathComponent(sessionName).appendingPathComponent(name),
            snapshotReference: snapshotReference, outputHash: try .make(bytes: data),
            owner: owner, name: name, inode: info.st_ino)
        artifacts[name] = info.st_ino
        complete = true
        return artifact
    }

    private static func writeBytes(_ fd: Int32, _ pdfData: Data) throws {
        try pdfData.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Self.ioError() }
                offset += count
            }
        }
    }

    /// Native writers may atomically replace their destination. Keep the session
    /// locked until they finish, then validate the resulting file before cleanup.
    /// A process crash leaves a UUID.pdf for the existing startup recovery.
    public func generatePDF(using writer: @Sendable (URL) async throws -> Data) async throws -> Data {
        guard sessionFD >= 0 else { throw ReportScratchFailure.closed }
        let name = UUID().uuidString.lowercased() + ".pdf"
        let fd = openat(sessionFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Self.ioError() }
        do {
            try Self.protect(fd)
            artifacts[name] = try Self.info(fd, directory: false).st_ino
        } catch {
            Darwin.close(fd); unlinkat(sessionFD, name, 0); throw error
        }
        Darwin.close(fd)
        let url = rootURL.appendingPathComponent(sessionName).appendingPathComponent(name)
        let result: Result<Data, Error>
        do { result = .success(try await writer(url)) }
        catch { result = .failure(error) }

        let output = openat(sessionFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if output >= 0 {
            defer { Darwin.close(output) }
            var info = stat()
            guard fstat(output, &info) == 0, info.st_uid == getuid(),
                  info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
                throw ReportScratchFailure.unsafePath
            }
            // A native atomic replacement can reset file permissions. The
            // parent remains 0700 throughout; normalize before later recovery.
            guard fchmod(output, 0o600) == 0 else { throw Self.ioError() }
            try Self.protect(output)
            guard unlinkat(sessionFD, name, 0) == 0 else { throw Self.ioError() }
        } else if errno != ENOENT {
            throw ReportScratchFailure.unsafePath
        }
        artifacts.removeValue(forKey: name)
        let bytes = try result.get()
        guard !bytes.isEmpty else { throw ReportScratchFailure.emptyContent }
        return bytes
    }

    private static func isNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (48...57).contains(value) || (65...90).contains(value) ||
            (97...122).contains(value) || value == 45
    }

    private static func isOwnedStem(_ stem: String) -> Bool {
        if UUID(uuidString: stem) != nil { return true }
        guard stem.count >= 39, UUID(uuidString: String(stem.suffix(36))) != nil else { return false }
        let prefix = stem.dropLast(36)
        return prefix.hasSuffix("--") && (3...62).contains(prefix.count) &&
            prefix.unicodeScalars.allSatisfy(isNameCharacter)
    }

    public func remove(_ artifact: ReportScratchArtifact) throws {
        guard sessionFD >= 0 else { throw ReportScratchFailure.closed }
        guard artifact.owner == owner, artifacts[artifact.name] == artifact.inode else {
            throw ReportScratchFailure.foreignArtifact
        }
        let fd = openat(sessionFD, artifact.name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ReportScratchFailure.unsafePath }
        defer { Darwin.close(fd) }
        guard try Self.info(fd, directory: false).st_ino == artifact.inode else {
            throw ReportScratchFailure.foreignArtifact
        }
        guard unlinkat(sessionFD, artifact.name, 0) == 0 else { throw Self.ioError() }
        artifacts.removeValue(forKey: artifact.name)
    }

    /// Only unlocked, well-formed sessions in this dedicated root are eligible.
    /// Unexpected files/symlinks are rejected, never recursively followed/deleted.
    public func recoverAbandonedSessions() throws {
        guard sessionFD >= 0 else { throw ReportScratchFailure.closed }
        try Self.lock(rootFD)
        defer { flock(rootFD, LOCK_UN) }
        for name in try Self.names(rootFD) {
            guard name != sessionName else { continue }
            guard name.hasPrefix("session-"), UUID(uuidString: String(name.dropFirst(8))) != nil else {
                throw ReportScratchFailure.unsafePath
            }
            let fd = openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw ReportScratchFailure.unsafePath }
            defer { Darwin.close(fd) }
            _ = try Self.info(fd, directory: true)
            if flock(fd, LOCK_EX | LOCK_NB) != 0 {
                if errno == EWOULDBLOCK { continue }
                throw Self.ioError()
            }
            let files = try Self.names(fd)
            // Validate the whole session before removing anything from it.
            for file in files {
                let parts = file.split(separator: ".", omittingEmptySubsequences: false)
                guard parts.count == 2, ReportScratchFormat(rawValue: String(parts[1])) != nil,
                      Self.isOwnedStem(String(parts[0])) else {
                    throw ReportScratchFailure.unsafePath
                }
                let child = openat(fd, file, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                guard child >= 0 else { throw ReportScratchFailure.unsafePath }
                defer { Darwin.close(child) }
                // Native atomic writers may leave 0644 on a crash. The parent
                // is already verified private and unlocked; permit read bits
                // only for deletion, never writable/executable-by-others files.
                _ = try Self.info(child, directory: false, recoveringNativeOutput: true)
            }
            for file in files {
                guard unlinkat(fd, file, 0) == 0 else { throw Self.ioError() }
            }
            guard unlinkat(rootFD, name, AT_REMOVEDIR) == 0 else { throw Self.ioError() }
        }
    }

    /// Refuses implicit deletion while a system handoff may still read the file.
    public func close() throws {
        guard sessionFD >= 0 else { return }
        guard artifacts.isEmpty else { throw ReportScratchFailure.artifactsPending }
        try Self.lock(rootFD)
        defer { flock(rootFD, LOCK_UN) }
        guard try Self.names(sessionFD).isEmpty else { throw ReportScratchFailure.unsafePath }
        guard unlinkat(rootFD, sessionName, AT_REMOVEDIR) == 0 else { throw Self.ioError() }
        Darwin.close(sessionFD)
        sessionFD = -1
        // Keep the root descriptor until deinit; defer must unlock a live fd.
    }

    private static func ioError(operation: String = #function, line: Int = #line) -> ReportScratchFailure {
        .operationFailed(operation, line, errno)
    }
    private static func lock(_ fd: Int32) throws {
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR { throw ioError() }
        }
    }
    private static func info(_ fd: Int32, directory: Bool, recoveringNativeOutput: Bool = false) throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0 else { throw ioError() }
        guard value.st_uid == getuid(), value.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              value.st_mode & (recoveringNativeOutput && !directory ? 0o033 : 0o077) == 0,
              directory || value.st_nlink == 1 else {
            throw ReportScratchFailure.unsafePath
        }
        return value
    }
    private static func protect(_ fd: Int32) throws {
        #if os(iOS) && !targetEnvironment(simulator)
        // Darwin protection class A (NSFileProtectionComplete). Use the owned
        // descriptor, so protection does not resolve a replaceable pathname.
        guard fcntl(fd, F_SETPROTECTIONCLASS, 1) == 0 else { throw ReportScratchFailure.protectionUnavailable(errno) }
        #endif
        // Simulator's host filesystem cannot supply iOS Data Protection. Its
        // fcntl can accept a directory class but then reject file creation with
        // EPERM; setting the class on a regular file also fails. Simulator uses
        // the same 0700/0600 ownership and cleanup, but is NOT protection evidence.
        // Physical iOS devices must pass the class-A call above; no fallback.
    }
    private static func openRoot(_ url: URL) throws -> Int32 {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { throw ReportScratchFailure.unsafePath }
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw ioError() }
        do {
            for (index, part) in parts.enumerated() {
                if index == parts.count - 1 {
                    if mkdirat(current, part, 0o700) != 0 && errno != EEXIST { throw ioError() }
                }
                let next = openat(current, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw ReportScratchFailure.unsafePath }
                Darwin.close(current)
                current = next
            }
            _ = try info(current, directory: true)
            try protect(current)
            return current
        } catch { Darwin.close(current); throw error }
    }
    private static func names(_ fd: Int32) throws -> [String] {
        let copy = dup(fd)
        guard copy >= 0 else { throw ioError() }
        guard let directory = fdopendir(copy) else { Darwin.close(copy); throw ioError() }
        defer { closedir(directory) }
        rewinddir(directory)
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { throw ioError() }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { result.append(name) }
        }
        return result.sorted()
    }
}
