import Foundation
import Testing
@testable import LedgeriOS

// Helper to create test projects without Firebase dependencies
private func makeProject(
    name: String = "",
    clientName: String = "",
    isArchived: Bool? = nil,
    updatedAt: Date? = nil,
    createdAt: Date? = nil
) -> Project {
    var p = Project()
    p.name = name
    p.clientName = clientName
    p.isArchived = isArchived
    p.updatedAt = updatedAt
    p.createdAt = createdAt
    return p
}

private func makeCategoryProgress(
    id: String = "cat1",
    name: String = "Test",
    budgetCents: Int = 10000,
    spentCents: Int = 5000,
    categoryType: BudgetCategoryType = .general,
    excludeFromOverallBudget: Bool = false
) -> BudgetProgress.CategoryProgress {
    BudgetProgress.CategoryProgress(
        id: id, name: name, budgetCents: budgetCents,
        spentCents: spentCents, categoryType: categoryType,
        excludeFromOverallBudget: excludeFromOverallBudget
    )
}

@Suite("Project List Calculation Tests")
struct ProjectListCalculationTests {

    // MARK: - filterByArchiveState

    @Test("Active filter returns non-archived projects")
    func activeFilterReturnsNonArchived() {
        let projects = [
            makeProject(name: "Active One"),
            makeProject(name: "Archived", isArchived: true),
            makeProject(name: "Active Nil", isArchived: nil),
            makeProject(name: "Active False", isArchived: false),
        ]
        let result = ProjectListCalculations.filterByArchiveState(projects: projects, showArchived: false)
        #expect(result.count == 3)
        #expect(result.map(\.name) == ["Active One", "Active Nil", "Active False"])
    }

    @Test("Archived filter returns only archived projects")
    func archivedFilterReturnsArchived() {
        let projects = [
            makeProject(name: "Active One"),
            makeProject(name: "Archived", isArchived: true),
            makeProject(name: "Active Nil", isArchived: nil),
        ]
        let result = ProjectListCalculations.filterByArchiveState(projects: projects, showArchived: true)
        #expect(result.count == 1)
        #expect(result[0].name == "Archived")
    }

    @Test("Empty input returns empty for archive filter")
    func archiveFilterEmptyInput() {
        let result = ProjectListCalculations.filterByArchiveState(projects: [], showArchived: false)
        #expect(result.isEmpty)
    }

    // MARK: - filterBySearch

    @Test("Matches project name case insensitively")
    func searchMatchesName() {
        let projects = [
            makeProject(name: "Kitchen Remodel"),
            makeProject(name: "Bathroom Renovation"),
        ]
        let result = ProjectListCalculations.filterBySearch(projects: projects, query: "kitchen")
        #expect(result.count == 1)
        #expect(result[0].name == "Kitchen Remodel")
    }

    @Test("Matches client name case insensitively")
    func searchMatchesClientName() {
        let projects = [
            makeProject(name: "Project A", clientName: "John Smith"),
            makeProject(name: "Project B", clientName: "Jane Doe"),
        ]
        let result = ProjectListCalculations.filterBySearch(projects: projects, query: "JANE")
        #expect(result.count == 1)
        #expect(result[0].clientName == "Jane Doe")
    }

    @Test("Empty query returns all projects")
    func searchEmptyQueryReturnsAll() {
        let projects = [
            makeProject(name: "A"),
            makeProject(name: "B"),
        ]
        let result = ProjectListCalculations.filterBySearch(projects: projects, query: "")
        #expect(result.count == 2)
    }

    @Test("Whitespace-only query returns all projects")
    func searchWhitespaceReturnsAll() {
        let projects = [
            makeProject(name: "A"),
            makeProject(name: "B"),
        ]
        let result = ProjectListCalculations.filterBySearch(projects: projects, query: "   ")
        #expect(result.count == 2)
    }

    @Test("No match returns empty")
    func searchNoMatchReturnsEmpty() {
        let projects = [
            makeProject(name: "Kitchen Remodel", clientName: "John Smith"),
        ]
        let result = ProjectListCalculations.filterBySearch(projects: projects, query: "garage")
        #expect(result.isEmpty)
    }

    // MARK: - sortByName

    @Test("Sorts alphabetically case-insensitive")
    func sortsAlphabetically() {
        let projects = [
            makeProject(name: "Zebra"),
            makeProject(name: "apple"),
            makeProject(name: "Mango"),
        ]
        let result = ProjectListCalculations.sortByName(projects)
        #expect(result.map(\.name) == ["apple", "Mango", "Zebra"])
    }

    @Test("Sort is case insensitive")
    func sortCaseInsensitive() {
        let projects = [
            makeProject(name: "banana"),
            makeProject(name: "Apple"),
        ]
        let result = ProjectListCalculations.sortByName(projects)
        #expect(result.map(\.name) == ["Apple", "banana"])
    }

    @Test("Projects with empty names sort last")
    func sortEmptyNamesLast() {
        let projects = [
            makeProject(name: ""),
            makeProject(name: "Has Name"),
        ]
        let result = ProjectListCalculations.sortByName(projects)
        #expect(result.map(\.name) == ["Has Name", ""])
    }

