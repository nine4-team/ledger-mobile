import CryptoKit
import Foundation

public enum ReceiptLineReconstructionFailure: Error, Equatable, Sendable {
    case invalidDescription
    case invalidMagnitude
    case duplicateLineIdentity
    case invalidClassification
    case accountMismatch
    case currencyMismatch
    case arithmeticOverflow
    case derivedEvidenceMismatch
    case evidenceFingerprintMismatch
    case invalidEncodedLine
    case invalidEncodedFingerprint
    case invalidEncodedReconstruction

    public var diagnosticCode: String {
        switch self {
        case .invalidDescription:
            "receipt_line_description_invalid"
        case .invalidMagnitude:
            "receipt_line_magnitude_invalid"
        case .duplicateLineIdentity:
            "receipt_line_identity_duplicate"
        case .invalidClassification:
            "receipt_reconstruction_classification_invalid"
        case .accountMismatch:
            "receipt_reconstruction_account_mismatch"
        case .currencyMismatch:
            "receipt_reconstruction_currency_mismatch"
        case .arithmeticOverflow:
            "receipt_reconstruction_arithmetic_overflow"
        case .derivedEvidenceMismatch:
            "receipt_reconstruction_derived_evidence_mismatch"
        case .evidenceFingerprintMismatch:
            "receipt_reconstruction_fingerprint_mismatch"
        case .invalidEncodedLine:
            "receipt_line_encoding_invalid"
        case .invalidEncodedFingerprint:
            "receipt_reconstruction_fingerprint_encoding_invalid"
        case .invalidEncodedReconstruction:
            "receipt_reconstruction_encoding_invalid"
        }
    }
}

public enum NonItemReceiptLineIDTag: Sendable {}
public typealias NonItemReceiptLineID = DomainEntityIdentifier<NonItemReceiptLineIDTag>

