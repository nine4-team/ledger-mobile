import Foundation

enum ListScope {
    case project(String)   // projectId
    case inventory         // projectId == nil
    case all               // no filter
}

enum ScopeFilters {
    static func transactions(_ transactions: [Transaction], scope: ListScope) -> [Transaction] {
        switch scope {
        case .project(let projectId):
            transactions.filter { $0.projectId == projectId }
        case .inventory:
            transactions.filter { $0.projectId == nil }
        case .all:
            transactions
        }
    }
}
