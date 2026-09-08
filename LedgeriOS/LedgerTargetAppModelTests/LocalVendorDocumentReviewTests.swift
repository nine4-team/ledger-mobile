import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Local vendor document review") @MainActor
struct LocalVendorDocumentReviewTests {
    private struct Parser: LocalVendorDocumentParsing {
        var result: LocalVendorDocument
        func parse(_ bytes: Data) async throws -> LocalVendorDocument { result }
    }

    @Test("Review edits retain original values and excluded-row identity")
    func edits() async throws {
        let review = LocalVendorDocumentReview(accountId: try AccountID(validating: "review-account"))
        let source = document()
        await review.load(Data("document-a".utf8), parser: Parser(result: source))
        let hash = try #require(review.documentHash)
        review.update(id: 0, documentHash: hash) { $0.included = false }
        review.update(id: 1, documentHash: hash) { row in
            row.description = "Reviewed chair"; row.quantity = "3"; row.unitPrice = "12.34"
        }
        #expect(review.includedCount == 1)
        #expect(review.rows[1].id == 1)
        #expect(review.rows[1].original == source.rows[1])
        #expect(review.rows[1].original.thumbnail?.pngBytes == Data("row-1-image".utf8))
        #expect(review.rows[0].original.thumbnail == nil)
        #expect(review.document == source)
        #expect(review.rows[1].description == "Reviewed chair")
        #expect(review.sourceBytes == Data("document-a".utf8))
        #expect(review.rows[0].unitPrice.isEmpty) // No line-total fallback.
        let otherRow = review.rows[1]
        review.update(id: 0, documentHash: hash) { $0 = otherRow }
        #expect(review.rows[0].id == 0 && review.rows[0].original == source.rows[0])

        await review.load(Data("document-b".utf8), parser: Parser(result: source))
        review.update(id: 1, documentHash: hash) { $0.description = "Stale edit" }
        #expect(review.rows[1].description == "Chair")
    }

    @Test("Cancellation cannot restore late extraction", arguments: [false, true])
    func cancel(clearExplicitly: Bool) async throws {
        actor Delayed: LocalVendorDocumentParsing {
            var continuation: CheckedContinuation<LocalVendorDocument, Never>?
            func parse(_ bytes: Data) async throws -> LocalVendorDocument {
                await withCheckedContinuation { continuation = $0 }
            }
            var started: Bool { continuation != nil }
            func finish(_ document: LocalVendorDocument) { continuation?.resume(returning: document); continuation = nil }
        }
        let parser = Delayed()
        let review = LocalVendorDocumentReview(accountId: try AccountID(validating: "review-account"))
        let load = Task { await review.load(Data("document".utf8), parser: parser) }
        while !(await parser.started) { await Task.yield() }
        if clearExplicitly { review.clear() } else { load.cancel() }
        await parser.finish(document())
        await load.value
        #expect(review.state == .empty)
        #expect(review.document == nil && review.sourceBytes == nil && review.documentHash == nil)
        #expect(review.rows.isEmpty)
    }

    @Test("An older parse cannot replace a newer document or its edits", arguments: [false, true])
    func overlappingDocuments(oldParseFails: Bool) async throws {
        actor Delayed: LocalVendorDocumentParsing {
            var continuation: CheckedContinuation<LocalVendorDocument, Error>?
            func parse(_ bytes: Data) async throws -> LocalVendorDocument {
                try await withCheckedThrowingContinuation { continuation = $0 }
            }
            var started: Bool { continuation != nil }
            func finish(_ document: LocalVendorDocument, fails: Bool) {
                if fails { continuation?.resume(throwing: LocalVendorDocumentFailure.corruptDocument) }
                else { continuation?.resume(returning: document) }
                continuation = nil
            }
        }
        let parser = Delayed()
        let review = LocalVendorDocumentReview(accountId: try AccountID(validating: "review-account"))
        let oldLoad = Task { await review.load(Data("older PDF".utf8), parser: parser) }
        while !(await parser.started) { await Task.yield() }
        #expect(review.state == .extracting)
        let currentBytes = Data("newer PDF".utf8)
        await review.load(currentBytes, parser: Parser(result: document()))
        let currentHash = try #require(review.documentHash)
        review.update(id: 1, documentHash: currentHash) { $0.description = "New document edit" }
        await parser.finish(document(), fails: oldParseFails)
        await oldLoad.value
        #expect(review.state == .review)
        #expect(review.documentHash == currentHash && review.sourceBytes == currentBytes)
        #expect(review.rows[1].description == "New document edit")
        #expect(review.document == document())
    }