public struct NonItemReceiptLineDescription: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let containsVisibleSourceWording = rawValue.unicodeScalars.contains {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        guard containsVisibleSourceWording else {
            throw ReceiptLineReconstructionFailure.invalidDescription
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as ReceiptLineReconstructionFailure {
            throw failure
        } catch {
            throw ReceiptLineReconstructionFailure.invalidDescription
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum NonItemReceiptLineEffect: String, Codable, CaseIterable, Sendable {
    case increase
    case decrease
}

public struct NonItemReceiptLine: Codable, Equatable, Hashable, Sendable {
    public let id: NonItemReceiptLineID
    public let description: NonItemReceiptLineDescription
    public let magnitude: Money
    public let effect: NonItemReceiptLineEffect
    public let quantity: Int64?

    public init(
        id: NonItemReceiptLineID,
        description: NonItemReceiptLineDescription,
        magnitude: Money,
        effect: NonItemReceiptLineEffect,
        quantity: Int64? = nil
    ) throws {
        guard magnitude.sign == .positive else {
            throw ReceiptLineReconstructionFailure.invalidMagnitude
        }
        self.id = id
        self.description = description
        self.magnitude = magnitude
        self.effect = effect
        self.quantity = quantity
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                id: container.decode(NonItemReceiptLineID.self, forKey: .id),
                description: container.decode(
                    NonItemReceiptLineDescription.self,
                    forKey: .description
                ),
                magnitude: container.decode(Money.self, forKey: .magnitude),
                effect: container.decode(
                    NonItemReceiptLineEffect.self,
                    forKey: .effect
                ),
                quantity: container.decodeIfPresent(Int64.self, forKey: .quantity)
            )
        } catch let failure as ReceiptLineReconstructionFailure {
            throw failure
        } catch {
            throw ReceiptLineReconstructionFailure.invalidEncodedLine
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case description
        case magnitude
        case effect
        case quantity
    }
}

public struct ReceiptReconstructionFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw ReceiptLineReconstructionFailure.invalidEncodedFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as ReceiptLineReconstructionFailure {
            throw failure
        } catch {
            throw ReceiptLineReconstructionFailure.invalidEncodedFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct TransactionReceiptReconstruction: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let transactionId: TransactionID
    public let classification: TransactionClassification
    public let recordedFinalAmount: Money
    public let physicalItemTotal: Money
    public let lines: [NonItemReceiptLine]
    public let lineIncreaseTotal: Money
    public let lineDecreaseTotal: Money
    public let lineNet: Money
    public let reconstructedTotal: Money
    public let variance: Money
    public let evidenceFingerprint: ReceiptReconstructionFingerprint

    public init(
        accountId: AccountID,
        transactionId: TransactionID,
        classification: TransactionClassification,
        recordedFinalAmount: Money,
        physicalItemTotal: Money,
        lines: [NonItemReceiptLine]
    ) throws {
        try self.init(
            accountId: accountId,
            transactionId: transactionId,
            classification: classification,
            recordedFinalAmount: recordedFinalAmount,
            physicalItemTotal: physicalItemTotal,
            lines: lines,
            expectedTotals: nil,
            expectedFingerprint: nil
        )
    }

    private init(
        accountId: AccountID,
        transactionId: TransactionID,
        classification: TransactionClassification,
        recordedFinalAmount: Money,
        physicalItemTotal: Money,
        lines: [NonItemReceiptLine],
        expectedTotals: Totals?,
        expectedFingerprint: ReceiptReconstructionFingerprint?
    ) throws {
        guard classification.role == .standalone,
              classification.type == .purchase || classification.type == .return else {
            throw ReceiptLineReconstructionFailure.invalidClassification
        }
        guard classification.scope.accountId == accountId else {
            throw ReceiptLineReconstructionFailure.accountMismatch
        }

        var lineIds: Set<NonItemReceiptLineID> = []
        for line in lines {
            guard lineIds.insert(line.id).inserted else {
                throw ReceiptLineReconstructionFailure.duplicateLineIdentity
            }
        }

        let totals = try Self.calculateTotals(
            recordedFinalAmount: recordedFinalAmount,
            physicalItemTotal: physicalItemTotal,
            lines: lines
        )
        if let expectedTotals, expectedTotals != totals {
            throw ReceiptLineReconstructionFailure.derivedEvidenceMismatch
        }

        let fingerprint = try Self.makeFingerprint(
            accountId: accountId,
            transactionId: transactionId,
            classification: classification,
            recordedFinalAmount: recordedFinalAmount,
            physicalItemTotal: physicalItemTotal,
            lines: lines,
            totals: totals
        )
        if let expectedFingerprint, expectedFingerprint != fingerprint {
            throw ReceiptLineReconstructionFailure.evidenceFingerprintMismatch
        }

        self.accountId = accountId
        self.transactionId = transactionId
        self.classification = classification
        self.recordedFinalAmount = recordedFinalAmount
        self.physicalItemTotal = physicalItemTotal
        self.lines = lines
        lineIncreaseTotal = totals.lineIncreaseTotal
        lineDecreaseTotal = totals.lineDecreaseTotal
        lineNet = totals.lineNet
        reconstructedTotal = totals.reconstructedTotal
        variance = totals.variance
        evidenceFingerprint = fingerprint
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let expectedTotals = Totals(
                lineIncreaseTotal: try container.decode(
                    Money.self,
                    forKey: .lineIncreaseTotal
                ),
                lineDecreaseTotal: try container.decode(
                    Money.self,
                    forKey: .lineDecreaseTotal
                ),
                lineNet: try container.decode(Money.self, forKey: .lineNet),
                reconstructedTotal: try container.decode(
                    Money.self,
                    forKey: .reconstructedTotal
                ),
                variance: try container.decode(Money.self, forKey: .variance)
            )
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                transactionId: container.decode(
                    TransactionID.self,
                    forKey: .transactionId
                ),
                classification: container.decode(
                    TransactionClassification.self,
                    forKey: .classification
                ),
                recordedFinalAmount: container.decode(
                    Money.self,
                    forKey: .recordedFinalAmount
                ),
                physicalItemTotal: container.decode(
                    Money.self,
                    forKey: .physicalItemTotal
                ),
                lines: container.decode(
                    [NonItemReceiptLine].self,
                    forKey: .lines
                ),
                expectedTotals: expectedTotals,
                expectedFingerprint: container.decode(
                    ReceiptReconstructionFingerprint.self,
                    forKey: .evidenceFingerprint
                )
            )
        } catch let failure as ReceiptLineReconstructionFailure {
            throw failure
        } catch {
            throw ReceiptLineReconstructionFailure.invalidEncodedReconstruction
        }
    }

