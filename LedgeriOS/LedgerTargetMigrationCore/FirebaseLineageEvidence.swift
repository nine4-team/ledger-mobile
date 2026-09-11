import Foundation

/// Source movement labels are retained as evidence only. In particular,
/// `returned` describes the legacy lineage document and does not establish a
/// client cash refund or any target accounting event.
public enum FirebaseLineageMovementKind: String, Equatable, Sendable {
    case sold
    case soldToInventory
    case returned
    case correction
    case association
}

public struct FirebaseLineageTimestamp: Equatable, Sendable {
    public let seconds: String
    public let nanoseconds: Int

    public init(seconds: String, nanoseconds: Int) {
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }
}

public enum FirebaseLineageEvidenceIssue: Equatable, Sendable {
    case invalidSourceAccountScopeID
    case invalidLineageDocumentID
    case invalidRawFields
    case missingRequiredField(String)
    case nullRequiredField(String)
    case invalidField(String)
    case crossAccount(expected: String, actual: String)
    case unknownMovementKind(String)
}

/// A lossless, structural reading of one legacy `lineageEdges` document.
///
/// This type deliberately does not decide target accounting meaning or verify
/// that referenced source documents exist. Those checks require the complete
/// exact-account source snapshot and belong to batch reconciliation.
public struct FirebaseLineageEvidence: Equatable, Sendable {
    public let sourceAccountScopeID: String
    public let lineageDocumentID: String
    public let rawFields: [FirebaseSourceMapEntry]

    public let accountID: String?
    public let itemID: String?
    public let fromTransactionID: String?
    public let toTransactionID: String?
    public let fromProjectID: String?
    public let toProjectID: String?
    public let movementKind: FirebaseLineageMovementKind?
    public let movementKindRaw: String?
    public let actorID: String?
    public let note: String?
    public let source: String?
    public let createdAt: FirebaseLineageTimestamp?
    public let issues: [FirebaseLineageEvidenceIssue]

    public var isStructurallyValid: Bool { issues.isEmpty }
}

public enum FirebaseLineageEvidenceReader {
    public static func read(
        accountScopeID: String,
        documentID: String,
        fields: [FirebaseSourceMapEntry]
    ) -> FirebaseLineageEvidence {
        var issues: [FirebaseLineageEvidenceIssue] = []
        let rawMap = FirebaseSourceValue.map(fields)
        if (try? rawMap.validated()) == nil {
            issues.append(.invalidRawFields)
        }
        if !isSourceDocumentID(accountScopeID) {
            issues.append(.invalidSourceAccountScopeID)
        }
        if !isSourceDocumentID(documentID) {
            issues.append(.invalidLineageDocumentID)
        }

        let accountID = string(
            "accountId",
            required: true,
            allowEmpty: false,
            documentID: true,
            fields: fields,
            issues: &issues
        )
        let itemID = string(
            "itemId",
            required: true,
            allowEmpty: false,
            documentID: true,
            fields: fields,
            issues: &issues
        )
        let fromTransactionID = string(
            "fromTransactionId",
            required: false,
            allowEmpty: false,
            documentID: true,
            fields: fields,
            issues: &issues
        )
        let toTransactionID = string(
            "toTransactionId",
            required: false,
            allowEmpty: false,
            documentID: true,
            fields: fields,
            issues: &issues
        )
        let fromProjectID = string(
            "fromProjectId",
            required: false,
            allowEmpty: false,
            documentID: true,
            fields: fields,
            issues: &issues
        )
        let toProjectID = string(
            "toProjectId",
            required: false,
            allowEmpty: false,
            documentID: true,
            fields: fields,
            issues: &issues
        )
        let movementKindRaw = string(
            "movementKind",
            required: true,
            allowEmpty: false,
            documentID: false,
            fields: fields,
            issues: &issues
        )
        let movementKind = movementKindRaw.flatMap(FirebaseLineageMovementKind.init(rawValue:))
        if let movementKindRaw, movementKind == nil {
            issues.append(.unknownMovementKind(movementKindRaw))
        }
        let actorID = string(
            "createdBy",
            required: false,
            allowEmpty: false,
            documentID: true,
            fields: fields,
            issues: &issues
        )
        let note = string(
            "note",
            required: false,
            allowEmpty: true,
            documentID: false,
            fields: fields,
            issues: &issues
        )
        let source = string(
            "source",
            required: false,
            allowEmpty: true,
            documentID: false,
            fields: fields,
            issues: &issues
        )
        let createdAt = timestamp(
            "createdAt",
            required: true,
            fields: fields,
            issues: &issues
        )

        if let accountID, !utf8Equal(accountID, accountScopeID) {
            issues.append(.crossAccount(expected: accountScopeID, actual: accountID))
        }

        return FirebaseLineageEvidence(
            sourceAccountScopeID: accountScopeID,
            lineageDocumentID: documentID,
            rawFields: fields,
            accountID: accountID,
            itemID: itemID,
            fromTransactionID: fromTransactionID,
            toTransactionID: toTransactionID,
            fromProjectID: fromProjectID,
            toProjectID: toProjectID,
            movementKind: movementKind,
            movementKindRaw: movementKindRaw,
            actorID: actorID,
            note: note,
            source: source,
            createdAt: createdAt,
            issues: issues
        )
    }

    private static func string(
        _ key: String,
        required: Bool,
        allowEmpty: Bool,
        documentID: Bool,
        fields: [FirebaseSourceMapEntry],
        issues: inout [FirebaseLineageEvidenceIssue]
    ) -> String? {
        let values = fields.filter { $0.key == key }.map(\.value)
        guard values.count <= 1 else {
            issues.append(.invalidField(key))
            return nil
        }
        guard let value = values.first else {
            if required { issues.append(.missingRequiredField(key)) }
            return nil
        }
        if case .null = value {
            if required { issues.append(.nullRequiredField(key)) }
            return nil
        }
        guard case .string(let decoded) = value,
              allowEmpty || !decoded.isEmpty,
              !documentID || isSourceDocumentID(decoded) else {
            issues.append(.invalidField(key))
            return nil
        }
        return decoded
    }

    private static func timestamp(
        _ key: String,
        required: Bool,
        fields: [FirebaseSourceMapEntry],
        issues: inout [FirebaseLineageEvidenceIssue]
    ) -> FirebaseLineageTimestamp? {
        let values = fields.filter { $0.key == key }.map(\.value)
        guard values.count <= 1 else {
            issues.append(.invalidField(key))
            return nil
        }
        guard let value = values.first else {
            if required { issues.append(.missingRequiredField(key)) }
            return nil
        }
        if case .null = value {
            if required { issues.append(.nullRequiredField(key)) }
            return nil
        }
        guard case .timestamp(let seconds, let nanoseconds) = value,
              (try? value.validated()) != nil else {
            issues.append(.invalidField(key))
            return nil
        }
        return FirebaseLineageTimestamp(seconds: seconds, nanoseconds: nanoseconds)
    }

    private static func isSourceDocumentID(_ value: String) -> Bool {
        (1...1_500).contains(value.utf8.count)
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\0")
    }

    private static func utf8Equal(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }
}
