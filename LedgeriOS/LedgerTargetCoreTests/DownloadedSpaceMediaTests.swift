import LedgerTargetCore
import Testing

@Suite("Downloaded Space media")
struct DownloadedSpaceMediaTests {
    private let account = try! AccountID(validating: "account")
    private let space = try! SpaceID(validating: "space")

    private func attachment(_ id: String, position: Int = 0, primary: Bool = false,
                            pdf: Bool = false, accountId: AccountID? = nil) throws -> DownloadedSpaceMedia.Attachment {
        let owner = accountId ?? account
        let hash = String(repeating: "a", count: 64)
        return try .init(id: EntityID(validating: id), object: .init(accountId: owner,
            attachmentId: id, sha256: hash, byteCount: "4", mediaType: pdf ? "application/pdf" : "image/jpeg",
            storagePath: "accounts/\(owner.rawValue)/attachments/\(id)/\(hash)", kind: pdf ? .pdf : .image),
            position: position, isPrimary: primary)
    }

    private func catalog(_ attachments: [DownloadedSpaceMedia.Attachment] = [], revision: Int64? = 1,
                         complete: Bool = true, scope: SpaceCreationScope = .businessInventory,
                         spaceId: SpaceID? = nil) throws -> DownloadedSpaceMedia {
        try .init(accountId: account, spaceId: spaceId ?? space, scope: scope,
                  revision: revision, isComplete: complete, attachments: attachments)
    }

    @Test func unknownIsNotEmpty() throws {
        #expect(try catalog(revision: nil, complete: false) != catalog())
        #expect(throws: DownloadedSpaceMedia.Failure.invalidEvidence) { try catalog(revision: nil) }
        #expect(throws: DownloadedSpaceMedia.Failure.invalidEvidence) { try catalog(revision: 0) }
        #expect(throws: DownloadedSpaceMedia.Failure.invalidEvidence) {
            try catalog([attachment("image")], revision: nil, complete: false)
        }
    }

    @Test func orderingAndPDFPrintExclusion() throws {
        let photo = try attachment("photo"), pdf = try attachment("pdf", position: 1, primary: true, pdf: true)
        let value = try catalog([pdf, photo])
        #expect(value.attachments == [photo, pdf])
        #expect(value.printableImages == [photo])
        #expect(try catalog([attachment("gap", position: 3)], complete: false).attachments.count == 1)
        #expect(throws: DownloadedSpaceMedia.Failure.invalidEvidence) { try catalog([attachment("gap", position: 3)]) }
    }

    @Test func rejectsForeignOrAmbiguousReferences() throws {
        #expect(throws: DownloadedSpaceMedia.Failure.invalidEvidence) {
            try catalog([attachment("foreign", accountId: AccountID(validating: "other"))])
        }
        #expect(throws: DownloadedSpaceMedia.Failure.invalidEvidence) { try catalog([attachment("a"), attachment("b")]) }
        #expect(throws: DownloadedSpaceMedia.Failure.invalidEvidence) {
            try catalog([attachment("a", primary: true), attachment("b", position: 1, primary: true)])
        }
        #expect(throws: DownloadedSpaceMedia.Failure.invalidEvidence) {
            try catalog([attachment("a"), attachment("a", position: 1)])
        }
    }

    @Test func selectionNeverSurvivesDifferentScopeOrRevision() throws {
        let photo = try attachment("photo"), original = try catalog([photo])
        #expect(original.retains(photo, from: original))
        #expect(try !catalog([photo], revision: 2).retains(photo, from: original))
        #expect(try !catalog([photo], scope: .project(ProjectID(validating: "project"))).retains(photo, from: original))
        #expect(try !catalog([photo], spaceId: SpaceID(validating: "other")).retains(photo, from: original))
        #expect(try !catalog().retains(photo, from: original))
    }
}
