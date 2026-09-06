import CryptoKit
import Foundation

public enum ProjectNoteDataFailure: Error, Equatable, Sendable {
    case invalidText
    case invalidCreatorDisplayName
    case invalidSource
    case invalidAuditTime
    case incompleteEditAudit
    case invalidAuditOrder
    case invalidPageSize
    case cursorScopeMismatch
    case queryFingerprintMismatch
    case noteScopeMismatch
    case duplicateNoteIdentity
    case invalidNoteOrder
    case pageLimitExceeded
    case visibleCountMismatch
    case historyCompletenessMismatch
    case continuationBoundaryMismatch
    case requestMismatch
    case localReadFailed
    case invalidEncodedContentState
    case invalidEncodedNote
    case invalidEncodedCursor
    case invalidEncodedRequest
    case invalidEncodedPage

    public var diagnosticCode: String {
        switch self {
        case .invalidText:
            "project_note_text_invalid"
        case .invalidCreatorDisplayName:
            "project_note_creator_display_name_invalid"
        case .invalidSource:
            "project_note_source_invalid"
        case .invalidAuditTime:
            "project_note_audit_time_invalid"
        case .incompleteEditAudit:
            "project_note_edit_audit_incomplete"
        case .invalidAuditOrder:
            "project_note_audit_order_invalid"
        case .invalidPageSize:
            "project_note_page_size_invalid"
        case .cursorScopeMismatch:
            "project_note_cursor_scope_mismatch"
        case .queryFingerprintMismatch:
            "project_note_query_fingerprint_mismatch"
        case .noteScopeMismatch:
            "project_note_scope_mismatch"
        case .duplicateNoteIdentity:
            "project_note_identity_duplicate"
        case .invalidNoteOrder:
            "project_note_order_invalid"
        case .pageLimitExceeded:
            "project_note_page_limit_exceeded"
        case .visibleCountMismatch:
            "project_note_visible_count_mismatch"
        case .historyCompletenessMismatch:
            "project_note_history_completeness_mismatch"
        case .continuationBoundaryMismatch:
            "project_note_continuation_boundary_mismatch"
        case .requestMismatch:
            "project_note_request_mismatch"
        case .localReadFailed:
            "project_note_local_read_failed"
        case .invalidEncodedContentState:
            "project_note_content_state_encoding_invalid"
        case .invalidEncodedNote:
            "project_note_encoding_invalid"
        case .invalidEncodedCursor:
            "project_note_cursor_encoding_invalid"
        case .invalidEncodedRequest:
            "project_note_request_encoding_invalid"
        case .invalidEncodedPage:
            "project_note_page_encoding_invalid"
        }
    }
}

public enum ProjectNoteIDTag: Sendable {}
public typealias ProjectNoteID = DomainEntityIdentifier<ProjectNoteIDTag>

public struct ProjectNoteText: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectNoteDataFailure.invalidText
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectNoteDataFailure {
            throw failure
        } catch {
            throw ProjectNoteDataFailure.invalidText
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProjectNoteCreatorDisplayName: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectNoteDataFailure.invalidCreatorDisplayName
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectNoteDataFailure {
            throw failure
        } catch {
            throw ProjectNoteDataFailure.invalidCreatorDisplayName
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProjectNoteSource: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "_"))
        guard rawValue.utf8.count >= 1,
              rawValue.utf8.count <= 64,
              rawValue.first?.isLetter == true,
              rawValue.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ProjectNoteDataFailure.invalidSource
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch let failure as ProjectNoteDataFailure {
            throw failure
        } catch {
            throw ProjectNoteDataFailure.invalidSource
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProjectNoteDeletionAudit: Codable, Equatable, Sendable {
    public let deletedByPrincipalId: PrincipalID
    public let deletedAt: Date

    public init(deletedByPrincipalId: PrincipalID, deletedAt: Date) throws {
        guard deletedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectNoteDataFailure.invalidAuditTime
        }
        self.deletedByPrincipalId = deletedByPrincipalId
        self.deletedAt = deletedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                deletedByPrincipalId: container.decode(
                    PrincipalID.self,
                    forKey: .deletedByPrincipalId
                ),
                deletedAt: container.decode(Date.self, forKey: .deletedAt)
            )
        } catch let failure as ProjectNoteDataFailure {
            throw failure
        } catch {
            throw ProjectNoteDataFailure.invalidEncodedContentState
        }
    }

    private enum CodingKeys: String, CodingKey {
        case deletedByPrincipalId
        case deletedAt
    }
}

