import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Fee installment intent and exact budget cap")
struct FeeInstallmentCommandTests {
    private func money(_ amount: Int64, _ currency: String = "USD") throws -> Money {
        try .init(minorUnits: amount, currency: .init(validating: currency))
    }
    private func draft(_ amount: Int64 = 100, label: String = "Design fee 1 of 3") throws -> FeeInstallmentDraft {
        try .init(accountId: .init(validating: "account"), projectId: .init(validating: "project"),
            installmentId: .init(validating: "fee"), categoryId: .init(validating: "category"),
            label: label, amount: money(amount))
    }
    @Test func capIncludesAllInstallmentsAndAbsenceIsNotZero() throws {
        let value = try draft()
        try value.validateBudget(configuredTotal: money(300), alreadyAllocated: money(200))
        try value.validateBudget(configuredTotal: nil, alreadyAllocated: money(300))
        #expect(throws: FeeInstallmentDraft.Failure.exceedsFeeTotal) {
            try value.validateBudget(configuredTotal: money(300), alreadyAllocated: money(201))
        }
        #expect(throws: FeeInstallmentDraft.Failure.exceedsFeeTotal) {
            try value.validateBudget(configuredTotal: money(0), alreadyAllocated: money(0))
        }
        #expect(throws: (any Error).self) { try value.validateBudget(configuredTotal: money(300, "EUR"), alreadyAllocated: money(0)) }
        #expect(throws: (any Error).self) { try value.validateBudget(configuredTotal: nil, alreadyAllocated: money(Int64.max)) }
    }
    @Test func positiveAmountLabelAndDecodedEnvelopeRemainValidated() throws {
        for amount: Int64 in [0, -1] { #expect(throws: FeeInstallmentDraft.Failure.invalidDraft) { try draft(amount) } }
        #expect(throws: FeeInstallmentDraft.Failure.invalidDraft) { try draft(label: " \n ") }
        let value = try draft(9_007_199_254_740_993)
        let command = try CreateFeeInstallmentCommand(operationId: .init(validating: "operation"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 123), draft: value)
        let encoded = try OperationContractCodec.encode(command)
        let decoded = try OperationContractCodec.decode(CreateFeeInstallmentCommand.self, from: encoded)
        #expect(decoded.envelope.payload == value)
        let bad = String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "fee-installment-create-v1", with: "wrong")
        #expect(throws: (any Error).self) { try OperationContractCodec.decode(CreateFeeInstallmentCommand.self, from: Data(bad.utf8)) }
    }
    @Test func orderingFitsStorageIncludingAfterDecode() throws {
        let value = try draft()
        for order in [Int64(Int32.min), Int64(Int32.max)] {
            let ordered = try FeeInstallmentDraft(accountId: value.accountId, projectId: value.projectId,
                installmentId: value.installmentId, categoryId: value.categoryId,
                label: value.label, amount: value.amount, sortOrder: order)
            let encoded = try OperationContractCodec.encode(ordered)
            #expect(try OperationContractCodec.decode(FeeInstallmentDraft.self, from: encoded) == ordered)
            let invalid = String(decoding: encoded, as: UTF8.self)
                .replacingOccurrences(of: "\"sortOrder\":\(order)", with: "\"sortOrder\":\(Int64(Int32.max) + 1)")
            #expect(throws: FeeInstallmentDraft.Failure.invalidDraft) {
                try OperationContractCodec.decode(FeeInstallmentDraft.self, from: Data(invalid.utf8))
            }
        }
        for order in [Int64(Int32.min) - 1, Int64(Int32.max) + 1] {
            #expect(throws: FeeInstallmentDraft.Failure.invalidDraft) {
                try FeeInstallmentDraft(accountId: value.accountId, projectId: value.projectId,
                    installmentId: value.installmentId, categoryId: value.categoryId,
                    label: value.label, amount: value.amount, sortOrder: order)
            }
        }
    }
}
