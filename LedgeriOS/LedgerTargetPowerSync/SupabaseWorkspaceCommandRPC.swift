import Foundation
import LedgerTargetCore

/// Transport mappings for the existing Client/Project/category command ports.
/// Business validation and terminal-result checks stay in their existing owners.
struct SupabaseWorkspaceCommandRPC: ClientCreationCommandApplying, ProjectCreationCommandApplying,
    EditTransactionDetailsApplying, EditTransactionReceiptLinesApplying,
    CategoryManagementCommandApplying, InventorySaleCommandApplying, EditUncollectedItemPriceApplying, EditItemDetailsApplying, ReturnUninvoicedItemsCommandApplying, ReturnPaidItemsCommandApplying, CreateExpenseCommandApplying, EditExpenseCommandApplying, CreateInvoiceCommandApplying, ReviseCreatedInvoiceCommandApplying, CreateFeeInstallmentCommandApplying, InventorySaleReviewReading, TransactionReceiptReading, Sendable {
    enum Failure: Error, Equatable { case scopeMismatch, invalidResponse, rejected(Int) }
    let url: URL
    let key: String
    let authorization: WorkspaceMembershipAuthorization
    let identity: SupabaseAuthenticatedSession
    let http: URLSession
    let categories: SupabaseCategoryManagementRPC
    private let revalidateAccess: (@Sendable () async throws -> Void)?

    init(url: URL, key: String, authorization: WorkspaceMembershipAuthorization,
         identity: SupabaseAuthenticatedSession, http: URLSession = .shared,
         revalidateAccess: (@Sendable () async throws -> Void)? = nil) throws {
        try SupabaseAuthenticatedAccountLookup.validateConfiguration(supabaseURL: url, publishableKey: key)
        guard authorization.authUserId == identity.userId else { throw Failure.scopeMismatch }
        self.url = url
        self.key = key
        self.authorization = authorization
        self.identity = identity
        self.http = http
        self.revalidateAccess = revalidateAccess
        categories = try SupabaseCategoryManagementRPC(supabaseURL: url, publishableKey: key,
            accessToken: { try await identity.accessToken() }, session: http)
    }

    func apply(_ command: CategoryManagementCommand) async throws -> CategoryManagementServerResult {
        try requireScope(account: command.envelope.accountId.rawValue, principal: command.envelope.actorPrincipalId.rawValue)
        do {
            let result = try await categories.apply(command)
            try Task.checkCancellation()
            try identity.requireCurrentIdentity()
            return result
        } catch SupabaseCategoryManagementRPC.Failure.rejected(403) {
            try identity.requireCurrentIdentity()
            try await revalidateAccess?()
            throw SupabaseCategoryManagementRPC.Failure.rejected(403)
        }
    }

    func read(transactionId: TransactionID) async throws -> TransactionReceiptSnapshot {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_account_id": authorization.accountId.rawValue, "p_transaction_id": transactionId.rawValue])
        let result: TransactionReceiptSnapshot = try await call("spike_read_transaction_receipt", body: body)
        try result.validate(accountId: authorization.accountId, principalId: authorization.principalId,
            transactionId: transactionId)
        return result
    }

    func apply(_ command: EditTransactionDetailsCommand) async throws -> EditTransactionDetailsServerResult {
        try requireScope(account: command.envelope.accountId.rawValue,
                         principal: command.envelope.actorPrincipalId.rawValue)
        let request = try EditTransactionDetailsUploadRequest(command)
        let result: EditTransactionDetailsServerResult = try await call("spike_edit_transaction_details", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: EditTransactionReceiptLinesCommand) async throws -> EditTransactionReceiptLinesServerResult {
        try requireScope(account: command.envelope.accountId.rawValue,
                         principal: command.envelope.actorPrincipalId.rawValue)
        let request = try EditTransactionReceiptLinesUploadRequest(command)
        let result: EditTransactionReceiptLinesServerResult = try await call("spike_edit_transaction_receipt_lines", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: EditItemDetailsCommand) async throws -> EditItemDetailsServerResult {
        try requireScope(account: command.envelope.accountId.rawValue,
                         principal: command.envelope.actorPrincipalId.rawValue)
        let request = try EditItemDetailsUploadRequest(command)
        let result: EditItemDetailsServerResult = try await call("spike_edit_item_details", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: EditUncollectedItemPriceCommand) async throws -> EditUncollectedItemPriceServerResult {
        try requireScope(account: command.envelope.accountId.rawValue,
                         principal: command.envelope.actorPrincipalId.rawValue)
        let request = try EditUncollectedItemPriceUploadRequest(command)
        let result: EditUncollectedItemPriceServerResult = try await call("spike_edit_uncollected_item_price", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: InventorySaleCommand) async throws -> InventorySaleServerResult {
        try requireScope(account: command.envelope.accountId.rawValue,
                         principal: command.envelope.actorPrincipalId.rawValue)
        let request = try InventorySaleUploadRequest(command)
        let result: InventorySaleServerResult = try await call("spike_sell_inventory_items", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: ReturnUninvoicedItemsCommand) async throws -> ReturnUninvoicedItemsServerResult {
        try requireScope(account: command.envelope.accountId.rawValue,
                         principal: command.envelope.actorPrincipalId.rawValue)
        let request = try ReturnUninvoicedItemsUploadRequest(command)
        let result: ReturnUninvoicedItemsServerResult = try await call("spike_return_uninvoiced_items", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: ReturnPaidItemsCommand) async throws -> ReturnPaidItemsServerResult {
        try requireScope(account: command.envelope.accountId.rawValue,
                         principal: command.envelope.actorPrincipalId.rawValue)
        let request = try ReturnPaidItemsUploadRequest(command)
        let result: ReturnPaidItemsServerResult = try await call("spike_return_paid_items", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: CreateExpenseCommand) async throws -> CreateExpenseServerResult {
        try requireScope(account: command.envelope.accountId.rawValue, principal: command.envelope.actorPrincipalId.rawValue)
        let request = try CreateExpenseUploadRequest(command)
        let result: CreateExpenseServerResult = try await call("spike_create_expense", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: CreateInvoiceCommand) async throws -> CreateInvoiceServerResult {
        try requireScope(account: command.envelope.accountId.rawValue, principal: command.envelope.actorPrincipalId.rawValue)
        let request = try CreateInvoiceUploadRequest(command)
        let result: CreateInvoiceServerResult = try await call("spike_create_invoice", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: CreateFeeInstallmentCommand) async throws -> CreateFeeInstallmentServerResult {
        try requireScope(account: command.envelope.accountId.rawValue, principal: command.envelope.actorPrincipalId.rawValue)
        let request = try CreateFeeInstallmentUploadRequest(command)
        let result: CreateFeeInstallmentServerResult = try await call("spike_create_fee_installment", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: ReviseCreatedInvoiceCommand) async throws -> CreateInvoiceServerResult {
        try requireScope(account: command.envelope.accountId.rawValue, principal: command.envelope.actorPrincipalId.rawValue)
        let request = try CreateInvoiceUploadRequest(command)
        let result: CreateInvoiceServerResult = try await call("spike_revise_created_invoice", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func apply(_ command: EditExpenseCommand) async throws -> EditExpenseServerResult {
        try requireScope(account: command.envelope.accountId.rawValue, principal: command.envelope.actorPrincipalId.rawValue)
        let request = try EditExpenseUploadRequest(command)
        let result: EditExpenseServerResult = try await call("spike_edit_expense", body: request.rpcBody)
        try result.validate(for: command)
        return result
    }

    func readInventorySaleReview(itemIds: [ItemID]) async throws -> InventorySaleReview {
        guard (1...500).contains(itemIds.count), Set(itemIds).count == itemIds.count else {
            throw InventorySaleReview.Failure.selectionMismatch
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "p_account_id": authorization.accountId.rawValue, "p_item_ids": itemIds.map(\.rawValue)])
        let result: InventorySaleReview = try await call("spike_read_inventory_sale_review", body: body)
        try result.validate(accountId: authorization.accountId, principalId: authorization.principalId, itemIds: itemIds)
        return result
    }

    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        try requireScope(account: request.accountId, principal: request.actorPrincipalId)
        let body = try JSONSerialization.data(withJSONObject: [
            "p_operation_id": request.operationId, "p_account_id": request.accountId,
            "p_actor_principal_id": request.actorPrincipalId, "p_contract_version": request.contractVersion,
            "p_client_created_at": timestamp(request.clientCreatedAtMilliseconds),
            "p_client_id": request.clientId, "p_display_name": request.displayName,
            "p_fingerprint": request.fingerprint, "p_envelope_json": request.envelopeJSON])
        return try await call("spike_create_client", body: body)
    }

    func apply(_ request: ProjectCreationUploadRequest) async throws -> ProjectCreationServerResult {
        try requireScope(account: request.accountId, principal: request.actorPrincipalId)
        let allocations = try JSONSerialization.jsonObject(with: Data(request.categoryAllocationsJSON.utf8))
        let body = try JSONSerialization.data(withJSONObject: [
            "p_operation_id": request.operationId, "p_account_id": request.accountId,
            "p_actor_principal_id": request.actorPrincipalId, "p_contract_version": request.contractVersion,
            "p_project_created_at": timestamp(request.projectCreatedAtMilliseconds),
            "p_project_id": request.projectId, "p_client_selection_kind": request.clientSelectionKind,
            "p_client_id": request.clientId, "p_new_client_display_name": request.newClientDisplayName as Any? ?? NSNull(),
            "p_project_display_name": request.projectDisplayName, "p_description": request.description as Any? ?? NSNull(),
            "p_category_allocations": allocations, "p_fingerprint": request.fingerprint,
            "p_envelope_json": request.envelopeJSON])
        return try await call("spike_create_project", body: body)
    }

    private func requireScope(account: String, principal: String) throws {
        guard account.utf8.elementsEqual(authorization.accountId.rawValue.utf8),
              principal.utf8.elementsEqual(authorization.principalId.rawValue.utf8) else { throw Failure.scopeMismatch }
    }

    private func timestamp(_ milliseconds: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1000))
    }

    private func call<Result: Decodable>(_ name: String, body: Data) async throws -> Result {
        var request = URLRequest(url: url.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await identity.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.data(for: request)
        try Task.checkCancellation()
        try identity.requireCurrentIdentity()
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if response.statusCode == 403 { try await revalidateAccess?() }
        guard response.statusCode == 200 else { throw Failure.rejected(response.statusCode) }
        return try JSONDecoder().decode(Result.self, from: data)
    }
}