    @Test("Empty input returns empty for sort")
    func sortEmptyInput() {
        let result = ProjectListCalculations.sortByName([])
        #expect(result.isEmpty)
    }

    // MARK: - filterProjects (combined)

    @Test("Active filter excludes archived with combined function")
    func activeFilterExcludesArchived() {
        let projects = [
            makeProject(name: "Active One"),
            makeProject(name: "Archived", isArchived: true),
            makeProject(name: "Active Two"),
        ]
        let result = ProjectListCalculations.filterProjects(projects, filter: .active, query: "")
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.isArchived != true })
    }

    @Test("Archived filter includes only archived with combined function")
    func archivedFilterIncludesOnlyArchived() {
        let projects = [
            makeProject(name: "Active One"),
            makeProject(name: "Archived One", isArchived: true),
            makeProject(name: "Archived Two", isArchived: true),
        ]
        let result = ProjectListCalculations.filterProjects(projects, filter: .archived, query: "")
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.isArchived == true })
    }

    @Test("Search by project name in combined filter")
    func searchByProjectName() {
        let projects = [
            makeProject(name: "Beach House"),
            makeProject(name: "Mountain Cabin"),
        ]
        let result = ProjectListCalculations.filterProjects(projects, filter: .active, query: "beach")
        #expect(result.count == 1)
        #expect(result[0].name == "Beach House")
    }

    @Test("Search by client name in combined filter")
    func searchByClientName() {
        let projects = [
            makeProject(name: "Project A", clientName: "Smith Family"),
            makeProject(name: "Project B", clientName: "Jones Family"),
        ]
        let result = ProjectListCalculations.filterProjects(projects, filter: .active, query: "smith")
        #expect(result.count == 1)
        #expect(result[0].clientName == "Smith Family")
    }

    @Test("Empty query returns all matching archive filter")
    func emptyQueryReturnsAll() {
        let projects = [
            makeProject(name: "A"),
            makeProject(name: "B"),
        ]
        let result = ProjectListCalculations.filterProjects(projects, filter: .active, query: "")
        #expect(result.count == 2)
    }

    // MARK: - projectEmptyStateText

    @Test("Empty state text for active filter")
    func emptyStateTextActive() {
        let text = ProjectListCalculations.projectEmptyStateText(for: .active)
        #expect(text == "No active projects yet.")
    }

    @Test("Empty state text for archived filter")
    func emptyStateTextArchived() {
        let text = ProjectListCalculations.projectEmptyStateText(for: .archived)
        #expect(text == "No archived projects yet.")
    }

    // MARK: - budgetBarCategories

    @Test("Pinned categories appear first in user-defined order")
    func budgetBarPinnedFirst() {
        let categories = [
            makeCategoryProgress(id: "cat-a", name: "A", budgetCents: 10000, spentCents: 5000),
            makeCategoryProgress(id: "cat-b", name: "B", budgetCents: 20000, spentCents: 18000),
            makeCategoryProgress(id: "cat-c", name: "C", budgetCents: 5000, spentCents: 1000),
        ]
        let result = ProjectListCalculations.budgetBarCategories(
            categories: categories,
            pinnedCategoryIds: ["cat-c", "cat-a"]
        )
        #expect(result[0].id == "cat-c")
        #expect(result[1].id == "cat-a")
        #expect(result[2].id == "cat-b")
    }

    @Test("Remaining categories sorted by spend percentage descending")
    func budgetBarSortBySpendPercent() {
        let categories = [
            makeCategoryProgress(id: "low", name: "Low", budgetCents: 10000, spentCents: 1000),
            makeCategoryProgress(id: "high", name: "High", budgetCents: 10000, spentCents: 9000),
            makeCategoryProgress(id: "mid", name: "Mid", budgetCents: 10000, spentCents: 5000),
        ]
        let result = ProjectListCalculations.budgetBarCategories(
            categories: categories,
            pinnedCategoryIds: []
        )
        #expect(result.map(\.id) == ["high", "mid", "low"])
    }

    @Test("Returns empty when no category has activity")
    func budgetBarEmptyWhenNoActivity() {
        let categories = [
            makeCategoryProgress(id: "cat-a", name: "A", budgetCents: 0, spentCents: 0),
        ]
        let result = ProjectListCalculations.budgetBarCategories(
            categories: categories,
            pinnedCategoryIds: []
        )
        #expect(result.isEmpty)
    }

    @Test("Budget bar skips pinned IDs not in enabled categories")
    func budgetBarSkipsMissingPinned() {
        let categories = [
            makeCategoryProgress(id: "cat-a", name: "A", budgetCents: 10000, spentCents: 5000),
        ]
        let result = ProjectListCalculations.budgetBarCategories(
            categories: categories,
            pinnedCategoryIds: ["nonexistent", "cat-a"]
        )
        #expect(result.count == 1)
        #expect(result[0].id == "cat-a")
    }
}
