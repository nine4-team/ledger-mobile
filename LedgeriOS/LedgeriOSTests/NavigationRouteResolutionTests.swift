import Testing
@testable import LedgeriOS

@Suite("Navigation Route Resolution Tests")
struct NavigationRouteResolutionTests {

    // MARK: - Helpers

    private func project(id: String, name: String = "") -> Project {
        var p = Project()
        p.id = id
        p.name = name
        return p
    }

    private func item(id: String, name: String? = nil) -> Item {
        var i = Item()
        i.id = id
        i.name = name
        return i
    }

    private func space(id: String, name: String = "") -> Space {
        var s = Space()
        s.id = id
        s.name = name
        return s
    }

    // MARK: - Project resolution

    @Test("Resolves project by ID")
    func resolvesProjectByID() {
        let projects = [project(id: "a", name: "Alpha"), project(id: "b", name: "Beta")]
        let resolved = NavigationRouteResolution.project(id: "b", in: projects)
        #expect(resolved?.id == "b")
        #expect(resolved?.name == "Beta")
    }

    @Test("Returns nil for missing project")
    func returnsNilForMissingProject() {
        let projects = [project(id: "a"), project(id: "b")]
        #expect(NavigationRouteResolution.project(id: "missing", in: projects) == nil)
    }

    // MARK: - Item resolution

    @Test("Resolves item from project items first")
    func resolvesItemFromProjectItems() {
        let projectItems = [item(id: "1", name: "In Project")]
        let accountItems = [item(id: "2", name: "In Account")]
        let resolved = NavigationRouteResolution.item(id: "1", projectItems: projectItems, accountItems: accountItems)
        #expect(resolved?.id == "1")
        #expect(resolved?.name == "In Project")
    }

    @Test("Falls back to account items when project item is missing")
    func fallsBackToAccountItems() {
        let projectItems = [item(id: "1", name: "In Project")]
        let accountItems = [item(id: "2", name: "In Account")]
        let resolved = NavigationRouteResolution.item(id: "2", projectItems: projectItems, accountItems: accountItems)
        #expect(resolved?.id == "2")
        #expect(resolved?.name == "In Account")
    }

    @Test("Returns nil for missing item")
    func returnsNilForMissingItem() {
        let projectItems = [item(id: "1")]
        let accountItems = [item(id: "2")]
        #expect(NavigationRouteResolution.item(id: "missing", projectItems: projectItems, accountItems: accountItems) == nil)
    }

    @Test("Prefers project item over account item for the same ID")
    func prefersProjectItemOverAccountItem() {
        // Same ID, different fields — the project-scoped copy should win.
        let projectItems = [item(id: "1", name: "Project Copy")]
        let accountItems = [item(id: "1", name: "Account Copy")]
        let resolved = NavigationRouteResolution.item(id: "1", projectItems: projectItems, accountItems: accountItems)
        #expect(resolved?.name == "Project Copy")
    }

    // MARK: - Space resolution

    @Test("Resolves space from project spaces first")
    func resolvesSpaceFromProjectSpaces() {
        let projectSpaces = [space(id: "s1", name: "Project Space")]
        let accountSpaces = [space(id: "s2", name: "Account Space")]
        let resolved = NavigationRouteResolution.space(id: "s1", projectSpaces: projectSpaces, accountSpaces: accountSpaces)
        #expect(resolved?.id == "s1")
        #expect(resolved?.name == "Project Space")
    }

    @Test("Falls back to account spaces when project space is missing")
    func fallsBackToAccountSpaces() {
        let projectSpaces = [space(id: "s1", name: "Project Space")]
        let accountSpaces = [space(id: "s2", name: "Account Space")]
        let resolved = NavigationRouteResolution.space(id: "s2", projectSpaces: projectSpaces, accountSpaces: accountSpaces)
        #expect(resolved?.id == "s2")
        #expect(resolved?.name == "Account Space")
    }

    @Test("Prefers project space over account space for the same ID")
    func prefersProjectSpaceOverAccountSpace() {
        let projectSpaces = [space(id: "s1", name: "Project Copy")]
        let accountSpaces = [space(id: "s1", name: "Account Copy")]
        let resolved = NavigationRouteResolution.space(id: "s1", projectSpaces: projectSpaces, accountSpaces: accountSpaces)
        #expect(resolved?.name == "Project Copy")
    }
}
