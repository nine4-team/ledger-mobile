import Foundation

enum ItemFilterOption: String, CaseIterable {
    case all
    case bookmarked
    case fromInventory = "from-inventory"
    case toReturn = "to-return"
    case returned
    case noSku = "no-sku"
    case noName = "no-name"
    case noProjectPrice = "no-project-price"
    case noImage = "no-image"
    case noTransaction = "no-transaction"
}

enum ItemSortOption: String, CaseIterable {
    case createdDesc = "created-desc"
    case createdAsc = "created-asc"
    case alphabeticalAsc = "alphabetical-asc"
    case alphabeticalDesc = "alphabetical-desc"
}
