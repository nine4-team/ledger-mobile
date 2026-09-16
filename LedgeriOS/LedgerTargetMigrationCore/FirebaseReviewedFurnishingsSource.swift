/// Validates an explicitly reviewed identity; never discovers Furnishings by name.
public enum FirebaseReviewedFurnishingsSource {
    public static func matches(_ documents: [FirebaseSourceDocument], accountID: String,
                               categoryID: String) -> Bool {
        let path = ["accounts", accountID, "presets", "default", "budgetCategories", categoryID]
        let matches = documents.filter { $0.documentPathSegments == path }
        guard matches.count == 1, let source = matches.first,
              source.accountScopeID == accountID,
              (try? source.fields.validated()) != nil,
              case .map(let fields) = source.fields,
              case .map(let metadata) = fields.first(where: { $0.key == "metadata" })?.value,
              case .string("itemized") = metadata.first(where: { $0.key == "categoryType" })?.value else {
            return false
        }
        return true
    }
}
