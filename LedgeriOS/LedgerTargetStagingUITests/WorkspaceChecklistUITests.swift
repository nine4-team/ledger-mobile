import XCTest

@MainActor
final class WorkspaceChecklistUITests: XCTestCase {
    func testPropertyManagementEmptyAndUnavailableStates() throws {
        continueAfterFailure = false
        for (fixture, identifier, exportEnabled) in [
            ("empty", "target-property-report-empty", true),
            ("loading", "target-property-report-loading", false),
            ("incomplete", "target-property-report-incomplete", false),
            ("failed", "target-property-report-unavailable", false),
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-report-\(fixture)"]
            app.launch()
            defer { app.terminate() }
            let project = app.buttons["target-active-project-card-project-ui-test"]
            XCTAssertTrue(project.waitForExistence(timeout: 10))
            project.tap()
            let openReport = app.buttons["target-property-report-open"]
            reveal(openReport, in: app)
            XCTAssertTrue(openReport.waitForExistence(timeout: 5))
            openReport.tap()
            let state = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(state.waitForExistence(timeout: 5), app.debugDescription)
            for control in ["target-property-report-share", "target-property-report-csv", "target-property-report-print"] {
                XCTAssertEqual(app.buttons[control].isEnabled, exportEnabled, fixture)
            }
            let refresh = app.buttons["target-property-report-refresh"]
            XCTAssertTrue(refresh.isEnabled)
            refresh.tap()
            XCTAssertTrue(state.waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)
                .matching(identifier: "target-property-report-item-report-ui-chair").firstMatch.exists)
            app.buttons["Done"].tap()
            XCTAssertTrue(openReport.waitForExistence(timeout: 5))
        }
    }

    #if os(macOS)
    func testPropertyManagementSystemDialogCancellation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let openReport = app.buttons["target-property-report-open"]
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
        openReport.tap()
        let share = app.buttons["target-property-report-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        let busy = app.descendants(matching: .any).matching(identifier: "target-property-report-exporting").firstMatch
        let failure = app.descendants(matching: .any).matching(identifier: "target-property-report-export-error").firstMatch
        let pickerVisible = {
            app.menuItems.allElementsBoundByIndex.contains { $0.isHittable }
                || app.popovers.allElementsBoundByIndex.contains { $0.isHittable }
        }

        // Open real native pickers, but never choose a destination or send data.
        // Repeat PDF after CSV to exercise native presentation-state release.
        for identifier in ["target-property-report-share", "target-property-report-csv", "target-property-report-share"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isEnabled)
            XCTAssertFalse(pickerVisible())
            button.tap()
            XCTAssertTrue(waitUntil(pickerVisible), app.debugDescription)
            XCTAssertFalse(failure.exists)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil { !pickerVisible() && !busy.exists && button.isEnabled }, app.debugDescription)
            XCTAssertFalse(failure.exists)
        }

        // Observe the actual print controls and cancel; never press Print.
        let printButton = app.buttons["target-property-report-print"]
        printButton.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(failure.exists)
        cancel.tap()
        XCTAssertTrue(waitUntil { !busy.exists && printButton.isEnabled }, app.debugDescription)
        XCTAssertFalse(failure.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
    }
    #endif

    func testPropertyManagementPreviewRefreshAndDismiss() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let openReport = app.buttons["target-property-report-open"]
        reveal(openReport, in: app)
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
        openReport.tap()
        let item = app.descendants(matching: .any)
            .matching(identifier: "target-property-report-item-report-ui-chair").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["target-property-report-share"].isEnabled)
        XCTAssertTrue(app.buttons["target-property-report-print"].isEnabled)
        XCTAssertTrue(app.buttons["target-property-report-csv"].isEnabled)
        XCTAssertTrue(waitUntil {
            let text = item.label + " " + ((item.value as? String) ?? "")
            return text.contains("Report test chair") && text.contains("CHAIR-001") && text.contains("Unknown")
        })
        let refresh = app.buttons["target-property-report-refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "target-property-report-totals").firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
        let remove = app.buttons["target-ui-fixture-remove-account"]
        reveal(remove, in: app, upwards: false)
        remove.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "target-workspace-access-removed").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(openReport.exists)
        XCTAssertFalse(item.exists)
    }

    func testDownloadedItemsRefreshAndRemoval() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let item = app.staticTexts["target-physical-item-physical-ui-chair"]
        reveal(item, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        // macOS SwiftUI static text can expose its content as AXValue;
        // iOS generally uses AXLabel. Verify content on this same element.
        XCTAssertTrue(waitUntil {
            item.label == "Downloaded test chair"
                || (item.value as? String) == "Downloaded test chair"
        })
        XCTAssertTrue(app.staticTexts["target-items-partial-notice"].exists)
        let refresh = app.buttons["target-items-refresh"]
        reveal(refresh, in: app)
        refresh.tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        let remove = app.buttons["target-ui-fixture-remove-account"]
        reveal(remove, in: app, upwards: false)
        remove.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "target-workspace-access-removed").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(item.exists)
        XCTAssertFalse(refresh.exists)
    }

    func testArchivedProjectHistoryNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let active = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(active.waitForExistence(timeout: 10))
        #if os(macOS)
        // Keep this task's own window clear of unrelated always-on-top panels.
        // Do not dismiss or interact with the user's other applications.
        let window = app.windows.firstMatch
        let titlebar = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 12))
        titlebar.press(forDuration: 0.1, thenDragTo: titlebar.withOffset(CGVector(
            dx: 24 - window.frame.minX, dy: 60 - window.frame.minY
        )))
        let archivedSegment = app.radioButtons["Archived"]
        #else
        let archivedSegment = app.segmentedControls.buttons["Archived"]
        #endif
        XCTAssertTrue(archivedSegment.waitForExistence(timeout: 5))
        if !archivedSegment.isHittable {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(archivedSegment.isHittable, app.debugDescription)
        archivedSegment.tap()
        let archived = app.buttons["target-active-project-card-project-archived-ui-test"]
        XCTAssertTrue(archived.waitForExistence(timeout: 5))
        XCTAssertFalse(active.exists)
        archived.tap()
        let notes = app.buttons["target-active-project-notes-tab"]
        reveal(notes, in: app)
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["target-active-project-spaces-tab"].exists)
        notes.tap()
        XCTAssertTrue(app.staticTexts["Measure the entry before delivery."].waitForExistence(timeout: 5))
        app.buttons["target-active-workspace-back"].tap()
        app.buttons["target-active-workspace-back"].tap()
        XCTAssertTrue(archived.waitForExistence(timeout: 5))
        XCTAssertFalse(active.exists)
    }

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
        let notes = app.buttons["target-active-project-notes-tab"]
        reveal(notes, in: app)
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        XCTAssertTrue(app.staticTexts["Measure the entry before delivery."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Test Designer"].exists)
        XCTAssertFalse(app.buttons["target-project-note-older"].isEnabled)
        app.buttons["target-active-workspace-back"].tap()
        XCTAssertTrue(app.buttons["target-active-project-spaces-tab"].waitForExistence(timeout: 5))
        let spaces = app.buttons["target-active-project-spaces-tab"]
        reveal(spaces, in: app)
        XCTAssertTrue(spaces.waitForExistence(timeout: 5), app.debugDescription)
        spaces.tap()
        let search = app.textFields["target-space-search"]
        reveal(search, in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("no-matching-space")
        XCTAssertTrue(app.staticTexts["target-space-search-no-match"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["target-active-space-card-space-ui-test"].exists)
        app.buttons["target-space-search-clear"].tap()
        search.tap()
        search.typeText("ui TEST")
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
