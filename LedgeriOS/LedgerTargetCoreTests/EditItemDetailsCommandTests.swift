import Foundation
import Testing
@testable import LedgerTargetCore

struct EditItemDetailsCommandTests {
    private func command(_ changes: EditItemDetailsCommand.Changes) throws -> EditItemDetailsCommand {
        try .init(operationId: .init(validating: "edit"), accountId: .init(validating: "account"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 100),
            payload: .init(items: [.init(itemId: .init(validating: "item"), expectedRevision: 7)], changes: changes))
    }
    @Test func omittedClearAndEmptyStayDistinctAcrossRetry() throws {
        let value = try command(.init(name: nil, sku: .clear, notes: .set(""), bookmark: false))
        let bytes = try OperationContractCodec.encode(value)
        let restored = try OperationContractCodec.decode(EditItemDetailsCommand.self, from: bytes)
        #expect(restored.envelope.payload == value.envelope.payload)
        #expect(restored.envelope.payload.changes.name == nil)
        #expect(restored.envelope.payload.changes.sku == .clear)
        #expect(restored.envelope.payload.changes.notes == .set(""))
        #expect(restored.envelope.payload.changes.bookmark == false)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        let raw = try command(.init(notes: .set("  Text\nsecond line 🪑  ")))
        #expect(raw.envelope.payload.changes.notes == .set("  Text\nsecond line 🪑  "))
    }
    @Test func refusesMalformedAndEmptyIntent() throws {
        #expect(throws: EditItemDetailsCommand.Failure.emptyChanges) { try command(.init()) }
        #expect(throws: EditItemDetailsCommand.Failure.unrepresentableText) { try command(.init(name: .set("bad\0name"))) }
        let value = try command(.init(status: .purchased))
        let text = String(decoding: try OperationContractCodec.encode(value), as: UTF8.self)
        for revision in ["0", "-1", "9223372036854775807"] {
            let invalid = text.replacingOccurrences(of: "\"expectedRevision\":7", with: "\"expectedRevision\":\(revision)")
            #expect(throws: EditItemDetailsCommand.Failure.invalidSelection) {
                try OperationContractCodec.decode(EditItemDetailsCommand.self, from: Data(invalid.utf8))
            }
        }
        let items: [EditItemDetailsCommand.Selection] = try ["a", "b"].map { .init(itemId: try .init(validating: $0), expectedRevision: 1) }
        #expect(try EditItemDetailsCommand.Payload(items: items, changes: .init(status: .clear)).items.count == 2)
        #expect(throws: EditItemDetailsCommand.Failure.invalidSelection) {
            try EditItemDetailsCommand.Payload(items: items, changes: .init(name: .set("same")))
        }
        #expect(throws: EditItemDetailsCommand.Failure.invalidSelection) {
            try EditItemDetailsCommand.Payload(items: [items[0], items[0]], changes: .init(status: .returned))
        }
    }
}