public enum ProjectNoteContentState: Codable, Equatable, Sendable {
    case visible(ProjectNoteText)
    case tombstone(ProjectNoteDeletionAudit)

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys>
        do {
            container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .visible:
                guard container.contains(.text), !container.contains(.deletion) else {
                    throw ProjectNoteDataFailure.invalidEncodedContentState
                }
                self = .visible(try container.decode(ProjectNoteText.self, forKey: .text))
            case .tombstone:
                guard container.contains(.deletion), !container.contains(.text) else {
                    throw ProjectNoteDataFailure.invalidEncodedContentState
                }
                self = .tombstone(
                    try container.decode(ProjectNoteDeletionAudit.self, forKey: .deletion)
                )
            }
        } catch let failure as ProjectNoteDataFailure {
            throw failure
        } catch {
            throw ProjectNoteDataFailure.invalidEncodedContentState
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .visible(let text):
            try container.encode(Kind.visible, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .tombstone(let deletion):
            try container.encode(Kind.tombstone, forKey: .kind)
            try container.encode(deletion, forKey: .deletion)
        }
    }

    private enum Kind: String, Codable {
        case visible
        case tombstone
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case deletion
    }
}

public struct ProjectNoteSnapshot: Codable, Equatable, Sendable {
    public let id: ProjectNoteID
    public let accountId: AccountID
    public let projectId: ProjectID
    public let content: ProjectNoteContentState
    public let source: ProjectNoteSource
    public let createdByPrincipalId: PrincipalID
    public let creatorDisplayName: ProjectNoteCreatorDisplayName?
    public let createdAt: Date
    public let revision: UInt64
    public let lastEditedByPrincipalId: PrincipalID?
    public let lastEditedAt: Date?

    public init(
        id: ProjectNoteID,
        accountId: AccountID,
        projectId: ProjectID,
        content: ProjectNoteContentState,
        source: ProjectNoteSource,
        createdByPrincipalId: PrincipalID,
        creatorDisplayName: ProjectNoteCreatorDisplayName?,
        createdAt: Date,
        revision: UInt64,
        lastEditedByPrincipalId: PrincipalID? = nil,
        lastEditedAt: Date? = nil
    ) throws {
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectNoteDataFailure.invalidAuditTime
        }
        if let lastEditedAt,
           !lastEditedAt.timeIntervalSinceReferenceDate.isFinite {
            throw ProjectNoteDataFailure.invalidAuditTime
        }
        guard (lastEditedByPrincipalId == nil) == (lastEditedAt == nil) else {
            throw ProjectNoteDataFailure.incompleteEditAudit
        }
        guard lastEditedAt.map({ createdAt <= $0 }) ?? true else {
            throw ProjectNoteDataFailure.invalidAuditOrder
        }
        if case .tombstone(let deletion) = content {
            guard createdAt <= deletion.deletedAt,
                  lastEditedAt.map({ $0 <= deletion.deletedAt }) ?? true else {
                throw ProjectNoteDataFailure.invalidAuditOrder
            }
        }
        self.id = id
        self.accountId = accountId
        self.projectId = projectId
        self.content = content
        self.source = source
        self.createdByPrincipalId = createdByPrincipalId
        self.creatorDisplayName = creatorDisplayName
        self.createdAt = createdAt
        self.revision = revision
        self.lastEditedByPrincipalId = lastEditedByPrincipalId
        self.lastEditedAt = lastEditedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: container.decode(ProjectNoteID.self, forKey: .id),
                accountId: container.decode(AccountID.self, forKey: .accountId),
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                content: container.decode(ProjectNoteContentState.self, forKey: .content),
                source: container.decode(ProjectNoteSource.self, forKey: .source),
                createdByPrincipalId: container.decode(
                    PrincipalID.self,
                    forKey: .createdByPrincipalId
                ),
                creatorDisplayName: container.decodeIfPresent(
                    ProjectNoteCreatorDisplayName.self,
                    forKey: .creatorDisplayName
                ),
                createdAt: container.decode(Date.self, forKey: .createdAt),
                revision: container.decode(UInt64.self, forKey: .revision),
                lastEditedByPrincipalId: container.decodeIfPresent(
                    PrincipalID.self,
                    forKey: .lastEditedByPrincipalId
                ),
                lastEditedAt: container.decodeIfPresent(Date.self, forKey: .lastEditedAt)
            )
        } catch let failure as ProjectNoteDataFailure {
            throw failure
        } catch {
            throw ProjectNoteDataFailure.invalidEncodedNote
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case projectId
        case content
        case source
        case createdByPrincipalId
        case creatorDisplayName
        case createdAt
        case revision
        case lastEditedByPrincipalId
        case lastEditedAt
    }
}

