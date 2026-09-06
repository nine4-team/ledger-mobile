import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Protected Artifact Export Lifecycle")
struct ProtectedArtifactExportTests {
    @Test("An authorized immutable snapshot reaches only an evidence-only cleanup receipt")
    func authorizedSnapshotProducesEvidenceOnlyReceipt() throws {
        let fixture = try Self.fixture()
        let request = try fixture.request()
        var lifecycle = try ProtectedArtifactExportValidator.start(
            request,
            policy: fixture.policy
        )

        lifecycle = try ProtectedArtifactExportValidator.advance(
            lifecycle,
            with: .materialized(
                ProtectedArtifactMaterializationEvidence(
                    requestFingerprint: request.requestFingerprint,
                    recordedAt: try Self.time(100),
                    byteCount: Self.outputBytes.count,
                    outputHash: Self.outputHash
                )
            )
        )
        #expect(lifecycle.phase == .materialized)

        lifecycle = try ProtectedArtifactExportValidator.advance(
            lifecycle,
            with: .handoffRecorded(
                ProtectedArtifactHandoffEvidence(
                    requestFingerprint: request.requestFingerprint,
                    outputHash: Self.outputHash,
                    recordedAt: try Self.time(200),
                    outcome: .destinationAccepted
                )
            )
        )
        lifecycle = try ProtectedArtifactExportValidator.advance(
            lifecycle,
            with: .cleanupRequired(
                ProtectedArtifactCleanupEvidence(
                    requestFingerprint: request.requestFingerprint,
                    outputHash: Self.outputHash,
                    recordedAt: try Self.time(300)
                )
            )
        )
        lifecycle = try ProtectedArtifactExportValidator.advance(
            lifecycle,
            with: .cleaned(
                ProtectedArtifactCleanupEvidence(
                    requestFingerprint: request.requestFingerprint,
                    outputHash: Self.outputHash,
                    recordedAt: try Self.time(400)
                )
            )
        )

        let receipt = try ProtectedArtifactExportValidator.makeReceipt(from: lifecycle)
        #expect(lifecycle.phase == .cleaned)
        #expect(request.lease.exportID == request.exportID)
        #expect(request.lease.requestFingerprint == request.requestFingerprint)
        #expect(request.lease.isExpired(at: request.expiresAt))
        #expect(receipt.requestFingerprint == request.requestFingerprint)
        #expect(receipt.snapshot == request.snapshot)
        #expect(receipt.output?.outputHash == Self.outputHash)
        #expect(receipt.destinationOutcome == .destinationAccepted)
        #expect(receipt.cleanupDisposition == .cleanupRecorded)
        #expect(receipt.authorityDisposition == .evidenceOnly)
        let expectedCompletedAt = try Self.time(400)
        #expect(receipt.completedAt == expectedCompletedAt)
        #expect(receipt.lifecycleDigest.rawValue.count == 64)
        #expect(receipt.contentDigest.rawValue.count == 64)
    }

    @Test("Request, lifecycle, and receipt evidence reconstruct exactly without a network or file")
    func canonicalEvidenceSurvivesRestart() throws {
        let fixture = try Self.fixture()
        let reorderedPolicy = try ProtectedArtifactExportPolicy(
            allowedContentKinds: [.csv, .pdf],
            allowedDestinationIntents: [.userSelectedFile, .systemActivity],
            maximumOutputByteCount: 20_000,
            maximumLeaseDurationMilliseconds: 60_000,
            maximumCanonicalByteCount: 4_096
        )
        let request = try fixture.request()
        let reorderedRequest = try ProtectedArtifactExportValidator.makeRequest(
            fixture.draft(),
            policy: reorderedPolicy
        )
        let requestData = try ProtectedArtifactExportValidator.canonicalRequestData(
            request,
            policy: fixture.policy
        )

        #expect(fixture.policy == reorderedPolicy)
        #expect(request == reorderedRequest)
        let reorderedRequestData = try ProtectedArtifactExportValidator.canonicalRequestData(
            reorderedRequest,
            policy: reorderedPolicy
        )
        #expect(requestData == reorderedRequestData)
        #expect(
            try ProtectedArtifactExportValidator.decodeRequest(
                requestData,
                policy: fixture.policy
            ) == request
        )

