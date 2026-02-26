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

    @Test("Sorts alphabetically by name")
    func sortAlphabeticallyByName() {
        let projects = [
            makeProject(name: "Zebra Project"),
            makeProject(name: "Apple Project"),
            makeProject(name: "Mango Project"),
        ]
        let result = ProjectListCalculations.sortByName(projects)
        #expect(result.map(\.name) == ["Apple Project", "Mango Project", "Zebra Project"])
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
}