public struct ProjectNoteCursor: Codable, Equatable, Hashable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let createdAt: Date
    public let noteId: ProjectNoteID

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        createdAt: Date,
        noteId: ProjectNoteID
    ) throws {
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectNoteDataFailure.invalidAuditTime
        }
        self.accountId = accountId
        self.projectId = projectId
        self.createdAt = createdAt
        self.noteId = noteId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                createdAt: container.decode(Date.self, forKey: .createdAt),
                noteId: container.decode(ProjectNoteID.self, forKey: .noteId)
            )
        } catch let failure as ProjectNoteDataFailure {
            throw failure
        } catch {
            throw ProjectNoteDataFailure.invalidEncodedCursor
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case projectId
        case createdAt
        case noteId
    }
}

public struct ProjectNotePageRequest: Codable, Equatable, Sendable {
    public static let maximumPageSize: UInt16 = 200

    public let accountId: AccountID
    public let projectId: ProjectID
    public let pageSize: UInt16
    public let after: ProjectNoteCursor?
    public let queryFingerprint: ListQueryFingerprint

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        pageSize: UInt16,
        after: ProjectNoteCursor? = nil
    ) throws {
        guard pageSize > 0, pageSize <= Self.maximumPageSize else {
            throw ProjectNoteDataFailure.invalidPageSize
        }
        guard after.map({ $0.accountId == accountId && $0.projectId == projectId }) ?? true else {
            throw ProjectNoteDataFailure.cursorScopeMismatch
        }
        self.accountId = accountId
        self.projectId = projectId
        self.pageSize = pageSize
        self.after = after
        queryFingerprint = try Self.makeFingerprint(
            accountId: accountId,
            projectId: projectId,
            pageSize: pageSize,
            after: after
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                pageSize: container.decode(UInt16.self, forKey: .pageSize),
                after: container.decodeIfPresent(ProjectNoteCursor.self, forKey: .after)
            )
        } catch let failure as ProjectNoteDataFailure {
            throw failure
        } catch {
            throw ProjectNoteDataFailure.invalidEncodedRequest
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(pageSize, forKey: .pageSize)
        try container.encodeIfPresent(after, forKey: .after)
    }

    private static func makeFingerprint(
        accountId: AccountID,
        projectId: ProjectID,
        pageSize: UInt16,
        after: ProjectNoteCursor?
    ) throws -> ListQueryFingerprint {
        let basis = FingerprintBasis(
            accountId: accountId,
            projectId: projectId,
            pageSize: pageSize,
            after: after
        )
        let bytes = try OperationContractCodec.encode(basis)
        let digest = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
        return try ListQueryFingerprint(validating: digest)
    }

    private struct FingerprintBasis: Codable {
        let accountId: AccountID
        let projectId: ProjectID
        let pageSize: UInt16
        let after: ProjectNoteCursor?
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case projectId
        case pageSize
        case after
    }
}

