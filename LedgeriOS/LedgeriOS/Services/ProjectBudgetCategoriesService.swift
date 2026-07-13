import FirebaseFirestore

struct ProjectBudgetCategoriesService: ProjectBudgetCategoriesServiceProtocol {
    private func repo(accountId: String, projectId: String) -> FirestoreRepository<ProjectBudgetCategory> {
        FirestoreRepository<ProjectBudgetCategory>(
            path: "accounts/\(accountId)/projects/\(projectId)/budgetCategories"
        )
    }

    private func collectionRef(accountId: String, projectId: String) -> CollectionReference {
        Firestore.firestore()
            .collection("accounts/\(accountId)/projects/\(projectId)/budgetCategories")
    }

    func subscribeToProjectBudgetCategories(
        accountId: String,
        projectId: String,
        onChange: @escaping ([ProjectBudgetCategory]) -> Void
    ) -> ListenerRegistration {
        repo(accountId: accountId, projectId: projectId).subscribe(onChange: onChange)
    }

    func setProjectBudgetCategory(
        accountId: String,
        projectId: String,
        categoryId: String,
        budgetCents: Int,
        userId: String?
    ) async throws {
        let docRef = collectionRef(accountId: accountId, projectId: projectId).document(categoryId)
        var fields: [String: Any] = [
            "budgetCents": budgetCents,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let userId {
            fields["updatedBy"] = userId
        }
        try await docRef.setData(fields, merge: true)
    }

    func deleteProjectBudgetCategory(
        accountId: String,
        projectId: String,
        categoryId: String
    ) async throws {
        let docRef = collectionRef(accountId: accountId, projectId: projectId).document(categoryId)
        try await docRef.delete()
    }
}

struct FeeInstallmentsService: FeeInstallmentsServiceProtocol {
    enum FeeInstallmentsServiceError: Error {
        case amountExceedsFeeTotal
    }

    private let makeBatch: @Sendable () -> any BatchWriting

    init(
        makeBatch: @escaping @Sendable () -> any BatchWriting = { FirestoreBatchWriter() }
    ) {
        self.makeBatch = makeBatch
    }

    private func repo(accountId: String, projectId: String) -> FirestoreRepository<FeeInstallment> {
        FirestoreRepository<FeeInstallment>(
            path: Self.collectionPath(accountId: accountId, projectId: projectId)
        )
    }

    private static func collectionPath(accountId: String, projectId: String) -> String {
        "accounts/\(accountId)/projects/\(projectId)/feeInstallments"
    }

    func subscribeToFeeInstallments(
        accountId: String,
        projectId: String,
        onChange: @escaping ([FeeInstallment]) -> Void
    ) -> ListenerRegistration {
        repo(accountId: accountId, projectId: projectId).subscribe(onChange: onChange)
    }

    func createFeeInstallment(
        accountId: String,
        projectId: String,
        budgetCategoryId: String,
        label: String,
        amountCents: Int,
        sortOrder: Int?,
        projectBudgetCategory: ProjectBudgetCategory?,
        existingInstallments: [FeeInstallment],
        userId: String?
    ) async throws -> String {
        try validate(
            amountCents: amountCents,
            budgetCategoryId: budgetCategoryId,
            projectBudgetCategory: projectBudgetCategory,
            existingInstallments: existingInstallments
        )

        let installmentId = UUID().uuidString
        let batch = makeBatch()
        let now = FieldValue.serverTimestamp()
        var fields = fieldsForWrite(
            accountId: accountId,
            projectId: projectId,
            budgetCategoryId: budgetCategoryId,
            label: label,
            amountCents: amountCents,
            sortOrder: sortOrder,
            userId: userId,
            timestamp: now
        )
        fields["createdAt"] = now
        if let userId { fields["createdBy"] = userId }

        batch.setData(
            fields,
            forDocumentAt: "\(Self.collectionPath(accountId: accountId, projectId: projectId))/\(installmentId)",
            merge: false
        )
        try await batch.commit()
        return installmentId
    }

    func updateFeeInstallment(
        accountId: String,
        projectId: String,
        installmentId: String,
        budgetCategoryId: String,
        label: String,
        amountCents: Int,
        sortOrder: Int?,
        projectBudgetCategory: ProjectBudgetCategory?,
        existingInstallments: [FeeInstallment],
        userId: String?
    ) async throws {
        try validate(
            amountCents: amountCents,
            budgetCategoryId: budgetCategoryId,
            projectBudgetCategory: projectBudgetCategory,
            existingInstallments: existingInstallments,
            excluding: installmentId
        )

        let batch = makeBatch()
        let fields = fieldsForWrite(
            accountId: accountId,
            projectId: projectId,
            budgetCategoryId: budgetCategoryId,
            label: label,
            amountCents: amountCents,
            sortOrder: sortOrder,
            userId: userId,
            timestamp: FieldValue.serverTimestamp()
        )
        batch.updateData(
            fields,
            forDocumentAt: "\(Self.collectionPath(accountId: accountId, projectId: projectId))/\(installmentId)"
        )
        try await batch.commit()
    }

    func deleteFeeInstallment(accountId: String, projectId: String, installmentId: String) async throws {
        let batch = makeBatch()
        batch.deleteDocument(atPath: "\(Self.collectionPath(accountId: accountId, projectId: projectId))/\(installmentId)")
        try await batch.commit()
    }

    private func validate(
        amountCents: Int,
        budgetCategoryId: String,
        projectBudgetCategory: ProjectBudgetCategory?,
        existingInstallments: [FeeInstallment],
        excluding installmentId: String? = nil
    ) throws {
        guard FeeInstallmentCalculations.canSave(
            amountCents: amountCents,
            totalCents: projectBudgetCategory?.budgetCents,
            budgetCategoryId: budgetCategoryId,
            installments: existingInstallments,
            excluding: installmentId
        ) else {
            throw FeeInstallmentsServiceError.amountExceedsFeeTotal
        }
    }

    private func fieldsForWrite(
        accountId: String,
        projectId: String,
        budgetCategoryId: String,
        label: String,
        amountCents: Int,
        sortOrder: Int?,
        userId: String?,
        timestamp: FieldValue
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "accountId": accountId,
            "projectId": projectId,
            "budgetCategoryId": budgetCategoryId,
            "label": label,
            "amountCents": amountCents,
            "updatedAt": timestamp,
        ]
        fields["sortOrder"] = sortOrder ?? FieldValue.delete()
        if let userId { fields["updatedBy"] = userId }
        return fields
    }
}
