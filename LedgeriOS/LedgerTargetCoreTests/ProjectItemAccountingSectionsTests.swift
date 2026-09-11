import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Item Accounting Section Contracts")
struct ProjectItemAccountingSectionsTests {
    @Test("Authoritative relationships derive the two ordered product sections")
    func authoritativeSectionDerivation() throws {
        let fixture = try Self.fixture()
        let sourceItems = [
            fixture.liveCredit,
            fixture.unlinked,
            fixture.clientPaid,
            fixture.availableCharge,
            fixture.frozenCharge
        ]
        let snapshot = try Self.snapshot(
            fixture: fixture,
            items: sourceItems,
            isComplete: true,
            quality: .ready,
            version: "item-sections-complete-v1"
        )

        #expect(snapshot.rows.map(\.evidence.itemId) == sourceItems.map(\.itemId))
        #expect(snapshot.sections.map(\.kind) == [.unaccountedFor, .accountedFor])
        #expect(snapshot.sections[0].rows.map(\.evidence.itemId) == [
            fixture.unlinked.itemId
        ])
        #expect(snapshot.sections[1].rows.map(\.evidence.itemId) == [
            fixture.liveCredit.itemId,
            fixture.clientPaid.itemId,
            fixture.availableCharge.itemId,
            fixture.frozenCharge.itemId
        ])
        #expect(snapshot.unresolvedRows.isEmpty)
        #expect(snapshot.availability == .available)
        #expect(snapshot.readiness == .ready)
        #expect(snapshot.isCompleteForAccounting)

        let unlinkedRow = try #require(snapshot.rows.first {
            $0.evidence.itemId == fixture.unlinked.itemId
        })
        #expect(unlinkedRow.accountingState == .unaccountedFor)
        #expect(unlinkedRow.evidence.spaceId == fixture.spaceId)

        let purchasedRow = try #require(snapshot.rows.first {
            $0.evidence.itemId == fixture.clientPaid.itemId
        })
        #expect(purchasedRow.accountingState == .accountedFor)
        #expect(
            purchasedRow.evidence.clientPaidPurchases[0].itemId ==
                purchasedRow.evidence.itemId
        )
        #expect(
            purchasedRow.evidence.clientPaidPurchases[0].classification.type ==
                .purchase
        )

        for row in snapshot.sections[1].rows {
            #expect(row.accountingState == .accountedFor)
            #expect(
                row.evidence.billableOccurrences.allSatisfy {
                    $0.itemId == row.evidence.itemId
                }
            )
        }
    }

    @Test("Space, polarity, and occurrence phase do not change accounting state")
    func nonAuthoritativePresentationAndOccurrenceEvidence() throws {
        let fixture = try Self.fixture()
        let unlinkedWithoutSpace = try Self.evidence(
            fixture: fixture,
            itemId: fixture.unlinked.itemId,
            spaceId: nil
        )
        let withoutSpace = try Self.snapshot(
            fixture: fixture,
            items: [unlinkedWithoutSpace],
            isComplete: true,
            quality: .ready,
            version: "item-space-none-v1"
        )
        let withSpace = try Self.snapshot(
            fixture: fixture,
            items: [fixture.unlinked],
            isComplete: true,
            quality: .ready,
            version: "item-space-present-v1"
        )

        #expect(withoutSpace.rows[0].accountingState == .unaccountedFor)
        #expect(withSpace.rows[0].accountingState == .unaccountedFor)
        #expect(withoutSpace.rows[0].evidence.spaceId == nil)
        #expect(withSpace.rows[0].evidence.spaceId == fixture.spaceId)

        let occurrenceItems = [
            fixture.availableCharge,
            fixture.liveCredit,
            fixture.frozenCharge,
            fixture.availableCredit,
            fixture.liveCharge,
            fixture.frozenCredit
        ]
        let occurrences = try Self.snapshot(
            fixture: fixture,
            items: occurrenceItems,
            isComplete: true,
            quality: .ready,
            version: "item-occurrence-variants-v1"
        )

        #expect(occurrences.sections[0].rows.isEmpty)
        #expect(
            occurrences.sections[1].rows.map(\.evidence.itemId) ==
                occurrenceItems.map(\.itemId)
        )
        #expect(
            Set(occurrences.rows.compactMap {
                $0.evidence.billableOccurrences.first?.polarity
            }) == Set(BillableItemOccurrencePolarity.allCases)
        )
        #expect(
            Set(occurrences.rows.compactMap {
                $0.evidence.billableOccurrences.first?.phase.kind
            }) == Set(BillableItemOccurrencePhaseKind.allCases)
        )
        #expect(occurrences.rows.allSatisfy {
            $0.accountingState == .accountedFor
        })
    }

    @Test("Incomplete absence remains unresolved and canonical snapshots restart")
    func incompleteEvidenceRestartAndPort() async throws {
        let fixture = try Self.fixture()
        let complete = try Self.snapshot(
            fixture: fixture,
            items: [fixture.unlinked, fixture.clientPaid],
            isComplete: true,
            quality: .ready,
            version: "item-restart-complete-v1"
        )
        let authoritativeEmpty = try Self.snapshot(
            fixture: fixture,
            items: [],
            isComplete: true,
            quality: .ready,
            version: "item-restart-empty-v1"
        )
        let partial = try Self.snapshot(
            fixture: fixture,
            items: [fixture.unlinked, fixture.availableCharge],
            isComplete: false,
            quality: .partial,
            version: "item-restart-partial-v1"
        )
        let stale = try Self.snapshot(
            fixture: fixture,
            items: [fixture.unlinked, fixture.frozenCredit],
            isComplete: false,
            quality: .stale,
            version: "item-restart-stale-v1"
        )

        #expect(authoritativeEmpty.rows.isEmpty)
        #expect(authoritativeEmpty.availability == .authoritativeEmpty)
        #expect(authoritativeEmpty.sections.allSatisfy { $0.rows.isEmpty })

        for incomplete in [partial, stale] {
            #expect(incomplete.availability == .relationshipEvidenceIncomplete)
            #expect(!incomplete.isCompleteForAccounting)
            #expect(incomplete.sections[0].rows.isEmpty)
            #expect(incomplete.sections[1].rows.count == 1)
            #expect(incomplete.sections[1].rows[0].accountingState == .accountedFor)
            #expect(incomplete.unresolvedRows.map(\.evidence.itemId) == [
                fixture.unlinked.itemId
            ])
            #expect(incomplete.unresolvedRows[0].accountingState == nil)
            #expect(
                incomplete.unresolvedRows[0].resolution ==
                    .relationshipEvidenceIncomplete
            )
        }

        let evidence = RestartEvidence(
            snapshots: [complete, authoritativeEmpty, partial, stale]
        )
        let bytes = try OperationContractCodec.encode(evidence)
        let restored = try OperationContractCodec.decode(
            RestartEvidence.self,
            from: bytes
        )
        #expect(restored == evidence)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(
            restored.snapshots.map(\.evidenceFingerprint) ==
                evidence.snapshots.map(\.evidenceFingerprint)
        )

        let port = InMemoryAccountingPort(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            snapshots: restored.snapshots
        )
        var iterator = port.watchProjectItemAccountingSections(
            accountId: fixture.accountId,
            projectId: fixture.projectId
        ).makeAsyncIterator()
        for expected in restored.snapshots {
            #expect(try await iterator.next() == expected)
        }
        #expect(try await iterator.next() == nil)

        var wrongScope = port.watchProjectItemAccountingSections(
            accountId: fixture.otherAccountId,
            projectId: fixture.projectId
        ).makeAsyncIterator()
        do {
            _ = try await wrongScope.next()
            Issue.record("Expected Account-scoped port refusal")
        } catch {
            #expect(
                error as? ProjectItemAccountingSectionFailure == .scopeMismatch
            )
        }
    }

    @Test("Invalid, duplicate, malformed, derived, and fingerprint evidence fails")
    func invalidAndTamperedEvidence() throws {
        let fixture = try Self.fixture()
        let itemId = fixture.unlinked.itemId

        #expect(Self.captureFailure {
            _ = try ClientPaidPurchaseAccountingConnection(
                id: ItemAccountingConnectionID(validating: "connection-return"),
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                clientId: fixture.clientId,
                itemId: itemId,
                transactionId: TransactionID(validating: "transaction-return"),
                classification: fixture.returnClassification
            )
        } == .invalidPurchaseClassification)

        #expect(Self.captureFailure {
            _ = try ClientPaidPurchaseAccountingConnection(
                id: ItemAccountingConnectionID(validating: "connection-wrong-scope"),
                accountId: fixture.accountId,
                projectId: fixture.otherProjectId,
                clientId: fixture.clientId,
                itemId: itemId,
                transactionId: TransactionID(validating: "transaction-wrong-scope"),
                classification: fixture.purchaseClassification
            )
        } == .scopeMismatch)

        let invalidPhase = PhaseWire(
            kind: .availableToInvoice,
            invoiceId: try InvoiceID(validating: "invoice-not-allowed")
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                BillableItemOccurrencePhase.self,
                from: OperationContractCodec.encode(invalidPhase)
            )
        } == .invalidOccurrencePhase)

        let purchase = try Self.purchase(
            fixture: fixture,
            itemId: itemId,
            connectionId: "connection-item-mismatch"
        )
        #expect(Self.captureFailure {
            _ = try Self.evidence(
                fixture: fixture,
                itemId: ItemID(validating: "item-other"),
                purchases: [purchase]
            )
        } == .itemRelationshipMismatch)

        #expect(Self.captureFailure {
            _ = try Self.evidence(
                fixture: fixture,
                itemId: itemId,
                purchases: [purchase, purchase]
            )
        } == .duplicateRelationshipIdentity)

        #expect(Self.captureFailure {
            _ = try Self.snapshot(
                fixture: fixture,
                items: [fixture.unlinked, fixture.unlinked],
                isComplete: true,
                quality: .ready,
                version: "item-duplicate-v1"
            )
        } == .duplicateItemIdentity)

        let duplicateConnectionId = "connection-global-duplicate"
        let firstItemId = try ItemID(validating: "item-duplicate-relationship-a")
        let secondItemId = try ItemID(validating: "item-duplicate-relationship-b")
        let first = try Self.evidence(
            fixture: fixture,
            itemId: firstItemId,
            purchases: [
                Self.purchase(
                    fixture: fixture,
                    itemId: firstItemId,
                    connectionId: duplicateConnectionId
                )
            ]
        )
        let second = try Self.evidence(
            fixture: fixture,
            itemId: secondItemId,
            purchases: [
                Self.purchase(
                    fixture: fixture,
                    itemId: secondItemId,
                    connectionId: duplicateConnectionId
                )
            ]
        )
        #expect(Self.captureFailure {
            _ = try Self.snapshot(
                fixture: fixture,
                items: [first, second],
                isComplete: true,
                quality: .ready,
                version: "item-relationship-duplicate-v1"
            )
        } == .duplicateRelationshipIdentity)

        #expect(Self.captureFailure {
            _ = try ProjectItemAccountingSectionsSnapshot(
                accountId: fixture.accountId,
                projectId: fixture.otherProjectId,
                clientId: fixture.clientId,
                items: [fixture.unlinked],
                isCompleteForAccounting: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(
                    validating: "item-cross-scope-v1"
                ),
                asOf: fixture.asOf
            )
        } == .scopeMismatch)

        #expect(Self.captureFailure {
            _ = try Self.snapshot(
                fixture: fixture,
                items: [],
                isComplete: true,
                quality: .partial,
                version: "item-false-complete-v1"
            )
        } == .invalidSnapshotCompleteness)

        #expect(Self.captureFailure {
            _ = try ProjectItemAccountingSectionsSnapshot(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                clientId: fixture.clientId,
                items: [],
                isCompleteForAccounting: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(
                    validating: "item-invalid-time-v1"
                ),
                asOf: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidSnapshotTimestamp)

        let complete = try Self.snapshot(
            fixture: fixture,
            items: [fixture.unlinked, fixture.clientPaid],
            isComplete: true,
            quality: .ready,
            version: "item-tamper-v1"
        )
        let invalidRow = RowWire(
            row: complete.rows[0],
            resolution: .accountedFor
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                ProjectItemAccountingRow.self,
                from: OperationContractCodec.encode(invalidRow)
            )
        } == .derivedEvidenceMismatch)

        let falseAuthoritativeAbsence = SnapshotWire(
            snapshot: complete,
            isCompleteForAccounting: false
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                ProjectItemAccountingSectionsSnapshot.self,
                from: OperationContractCodec.encode(falseAuthoritativeAbsence)
            )
        } == .derivedEvidenceMismatch)

        let reversedSections = SnapshotWire(
            snapshot: complete,
            sections: Array(complete.sections.reversed())
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                ProjectItemAccountingSectionsSnapshot.self,
                from: OperationContractCodec.encode(reversedSections)
            )
        } == .derivedEvidenceMismatch)

        let changedFingerprint = try ProjectItemAccountingEvidenceFingerprint(
            validating: String(repeating: "f", count: 64)
        )
        let fingerprintWire = SnapshotWire(
            snapshot: complete,
            evidenceFingerprint: changedFingerprint
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                ProjectItemAccountingSectionsSnapshot.self,
                from: OperationContractCodec.encode(fingerprintWire)
            )
        } == .evidenceFingerprintMismatch)

        let malformedCases: [(Decodable.Type, ProjectItemAccountingSectionFailure)] = [
            (
                ClientPaidPurchaseAccountingConnection.self,
                .invalidEncodedPurchaseConnection
            ),
            (BillableItemAccountingOccurrence.self, .invalidEncodedOccurrence),
            (ProjectItemAccountingEvidence.self, .invalidEncodedItemEvidence),
            (ProjectItemAccountingRow.self, .invalidEncodedRow),
            (ProjectItemAccountingSection.self, .invalidEncodedSection),
            (
                ProjectItemAccountingSectionsSnapshot.self,
                .invalidEncodedSnapshot
            )
        ]
        for (type, expected) in malformedCases {
            #expect(Self.captureDecodeFailure(type, from: Data("{}".utf8)) == expected)
        }
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                ProjectItemAccountingEvidenceFingerprint.self,
                from: OperationContractCodec.encode("not-a-fingerprint")
            )
        } == .invalidEncodedFingerprint)

        let diagnostics: [(ProjectItemAccountingSectionFailure, String)] = [
            (
                .invalidPurchaseClassification,
                "project_item_accounting_purchase_classification_invalid"
            ),
            (
                .invalidOccurrencePhase,
                "project_item_accounting_occurrence_phase_invalid"
            ),
            (.scopeMismatch, "project_item_accounting_scope_mismatch"),
            (
                .itemRelationshipMismatch,
                "project_item_accounting_item_relationship_mismatch"
            ),
            (
                .duplicateItemIdentity,
                "project_item_accounting_item_identity_duplicate"
            ),
            (
                .duplicateRelationshipIdentity,
                "project_item_accounting_relationship_identity_duplicate"
            ),
            (
                .invalidSnapshotCompleteness,
                "project_item_accounting_snapshot_completeness_invalid"
            ),
            (
                .invalidSnapshotTimestamp,
                "project_item_accounting_snapshot_timestamp_invalid"
            ),
            (
                .derivedEvidenceMismatch,
                "project_item_accounting_derived_evidence_mismatch"
            ),
            (
                .evidenceFingerprintMismatch,
                "project_item_accounting_fingerprint_mismatch"
            ),
            (
                .invalidEncodedPurchaseConnection,
                "project_item_accounting_purchase_connection_encoding_invalid"
            ),
            (
                .invalidEncodedOccurrence,
                "project_item_accounting_occurrence_encoding_invalid"
            ),
            (
                .invalidEncodedItemEvidence,
                "project_item_accounting_item_evidence_encoding_invalid"
            ),
            (
                .invalidEncodedRow,
                "project_item_accounting_row_encoding_invalid"
            ),
            (
                .invalidEncodedSection,
                "project_item_accounting_section_encoding_invalid"
            ),
            (
                .invalidEncodedFingerprint,
                "project_item_accounting_fingerprint_encoding_invalid"
            ),
            (
                .invalidEncodedSnapshot,
                "project_item_accounting_snapshot_encoding_invalid"
            )
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    private struct Fixture {
        let accountId: AccountID
        let otherAccountId: AccountID
        let projectId: ProjectID
        let otherProjectId: ProjectID
        let clientId: ClientID
        let spaceId: SpaceID
        let asOf: Date
        let purchaseClassification: TransactionClassification
        let returnClassification: TransactionClassification
        let unlinked: ProjectItemAccountingEvidence
        let clientPaid: ProjectItemAccountingEvidence
        let availableCharge: ProjectItemAccountingEvidence
        let availableCredit: ProjectItemAccountingEvidence
        let liveCharge: ProjectItemAccountingEvidence
        let liveCredit: ProjectItemAccountingEvidence
        let frozenCharge: ProjectItemAccountingEvidence
        let frozenCredit: ProjectItemAccountingEvidence
    }

    private struct RestartEvidence: Codable, Equatable {
        let snapshots: [ProjectItemAccountingSectionsSnapshot]
    }

    private struct PhaseWire: Codable {
        let kind: BillableItemOccurrencePhaseKind
        let invoiceId: InvoiceID?
    }

    private struct RowWire: Codable {
        let evidence: ProjectItemAccountingEvidence
        let relationshipAbsenceIsAuthoritative: Bool
        let resolution: ProjectItemAccountingResolution

        init(
            row: ProjectItemAccountingRow,
            relationshipAbsenceIsAuthoritative: Bool? = nil,
            resolution: ProjectItemAccountingResolution? = nil
        ) {
            evidence = row.evidence
            self.relationshipAbsenceIsAuthoritative =
                relationshipAbsenceIsAuthoritative ??
                row.relationshipAbsenceIsAuthoritative
            self.resolution = resolution ?? row.resolution
        }
    }

    private struct SnapshotWire: Codable {
        let accountId: AccountID
        let projectId: ProjectID
        let clientId: ClientID
        let rows: [ProjectItemAccountingRow]
        let sections: [ProjectItemAccountingSection]
        let unresolvedRows: [ProjectItemAccountingRow]
        let availability: ProjectItemAccountingSectionsAvailability
        let isCompleteForAccounting: Bool
        let quality: ListSnapshotQuality
        let localDataVersion: LocalDataVersion
        let asOf: Date
        let evidenceFingerprint: ProjectItemAccountingEvidenceFingerprint

        init(
            snapshot: ProjectItemAccountingSectionsSnapshot,
            rows: [ProjectItemAccountingRow]? = nil,
            sections: [ProjectItemAccountingSection]? = nil,
            unresolvedRows: [ProjectItemAccountingRow]? = nil,
            availability: ProjectItemAccountingSectionsAvailability? = nil,
            isCompleteForAccounting: Bool? = nil,
            evidenceFingerprint: ProjectItemAccountingEvidenceFingerprint? = nil
        ) {
            accountId = snapshot.accountId
            projectId = snapshot.projectId
            clientId = snapshot.clientId
            self.rows = rows ?? snapshot.rows
            self.sections = sections ?? snapshot.sections
            self.unresolvedRows = unresolvedRows ?? snapshot.unresolvedRows
            self.availability = availability ?? snapshot.availability
            self.isCompleteForAccounting =
                isCompleteForAccounting ?? snapshot.isCompleteForAccounting
            quality = snapshot.quality
            localDataVersion = snapshot.localDataVersion
            asOf = snapshot.asOf
            self.evidenceFingerprint =
                evidenceFingerprint ?? snapshot.evidenceFingerprint
        }
    }

    private struct InMemoryAccountingPort: ProjectItemAccountingQuerying {
        let accountId: AccountID
        let projectId: ProjectID
        let snapshots: [ProjectItemAccountingSectionsSnapshot]

        func watchProjectItemAccountingSections(
            accountId requestedAccountId: AccountID,
            projectId requestedProjectId: ProjectID
        ) -> AsyncThrowingStream<ProjectItemAccountingSectionsSnapshot, Error> {
            AsyncThrowingStream { continuation in
                guard requestedAccountId == accountId,
                      requestedProjectId == projectId else {
                    continuation.finish(
                        throwing: ProjectItemAccountingSectionFailure.scopeMismatch
                    )
                    return
                }
                for snapshot in snapshots {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
        }
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-item-accounting")
        let otherAccountId = try AccountID(validating: "account-item-other")
        let projectId = try ProjectID(validating: "project-item-accounting")
        let otherProjectId = try ProjectID(validating: "project-item-other")
        let clientId = try ClientID(validating: "client-item-accounting")
        let spaceId = try SpaceID(validating: "space-item-accounting")
        let projectScope = TransactionScope.project(
            accountId: accountId,
            projectId: projectId,
            clientId: clientId
        )
        let purchaseClassification = try TransactionClassification(
            type: .purchase,
            scope: projectScope,
            role: .standalone
        )
        let returnClassification = try TransactionClassification(
            type: .return,
            scope: projectScope,
            role: .standalone
        )

        func item(_ rawValue: String) throws -> ItemID {
            try ItemID(validating: rawValue)
        }
        func occurrenceEvidence(
            itemRawValue: String,
            occurrenceRawValue: String,
            polarity: BillableItemOccurrencePolarity,
            phase: BillableItemOccurrencePhase
        ) throws -> ProjectItemAccountingEvidence {
            let itemId = try item(itemRawValue)
            return try evidence(
                accountId: accountId,
                projectId: projectId,
                clientId: clientId,
                itemId: itemId,
                occurrences: [
                    BillableItemAccountingOccurrence(
                        id: try BillableItemOccurrenceID(
                            validating: occurrenceRawValue
                        ),
                        accountId: accountId,
                        projectId: projectId,
                        itemId: itemId,
                        polarity: polarity,
                        phase: phase
                    )
                ]
            )
        }

        let unlinkedItemId = try item("item-unlinked")
        let clientPaidItemId = try item("item-client-paid")
        let clientPaidConnection = try ClientPaidPurchaseAccountingConnection(
            id: ItemAccountingConnectionID(validating: "connection-client-paid"),
            accountId: accountId,
            projectId: projectId,
            clientId: clientId,
            itemId: clientPaidItemId,
            transactionId: TransactionID(validating: "transaction-client-paid"),
            classification: purchaseClassification
        )
        let invoiceLive = try InvoiceID(validating: "invoice-live")
        let invoicePaid = try InvoiceID(validating: "invoice-paid")

        return try Fixture(
            accountId: accountId,
            otherAccountId: otherAccountId,
            projectId: projectId,
            otherProjectId: otherProjectId,
            clientId: clientId,
            spaceId: spaceId,
            asOf: Date(timeIntervalSince1970: 1_788_300_000),
            purchaseClassification: purchaseClassification,
            returnClassification: returnClassification,
            unlinked: evidence(
                accountId: accountId,
                projectId: projectId,
                clientId: clientId,
                itemId: unlinkedItemId,
                spaceId: spaceId
            ),
            clientPaid: evidence(
                accountId: accountId,
                projectId: projectId,
                clientId: clientId,
                itemId: clientPaidItemId,
                purchases: [clientPaidConnection]
            ),
            availableCharge: occurrenceEvidence(
                itemRawValue: "item-available-charge",
                occurrenceRawValue: "occurrence-available-charge",
                polarity: .charge,
                phase: .availableToInvoice
            ),
            availableCredit: occurrenceEvidence(
                itemRawValue: "item-available-credit",
                occurrenceRawValue: "occurrence-available-credit",
                polarity: .credit,
                phase: .availableToInvoice
            ),
            liveCharge: occurrenceEvidence(
                itemRawValue: "item-live-charge",
                occurrenceRawValue: "occurrence-live-charge",
                polarity: .charge,
                phase: .onLiveInvoice(invoiceId: invoiceLive)
            ),
            liveCredit: occurrenceEvidence(
                itemRawValue: "item-live-credit",
                occurrenceRawValue: "occurrence-live-credit",
                polarity: .credit,
                phase: .onLiveInvoice(invoiceId: invoiceLive)
            ),
            frozenCharge: occurrenceEvidence(
                itemRawValue: "item-frozen-charge",
                occurrenceRawValue: "occurrence-frozen-charge",
                polarity: .charge,
                phase: .frozenPaid(invoiceId: invoicePaid)
            ),
            frozenCredit: occurrenceEvidence(
                itemRawValue: "item-frozen-credit",
                occurrenceRawValue: "occurrence-frozen-credit",
                polarity: .credit,
                phase: .frozenPaid(invoiceId: invoicePaid)
            )
        )
    }

    private static func snapshot(
        fixture: Fixture,
        items: [ProjectItemAccountingEvidence],
        isComplete: Bool,
        quality: ListSnapshotQuality,
        version: String
    ) throws -> ProjectItemAccountingSectionsSnapshot {
        try ProjectItemAccountingSectionsSnapshot(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            clientId: fixture.clientId,
            items: items,
            isCompleteForAccounting: isComplete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: fixture.asOf
        )
    }

    private static func evidence(
        fixture: Fixture,
        itemId: ItemID,
        spaceId: SpaceID? = nil,
        purchases: [ClientPaidPurchaseAccountingConnection] = [],
        occurrences: [BillableItemAccountingOccurrence] = []
    ) throws -> ProjectItemAccountingEvidence {
        try evidence(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            clientId: fixture.clientId,
            itemId: itemId,
            spaceId: spaceId,
            purchases: purchases,
            occurrences: occurrences
        )
    }

    private static func evidence(
        accountId: AccountID,
        projectId: ProjectID,
        clientId: ClientID,
        itemId: ItemID,
        spaceId: SpaceID? = nil,
        purchases: [ClientPaidPurchaseAccountingConnection] = [],
        occurrences: [BillableItemAccountingOccurrence] = []
    ) throws -> ProjectItemAccountingEvidence {
        try ProjectItemAccountingEvidence(
            accountId: accountId,
            projectId: projectId,
            clientId: clientId,
            itemId: itemId,
            spaceId: spaceId,
            clientPaidPurchases: purchases,
            billableOccurrences: occurrences
        )
    }

    private static func purchase(
        fixture: Fixture,
        itemId: ItemID,
        connectionId: String
    ) throws -> ClientPaidPurchaseAccountingConnection {
        try ClientPaidPurchaseAccountingConnection(
            id: ItemAccountingConnectionID(validating: connectionId),
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            clientId: fixture.clientId,
            itemId: itemId,
            transactionId: TransactionID(
                validating: "transaction-\(connectionId)"
            ),
            classification: fixture.purchaseClassification
        )
    }

    private static func captureFailure<Value>(
        _ body: () throws -> Value
    ) -> ProjectItemAccountingSectionFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as ProjectItemAccountingSectionFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func captureDecodeFailure(
        _ type: Decodable.Type,
        from data: Data
    ) -> ProjectItemAccountingSectionFailure? {
        do {
            _ = try OperationContractCodec.decode(type, from: data)
            return nil
        } catch let failure as ProjectItemAccountingSectionFailure {
            return failure
        } catch {
            return nil
        }
    }
}