    private static func calculateTotals(
        recordedFinalAmount: Money,
        physicalItemTotal: Money,
        lines: [NonItemReceiptLine]
    ) throws -> Totals {
        let currency = recordedFinalAmount.currency
        guard physicalItemTotal.currency == currency,
              lines.allSatisfy({ $0.magnitude.currency == currency }) else {
            throw ReceiptLineReconstructionFailure.currencyMismatch
        }

        do {
            var increase = Money.zero(currency: currency)
            var decrease = Money.zero(currency: currency)
            for line in lines {
                switch line.effect {
                case .increase:
                    increase = try increase.adding(line.magnitude)
                case .decrease:
                    decrease = try decrease.adding(line.magnitude)
                }
            }
            let net = try increase.subtracting(decrease)
            let reconstructed = try physicalItemTotal.adding(net)
            let variance = try reconstructed.subtracting(recordedFinalAmount)
            return Totals(
                lineIncreaseTotal: increase,
                lineDecreaseTotal: decrease,
                lineNet: net,
                reconstructedTotal: reconstructed,
                variance: variance
            )
        } catch let failure as DomainPrimitiveFailure {
            switch failure {
            case .currencyMismatch:
                throw ReceiptLineReconstructionFailure.currencyMismatch
            case .arithmeticOverflow:
                throw ReceiptLineReconstructionFailure.arithmeticOverflow
            default:
                throw ReceiptLineReconstructionFailure.invalidEncodedReconstruction
            }
        } catch {
            throw ReceiptLineReconstructionFailure.arithmeticOverflow
        }
    }

    private static func makeFingerprint(
        accountId: AccountID,
        transactionId: TransactionID,
        classification: TransactionClassification,
        recordedFinalAmount: Money,
        physicalItemTotal: Money,
        lines: [NonItemReceiptLine],
        totals: Totals
    ) throws -> ReceiptReconstructionFingerprint {
        do {
            let basis = FingerprintBasis(
                contractVersion: "receipt-line-reconstruction-v1",
                accountId: accountId,
                transactionId: transactionId,
                classification: classification,
                recordedFinalAmount: recordedFinalAmount,
                physicalItemTotal: physicalItemTotal,
                lines: lines,
                totals: totals
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return try ReceiptReconstructionFingerprint(validating: digest)
        } catch let failure as ReceiptLineReconstructionFailure {
            throw failure
        } catch {
            throw ReceiptLineReconstructionFailure.evidenceFingerprintMismatch
        }
    }

    private struct Totals: Codable, Equatable {
        let lineIncreaseTotal: Money
        let lineDecreaseTotal: Money
        let lineNet: Money
        let reconstructedTotal: Money
        let variance: Money
    }

    private struct FingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let transactionId: TransactionID
        let classification: TransactionClassification
        let recordedFinalAmount: Money
        let physicalItemTotal: Money
        let lines: [NonItemReceiptLine]
        let totals: Totals
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case transactionId
        case classification
        case recordedFinalAmount
        case physicalItemTotal
        case lines
        case lineIncreaseTotal
        case lineDecreaseTotal
        case lineNet
        case reconstructedTotal
        case variance
        case evidenceFingerprint
    }
}
