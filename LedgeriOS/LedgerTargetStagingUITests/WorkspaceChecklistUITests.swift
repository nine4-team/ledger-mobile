import XCTest
#if os(macOS)
import AppKit
#endif

@MainActor
final class WorkspaceChecklistUITests: XCTestCase {
    func testPropertyManagementExportFailureAllowsRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-report-export-denied"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let openReport = app.buttons["target-property-report-open"]
        reveal(openReport, in: app)
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
        openReport.tap()
        let failure = app.descendants(matching: .any)
            .matching(identifier: "target-property-report-export-error").firstMatch
        let busy = app.descendants(matching: .any)
            .matching(identifier: "target-property-report-exporting").firstMatch
        // A complete preview is not sufficient authority to deliver. The
        // fixture denies the final read, exercising the real export error path
        // without substituting a fake native Share/Print completion.
        for identifier in ["target-property-report-share", "target-property-report-csv", "target-property-report-print"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isEnabled)
            button.tap()
            XCTAssertTrue(failure.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(waitUntil { !busy.exists && button.isEnabled })
            let text = failure.label + " " + ((failure.value as? String) ?? "")
            XCTAssertTrue(text.contains("could not be shared or printed"))
            let refresh = app.buttons["target-property-report-refresh"]
            XCTAssertTrue(refresh.isEnabled)
            refresh.tap()
            XCTAssertTrue(waitUntil { button.isEnabled })
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
    }

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
    func testPropertyManagementNativeCopyCompletion() throws {
        // Only the disposable CI desktop's clipboard may be changed by this
        // check. Do not overwrite the developer's clipboard during local QA.
        guard ProcessInfo.processInfo.environment["LEDGER_ISOLATED_CI_CLIPBOARD"] == "true" else {
            throw XCTSkip("Native Copy completion uses the isolated CI clipboard")
        }
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
        let busy = app.descendants(matching: .any).matching(identifier: "target-property-report-exporting").firstMatch
        let failure = app.descendants(matching: .any).matching(identifier: "target-property-report-export-error").firstMatch
        let picker = app.popovers.containing(.button, identifier: "Copy").firstMatch
        for identifier in ["target-property-report-share", "target-property-report-csv"] {
            NSPasteboard.general.clearContents()
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isEnabled)
            button.tap()
            let copy = picker.buttons["Copy"]
            XCTAssertTrue(copy.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(busy.exists)
            copy.tap()
            // This observes the actual service delegate completion, not merely
            // choosing a destination or an injected test handoff callback.
            XCTAssertTrue(waitUntil { !picker.exists && !busy.exists && button.isEnabled }, app.debugDescription)
            XCTAssertFalse(failure.exists)
            // A callback is not usable delivery if cleanup deletes the file
            // referenced by the clipboard. Inspect only this isolated CI
            // clipboard, which we cleared immediately before the synthetic copy.
            let copiedURLs = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            let isPDF = identifier == "target-property-report-share"
            let bytes: Data
            if let url = copiedURLs.first {
                bytes = try Data(contentsOf: url)
            } else if let data = NSPasteboard.general.data(forType: isPDF ? .pdf : .string) {
                bytes = data
            } else {
                XCTFail("Share Copy produced no usable report payload: \(NSPasteboard.general.types ?? [])")
                return
            }
            if isPDF { XCTAssertTrue(bytes.starts(with: Data("%PDF-".utf8))) }
            else { XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("Report test chair")) }
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
    }

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
        // The observed macOS Share popover has real destination buttons, but
        // its non-interactive container reports disabled/not hittable. Observe
        // that concrete native UI instead of scanning every app menu item.
        let picker = app.popovers.containing(.button, identifier: "Copy").firstMatch
        let pickerVisible = {
            picker.exists && !picker.frame.isEmpty && picker.buttons["Copy"].exists
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
        let printDialog = app.dialogs["Print"]
        let cancel = printDialog.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(failure.exists)
        // The actual application-modal panel is a Dialog; the AX tree also
        // contains another offscreen Cancel. Target the visible dialog's own
        // control instead of sending Escape to whichever window has focus.
        XCTAssertTrue(waitUntil { cancel.isHittable }, app.debugDescription)
        cancel.click()
        XCTAssertTrue(waitUntil { !printDialog.exists }, app.debugDescription)
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
