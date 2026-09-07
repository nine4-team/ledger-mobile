import XCTest

@MainActor
final class WorkspaceChecklistUITests: XCTestCase {
    func testRemovalHidesProtectedWorkspace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let spaces = app.buttons["target-active-project-spaces-tab"]
        reveal(spaces, in: app)
        XCTAssertTrue(spaces.waitForExistence(timeout: 5))
        spaces.tap()
        let space = app.buttons["target-active-space-card-space-ui-test"]
        reveal(space, in: app)
        XCTAssertTrue(space.waitForExistence(timeout: 5))
        space.tap()
        let name = app.staticTexts["target-active-space-detail-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let remove = app.buttons["target-ui-fixture-remove-account"]
        reveal(remove, in: app, upwards: false)
        remove.tap()
        let locked = app.descendants(matching: .any)
            .matching(identifier: "target-workspace-access-removed").firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 5))
        XCTAssertFalse(name.exists)
        XCTAssertFalse(app.buttons["target-active-workspace-back"].exists)
        XCTAssertFalse(app.buttons["target-active-space-checklist-item-checklist-ui-test-item-ui-test"].exists)
        XCTAssertFalse(project.exists)
    }

    func testProjectSpaceChecklistInteraction() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["target-ui-fixture-banner"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["target-staging-banner"].exists)

        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let spaces = app.buttons["target-active-project-spaces-tab"]
        reveal(spaces, in: app)
        XCTAssertTrue(spaces.waitForExistence(timeout: 5), app.debugDescription)
        spaces.tap()
        let space = app.buttons["target-active-space-card-space-ui-test"]
        reveal(space, in: app)
        XCTAssertTrue(space.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(space.value as? String,
                       "0 of 1 checklist items complete; item count unavailable; image unavailable")
        space.tap()

        let section = app.descendants(matching: .any)
            .matching(identifier: "target-active-space-checklists-section").firstMatch
        reveal(section, in: app)
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        #if os(macOS)
        let expanders = app.descendants(matching: .disclosureTriangle)
        XCTAssertEqual(expanders.count, 1, "This fixture exposes exactly one checklist disclosure")
        let expander = expanders.firstMatch
        XCTAssertTrue(expander.exists, app.debugDescription)
        #else
        let expander = section
        #endif
        let item = app.buttons["target-active-space-checklist-item-checklist-ui-test-item-ui-test"]
        // Exercise both directions regardless of the initial expansion state.
        if !item.exists { expander.tap() }
        reveal(item, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        expander.tap()
        XCTAssertTrue(waitUntil { !item.exists })
        expander.tap()
        reveal(item, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual(item.value as? String, "Not checked")
        XCTAssertTrue(item.isEnabled)
        item.tap()
        XCTAssertTrue(waitUntil { item.value as? String == "Checked" })

        let accepted = app.descendants(matching: .any)
            .matching(identifier: "target-ui-fixture-acceptance-count").firstMatch
        reveal(accepted, in: app, upwards: false)
        XCTAssertTrue(accepted.exists, app.debugDescription)
        XCTAssertTrue(waitUntil { accepted.label == "Accepted invocations: 1" || (accepted.value as? String) == "1" })
        let status = app.descendants(matching: .any)
            .matching(identifier: "target-active-space-checklist-operation-status").firstMatch
        reveal(status, in: app)
        XCTAssertTrue(status.exists)
        XCTAssertTrue(waitUntil {
            let text = status.label + " " + (status.value as? String ?? "")
                + " " + status.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            return text.localizedCaseInsensitiveContains("queued")
                || text.localizedCaseInsensitiveContains("pending")
        })

        let back = app.buttons["target-active-workspace-back"]
        reveal(back, in: app, upwards: false)
        back.tap()
        reveal(space, in: app)
        XCTAssertTrue(space.waitForExistence(timeout: 5))
        XCTAssertFalse(item.exists)
        XCTAssertFalse(status.exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        #if os(iOS)
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.exists)
        for _ in 0..<6 {
            if element.waitForExistence(timeout: 1), element.isHittable { return }
            if upwards { list.swipeUp() } else { list.swipeDown() }
        }
        #endif
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() }, object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