        var lifecycle = try ProtectedArtifactExportValidator.start(
            request,
            policy: fixture.policy
        )
        lifecycle = try ProtectedArtifactExportValidator.advance(
            lifecycle,
            with: .materialized(
                ProtectedArtifactMaterializationEvidence(
                    requestFingerprint: request.requestFingerprint,
                    recordedAt: try Self.time(100),
                    byteCount: Self.outputBytes.count,
                    outputHash: Self.outputHash
                )
            )
        )
        lifecycle = try ProtectedArtifactExportValidator.advance(
            lifecycle,
            with: .handoffRecorded(
                ProtectedArtifactHandoffEvidence(
                    requestFingerprint: request.requestFingerprint,
                    outputHash: Self.outputHash,
                    recordedAt: try Self.time(200),
                    outcome: .destinationAccepted
                )
            )
        )
        // Cleanup may finish after lease expiry; the lease blocks a new handoff,
        // not recovery of already-materialized local evidence.
        lifecycle = try ProtectedArtifactExportValidator.advance(
            lifecycle,
            with: .cleanupRequired(
                ProtectedArtifactCleanupEvidence(
                    requestFingerprint: request.requestFingerprint,
                    outputHash: Self.outputHash,
                    recordedAt: try Self.time(60_100)
                )
            )
        )
        lifecycle = try ProtectedArtifactExportValidator.advance(
            lifecycle,
            with: .cleaned(
                ProtectedArtifactCleanupEvidence(
                    requestFingerprint: request.requestFingerprint,
                    outputHash: Self.outputHash,
                    recordedAt: try Self.time(60_200)
                )
            )
        )

        let lifecycleData = try ProtectedArtifactExportValidator.canonicalLifecycleData(lifecycle)
        let restoredLifecycle = try ProtectedArtifactExportValidator.decodeLifecycle(
            lifecycleData,
            policy: fixture.policy
        )
        #expect(restoredLifecycle == lifecycle)
        #expect(restoredLifecycle.phase == .cleaned)