    @Test("Invalid row provenance fails instead of exposing an ambiguous draft")
    func invalidIdentity() async throws {
        let review = LocalVendorDocumentReview(accountId: try AccountID(validating: "review-account"))
        let source = document()
        let invalid = LocalVendorDocument(vendor: .amazon, fields: [:], rows: [source.rows[1]],
            warnings: [], rawText: "source", pageCount: 1)
        await review.load(Data("document".utf8), parser: Parser(result: invalid))
        #expect(review.state == .failed(.invalidRowIdentity))
        #expect(review.document == nil && review.rows.isEmpty && review.sourceBytes == nil)
    }

    @Test("Missing-date display never recommends today while raw warnings remain intact")
    func missingDateWarning() {
        let original = "Could not confidently find an order date; defaulting to today is recommended."
        let document = LocalVendorDocument(vendor: .amazon, fields: [:], rows: [],
            warnings: [original, "Missing order total"], rawText: "Source text", pageCount: 1)
        #expect(document.reviewWarnings == ["The order date could not be found. No date has been assumed.", "Missing order total"])
        #expect(document.warnings[0] == original)
        #expect(document.fields["Order date"] == nil)
    }

    @Test("A closed review rejects late file-picker completions and cannot reopen")
    func terminalClose() async throws {
        let review = LocalVendorDocumentReview(accountId: try AccountID(validating: "review-account"))
        await review.load(Data("first".utf8), parser: Parser(result: document()))
        review.close()
        await review.load(Data("late-picker-file".utf8), parser: Parser(result: document()))
        #expect(review.isClosed && review.state == .empty)
        #expect(review.sourceBytes == nil && review.documentHash == nil && review.document == nil)
        #expect(review.rows.isEmpty && review.categories.isEmpty)
    }

    @Test("Categories preserve visible choices, reject foreign data and retain document edits")
    func categorySelection() async throws {
        let account = try AccountID(validating: "review-account")
        let review = LocalVendorDocumentReview(accountId: account)
        await review.load(Data("document".utf8), parser: Parser(result: document()))
        let hash = try #require(review.documentHash)
        review.update(id: 0, documentHash: hash) { $0.description = "Edited table" }
        func snapshot(account: AccountID, empty: Bool = false) throws -> BudgetCategoryReferenceSnapshot {
            let rows = try (empty ? [] : ["active", "archived", "system"]).enumerated().map { index, name in
                BudgetCategoryDefinitionSnapshot(id: try BudgetCategoryID(validating: name), accountId: account,
                    name: try BudgetCategoryName(validating: name), kind: .general,
                    lifecycle: name == "archived" ? .archived : .active, isSystem: name == "system",
                    excludesFromOverallBudget: false, presentationOrder: UInt32(index), revision: 1)
            }
            return try BudgetCategoryReferenceSnapshot(accountId: account, local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(validating: String(repeating: "2", count: 64)),
                rows: rows, visibleRowCountBeforeFiltering: rows.count, isCompleteForQuery: true,
                quality: .ready, localDataVersion: LocalDataVersion(validating: "categories"), asOf: Date()))
        }
        review.receiveCategories(try snapshot(account: account))
        #expect(review.categories.map { $0.id.rawValue } == ["active"])
        review.selectCategory(try BudgetCategoryID(validating: "archived"))
        #expect(review.selectedCategoryId == nil)
        review.selectCategory(try BudgetCategoryID(validating: "active"))
        #expect(review.selectedCategoryId?.rawValue == "active")
        review.selectCategory(nil)
        #expect(review.selectedCategoryId == nil)
        review.selectCategory(try BudgetCategoryID(validating: "active"))
        review.receiveCategories(try snapshot(account: account, empty: true))
        #expect(review.selectedCategoryId == nil && review.categoryStatus.contains("Choose again"))
        review.receiveCategories(try snapshot(account: AccountID(validating: "other-account")))
        #expect(review.categories.isEmpty && review.selectedCategoryId == nil)
        #expect(review.rows[0].description == "Edited table" && review.documentHash == hash)
        #expect(review.document == document())
    }

    private func document() -> LocalVendorDocument {
        LocalVendorDocument(vendor: .amazon, fields: [:], rows: [
            .init(id: 0, description: "Table", quantity: 2, unitPrice: nil, total: "20.00"),
            .init(id: 1, description: "Chair", quantity: 1, unitPrice: "10.00", total: "10.00",
                  thumbnail: .init(pngBytes: Data("row-1-image".utf8), pageIndex: 1,
                      anchorRange: NSRange(location: 25, length: 6),
                      imageBounds: .init(x: 20, y: 100, width: 48, height: 48)))
        ], warnings: ["Review source"], rawText: "Original source text", pageCount: 1)
    }
}
