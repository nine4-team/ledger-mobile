import Foundation

enum BudgetCategoryType: String, Codable {
    case general, itemized, fee
}

enum MemberRole: String, Codable {
    case owner, admin, user
}

enum InventorySaleDirection: String, Codable {
    case businessToProject = "business_to_project"
    case projectToBusiness = "project_to_business"
}
