import CryptoKit
import Darwin
import Foundation
import LedgerTargetCore

struct AttachmentMediaEncryptionKey: Sendable {
    fileprivate let value: SymmetricKey

    init(bytes: Data) throws {
        guard bytes.count == 32 else {
            throw AttachmentLocalByteVaultFailure.invalidMediaKey
        }
        value = SymmetricKey(data: bytes)
    }
}

struct AttachmentDurabilityNamespaceScope: Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let principalId: PrincipalID
    public let accountId: AccountID
    fileprivate let namespace: LocalDataNamespace

    init(
        validatedEnvironment: ValidatedLedgerEnvironment,
        principalId: PrincipalID,
        accountId: AccountID
    ) throws {
        environment = validatedEnvironment.manifest.environment
        self.principalId = principalId
        self.accountId = accountId
        namespace = try validatedEnvironment.localDataNamespace(
            principalID: principalId.rawValue,
            accountID: accountId.rawValue
        )
    }

    func contains(_ captureScope: AttachmentCaptureScope) -> Bool {
        environment == captureScope.environment &&
            principalId == captureScope.principalId &&
            accountId == captureScope.accountId
    }

    var databaseBindingFingerprint: String {
        let material = [
            "attachment_durability_scope_v1", namespace.root, environment.rawValue,
            principalId.rawValue, accountId.rawValue
        ].joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum AttachmentVaultCheckpoint: String, CaseIterable, Sendable {
    case beforeStagingWrite
    case afterStagingWrite
    case afterStagingSynchronization
    case beforePromotion
    case afterPromotion
    case beforeOrphanInventory
}

public enum AttachmentLocalByteVaultFailure: Error, Equatable, Sendable {
    case invalidMediaKey
    case invalidTrustedRoot
    case invalidNamespace
    case scopeMismatch
    case invalidLocalObjectIdentity
    case linkSubstitution
    case missingObject
    case corruptObject
    case storageFailure
    case interrupted(AttachmentVaultCheckpoint)

    public var diagnosticCode: String {
        switch self {
        case .invalidMediaKey: "attachment_vault_media_key_invalid"
        case .invalidTrustedRoot: "attachment_vault_root_invalid"
        case .invalidNamespace: "attachment_vault_namespace_invalid"
        case .scopeMismatch: "attachment_vault_scope_mismatch"
        case .invalidLocalObjectIdentity: "attachment_vault_object_identity_invalid"
        case .linkSubstitution: "attachment_vault_link_substitution"
        case .missingObject: "attachment_vault_object_missing"
        case .corruptObject: "attachment_vault_object_corrupt"
        case .storageFailure: "attachment_vault_storage_failed"
        case .interrupted(let checkpoint):
            "attachment_vault_interrupted_\(checkpoint.rawValue)"
        }
    }
}

public enum AttachmentVaultOrphanKind: String, Equatable, Sendable {
    case staging
    case finalObject
}

public struct AttachmentVaultOrphan: Equatable, Sendable {
    public let kind: AttachmentVaultOrphanKind
    public let opaqueIdentity: String
}

/// An app-managed encrypted byte store. It deliberately has no discard, delete,
/// eviction, remote-upload, or remote-success operation.
actor AttachmentLocalByteVault {
    private static let contract = "attachment_local_byte_vault_v1"
    private static let aesGCMCombinedOverhead = 28
    private static let mediaKeySentinelName = ".media-key-sentinel-v1"
    private static let mediaKeySentinelPlaintext = Data(
        "ledger-attachment-media-key-sentinel-v1".utf8
    )
    private static let reservedObjectNames: Set<String> = [
        ".", "..", "con", "prn", "aux", "nul",
        "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
        "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"
    ]

    private let namespace: LocalDataNamespace
    private let scope: AttachmentDurabilityNamespaceScope
    private let mediaKey: AttachmentMediaEncryptionKey
    private let trustedRoot: URL
    private let namespaceDirectory: URL
    private let objectsDirectory: URL
    private let stagingDirectory: URL
    private let trustedRootDescriptor: Int32
    private let namespaceDescriptor: Int32
    private let objectsDescriptor: Int32
    private let stagingDescriptor: Int32
    private let fault: @Sendable (AttachmentVaultCheckpoint) throws -> Void

    init(
        trustedRoot: URL,
        scope: AttachmentDurabilityNamespaceScope,
        mediaKey: AttachmentMediaEncryptionKey,
        fault: @Sendable @escaping (AttachmentVaultCheckpoint) throws -> Void = { _ in }
    ) throws {
        guard trustedRoot.isFileURL,
              trustedRoot.path.hasPrefix("/"),
              trustedRoot.standardizedFileURL.path == trustedRoot.path else {
            throw AttachmentLocalByteVaultFailure.invalidTrustedRoot
        }
        guard Self.isValidNamespace(scope.namespace.root) else {
            throw AttachmentLocalByteVaultFailure.invalidNamespace
        }

        let partition = Self.sha256Hex(
            Data(Self.partitionMaterial(namespace: scope.namespace, scope: scope).utf8)
        )
        let namespaceDirectory = trustedRoot.appendingPathComponent(partition, isDirectory: true)
        let objectsDirectory = namespaceDirectory.appendingPathComponent("objects", isDirectory: true)
        let stagingDirectory = namespaceDirectory.appendingPathComponent("staging", isDirectory: true)
        guard Self.isDirectChild(namespaceDirectory, of: trustedRoot),
              Self.isDirectChild(objectsDirectory, of: namespaceDirectory),
              Self.isDirectChild(stagingDirectory, of: namespaceDirectory) else {
            throw AttachmentLocalByteVaultFailure.invalidTrustedRoot
        }

        let trustedRootDescriptor: Int32
        let namespaceDescriptor: Int32
        let objectsDescriptor: Int32
        let stagingDescriptor: Int32
        do {
            trustedRootDescriptor = try Self.openTrustedRoot(trustedRoot)
            do {
                namespaceDescriptor = try Self.createAndOpenDirectory(
                    named: partition,
                    beneath: trustedRootDescriptor
                )
            } catch {
                Darwin.close(trustedRootDescriptor)
                throw error
            }
            do {
                objectsDescriptor = try Self.createAndOpenDirectory(
                    named: "objects",
                    beneath: namespaceDescriptor
                )
            } catch {
                Darwin.close(namespaceDescriptor)
                Darwin.close(trustedRootDescriptor)
                throw error
            }
            do {
                stagingDescriptor = try Self.createAndOpenDirectory(
                    named: "staging",
                    beneath: namespaceDescriptor
                )
            } catch {
                Darwin.close(objectsDescriptor)
                Darwin.close(namespaceDescriptor)
                Darwin.close(trustedRootDescriptor)
                throw error
            }
            do {
                try Self.applyProtectionAndBackupExclusion(namespaceDirectory)
                try Self.applyProtectionAndBackupExclusion(objectsDirectory)
                try Self.applyProtectionAndBackupExclusion(stagingDirectory)
                try Self.validateOrCreateMediaKeySentinel(
                    namespace: scope.namespace,
                    scope: scope,
                    mediaKey: mediaKey,
                    namespaceDirectory: namespaceDirectory,
                    namespaceDescriptor: namespaceDescriptor,
                    objectsDescriptor: objectsDescriptor,
                    stagingDescriptor: stagingDescriptor
                )
                try Self.synchronizeDirectory(namespaceDescriptor)
                try Self.synchronizeDirectory(objectsDescriptor)
                try Self.synchronizeDirectory(stagingDescriptor)
            } catch {
                Darwin.close(stagingDescriptor)
                Darwin.close(objectsDescriptor)
                Darwin.close(namespaceDescriptor)
                Darwin.close(trustedRootDescriptor)
                throw error
            }
        } catch let failure as AttachmentLocalByteVaultFailure {
            throw failure
        } catch {
            throw AttachmentLocalByteVaultFailure.storageFailure
        }

        namespace = scope.namespace
        self.scope = scope
        self.mediaKey = mediaKey
        self.trustedRoot = trustedRoot
        self.namespaceDirectory = namespaceDirectory
        self.objectsDirectory = objectsDirectory
        self.stagingDirectory = stagingDirectory
        self.trustedRootDescriptor = trustedRootDescriptor
        self.namespaceDescriptor = namespaceDescriptor
        self.objectsDescriptor = objectsDescriptor
        self.stagingDescriptor = stagingDescriptor
        self.fault = fault
    }

    deinit {
        Darwin.close(stagingDescriptor)
        Darwin.close(objectsDescriptor)
        Darwin.close(namespaceDescriptor)
        Darwin.close(trustedRootDescriptor)
    }

    public func persist(
        _ capture: LocalAttachmentCapture,
        persistedAt: AttachmentEpochMilliseconds
    ) throws -> AttachmentPersistedLocalObjectEvidence {
        guard scope.contains(capture.scope) else {
            throw AttachmentLocalByteVaultFailure.scopeMismatch
        }
        let objectID = try objectIdentity(for: capture.attachmentId)
        let evidence = try AttachmentPersistedLocalObjectEvidence(
            attachmentId: capture.attachmentId,
            scope: capture.scope,
            localObjectId: objectID,
            byteCount: capture.byteCount,
            contentSHA256: capture.contentSHA256,
            persistedAt: persistedAt
        )
        if try objectEntryExists(objectID.rawValue) {
            let existing = try verifiedBytes(for: evidence)
            guard existing == capture.bytes else {
                throw AttachmentLocalByteVaultFailure.corruptObject
            }
            return evidence
        }

        let aad = try associatedData(for: evidence)
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(capture.bytes, using: mediaKey.value, authenticating: aad)
        } catch {
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
        guard let encryptedBytes = sealed.combined else {
            throw AttachmentLocalByteVaultFailure.storageFailure
        }

        let stagingIdentity = "stage-\(UUID().uuidString.lowercased())"
        let stagingURL = stagingDirectory.appendingPathComponent(stagingIdentity, isDirectory: false)
        do {
            try invoke(.beforeStagingWrite)
            let descriptor = Darwin.openat(
                stagingDescriptor,
                stagingIdentity,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
            guard descriptor >= 0 else {
                throw AttachmentLocalByteVaultFailure.storageFailure
            }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                if !Self.protectionAttributes.isEmpty {
                    try FileManager.default.setAttributes(
                        Self.protectionAttributes,
                        ofItemAtPath: stagingURL.path
                    )
                }
                try Self.excludeFromBackup(stagingURL)
                try handle.write(contentsOf: encryptedBytes)
                try invoke(.afterStagingWrite)
                try handle.synchronize()
                try invoke(.afterStagingSynchronization)
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            try invoke(.beforePromotion)
            guard Darwin.renameatx_np(
                stagingDescriptor,
                stagingIdentity,
                objectsDescriptor,
                objectID.rawValue,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                if errno == EEXIST {
                    _ = Darwin.unlinkat(stagingDescriptor, stagingIdentity, 0)
                    let existing = try verifiedBytes(for: evidence)
                    guard existing == capture.bytes else {
                        throw AttachmentLocalByteVaultFailure.corruptObject
                    }
                    return evidence
                }
                throw AttachmentLocalByteVaultFailure.storageFailure
            }
            try Self.synchronizeDirectory(stagingDescriptor)
            try Self.synchronizeDirectory(objectsDescriptor)
            try invoke(.afterPromotion)
            _ = try verifiedBytes(for: evidence)
            return evidence
        } catch let failure as AttachmentLocalByteVaultFailure {
            throw failure
        } catch {
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
    }

    public func verifiedBytes(
        for evidence: AttachmentPersistedLocalObjectEvidence
    ) throws -> Data {
        guard scope.contains(evidence.scope) else {
            throw AttachmentLocalByteVaultFailure.scopeMismatch
        }
        let expectedObjectID = try objectIdentity(for: evidence.attachmentId)
        guard evidence.localObjectId == expectedObjectID else {
            throw AttachmentLocalByteVaultFailure.invalidLocalObjectIdentity
        }
        let encryptedBytes = try readRegularSingleLinkFile(
            named: evidence.localObjectId.rawValue,
            expectedPlaintextByteCount: evidence.byteCount
        )
        let aad = try associatedData(for: evidence)
        let clearBytes: Data
        do {
            let sealed = try AES.GCM.SealedBox(combined: encryptedBytes)
            clearBytes = try AES.GCM.open(sealed, using: mediaKey.value, authenticating: aad)
        } catch {
            throw AttachmentLocalByteVaultFailure.corruptObject
        }
        guard clearBytes.count == evidence.byteCount,
              try AttachmentContentSHA256.make(bytes: clearBytes) == evidence.contentSHA256 else {
            throw AttachmentLocalByteVaultFailure.corruptObject
        }
        return clearBytes
    }

    public func orphanInventory(
        referencedObjectIDs: Set<AttachmentLocalObjectID>
    ) throws -> [AttachmentVaultOrphan] {
        do {
            try invoke(.beforeOrphanInventory)
            let referenced = Set(referencedObjectIDs.map(\.rawValue))
            let staging = try Self.directoryEntryNames(stagingDescriptor).map {
                AttachmentVaultOrphan(kind: .staging, opaqueIdentity: $0)
            }
            let final = try Self.directoryEntryNames(objectsDescriptor).compactMap { name -> AttachmentVaultOrphan? in
                guard !referenced.contains(name) else { return nil }
                return AttachmentVaultOrphan(kind: .finalObject, opaqueIdentity: name)
            }
            return (staging + final).sorted {
                ($0.kind.rawValue, $0.opaqueIdentity) < ($1.kind.rawValue, $1.opaqueIdentity)
            }
        } catch let failure as AttachmentLocalByteVaultFailure {
            throw failure
        } catch {
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
    }

    // Path-bearing test hooks remain internal to the provider module.
    func objectFileURLForTesting(_ objectID: AttachmentLocalObjectID) throws -> URL {
        try objectURL(for: objectID)
    }

    func stagingDirectoryURLForTesting() -> URL { stagingDirectory }

    private func invoke(_ checkpoint: AttachmentVaultCheckpoint) throws {
        do {
            try fault(checkpoint)
        } catch let failure as AttachmentLocalByteVaultFailure {
            throw failure
        } catch {
            throw AttachmentLocalByteVaultFailure.interrupted(checkpoint)
        }
    }

    private func objectIdentity(for attachmentID: AttachmentID) throws -> AttachmentLocalObjectID {
        let material = [
            Self.contract, namespace.root, scope.environment.rawValue,
            scope.principalId.rawValue, scope.accountId.rawValue, attachmentID.rawValue
        ].joined(separator: "\u{1f}")
        return try AttachmentLocalObjectID(validating: Self.sha256Hex(Data(material.utf8)))
    }

    private func objectURL(for objectID: AttachmentLocalObjectID) throws -> URL {
        guard Self.isValidObjectIdentity(objectID.rawValue) else {
            throw AttachmentLocalByteVaultFailure.invalidLocalObjectIdentity
        }
        let url = objectsDirectory.appendingPathComponent(objectID.rawValue, isDirectory: false)
        guard Self.isDirectChild(url, of: objectsDirectory) else {
            throw AttachmentLocalByteVaultFailure.invalidLocalObjectIdentity
        }
        return url
    }

    private func associatedData(for evidence: AttachmentPersistedLocalObjectEvidence) throws -> Data {
        do {
            return try OperationContractCodec.encode(
                AuthenticatedMetadata(
                    contract: Self.contract,
                    namespace: namespace.root,
                    environment: evidence.scope.environment,
                    principalId: evidence.scope.principalId,
                    accountId: evidence.scope.accountId,
                    parent: evidence.scope.parent,
                    attachmentId: evidence.attachmentId,
                    localObjectId: evidence.localObjectId,
                    byteCount: evidence.byteCount,
                    contentSHA256: evidence.contentSHA256
                )
            )
        } catch {
            throw AttachmentLocalByteVaultFailure.corruptObject
        }
    }

    private func objectEntryExists(_ name: String) throws -> Bool {
        var metadata = stat()
        if Darwin.fstatat(objectsDescriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
            return true
        }
        if errno == ENOENT { return false }
        throw AttachmentLocalByteVaultFailure.storageFailure
    }

    private func readRegularSingleLinkFile(
        named name: String,
        expectedPlaintextByteCount: UInt64
    ) throws -> Data {
        guard Self.isValidObjectIdentity(name),
              expectedPlaintextByteCount <= UInt64(Int.max - Self.aesGCMCombinedOverhead) else {
            throw AttachmentLocalByteVaultFailure.corruptObject
        }
        let expectedCiphertextByteCount = Int(expectedPlaintextByteCount) + Self.aesGCMCombinedOverhead
        let descriptor = Darwin.openat(
            objectsDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ENOENT { throw AttachmentLocalByteVaultFailure.missingObject }
            throw AttachmentLocalByteVaultFailure.linkSubstitution
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            try? handle.close()
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
        guard metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1 else {
            try? handle.close()
            throw AttachmentLocalByteVaultFailure.linkSubstitution
        }
        guard metadata.st_size == expectedCiphertextByteCount else {
            try? handle.close()
            throw AttachmentLocalByteVaultFailure.corruptObject
        }
        do {
            let bytes = try handle.read(upToCount: expectedCiphertextByteCount) ?? Data()
            try handle.close()
            guard bytes.count == expectedCiphertextByteCount else {
                throw AttachmentLocalByteVaultFailure.corruptObject
            }
            return bytes
        } catch {
            try? handle.close()
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
    }

    private static func isValidNamespace(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return !value.isEmpty && value.utf8.count <= 240 &&
            !value.contains("..") && !value.contains("/") && !value.contains("\\") &&
            value.unicodeScalars.allSatisfy(allowed.contains) &&
            components.allSatisfy { !$0.isEmpty && !reservedObjectNames.contains($0.lowercased()) }
    }

    private static func isValidObjectIdentity(_ value: String) -> Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        return value.utf8.count == 64 && value.unicodeScalars.allSatisfy(hex.contains) &&
            !reservedObjectNames.contains(value.lowercased())
    }

    private static func partitionMaterial(
        namespace: LocalDataNamespace,
        scope: AttachmentDurabilityNamespaceScope
    ) -> String {
        [contract, namespace.root, scope.environment.rawValue,
         scope.principalId.rawValue, scope.accountId.rawValue].joined(separator: "\u{1f}")
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validateOrCreateMediaKeySentinel(
        namespace: LocalDataNamespace,
        scope: AttachmentDurabilityNamespaceScope,
        mediaKey: AttachmentMediaEncryptionKey,
        namespaceDirectory: URL,
        namespaceDescriptor: Int32,
        objectsDescriptor: Int32,
        stagingDescriptor: Int32
    ) throws {
        let associatedData = Data(
            [
                contract,
                "media-key-sentinel-v1",
                namespace.root,
                scope.environment.rawValue,
                scope.principalId.rawValue,
                scope.accountId.rawValue
            ].joined(separator: "\u{1f}").utf8
        )
        if try mediaKeySentinelExists(beneath: namespaceDescriptor) {
            try validateMediaKeySentinel(
                beneath: namespaceDescriptor,
                mediaKey: mediaKey,
                associatedData: associatedData
            )
            return
        }

        guard try directoryEntryNames(objectsDescriptor).isEmpty,
              try directoryEntryNames(stagingDescriptor).isEmpty else {
            throw AttachmentLocalByteVaultFailure.invalidMediaKey
        }

        let encryptedBytes: Data
        do {
            let sealed = try AES.GCM.seal(
                mediaKeySentinelPlaintext,
                using: mediaKey.value,
                authenticating: associatedData
            )
            guard let combined = sealed.combined else {
                throw AttachmentLocalByteVaultFailure.storageFailure
            }
            encryptedBytes = combined
        } catch let failure as AttachmentLocalByteVaultFailure {
            throw failure
        } catch {
            throw AttachmentLocalByteVaultFailure.storageFailure
        }

        let stagingName = ".media-key-sentinel-stage-\(UUID().uuidString.lowercased())"
        let stagingURL = namespaceDirectory.appendingPathComponent(stagingName, isDirectory: false)
        let descriptor = Darwin.openat(
            namespaceDescriptor,
            stagingName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            if !protectionAttributes.isEmpty {
                try FileManager.default.setAttributes(
                    protectionAttributes,
                    ofItemAtPath: stagingURL.path
                )
            }
            try excludeFromBackup(stagingURL)
            try handle.write(contentsOf: encryptedBytes)
            try handle.synchronize()
            try handle.close()

            if Darwin.renameatx_np(
                namespaceDescriptor,
                stagingName,
                namespaceDescriptor,
                mediaKeySentinelName,
                UInt32(RENAME_EXCL)
            ) != 0 {
                let renameError = errno
                _ = Darwin.unlinkat(namespaceDescriptor, stagingName, 0)
                guard renameError == EEXIST else {
                    throw AttachmentLocalByteVaultFailure.storageFailure
                }
            }
            try synchronizeDirectory(namespaceDescriptor)
            try validateMediaKeySentinel(
                beneath: namespaceDescriptor,
                mediaKey: mediaKey,
                associatedData: associatedData
            )
        } catch let failure as AttachmentLocalByteVaultFailure {
            try? handle.close()
            _ = Darwin.unlinkat(namespaceDescriptor, stagingName, 0)
            throw failure
        } catch {
            try? handle.close()
            _ = Darwin.unlinkat(namespaceDescriptor, stagingName, 0)
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
    }

    private static func mediaKeySentinelExists(beneath namespaceDescriptor: Int32) throws -> Bool {
        var metadata = stat()
        if Darwin.fstatat(
            namespaceDescriptor,
            mediaKeySentinelName,
            &metadata,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            return true
        }
        if errno == ENOENT { return false }
        throw AttachmentLocalByteVaultFailure.storageFailure
    }

    private static func validateMediaKeySentinel(
        beneath namespaceDescriptor: Int32,
        mediaKey: AttachmentMediaEncryptionKey,
        associatedData: Data
    ) throws {
        let expectedByteCount = mediaKeySentinelPlaintext.count + aesGCMCombinedOverhead
        let descriptor = Darwin.openat(
            namespaceDescriptor,
            mediaKeySentinelName,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ENOENT {
                throw AttachmentLocalByteVaultFailure.storageFailure
            }
            throw AttachmentLocalByteVaultFailure.linkSubstitution
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            try? handle.close()
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
        guard metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1 else {
            try? handle.close()
            throw AttachmentLocalByteVaultFailure.linkSubstitution
        }
        guard metadata.st_size == expectedByteCount else {
            try? handle.close()
            throw AttachmentLocalByteVaultFailure.invalidMediaKey
        }
        let encryptedBytes: Data
        do {
            encryptedBytes = try handle.read(upToCount: expectedByteCount) ?? Data()
            try handle.close()
        } catch {
            try? handle.close()
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
        guard encryptedBytes.count == expectedByteCount else {
            throw AttachmentLocalByteVaultFailure.invalidMediaKey
        }
        do {
            let sealed = try AES.GCM.SealedBox(combined: encryptedBytes)
            let clear = try AES.GCM.open(
                sealed,
                using: mediaKey.value,
                authenticating: associatedData
            )
            guard clear == mediaKeySentinelPlaintext else {
                throw AttachmentLocalByteVaultFailure.invalidMediaKey
            }
        } catch let failure as AttachmentLocalByteVaultFailure {
            throw failure
        } catch {
            throw AttachmentLocalByteVaultFailure.invalidMediaKey
        }
    }

    private static func isDirectChild(_ child: URL, of parent: URL) -> Bool {
        child.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL
    }

    private static var protectionAttributes: [FileAttributeKey: Any] {
#if os(iOS) || os(tvOS) || os(watchOS)
        [.protectionKey: FileProtectionType.complete]
#else
        [:]
#endif
    }

    private static func openTrustedRoot(_ url: URL) throws -> Int32 {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let name = url.lastPathComponent
        guard !name.isEmpty, parent.path != url.path else {
            throw AttachmentLocalByteVaultFailure.invalidTrustedRoot
        }
        let parentDescriptor = Darwin.open(
            parent.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard parentDescriptor >= 0 else {
            throw AttachmentLocalByteVaultFailure.invalidTrustedRoot
        }
        defer { Darwin.close(parentDescriptor) }

        var metadata = stat()
        var created = false
        if Darwin.fstatat(parentDescriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else {
                throw AttachmentLocalByteVaultFailure.invalidTrustedRoot
            }
            guard Darwin.mkdirat(parentDescriptor, name, S_IRWXU) == 0 else {
                throw AttachmentLocalByteVaultFailure.storageFailure
            }
            created = true
        } else if metadata.st_mode & S_IFMT != S_IFDIR {
            throw AttachmentLocalByteVaultFailure.linkSubstitution
        }
        let descriptor = Darwin.openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw AttachmentLocalByteVaultFailure.linkSubstitution
        }
        if created, Darwin.fsync(parentDescriptor) != 0 {
            Darwin.close(descriptor)
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
        return descriptor
    }

    private static func createAndOpenDirectory(named name: String, beneath parent: Int32) throws -> Int32 {
        let created: Bool
        if Darwin.mkdirat(parent, name, S_IRWXU) == 0 {
            created = true
        } else {
            guard errno == EEXIST else {
                throw AttachmentLocalByteVaultFailure.storageFailure
            }
            created = false
        }
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw AttachmentLocalByteVaultFailure.linkSubstitution
        }
        if created, Darwin.fsync(parent) != 0 {
            Darwin.close(descriptor)
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
        return descriptor
    }

    private static func applyProtectionAndBackupExclusion(_ url: URL) throws {
        if !protectionAttributes.isEmpty {
            try FileManager.default.setAttributes(
                protectionAttributes,
                ofItemAtPath: url.path
            )
        }
        try excludeFromBackup(url)
    }

    private static func directoryEntryNames(_ descriptor: Int32) throws -> [String] {
        let freshDescriptor = Darwin.openat(
            descriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard freshDescriptor >= 0 else {
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
        guard let directory = Darwin.fdopendir(freshDescriptor) else {
            Darwin.close(freshDescriptor)
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
        defer { Darwin.closedir(directory) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = Darwin.readdir(directory) else {
                guard errno == 0 else {
                    throw AttachmentLocalByteVaultFailure.storageFailure
                }
                break
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name != ".", name != "..", !name.hasPrefix(".") {
                names.append(name)
            }
        }
        return names
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private static func synchronizeDirectory(_ descriptor: Int32) throws {
        guard Darwin.fsync(descriptor) == 0 else {
            throw AttachmentLocalByteVaultFailure.storageFailure
        }
    }
}

private struct AuthenticatedMetadata: Codable, Sendable {
    let contract: String
    let namespace: String
    let environment: LedgerEnvironmentKind
    let principalId: PrincipalID
    let accountId: AccountID
    let parent: LedgerEntityReference
    let attachmentId: AttachmentID
    let localObjectId: AttachmentLocalObjectID
    let byteCount: UInt64
    let contentSHA256: AttachmentContentSHA256
}
