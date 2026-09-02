import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Non-Item Receipt Line Reconstruction Contracts")
struct ReceiptLineReconstructionTests {
    @Test("Purchase and Return evidence reconstruct exact ordered receipt totals")
    func exactPurchaseAndReturnReconstruction() throws {
        let fixture = try Self.fixture()
        let purchaseLines = try [
            Self.line(
                "line-installation",
                "Installation",
                13_998,
                .increase,
                currency: fixture.currency
            ),
            Self.line(
                "line-warranty",
                "5 Year Appliance Warranty",
                72_000,
                .increase,
                quantity: 4,
                currency: fixture.currency
            ),
            Self.line(
                "line-promotion",
                "Promotional discount",
                15_000,
                .decrease,
                currency: fixture.currency
            ),
            Self.line(
                "line-delivery",
                "Delivery",
                2_900,
                .increase,
                currency: fixture.currency
            ),
            Self.line(
                "line-tax",
                "  Sales Tax  ",
                30_878,
                .increase,
                currency: fixture.currency
            )
        ]
        let purchase = try TransactionReceiptReconstruction(
            accountId: fixture.accountId,
            transactionId: TransactionID(validating: "transaction-purchase"),
            classification: fixture.purchase,
            recordedFinalAmount: Self.money(504_772, fixture.currency),
            physicalItemTotal: Self.money(399_996, fixture.currency),
            lines: purchaseLines
        )

        #expect(purchase.lines.map(\.id) == purchaseLines.map(\.id))
        #expect(purchase.lines[1].quantity == 4)
        #expect(purchase.lines[4].description.rawValue == "  Sales Tax  ")
        #expect(purchase.lineIncreaseTotal == Self.money(119_776, fixture.currency))
        #expect(purchase.lineDecreaseTotal == Self.money(15_000, fixture.currency))
        #expect(purchase.lineNet == Self.money(104_776, fixture.currency))
        #expect(purchase.reconstructedTotal == Self.money(504_772, fixture.currency))
        #expect(purchase.variance == Self.money(0, fixture.currency))
        #expect(purchase.classification.economicMeaning == .scopeOwnerPaid)

        let returnEvidence = try TransactionReceiptReconstruction(
            accountId: fixture.accountId,
            transactionId: TransactionID(validating: "transaction-return"),
            classification: fixture.returnRecord,
            recordedFinalAmount: Self.money(85_253, fixture.currency),
            physicalItemTotal: Self.money(89_853, fixture.currency),
            lines: [
                Self.line(
                    "line-tax-refund",
                    "Tax Refund",
                    6_064,
                    .increase,
                    currency: fixture.currency
                ),
                Self.line(
                    "line-return-shipping",
                    "Return Shipping",
                    10_665,
                    .decrease,
                    currency: fixture.currency
                )
            ]
        )

        #expect(returnEvidence.lineIncreaseTotal == Self.money(6_064, fixture.currency))
        #expect(returnEvidence.lineDecreaseTotal == Self.money(10_665, fixture.currency))
        #expect(returnEvidence.lineNet == Self.money(-4_601, fixture.currency))
        #expect(returnEvidence.reconstructedTotal == Self.money(85_252, fixture.currency))
        #expect(returnEvidence.variance == Self.money(-1, fixture.currency))
        #expect(
            returnEvidence.classification.economicMeaning ==
                .scopeOwnerReceivedMoneyBack
        )
    }

    @Test("Exact variance remains evidence and currency or overflow fails atomically")
    func exactVarianceCurrencyAndOverflow() throws {
        let fixture = try Self.fixture()
        let otherCurrencyLine = try Self.line(
            "line-eur",
            "Freight",
            100,
            .increase,
            currency: fixture.otherCurrency
        )
        #expect(Self.captureFailure {
            _ = try TransactionReceiptReconstruction(
                accountId: fixture.accountId,
                transactionId: TransactionID(validating: "transaction-currency"),
                classification: fixture.purchase,
                recordedFinalAmount: Self.money(100, fixture.currency),
                physicalItemTotal: Self.money(0, fixture.currency),
                lines: [otherCurrencyLine]
            )
        } == .currencyMismatch)

        let maximumIncrease = try Self.line(
            "line-max-increase",
            "Maximum increase",
            Int64.max,
            .increase,
            currency: fixture.currency
        )
        let oneIncrease = try Self.line(
            "line-one-increase",
            "One more",
            1,
            .increase,
            currency: fixture.currency
        )
        #expect(Self.captureFailure {
            _ = try TransactionReceiptReconstruction(
                accountId: fixture.accountId,
                transactionId: TransactionID(validating: "transaction-increase-overflow"),
                classification: fixture.purchase,
                recordedFinalAmount: Self.money(0, fixture.currency),
                physicalItemTotal: Self.money(0, fixture.currency),
                lines: [maximumIncrease, oneIncrease]
            )
        } == .arithmeticOverflow)

        let maximumDecrease = try Self.line(
            "line-max-decrease",
            "Maximum decrease",
            Int64.max,
            .decrease,
            currency: fixture.currency
        )
        let oneDecrease = try Self.line(
            "line-one-decrease",
            "One less",
            1,
            .decrease,
            currency: fixture.currency
        )
        #expect(Self.captureFailure {
            _ = try TransactionReceiptReconstruction(
                accountId: fixture.accountId,
                transactionId: TransactionID(validating: "transaction-decrease-overflow"),
                classification: fixture.purchase,
                recordedFinalAmount: Self.money(0, fixture.currency),
                physicalItemTotal: Self.money(0, fixture.currency),
                lines: [maximumDecrease, oneDecrease]
            )
        } == .arithmeticOverflow)

        #expect(Self.captureFailure {
            _ = try TransactionReceiptReconstruction(
                accountId: fixture.accountId,
                transactionId: TransactionID(
                    validating: "transaction-reconstruction-overflow"
                ),
                classification: fixture.purchase,
                recordedFinalAmount: Self.money(0, fixture.currency),
                physicalItemTotal: Self.money(Int64.max, fixture.currency),
                lines: [oneIncrease]
            )
        } == .arithmeticOverflow)

        #expect(Self.captureFailure {
            _ = try TransactionReceiptReconstruction(
                accountId: fixture.accountId,
                transactionId: TransactionID(validating: "transaction-variance-overflow"),
                classification: fixture.purchase,
                recordedFinalAmount: Self.money(1, fixture.currency),
                physicalItemTotal: Self.money(Int64.min, fixture.currency),
                lines: []
            )
        } == .arithmeticOverflow)
    }

    @Test("Ordered reconstruction evidence survives canonical restart")
    func canonicalRestart() throws {
        let fixture = try Self.fixture()
        let evidence = try TransactionReceiptReconstruction(
            accountId: fixture.accountId,
            transactionId: TransactionID(validating: "transaction-restart"),
            classification: fixture.purchase,
            recordedFinalAmount: Self.money(12_500, fixture.currency),
            physicalItemTotal: Self.money(10_000, fixture.currency),
            lines: [
                Self.line(
                    "line-shipping",
                    "Shipping",
                    3_900,
                    .increase,
                    currency: fixture.currency
                ),
                Self.line(
                    "line-credit",
                    "Vendor promotion",
                    1_400,
                    .decrease,
                    quantity: 1,
                    currency: fixture.currency
                )
            ]
        )
        let bytes = try OperationContractCodec.encode(evidence)
        let restored = try OperationContractCodec.decode(
            TransactionReceiptReconstruction.self,
            from: bytes
        )

        #expect(restored == evidence)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.lines.map(\.description.rawValue) == [
            "Shipping",
            "Vendor promotion"
        ])
        #expect(restored.evidenceFingerprint == evidence.evidenceFingerprint)
    }

    @Test("Invalid, duplicate, mismatched, malformed, and tampered evidence fails")
    func invalidAndTamperedEvidence() throws {
        let fixture = try Self.fixture()

        #expect(Self.captureFailure {
            _ = try NonItemReceiptLineDescription(validating: " \n\t ")
        } == .invalidDescription)

        let description = try NonItemReceiptLineDescription(validating: "Shipping")
        #expect(Self.captureFailure {
            _ = try NonItemReceiptLine(
                id: NonItemReceiptLineID(validating: "line-zero"),
                description: description,
                magnitude: Self.money(0, fixture.currency),
                effect: .increase
            )
        } == .invalidMagnitude)
        #expect(Self.captureFailure {
            _ = try NonItemReceiptLine(
                id: NonItemReceiptLineID(validating: "line-negative"),
                description: description,
                magnitude: Self.money(-1, fixture.currency),
                effect: .decrease
            )
        } == .invalidMagnitude)

        let line = try Self.line(
            "line-valid",
            "Shipping",
            100,
            .increase,
            currency: fixture.currency
        )
        #expect(Self.captureFailure {
            _ = try TransactionReceiptReconstruction(
                accountId: fixture.accountId,
                transactionId: TransactionID(validating: "transaction-duplicate"),
                classification: fixture.purchase,
                recordedFinalAmount: Self.money(200, fixture.currency),
                physicalItemTotal: Self.money(100, fixture.currency),
                lines: [line, line]
            )
        } == .duplicateLineIdentity)

        #expect(Self.captureFailure {
            _ = try TransactionReceiptReconstruction(
                accountId: fixture.accountId,
                transactionId: TransactionID(validating: "transaction-transfer"),
                classification: fixture.transfer,
                recordedFinalAmount: Self.money(100, fixture.currency),
                physicalItemTotal: Self.money(0, fixture.currency),
                lines: [line]
            )
        } == .invalidClassification)

        #expect(Self.captureFailure {
            _ = try TransactionReceiptReconstruction(
                accountId: fixture.otherAccountId,
                transactionId: TransactionID(validating: "transaction-account"),
                classification: fixture.purchase,
                recordedFinalAmount: Self.money(100, fixture.currency),
                physicalItemTotal: Self.money(0, fixture.currency),
                lines: [line]
            )
        } == .accountMismatch)

        let valid = try TransactionReceiptReconstruction(
            accountId: fixture.accountId,
            transactionId: TransactionID(validating: "transaction-valid"),
            classification: fixture.purchase,
            recordedFinalAmount: Self.money(100, fixture.currency),
            physicalItemTotal: Self.money(0, fixture.currency),
            lines: [line]
        )
        let changedTotal = ReconstructionWire(
            snapshot: valid,
            lineIncreaseTotal: Self.money(101, fixture.currency)
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransactionReceiptReconstruction.self,
                from: OperationContractCodec.encode(changedTotal)
            )
        } == .derivedEvidenceMismatch)

        let secondLine = try Self.line(
            "line-second",
            "Tax",
            50,
            .increase,
            currency: fixture.currency
        )
        let ordered = try TransactionReceiptReconstruction(
            accountId: fixture.accountId,
            transactionId: TransactionID(validating: "transaction-order"),
            classification: fixture.purchase,
            recordedFinalAmount: Self.money(150, fixture.currency),
            physicalItemTotal: Self.money(0, fixture.currency),
            lines: [line, secondLine]
        )
        let reordered = ReconstructionWire(
            snapshot: ordered,
            lines: [secondLine, line]
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransactionReceiptReconstruction.self,
                from: OperationContractCodec.encode(reordered)
            )
        } == .evidenceFingerprintMismatch)

        let changedFingerprint = try ReceiptReconstructionFingerprint(
            validating: String(repeating: "f", count: 64)
        )
        let fingerprintWire = ReconstructionWire(
            snapshot: valid,
            evidenceFingerprint: changedFingerprint
        )
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransactionReceiptReconstruction.self,
                from: OperationContractCodec.encode(fingerprintWire)
            )
        } == .evidenceFingerprintMismatch)

        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                NonItemReceiptLine.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedLine)
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                ReceiptReconstructionFingerprint.self,
                from: OperationContractCodec.encode("not-a-fingerprint")
            )
        } == .invalidEncodedFingerprint)
        #expect(Self.captureFailure {
            _ = try OperationContractCodec.decode(
                TransactionReceiptReconstruction.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedReconstruction)

        let diagnostics: [(ReceiptLineReconstructionFailure, String)] = [
            (.invalidDescription, "receipt_line_description_invalid"),
            (.invalidMagnitude, "receipt_line_magnitude_invalid"),
            (.duplicateLineIdentity, "receipt_line_identity_duplicate"),
            (
                .invalidClassification,
                "receipt_reconstruction_classification_invalid"
            ),
            (.accountMismatch, "receipt_reconstruction_account_mismatch"),
            (.currencyMismatch, "receipt_reconstruction_currency_mismatch"),
            (.arithmeticOverflow, "receipt_reconstruction_arithmetic_overflow"),
            (
                .derivedEvidenceMismatch,
                "receipt_reconstruction_derived_evidence_mismatch"
            ),
            (
                .evidenceFingerprintMismatch,
                "receipt_reconstruction_fingerprint_mismatch"
            ),
            (.invalidEncodedLine, "receipt_line_encoding_invalid"),
            (
                .invalidEncodedFingerprint,
                "receipt_reconstruction_fingerprint_encoding_invalid"
            ),
            (
                .invalidEncodedReconstruction,
                "receipt_reconstruction_encoding_invalid"
            )
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    private struct Fixture {
        let accountId: AccountID
        let otherAccountId: AccountID
        let currency: CurrencyCode
        let otherCurrency: CurrencyCode
        let purchase: TransactionClassification
        let returnRecord: TransactionClassification
        let transfer: TransactionClassification
    }

    private struct ReconstructionWire: Codable {
        let accountId: AccountID
        let transactionId: TransactionID
        let classification: TransactionClassification
        let recordedFinalAmount: Money
        let physicalItemTotal: Money
        let lines: [NonItemReceiptLine]
        let lineIncreaseTotal: Money
        let lineDecreaseTotal: Money
        let lineNet: Money
        let reconstructedTotal: Money
        let variance: Money
        let evidenceFingerprint: ReceiptReconstructionFingerprint

        init(
            snapshot: TransactionReceiptReconstruction,
            lines: [NonItemReceiptLine]? = nil,
            lineIncreaseTotal: Money? = nil,
            evidenceFingerprint: ReceiptReconstructionFingerprint? = nil
        ) {
            accountId = snapshot.accountId
            transactionId = snapshot.transactionId
            classification = snapshot.classification
            recordedFinalAmount = snapshot.recordedFinalAmount
            physicalItemTotal = snapshot.physicalItemTotal
            self.lines = lines ?? snapshot.lines
            self.lineIncreaseTotal =
                lineIncreaseTotal ?? snapshot.lineIncreaseTotal
            lineDecreaseTotal = snapshot.lineDecreaseTotal
            lineNet = snapshot.lineNet
            reconstructedTotal = snapshot.reconstructedTotal
            variance = snapshot.variance
            self.evidenceFingerprint =
                evidenceFingerprint ?? snapshot.evidenceFingerprint
        }
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-receipt")
        let otherAccountId = try AccountID(validating: "account-other")
        let projectScope = TransactionScope.project(
            accountId: accountId,
            projectId: try ProjectID(validating: "project-receipt"),
            clientId: try ClientID(validating: "client-receipt")
        )
        return try Fixture(
            accountId: accountId,
            otherAccountId: otherAccountId,
            currency: CurrencyCode(validating: "USD"),
            otherCurrency: CurrencyCode(validating: "EUR"),
            purchase: TransactionClassification(
                type: .purchase,
                scope: projectScope,
                role: .standalone
            ),
            returnRecord: TransactionClassification(
                type: .return,
                scope: projectScope,
                role: .standalone
            ),
            transfer: TransactionClassification(
                type: .transfer,
                scope: projectScope,
                role: .transferSource
            )
        )
    }

    private static func line(
        _ id: String,
        _ description: String,
        _ minorUnits: Int64,
        _ effect: NonItemReceiptLineEffect,
        quantity: Int64? = nil,
        currency: CurrencyCode
    ) throws -> NonItemReceiptLine {
        try NonItemReceiptLine(
            id: NonItemReceiptLineID(validating: id),
            description: NonItemReceiptLineDescription(validating: description),
            magnitude: money(minorUnits, currency),
            effect: effect,
            quantity: quantity
        )
    }

    private static func money(_ minorUnits: Int64, _ currency: CurrencyCode) -> Money {
        Money(minorUnits: minorUnits, currency: currency)
    }

    private static func captureFailure<Value>(
        _ body: () throws -> Value
    ) -> ReceiptLineReconstructionFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as ReceiptLineReconstructionFailure {
            return failure
        } catch {
            return nil
        }
    }
}