        let receipt = try ProtectedArtifactExportValidator.makeReceipt(from: lifecycle)
        let receiptData = try ProtectedArtifactExportValidator.canonicalReceiptData(
            receipt,
            maximumBytes: request.maximumCanonicalByteCount
        )
        #expect(
            try ProtectedArtifactExportValidator.decodeReceipt(
                receiptData,
                matching: restoredLifecycle
            ) == receipt
        )
        #expect(requestData.count <= request.maximumCanonicalByteCount)
        #expect(lifecycleData.count <= request.maximumCanonicalByteCount)
        #expect(receiptData.count <= request.maximumCanonicalByteCount)
    }

    @Test("Policy, scope, expiry, transitions, hashes, and canonical evidence fail closed")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        let fixture = try Self.fixture()
        let request = try fixture.request()

        #expect(Self.captureFailure {
            try ProtectedArtifactExportID(validating: "file:///private/report.pdf")
        } == .invalidExportID)
        #expect(Self.captureFailure {
            try ProtectedArtifactVisibilityScopeID(validating: "https://private.invalid")
        } == .invalidVisibilityScopeID)

        let disallowedDraft = fixture.draft(contentKind: .archive)
        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.makeRequest(
                disallowedDraft,
                policy: fixture.policy
            )
        } == .contentKindNotAllowed(.archive))

        let longLeaseDraft = fixture.draft(expiresOffset: 60_001)
        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.makeRequest(
                longLeaseDraft,
                policy: fixture.policy
            )
        } == .leaseDurationExceeded)

        var lifecycle = try ProtectedArtifactExportValidator.start(
            request,
            policy: fixture.policy
        )
        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.advance(
                lifecycle,
                with: .materialized(
                    ProtectedArtifactMaterializationEvidence(
                        requestFingerprint: request.requestFingerprint,
                        recordedAt: try Self.time(100),
                        byteCount: 10_001,
                        outputHash: Self.outputHash
                    )
                )
            )
        } == .outputByteCountExceeded)

        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.advance(
                lifecycle,
                with: .materialized(
                    ProtectedArtifactMaterializationEvidence(
                        requestFingerprint: request.requestFingerprint,
                        recordedAt: try Self.time(60_001),
                        byteCount: Self.outputBytes.count,
                        outputHash: Self.outputHash
                    )
                )
            )
        } == .eventAfterLeaseExpiry)

        let otherRequest = try fixture.request(exportID: String(repeating: "c", count: 32))
        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.advance(
                lifecycle,
                with: .materialized(
                    ProtectedArtifactMaterializationEvidence(
                        requestFingerprint: otherRequest.requestFingerprint,
                        recordedAt: try Self.time(100),
                        byteCount: Self.outputBytes.count,
                        outputHash: Self.outputHash
                    )
                )
            )
        } == .requestFingerprintMismatch)

        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.advance(
                lifecycle,
                with: .cleaned(
                    ProtectedArtifactCleanupEvidence(
                        requestFingerprint: request.requestFingerprint,
                        outputHash: Self.outputHash,
                        recordedAt: try Self.time(100)
                    )
                )
            )
        } == .illegalLifecycleTransition(from: .requested, event: .cleaned))

        lifecycle = try ProtectedArtifactExportValidator.advance(
            lifecycle,
            with: .materialized(
                ProtectedArtifactMaterializationEvidence(
                    requestFingerprint: request.requestFingerprint,
                    recordedAt: try Self.time(100),
                    byteCount: Self.outputBytes.count,
                    outputHash: Self.outputHash
                )
            )
        )
        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.advance(
                lifecycle,
                with: .handoffRecorded(
                    ProtectedArtifactHandoffEvidence(
                        requestFingerprint: request.requestFingerprint,
                        outputHash: try ProtectedArtifactSHA256.make(bytes: Data("changed".utf8)),
                        recordedAt: try Self.time(200),
                        outcome: .destinationAccepted
                    )
                )
            )
        } == .outputHashMismatch)

        let requestData = try ProtectedArtifactExportValidator.canonicalRequestData(
            request,
            policy: fixture.policy
        )
        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.decodeRequest(
                requestData + Data([0x0a]),
                policy: fixture.policy
            )
        } == .noncanonicalEvidence)

        let otherPolicy = try ProtectedArtifactExportPolicy(
            allowedContentKinds: [.pdf, .csv],
            allowedDestinationIntents: [.systemActivity, .userSelectedFile],
            maximumOutputByteCount: 20_001,
            maximumLeaseDurationMilliseconds: 60_000,
            maximumCanonicalByteCount: 4_096
        )
        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.decodeRequest(
                requestData,
                policy: otherPolicy
            )
        } == .policyMismatch)

        let lifecycleData = try ProtectedArtifactExportValidator.canonicalLifecycleData(lifecycle)
        var lifecycleObject = try #require(
            JSONSerialization.jsonObject(with: lifecycleData) as? [String: Any]
        )
        lifecycleObject["contentDigest"] = String(repeating: "f", count: 64)
        let digestTamper = try JSONSerialization.data(
            withJSONObject: lifecycleObject,
            options: [.sortedKeys]
        )
        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.decodeLifecycle(
                digestTamper,
                policy: fixture.policy
            )
        } == .contentDigestMismatch)

        let oversized = Data(
            repeating: 0x20,
            count: fixture.policy.maximumCanonicalByteCount + 1
        )
        guard case .evidenceTooLarge(let actual, let maximum) = Self.captureFailure({
            try ProtectedArtifactExportValidator.decodeRequest(
                oversized,
                policy: fixture.policy
            )
        }) else {
            Issue.record("Oversized evidence should fail before decoding")
            return
        }
        #expect(actual == oversized.count)
        #expect(maximum == fixture.policy.maximumCanonicalByteCount)
    }

    @Test("Cancellation and expiry remain explicit without claiming delivery or deletion")
    func terminalReceiptsRemainNonauthoritative() throws {
        let fixture = try Self.fixture()
        let request = try fixture.request()
        let pending = try ProtectedArtifactExportValidator.start(
            request,
            policy: fixture.policy
        )
        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.makeReceipt(from: pending)
        } == .receiptNotTerminal)

        let cancelled = try ProtectedArtifactExportValidator.advance(
            pending,
            with: .cancelled(
                requestFingerprint: request.requestFingerprint,
                at: try Self.time(100)
            )
        )
        let cancelledReceipt = try ProtectedArtifactExportValidator.makeReceipt(from: cancelled)
        #expect(cancelledReceipt.output == nil)
        #expect(cancelledReceipt.destinationOutcome == .cancelled)
        #expect(cancelledReceipt.cleanupDisposition == .notRequired)
        #expect(cancelledReceipt.authorityDisposition == .evidenceOnly)

        let expired = try ProtectedArtifactExportValidator.advance(
            pending,
            with: .failed(
                ProtectedArtifactFailureEvidence(
                    requestFingerprint: request.requestFingerprint,
                    recordedAt: request.expiresAt,
                    code: .leaseExpired
                )
            )
        )
        let expiredReceipt = try ProtectedArtifactExportValidator.makeReceipt(from: expired)
        #expect(expiredReceipt.output == nil)
        #expect(expiredReceipt.destinationOutcome == .failed)
        #expect(expiredReceipt.cleanupDisposition == .notRequired)

        #expect(Self.captureFailure {
            try ProtectedArtifactExportValidator.advance(
                pending,
                with: .failed(
                    ProtectedArtifactFailureEvidence(
                        requestFingerprint: request.requestFingerprint,
                        recordedAt: try Self.time(100),
                        code: .leaseExpired
                    )
                )
            )
        } == .leaseExpiryFailureBeforeExpiry)

        let encoded = String(
            decoding: try ProtectedArtifactExportValidator.canonicalReceiptData(
                expiredReceipt,
                maximumBytes: request.maximumCanonicalByteCount
            ),
            as: UTF8.self
        )
        for forbidden in [
            "/Users/private",
            "file://",
            "https://",
            "access_token",
            "service_role",
            "principal-private",
            "account-private",
            "entity-private",
            "client-delivered",
            "physically-deleted"
        ] {
            #expect(!encoded.localizedCaseInsensitiveContains(forbidden))
        }
    }

    private static let baseMilliseconds: Int64 = 1_788_000_000_000
    private static let outputBytes = Data("authorized-immutable-snapshot-output".utf8)
    private static let outputHash = try! ProtectedArtifactSHA256.make(bytes: outputBytes)

    private struct Fixture {
        let policy: ProtectedArtifactExportPolicy
        let snapshot: ProtectedArtifactSnapshotReference

        func draft(
            exportID: String = String(repeating: "a", count: 32),
            contentKind: ProtectedArtifactContentKind = .pdf,
            destinationIntent: ProtectedArtifactDestinationIntent = .systemActivity,
            expiresOffset: Int64 = 60_000
        ) -> ProtectedArtifactExportRequestDraft {
            ProtectedArtifactExportRequestDraft(
                exportID: try! ProtectedArtifactExportID(validating: exportID),
                snapshot: snapshot,
                contentKind: contentKind,
                destinationIntent: destinationIntent,
                requestedAt: try! ProtectedArtifactExportTests.time(0),
                expiresAt: try! ProtectedArtifactExportTests.time(expiresOffset),
                maximumOutputByteCount: 10_000
            )
        }

        func request(
            exportID: String = String(repeating: "a", count: 32)
        ) throws -> ProtectedArtifactExportRequest {
            try ProtectedArtifactExportValidator.makeRequest(
                draft(exportID: exportID),
                policy: policy
            )
        }
    }

    private static func fixture() throws -> Fixture {
        Fixture(
            policy: try ProtectedArtifactExportPolicy(
                allowedContentKinds: [.pdf, .csv],
                allowedDestinationIntents: [.systemActivity, .userSelectedFile],
                maximumOutputByteCount: 20_000,
                maximumLeaseDurationMilliseconds: 60_000,
                maximumCanonicalByteCount: 4_096
            ),
            snapshot: ProtectedArtifactSnapshotReference(
                snapshotID: try ProtectedArtifactSnapshotID(
                    validating: String(repeating: "b", count: 32)
                ),
                snapshotHash: try ProtectedArtifactSHA256.make(
                    bytes: Data("authorized-immutable-snapshot".utf8)
                ),
                visibilityScopeID: try ProtectedArtifactVisibilityScopeID.make(
                    bytes: Data("synthetic-financial-limited-scope".utf8)
                ),
                profileVersion: try ProtectedArtifactProfileVersion(
                    validating: "transaction_export.v1"
                ),
                authorityVersion: try ProtectedArtifactAuthorityVersion(
                    validating: "authorization.v1"
                )
            )
        )
    }

    private static func time(_ offset: Int64) throws -> ProtectedArtifactEpochMilliseconds {
        try ProtectedArtifactEpochMilliseconds(validating: baseMilliseconds + offset)
    }

    private static func captureFailure<Result>(
        _ operation: () throws -> Result
    ) -> ProtectedArtifactFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ProtectedArtifactFailure {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }
}
