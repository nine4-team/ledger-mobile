import Foundation

public enum VendorSuggestionReferenceFailure: Error, Equatable, Sendable {
    case invalidDisplayValue
    case accountScopeMismatch
    case duplicateSuggestionIdentity
    case duplicateNormalizedValue
    case duplicatePresentationOrder
    case visibleCountMismatch
    case invalidSnapshotAsOf
    case localReadFailed
    case invalidEncodedDisplayValue
    case invalidEncodedSuggestion
    case invalidEncodedSnapshot

    public var diagnosticCode: String {
        switch self {
        case .invalidDisplayValue:
            "vendor_suggestion_display_value_invalid"
        case .accountScopeMismatch:
            "vendor_suggestion_account_scope_mismatch"
        case .duplicateSuggestionIdentity:
            "vendor_suggestion_identity_duplicate"
        case .duplicateNormalizedValue:
            "vendor_suggestion_normalized_value_duplicate"
        case .duplicatePresentationOrder:
            "vendor_suggestion_order_duplicate"
        case .visibleCountMismatch:
            "vendor_suggestion_visible_count_mismatch"
        case .invalidSnapshotAsOf:
            "vendor_suggestion_as_of_invalid"
        case .localReadFailed:
            "vendor_suggestion_local_read_failed"
        case .invalidEncodedDisplayValue:
            "vendor_suggestion_display_value_encoding_invalid"
        case .invalidEncodedSuggestion:
            "vendor_suggestion_encoding_invalid"
        case .invalidEncodedSnapshot:
            "vendor_suggestion_snapshot_encoding_invalid"
        }
    }
}

public enum VendorSuggestionIDTag: Sendable {}
public typealias VendorSuggestionID = DomainEntityIdentifier<VendorSuggestionIDTag>

public struct VendorSuggestionDisplayValue: Codable, Equatable, Hashable, Sendable {
    public static let maximumUTF8ByteCount = 200

    public let rawValue: String
    public let normalizedComparisonKey: String

    public init(validating rawValue: String) throws {
        let containsControlCharacter = rawValue.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        let displayValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = displayValue
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        guard !displayValue.isEmpty,
              displayValue.utf8.count <= Self.maximumUTF8ByteCount,
              !containsControlCharacter,
              !normalizedValue.isEmpty else {
            throw VendorSuggestionReferenceFailure.invalidDisplayValue
        }
        self.rawValue = displayValue
        normalizedComparisonKey = normalizedValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as VendorSuggestionReferenceFailure {
            throw failure
        } catch {
            throw VendorSuggestionReferenceFailure.invalidEncodedDisplayValue
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct VendorSuggestionSnapshot: Codable, Equatable, Sendable {
    public let id: VendorSuggestionID
    public let accountId: AccountID
    public let displayValue: VendorSuggestionDisplayValue
    public let lifecycle: DirectoryLifecycleState
    public let presentationOrder: UInt32
    public let revision: UInt64

    public var isSelectable: Bool {
        lifecycle == .active
    }

    public var sourceSnapshot: String {
        displayValue.rawValue
    }

    public init(
        id: VendorSuggestionID,
        accountId: AccountID,
        displayValue: VendorSuggestionDisplayValue,
        lifecycle: DirectoryLifecycleState,
        presentationOrder: UInt32,
        revision: UInt64
    ) {
        self.id = id
        self.accountId = accountId
        self.displayValue = displayValue
        self.lifecycle = lifecycle
        self.presentationOrder = presentationOrder
        self.revision = revision
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(VendorSuggestionID.self, forKey: .id),
                accountId: try container.decode(AccountID.self, forKey: .accountId),
                displayValue: try container.decode(
                    VendorSuggestionDisplayValue.self,
                    forKey: .displayValue
                ),
                lifecycle: try container.decode(
                    DirectoryLifecycleState.self,
                    forKey: .lifecycle
                ),
                presentationOrder: try container.decode(
                    UInt32.self,
                    forKey: .presentationOrder
                ),
                revision: try container.decode(UInt64.self, forKey: .revision)
            )
        } catch let failure as VendorSuggestionReferenceFailure {
            throw failure
        } catch {
            throw VendorSuggestionReferenceFailure.invalidEncodedSuggestion
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case displayValue
        case lifecycle
        case presentationOrder
        case revision
    }
}

public struct VendorSuggestionReferenceSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let local: ListLocalSnapshot<VendorSuggestionSnapshot>

    public var selectableSuggestions: [VendorSuggestionSnapshot] {
        local.rows.filter(\.isSelectable)
    }

    public var selectableSourceSnapshots: [String] {
        selectableSuggestions.map(\.sourceSnapshot)
    }

    public init(
        accountId: AccountID,
        local: ListLocalSnapshot<VendorSuggestionSnapshot>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw VendorSuggestionReferenceFailure.invalidSnapshotAsOf
        }
        guard local.rows.allSatisfy({ $0.accountId == accountId }) else {
            throw VendorSuggestionReferenceFailure.accountScopeMismatch
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw VendorSuggestionReferenceFailure.visibleCountMismatch
        }
        guard Self.firstDuplicate(local.rows.map(\.id)) == nil else {
            throw VendorSuggestionReferenceFailure.duplicateSuggestionIdentity
        }
        guard Self.firstDuplicate(
            local.rows.map { $0.displayValue.normalizedComparisonKey }
        ) == nil else {
            throw VendorSuggestionReferenceFailure.duplicateNormalizedValue
        }
        guard Self.firstDuplicate(local.rows.map(\.presentationOrder)) == nil else {
            throw VendorSuggestionReferenceFailure.duplicatePresentationOrder
        }

        let rows = local.rows.sorted {
            if $0.presentationOrder != $1.presentationOrder {
                return $0.presentationOrder < $1.presentationOrder
            }
            return $0.id.rawValue < $1.id.rawValue
        }
        self.accountId = accountId
        self.local = try ListLocalSnapshot(
            queryFingerprint: local.queryFingerprint,
            rows: rows,
            visibleRowCountBeforeFiltering: local.visibleRowCountBeforeFiltering,
            isCompleteForQuery: local.isCompleteForQuery,
            quality: local.quality,
            localDataVersion: local.localDataVersion,
            asOf: local.asOf
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                local: container.decode(
                    ListLocalSnapshot<VendorSuggestionSnapshot>.self,
                    forKey: .local
                )
            )
        } catch let failure as VendorSuggestionReferenceFailure {
            throw failure
        } catch {
            throw VendorSuggestionReferenceFailure.invalidEncodedSnapshot
        }
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case local
    }
}

public protocol VendorSuggestionQuerying: Sendable {
    func watchVendorSuggestions(
        accountId: AccountID
    ) -> AsyncThrowingStream<VendorSuggestionReferenceSnapshot, Error>
}
