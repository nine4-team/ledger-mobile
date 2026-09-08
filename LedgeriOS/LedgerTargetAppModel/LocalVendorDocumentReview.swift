import Foundation
import LedgerTargetCore
import Observation

/// A document review is not an accepted Item, receipt, or payment operation.
/// Original extracted values stay intact while the user edits a separate draft.
public struct LocalVendorDocumentThumbnail: Equatable, Sendable {
    public struct Bounds: Equatable, Sendable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }
    public let pngBytes: Data
    public let pageIndex: Int
    public let anchorRange: NSRange
    public let imageBounds: Bounds

    public init(pngBytes: Data, pageIndex: Int, anchorRange: NSRange, imageBounds: Bounds) {
        self.pngBytes = pngBytes; self.pageIndex = pageIndex
        self.anchorRange = anchorRange; self.imageBounds = imageBounds
    }
}

public struct LocalVendorDocumentRow: Equatable, Sendable, Identifiable {
    public let id: Int
    public let description: String
    public let quantity: Int
    public let unitPrice: String?
    public let total: String
    public let sku: String?
    public let attributes: [String]
    public let details: [String: String]
    public let thumbnail: LocalVendorDocumentThumbnail?

    public init(id: Int, description: String, quantity: Int, unitPrice: String?,
                total: String, sku: String? = nil, attributes: [String] = [], details: [String: String] = [:],
                thumbnail: LocalVendorDocumentThumbnail? = nil) {
        self.id = id; self.description = description; self.quantity = quantity
        self.unitPrice = unitPrice; self.total = total; self.sku = sku; self.attributes = attributes
        self.details = details
        self.thumbnail = thumbnail
    }
}

public struct LocalVendorDocument: Equatable, Sendable {
    public enum Vendor: String, Sendable { case amazon, wayfair }
    public let vendor: Vendor
    public let fields: [String: String]
    public let rows: [LocalVendorDocumentRow]
    public let warnings: [String]
    public let rawText: String
    public let pageCount: Int

    /// Keep raw parser evidence intact without presenting legacy date-default
    /// advice as a valid target accounting choice.
    public var reviewWarnings: [String] {
        warnings.map { warning in
            warning == "Could not confidently find an order date; defaulting to today is recommended."
                ? "The order date could not be found. No date has been assumed."
                : warning
        }
    }

    public init(vendor: Vendor, fields: [String: String], rows: [LocalVendorDocumentRow],
                warnings: [String], rawText: String, pageCount: Int) {
        self.vendor = vendor; self.fields = fields; self.rows = rows
        self.warnings = warnings; self.rawText = rawText; self.pageCount = pageCount
    }
}

public enum LocalVendorDocumentFailure: Error, Equatable {
    case corruptDocument, imageOnlyDocument, unsupportedVendor, ambiguousVendor, invalidRowIdentity
}

public protocol LocalVendorDocumentParsing: Sendable {
    func parse(_ bytes: Data) async throws -> LocalVendorDocument
}

public struct LocalVendorDocumentDraftRow: Equatable, Sendable, Identifiable {
    public let id: Int
    public let original: LocalVendorDocumentRow
    public var description: String
    public var quantity: String
    public var unitPrice: String
    public var included: Bool

    init(_ original: LocalVendorDocumentRow) {
        self.id = original.id; self.original = original
        description = original.description; quantity = String(original.quantity)
        unitPrice = original.unitPrice ?? ""; included = true
    }
}

@MainActor @Observable
public final class LocalVendorDocumentReview {
    public enum State: Equatable { case empty, extracting, review, failed(LocalVendorDocumentFailure) }
    public let accountId: AccountID
    public private(set) var isClosed = false
    public private(set) var state: State = .empty
    public private(set) var document: LocalVendorDocument?
    public private(set) var documentHash: ProtectedArtifactSHA256?
    public private(set) var sourceBytes: Data?
    public private(set) var rows: [LocalVendorDocumentDraftRow] = []
    public private(set) var categories: [BudgetCategoryDefinitionSnapshot] = []
    public private(set) var selectedCategoryId: BudgetCategoryID?
    public private(set) var categoryStatus = "Category data is loading or unavailable."
    private var generation: UInt64 = 0

    public init(accountId: AccountID) { self.accountId = accountId }
    public var includedCount: Int { rows.filter(\.included).count }

    public func receiveCategories(_ snapshot: BudgetCategoryReferenceSnapshot) {
        guard !isClosed else { return }
        guard snapshot.accountId == accountId else { categoriesUnavailable(); return }
        categories = snapshot.local.rows.filter(\.isSelectableForProjectConfiguration)
        categoryStatus = snapshot.local.isCompleteForQuery
            ? (categories.isEmpty ? "No selectable categories." : "Downloaded categories.")
            : "Category download is incomplete; showing available choices."
        if let selectedCategoryId, !categories.contains(where: { $0.id == selectedCategoryId }) {
            self.selectedCategoryId = nil
            categoryStatus = "The selected category is no longer available. Choose again."
        }
    }

    public func selectCategory(_ id: BudgetCategoryID?) {
        guard state == .review, id == nil || categories.contains(where: { $0.id == id }) else { return }
        selectedCategoryId = id
    }

    public func categoriesUnavailable() {
        guard !isClosed else { return }
        categories = []; selectedCategoryId = nil
        categoryStatus = "Category data is unavailable. Review edits are unchanged."
    }

    public func load(_ bytes: Data, parser: any LocalVendorDocumentParsing) async {
        guard !isClosed, !Task.isCancelled else { return }
        clear()
        let requestGeneration = generation
        state = .extracting
        do {
            let hash = try ProtectedArtifactSHA256.make(bytes: bytes)
            let parsed = try await parser.parse(bytes)
            guard requestGeneration == generation else { return }
            if Task.isCancelled { clear(); return }
            guard parsed.rows.map(\.id) == Array(parsed.rows.indices) else {
                throw LocalVendorDocumentFailure.invalidRowIdentity
            }
            document = parsed; documentHash = hash; sourceBytes = bytes
            rows = parsed.rows.map(LocalVendorDocumentDraftRow.init)
            state = .review
        } catch {
            guard requestGeneration == generation else { return }
            if Task.isCancelled { clear(); return }
            state = .failed((error as? LocalVendorDocumentFailure) ?? .corruptDocument)
        }
    }

    /// Identity is (Account, document digest, original row ordinal), not the
    /// current included-row position. Editing never changes source evidence.
    public func update(id: Int, documentHash expectedHash: ProtectedArtifactSHA256,
                       edit: (inout LocalVendorDocumentDraftRow) -> Void) {
        guard state == .review, documentHash == expectedHash,
              let index = rows.firstIndex(where: { $0.id == id }) else { return }
        var draft = rows[index]
        edit(&draft)
        guard draft.id == id, draft.original == rows[index].original else { return }
        rows[index] = draft
    }

    public func clear() {
        generation &+= 1
        document = nil; documentHash = nil; sourceBytes = nil; rows = []
        selectedCategoryId = nil
        state = .empty
    }

    /// Closing the sheet is terminal. Late picker/read completions cannot start
    /// another document in this session; opening a new sheet creates a new model.
    public func close() {
        isClosed = true
        clear()
        categories = []
        categoryStatus = "Review closed."
    }
}