public struct ProjectNotePage: Codable, Equatable, Sendable {
    public let request: ProjectNotePageRequest
    public let local: ListLocalSnapshot<ProjectNoteSnapshot>
    public let isCompleteForProjectHistory: Bool
    public let nextCursor: ProjectNoteCursor?

    public init(
        request: ProjectNotePageRequest,
        local: ListLocalSnapshot<ProjectNoteSnapshot>,
        isCompleteForProjectHistory: Bool,
        nextCursor: ProjectNoteCursor?
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectNoteDataFailure.invalidAuditTime
        }
        guard local.queryFingerprint == request.queryFingerprint else {
            throw ProjectNoteDataFailure.queryFingerprintMismatch
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw ProjectNoteDataFailure.visibleCountMismatch
        }
        guard local.rows.count <= Int(request.pageSize) else {
            throw ProjectNoteDataFailure.pageLimitExceeded
        }
        guard local.rows.allSatisfy({
            $0.accountId == request.accountId && $0.projectId == request.projectId
        }) else {
            throw ProjectNoteDataFailure.noteScopeMismatch
        }
        guard Set(local.rows.map(\.id)).count == local.rows.count else {
            throw ProjectNoteDataFailure.duplicateNoteIdentity
        }
        guard Self.isStrictlyOrdered(local.rows) else {
            throw ProjectNoteDataFailure.invalidNoteOrder
        }
        if let after = request.after {
            guard local.rows.allSatisfy({ Self.precedes(after, $0) }) else {
                throw ProjectNoteDataFailure.invalidNoteOrder
            }
        }
        guard !isCompleteForProjectHistory || local.isCompleteForQuery else {
            throw ProjectNoteDataFailure.historyCompletenessMismatch
        }
        if let nextCursor {
            guard !isCompleteForProjectHistory,
                  nextCursor.accountId == request.accountId,
                  nextCursor.projectId == request.projectId,
                  let last = local.rows.last,
                  nextCursor.createdAt == last.createdAt,
                  nextCursor.noteId == last.id else {
                throw ProjectNoteDataFailure.continuationBoundaryMismatch
            }
        }
        self.request = request
        self.local = local
        self.isCompleteForProjectHistory = isCompleteForProjectHistory
        self.nextCursor = nextCursor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                request: container.decode(ProjectNotePageRequest.self, forKey: .request),
                local: container.decode(
                    ListLocalSnapshot<ProjectNoteSnapshot>.self,
                    forKey: .local
                ),
                isCompleteForProjectHistory: container.decode(
                    Bool.self,
                    forKey: .isCompleteForProjectHistory
                ),
                nextCursor: container.decodeIfPresent(
                    ProjectNoteCursor.self,
                    forKey: .nextCursor
                )
            )
        } catch let failure as ProjectNoteDataFailure {
            throw failure
        } catch {
            throw ProjectNoteDataFailure.invalidEncodedPage
        }
    }

    private static func isStrictlyOrdered(_ notes: [ProjectNoteSnapshot]) -> Bool {
        zip(notes, notes.dropFirst()).allSatisfy { earlier, later in
            precedes(earlier.createdAt, earlier.id, later.createdAt, later.id)
        }
    }

    private static func precedes(
        _ cursor: ProjectNoteCursor,
        _ note: ProjectNoteSnapshot
    ) -> Bool {
        precedes(cursor.createdAt, cursor.noteId, note.createdAt, note.id)
    }

    private static func precedes(
        _ lhsDate: Date,
        _ lhsId: ProjectNoteID,
        _ rhsDate: Date,
        _ rhsId: ProjectNoteID
    ) -> Bool {
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhsId.rawValue > rhsId.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case local
        case isCompleteForProjectHistory
        case nextCursor
    }
}

public protocol ProjectNoteQuerying: Sendable {
    func watchNotes(
        _ request: ProjectNotePageRequest
    ) -> AsyncThrowingStream<ProjectNotePage, Error>
}
