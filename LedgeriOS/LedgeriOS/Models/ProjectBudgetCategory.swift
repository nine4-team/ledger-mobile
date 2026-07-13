import FirebaseFirestore

struct ProjectBudgetCategory: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var budgetCents: Int?
    var createdBy: String?
    var updatedBy: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, budgetCents, createdBy, updatedBy
    }
}

/// A manually created billable slice of a project fee category.
///
/// The parent fee total lives on `ProjectBudgetCategory.budgetCents`; individual
/// installments must not exceed that project-level fee total in aggregate.
struct FeeInstallment: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var budgetCategoryId: String
    var label: String
    var amountCents: Int
    var sortOrder: Int?
    var createdBy: String?
    var updatedBy: String?
    var createdAt: Date?
    var updatedAt: Date?

    init(
        accountId: String? = nil,
        projectId: String? = nil,
        budgetCategoryId: String,
        label: String,
        amountCents: Int,
        sortOrder: Int? = nil,
        createdBy: String? = nil,
        updatedBy: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.accountId = accountId
        self.projectId = projectId
        self.budgetCategoryId = budgetCategoryId
        self.label = label
        self.amountCents = amountCents
        self.sortOrder = sortOrder
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, budgetCategoryId, label, amountCents,
             sortOrder, createdBy, updatedBy
    }
}

enum FeeInstallmentCalculations {
    static func invoicedCents(
        budgetCategoryId: String,
        installments: [FeeInstallment],
        excluding installmentId: String? = nil
    ) -> Int {
        installments.reduce(0) { partial, installment in
            guard installment.budgetCategoryId == budgetCategoryId else { return partial }
            guard installment.id != installmentId else { return partial }
            return partial + installment.amountCents
        }
    }

    static func toInvoiceCents(
        totalCents: Int?,
        budgetCategoryId: String,
        installments: [FeeInstallment],
        excluding installmentId: String? = nil
    ) -> Int? {
        guard let totalCents else { return nil }
        return max(
            totalCents - invoicedCents(
                budgetCategoryId: budgetCategoryId,
                installments: installments,
                excluding: installmentId
            ),
            0
        )
    }

    static func canSave(
        amountCents: Int,
        totalCents: Int?,
        budgetCategoryId: String,
        installments: [FeeInstallment],
        excluding installmentId: String? = nil
    ) -> Bool {
        guard amountCents > 0 else { return false }
        guard let totalCents else { return true }
        let existing = invoicedCents(
            budgetCategoryId: budgetCategoryId,
            installments: installments,
            excluding: installmentId
        )
        return existing + amountCents <= totalCents
    }
}
