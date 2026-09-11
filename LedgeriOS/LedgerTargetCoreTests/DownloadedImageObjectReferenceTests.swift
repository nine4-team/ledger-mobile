import Foundation
import LedgerTargetCore
import Testing

@Suite("Downloaded image byte identity")
struct DownloadedImageObjectReferenceTests {
    @Test("Exact count and Account-bound content path are required")
    func identity() throws {
        let account = try AccountID(validating: "account")
        let hash = String(repeating: "a", count: 64)
        let path = "accounts/account/attachments/image/\(hash)"
        let reference = try DownloadedImageObjectReference(accountId: account, attachmentId: "image",
            sha256: hash, byteCount: "9007199254740993", mediaType: "image/png", storagePath: path)
        #expect(reference.byteCount == 9_007_199_254_740_993)
        for type in ["image/png\r\nAuthorization: forged", "image/png\n", "text/html",
                     "image/", "image/é", "image/png; charset=utf-8", "image/.png", "image/" + String(repeating: "a", count: 128)] {
            #expect(throws: DownloadedImageObjectReferenceFailure.self) {
                try DownloadedImageObjectReference(accountId: account, attachmentId: "image",
                    sha256: hash, byteCount: "1", mediaType: type, storagePath: path)
            }
        }
        for type in ["image/jpeg", "image/svg+xml", "image/vnd.microsoft.icon"] {
            #expect(try DownloadedImageObjectReference(accountId: account, attachmentId: "image",
                sha256: hash, byteCount: "1", mediaType: type, storagePath: path).mediaType == type)
        }
        for count in ["0", "-1", "01", "+1", "9223372036854775808"] {
            #expect(throws: DownloadedImageObjectReferenceFailure.self) {
                try DownloadedImageObjectReference(accountId: account, attachmentId: "image",
                    sha256: hash, byteCount: count, mediaType: "image/png", storagePath: path)
            }
        }
        #expect(throws: DownloadedImageObjectReferenceFailure.self) {
            try DownloadedImageObjectReference(accountId: account, attachmentId: "image",
                sha256: hash, byteCount: "1", mediaType: "image/png",
                storagePath: "accounts/foreign/attachments/image/\(hash)")
        }
    }
}
