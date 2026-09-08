import XCTest
import CoreText
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
final class WorkspaceChecklistUITests: XCTestCase {
    private func displayedText(_ element: XCUIElement) -> String {
        #if os(macOS)
        return element.value as? String ?? ""
        #else
        return element.label
        #endif
    }

    func testAccountSettingsDownloadedProfileRefreshAndDismiss() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["target-account-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let name = app.staticTexts["target-account-profile-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(name), "Design studio")
        XCTAssertTrue(app.staticTexts["No business logo"].exists)
        XCTAssertTrue(app.staticTexts["target-account-profile-stale"].exists)
        app.buttons["target-account-profile-refresh"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(name), "Design studio")
        app.buttons["target-account-settings-done"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertFalse(name.exists)
        app.buttons["target-active-project-card-project-ui-test"].tap()
        let report = app.buttons["target-property-report-open"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(name), "Design studio")
        XCTAssertTrue(app.staticTexts["No business logo"].exists)
        let share = app.buttons["target-property-report-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: share)
        waitForExpectations(timeout: 5)
    }

    func testInventoryNavigationAndRememberedSection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-reset-inventory-section"]
        app.launch()
        defer { app.terminate() }
        let inventory = app.buttons["target-business-inventory-card"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 10))
        func segment(_ name: String) -> XCUIElement {
            #if os(macOS)
            return app.radioButtons[name]
            #else
            return app.segmentedControls.buttons[name]
            #endif
        }
        segment("Archived").tap()
        XCTAssertFalse(inventory.exists)
        segment("Active").tap()
        XCTAssertTrue(inventory.waitForExistence(timeout: 5))
        inventory.tap()
        XCTAssertTrue(app.staticTexts["target-items-partial-notice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["target-vendor-pdf-open"].exists)
        segment("Spaces").tap()
        XCTAssertTrue(app.staticTexts["No Spaces in Business Inventory."].waitForExistence(timeout: 5))
        segment("Transactions").tap()
        let unavailable = app.staticTexts["target-inventory-transactions-unavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        app.buttons["target-active-workspace-back"].tap()
        inventory.tap()
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        XCTAssertTrue(inventory.waitForExistence(timeout: 10))
        inventory.tap()
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        segment("Items").tap()
        XCTAssertTrue(app.staticTexts["target-items-partial-notice"].waitForExistence(timeout: 5))
    }

    #if os(macOS)
    func testVendorPDFActualFileReview() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_ISOLATED_CI_CLIPBOARD"] == "true" else {
            throw XCTSkip("Diagnostic Copy uses only the isolated CI clipboard")
        }
        continueAfterFailure = false
        let permissionMonitor = installOfflinePDFPermissionHandler()
        defer { removeUIInterruptionMonitor(permissionMonitor) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-synthetic-\(UUID().uuidString).pdf")
        try Data("synthetic unreadable PDF".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        app.buttons["target-vendor-pdf-open"].tap()
        let select = app.buttons["target-vendor-pdf-select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        selectVendorPDF(file, in: app)
        let parseError = app.descendants(matching: .any)["target-vendor-pdf-error"].firstMatch
        XCTAssertTrue(parseError.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(displayedText(parseError).contains("could not be read"))
        // Replacing bytes at the same path must not reuse the failed parse.
        try syntheticVendorPDF().write(to: file, options: .atomic)
        selectVendorPDF(file, in: app)
        let count = app.descendants(matching: .any)["target-vendor-pdf-included-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(parseError.exists)
        XCTAssertEqual(displayedText(count), "Included rows: 2 of 2")
        let category = app.descendants(matching: .any)["target-vendor-pdf-category"].firstMatch
        XCTAssertEqual(category.value as? String, "No Category")
        category.tap()
        let furnishings = app.menuItems["Furnishings"].firstMatch
        XCTAssertTrue(furnishings.waitForExistence(timeout: 5))
        furnishings.tap()
        XCTAssertEqual(category.value as? String, "Furnishings")
        let scroll = app.scrollViews["target-vendor-pdf-scroll"].firstMatch
        func show(_ element: XCUIElement, upward: Bool = true) {
            for _ in 0..<10 {
                if element.exists && element.isHittable { return }
                if upward { scroll.swipeUp() } else { scroll.swipeDown() }
            }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        for (id, value) in [("description", "Edited chair"), ("quantity", "3"), ("price", "12.34")] {
            let field = app.descendants(matching: .any)["target-vendor-pdf-\(id)-1"].firstMatch
            show(field)
            field.tap()
            app.typeKey("a", modifierFlags: .command)
            app.typeText(value)
            XCTAssertEqual(field.value as? String, value)
        }
        let include = vendorIncludeControl(row: 0, in: app)
        show(include, upward: false)
        include.tap()
        XCTAssertEqual(displayedText(count), "Included rows: 1 of 2")
        let stats = app.buttons["target-vendor-pdf-stats-toggle"]
        show(stats)
        stats.tap()
        XCTAssertTrue(app.descendants(matching: .any)["target-vendor-pdf-stats"].exists)
        let raw = app.buttons["target-vendor-pdf-raw-toggle"]
        show(raw)
        raw.tap()
        let rawText = app.descendants(matching: .any)["target-vendor-pdf-raw"].firstMatch
        XCTAssertTrue(rawText.exists)
        XCTAssertTrue(displayedText(rawText).contains("Synthetic Chair"))
        XCTAssertFalse(displayedText(rawText).contains("synthetic-secret"))
        raw.tap()
        let copy = app.buttons["target-vendor-pdf-copy-debug"]
        show(copy)
        copy.tap()
        let json = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertFalse(json.contains("synthetic-secret"))
        XCTAssertTrue(json.contains("Synthetic Chair")) // Originals, not edited draft text.
        show(select, upward: false)
        select.tap()
        let pickerCancel = vendorPickerCancel(in: app)
        XCTAssertTrue(pickerCancel.waitForExistence(timeout: 5))
        pickerCancel.tap()
        XCTAssertTrue(pickerCancel.waitForNonExistence(timeout: 5))
        XCTAssertEqual(displayedText(count), "Included rows: 1 of 2")
        let description = app.descendants(matching: .any)["target-vendor-pdf-description-1"].firstMatch
        show(description)
        XCTAssertEqual(description.value as? String, "Edited chair")
        XCTAssertEqual(category.value as? String, "Furnishings")
        app.buttons["target-vendor-pdf-cancel"].tap()
        XCTAssertTrue(count.waitForNonExistence(timeout: 5))
    }

    private func selectVendorPDF(_ file: URL, in app: XCUIApplication) {
        app.buttons["target-vendor-pdf-select"].tap()
        let open = app.sheets["open-panel"].buttons["OKButton"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(file.path)
        app.typeKey(.return, modifierFlags: [])
        // Let XCTest perform its interruption handling as part of the action.
        // Polling isHittable alone cannot dismiss a native permission prompt.
        open.tap()
    }

    private func installOfflinePDFPermissionHandler() -> NSObjectProtocol {
        addUIInterruptionMonitor(withDescription: "Deny local-network discovery for offline PDF review") { dialog in
            let text = dialog.staticTexts.allElementsBoundByIndex.map {
                $0.label + " " + (($0.value as? String) ?? "")
            }.joined(separator: " ")
            guard text.contains("Ledger STAGING"), text.contains("local networks") else { return false }
            // The native report/print UI can leave this discovery prompt pending.
            // PDF review needs no discovery permission; never grant it to pass.
            let deny = dialog.buttons["Don’t Allow"]
            guard deny.exists else { return false }
            deny.tap()
            return true
        }
    }

    #endif

    private func syntheticVendorPDF(lines suppliedLines: [String]? = nil) throws -> Data {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let lines = suppliedLines ?? ["Amazon.com order number: 111-2222222-3333333", "Order Placed: January 2, 2025",
                     "1 of: Synthetic Table $10.00", "1 of: Synthetic Chair $20.00",
                     "Grand Total: $30.00", "access_token=synthetic-secret"]
        for (index, line) in lines.enumerated() {
            context.textPosition = CGPoint(x: 36, y: 750 - index * 20)
            let attributed = NSAttributedString(string: line,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    func testVendorPDFRemovalClosesLoadedReview() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-vendor-pdf-bytes",
            "--ledger-ui-test-remove-after-pdf-edit",
            "--ledger-ui-test-pdf-base64=" + (try syntheticVendorPDF().base64EncodedString())]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let open = app.buttons["target-vendor-pdf-open"]
        reveal(open, in: app)
        open.tap()
        let count = app.descendants(matching: .any)["target-vendor-pdf-included-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(displayedText(count), "Included rows: 2 of 2")
        let include = vendorIncludeControl(row: 0, in: app)
        let scroll = app.scrollViews["target-vendor-pdf-scroll"].firstMatch
        for _ in 0..<8 {
            if include.exists && include.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(include.isHittable, app.debugDescription)
        include.tap() // The fixture now delivers removal through its normal access stream.
        XCTAssertTrue(count.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(open.exists)
        XCTAssertFalse(app.buttons["target-vendor-pdf-select"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["target-vendor-pdf-row-0"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["target-workspace-access-removed"]
            .firstMatch.waitForExistence(timeout: 5))
        let cleared = app.descendants(matching: .any)["target-ui-fixture-pdf-cleared"].firstMatch
        XCTAssertTrue(cleared.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { (cleared.value as? String) == "true" }, app.debugDescription)
    }

    func testVendorPDFSelectionCancellation() throws {
        continueAfterFailure = false
        #if os(macOS)
        let permissionMonitor = installOfflinePDFPermissionHandler()
        defer { removeUIInterruptionMonitor(permissionMonitor) }
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let open = app.buttons["target-vendor-pdf-open"]
        reveal(open, in: app)
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            open.tap()
            let empty = app.descendants(matching: .any)["target-vendor-pdf-empty"].firstMatch
            XCTAssertTrue(empty.waitForExistence(timeout: 5))
            app.buttons["target-vendor-pdf-select"].tap()
            // Match the system picker's Cancel, not the underlying review toolbar.
            let pickerCancel = vendorPickerCancel(in: app)
            XCTAssertTrue(pickerCancel.waitForExistence(timeout: 10), app.debugDescription)
            pickerCancel.tap()
            XCTAssertTrue(pickerCancel.waitForNonExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(empty.exists)
            XCTAssertFalse(app.descendants(matching: .any)["target-vendor-pdf-error"].exists)
            app.buttons["target-vendor-pdf-cancel"].tap()
            XCTAssertTrue(empty.waitForNonExistence(timeout: 5))
            XCTAssertTrue(open.waitForExistence(timeout: 5))
        }
    }

    #if os(iOS)
    func testVendorPDFIOSFailureAndEmptyStates() throws {
        continueAfterFailure = false
        let cases: [(Data, String, String)] = [
            (Data("Unreadable synthetic PDF".utf8), "target-vendor-pdf-error",
             "The PDF could not be read. It may be corrupt or locked."),
            (try syntheticVendorPDF(lines: ["Unsupported synthetic supplier", "Total: $10.00"]),
             "target-vendor-pdf-error", "This PDF is not a supported Amazon or Wayfair document."),
            (try syntheticVendorPDF(lines: ["Amazon.com order number: 111-2222222-3333333"]),
             "target-vendor-pdf-no-rows", "No line items were extracted. Choose another PDF or review the source document.")
        ]
        for (bytes, identifier, expectedText) in cases {
            let app = XCUIApplication()
            app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-vendor-pdf-bytes",
                "--ledger-ui-test-pdf-base64=" + bytes.base64EncodedString()]
            app.launch()
            defer { app.terminate() }
            let project = app.buttons["target-active-project-card-project-ui-test"]
            XCTAssertTrue(project.waitForExistence(timeout: 10))
            project.tap()
            let open = app.buttons["target-vendor-pdf-open"]
            reveal(open, in: app)
            open.tap()
            let state = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(state.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(state.label, expectedText)
            XCTAssertFalse(app.descendants(matching: .any)["target-vendor-pdf-row-0"].exists)
            XCTAssertTrue(app.buttons["target-vendor-pdf-select"].isEnabled)
            app.buttons["target-vendor-pdf-cancel"].tap()
            XCTAssertTrue(state.waitForNonExistence(timeout: 5))
            XCTAssertTrue(open.exists)
        }
    }

    func testVendorPDFIOSLoadedReview() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-vendor-pdf-bytes"]
        app.launchArguments.append("--ledger-ui-test-pdf-base64=" + (try syntheticVendorPDF().base64EncodedString()))
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let open = app.buttons["target-vendor-pdf-open"]
        reveal(open, in: app)
        open.tap()
        let count = app.descendants(matching: .any)["target-vendor-pdf-included-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(count.label, "Included rows: 2 of 2")
        let category = app.descendants(matching: .any)["target-vendor-pdf-category"].firstMatch
        category.tap()
        let choice = app.buttons["Furnishings"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
        choice.tap()
        XCTAssertEqual(category.value as? String, "Furnishings")
        let scroll = app.scrollViews["target-vendor-pdf-scroll"].firstMatch
        func show(_ element: XCUIElement) {
            for _ in 0..<10 {
                if element.exists && element.isHittable { return }
                scroll.swipeUp()
            }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        let include = vendorIncludeControl(row: 0, in: app)
        show(include)
        include.tap()
        XCTAssertEqual(count.label, "Included rows: 1 of 2")
        var originalDescription: String?
        for (id, value) in [("description", "Edited table"), ("quantity", "3"), ("price", "12.34")] {
            let field = app.descendants(matching: .any)["target-vendor-pdf-\(id)-1"].firstMatch
            show(field)
            if id == "description" { originalDescription = try XCTUnwrap(field.value as? String) }
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            // Use native selection without depending on the transient long-press menu.
            app.typeKey("a", modifierFlags: .command)
            field.typeText(value)
            XCTAssertEqual(field.value as? String, value)
            let done = app.buttons["target-vendor-pdf-keyboard-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
            XCTAssertTrue(waitUntil { !app.keyboards.firstMatch.exists }, app.debugDescription)
        }
        app.buttons["target-vendor-pdf-cancel"].tap()
        XCTAssertTrue(count.waitForNonExistence(timeout: 5))
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "Included rows: 2 of 2")
        // Reopening constructs a new document review, not the abandoned draft.
        let description = app.descendants(matching: .any)["target-vendor-pdf-description-1"].firstMatch
        show(description)
        XCTAssertEqual(description.value as? String, try XCTUnwrap(originalDescription))
        app.buttons["target-vendor-pdf-cancel"].tap()
    }

    func testPropertyManagementIOSSystemDialogCancellation() throws {
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
        let busy = app.descendants(matching: .any).matching(identifier: "target-property-report-exporting").firstMatch
        let failure = app.descendants(matching: .any).matching(identifier: "target-property-report-export-error").firstMatch
        for identifier in ["target-property-report-share", "target-property-report-csv", "target-property-report-share"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isEnabled)
            button.tap()
            let activity = app.otherElements["ActivityListView"].firstMatch
            let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
            XCTAssertTrue(activity.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(dismiss.exists, app.debugDescription)
            XCTAssertFalse(failure.exists)
            // The native iPhone share popover has no Close button. Let XCTest
            // resolve the dismissal element's hittable point rather than send
            // an unchecked coordinate into its full-window bounding rectangle.
            XCTAssertTrue(waitUntil { dismiss.isHittable }, app.debugDescription)
            dismiss.tap()
            XCTAssertTrue(activity.waitForNonExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(busy.waitForNonExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(waitUntil { button.isEnabled }, app.debugDescription)
            XCTAssertFalse(failure.exists)
        }
        let printButton = app.buttons["target-property-report-print"]
        printButton.tap()
        let cancel = app.navigationBars["Options"].buttons["Close"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(failure.exists)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(busy.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitUntil { printButton.isEnabled }, app.debugDescription)
        XCTAssertFalse(failure.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
    }

    func testPropertyManagementIOSCopyCompletion() throws {
        executionTimeAllowance = 120
        guard ProcessInfo.processInfo.environment["LEDGER_ISOLATED_CI_CLIPBOARD"] == "true" else {
            throw XCTSkip("Native Copy completion uses only the isolated CI simulator clipboard")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-report-copy-receiver",
                               "--ledger-ui-test-profile-logo-unavailable"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let openReport = app.buttons["target-property-report-open"]
        reveal(openReport, in: app)
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
        let busy = app.descendants(matching: .any).matching(identifier: "target-property-report-exporting").firstMatch
        let failure = app.descendants(matching: .any).matching(identifier: "target-property-report-export-error").firstMatch
        for identifier in ["target-property-report-share", "target-property-report-csv"] {
            UIPasteboard.general.items = []
            reveal(openReport, in: app)
            openReport.tap()
            XCTAssertTrue(app.staticTexts["Business logo unavailable. Refresh to try again."].waitForExistence(timeout: 5))
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isEnabled)
            button.tap()
            let copy = app.otherElements["ActivityListView"].cells["Copy"].firstMatch
            XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
            copy.tap()
            // Each AX query can wait for a fresh hierarchy during dismissal.
            // Do not spend one predicate deadline fetching three snapshots.
            XCTAssertTrue(copy.waitForNonExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(busy.waitForNonExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(waitUntil { button.isEnabled }, app.debugDescription)
            XCTAssertFalse(failure.exists)
            let isPDF = identifier == "target-property-report-share"
            app.buttons["Done"].tap()
            let paste = app.buttons["target-ui-fixture-paste-report"]
            XCTAssertTrue(paste.waitForExistence(timeout: 5))
            XCTAssertTrue(paste.isEnabled)
            paste.tap()
            let result = app.staticTexts["target-ui-fixture-paste-result"]
            XCTAssertTrue(waitUntil { result.label == (isPDF ? "PDF content received" : "CSV content received") }, app.debugDescription)
        }
        XCTAssertTrue(openReport.waitForExistence(timeout: 5))
    }
    #endif

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
            XCTAssertTrue(busy.waitForNonExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(waitUntil { button.isEnabled }, app.debugDescription)
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
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-report-grouped"]
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
        XCTAssertTrue(app.staticTexts["Report Living Room"].exists)
        XCTAssertTrue(app.staticTexts["No Space"].exists)
        for (id, name, sku, value) in [
            ("table", "Report test table", "TABLE-002", "USD 123.45"),
            ("lamp", "Report test lamp", "Not provided", "USD 0.00")
        ] {
            let row = app.descendants(matching: .any)
                .matching(identifier: "target-property-report-item-report-ui-\(id)").firstMatch
            XCTAssertTrue(row.exists)
            let text = row.label + " " + ((row.value as? String) ?? "")
            XCTAssertTrue(text.contains(name) && text.contains(sku) && text.contains(value), text)
            XCTAssertFalse(text.contains("Unknown"))
        }
        let reportTotals = app.descendants(matching: .any)
            .matching(identifier: "target-property-report-totals")
        for text in ["Items: 3", "Known market value subtotal: USD 123.45", "Unknown values: 1"] {
            XCTAssertTrue(reportTotals.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch.exists)
        }
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
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        // macOS SwiftUI static text can expose its content as AXValue;
        // iOS generally uses AXLabel. Verify content on this same element.
        XCTAssertTrue(waitUntil {
            item.label == "Downloaded test chair"
                || (item.value as? String) == "Downloaded test chair"
        })
        XCTAssertTrue(app.staticTexts["target-items-partial-notice"].exists)
        item.tap()
        XCTAssertTrue(app.staticTexts["target-item-history-partial"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current test Project"].exists)
        XCTAssertTrue(app.staticTexts["Business Inventory"].exists)
        XCTAssertTrue(app.staticTexts["Space name not downloaded"].exists)
        app.buttons["target-item-history-refresh"].tap()
        XCTAssertTrue(app.staticTexts["Current downloaded location"].waitForExistence(timeout: 5))
        app.buttons["target-item-history-done"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
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
        try exerciseSpaceChecklist(inventory: false)
    }

    func testLegacyProjectNotesRemainSeparate() throws {
        continueAfterFailure = false
        for mode in ["both", "legacy-only", "individual-only", "neither"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-legacy-notes=\(mode)"]
            app.launch()
            defer { app.terminate() }
            let project = app.buttons["target-active-project-card-project-ui-test"]
            XCTAssertTrue(project.waitForExistence(timeout: 10))
            project.tap()
            let notes = app.buttons["target-active-project-notes-tab"]
            reveal(notes, in: app)
            XCTAssertTrue(notes.waitForExistence(timeout: 5))
            notes.tap()
            let status = app.descendants(matching: .any)["target-project-note-history-status"].firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            let legacy = app.staticTexts["target-project-legacy-notes-text"]
            if mode == "both" || mode == "legacy-only" {
                XCTAssertTrue(legacy.waitForExistence(timeout: 5))
                XCTAssertEqual(displayedText(legacy), "Original planning notes\nKeep the blue sofa.")
                let card = app.descendants(matching: .any)["target-project-legacy-notes-card"].firstMatch
                XCTAssertFalse(card.staticTexts["Test Designer"].exists)
                XCTAssertFalse(card.staticTexts["target-project-note-source"].exists)
            } else { XCTAssertFalse(legacy.exists) }
            if mode == "both" || mode == "individual-only" {
                XCTAssertTrue(app.staticTexts["Measure the entry before delivery."].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Test Designer"].exists)
            } else {
                XCTAssertTrue(app.staticTexts["target-project-note-history-empty"].waitForExistence(timeout: 5))
                XCTAssertEqual(displayedText(app.staticTexts["target-project-note-history-empty"]), "No individual notes")
            }
            app.terminate()
        }
    }

    func testInventorySpaceChecklistInteraction() throws {
        try exerciseSpaceChecklist(inventory: true)
    }

    private func exerciseSpaceChecklist(inventory: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        if inventory {
            app.launchArguments += ["--ledger-ui-test-inventory-space", "--ledger-ui-test-reset-inventory-section"]
        }
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["target-ui-fixture-banner"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["target-staging-banner"].exists)

        if inventory {
            let card = app.buttons["target-business-inventory-card"]
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            card.tap()
            #if os(macOS)
            app.radioButtons["Spaces"].tap()
            #else
            app.segmentedControls.buttons["Spaces"].tap()
            #endif
            XCTAssertFalse(app.buttons["target-active-project-notes-tab"].exists)
        } else {
            let project = app.buttons["target-active-project-card-project-ui-test"]
            XCTAssertTrue(project.waitForExistence(timeout: 10))
            project.tap()
            let notes = app.buttons["target-active-project-notes-tab"]
            reveal(notes, in: app)
            XCTAssertTrue(notes.waitForExistence(timeout: 5))
            notes.tap()
            XCTAssertTrue(app.staticTexts["Measure the entry before delivery."].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Test Designer"].exists)
            let noteSource = app.descendants(matching: .any)["target-project-note-source"].firstMatch
            XCTAssertTrue(noteSource.waitForExistence(timeout: 5))
            XCTAssertEqual(displayedText(noteSource), "Source: text")
            XCTAssertFalse(app.buttons["target-project-note-older"].isEnabled)
            app.buttons["target-active-workspace-back"].tap()
            XCTAssertTrue(app.buttons["target-active-project-spaces-tab"].waitForExistence(timeout: 5))
            let spaces = app.buttons["target-active-project-spaces-tab"]
            reveal(spaces, in: app)
            XCTAssertTrue(spaces.waitForExistence(timeout: 5), app.debugDescription)
            spaces.tap()
        }
        let search = app.textFields["target-space-search"]
        reveal(search, in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("no-matching-space")
        XCTAssertTrue(app.staticTexts["target-space-search-no-match"].waitForExistence(timeout: 5), app.debugDescription)
        let spaceIdentifier = inventory ? "target-inventory-space-space-ui-test" : "target-active-space-card-space-ui-test"
        XCTAssertFalse(app.buttons[spaceIdentifier].exists)
        app.buttons["target-space-search-clear"].tap()
        search.tap()
        search.typeText("ui TEST")
        #if os(iOS)
        let submitSearch = app.keyboards.buttons["Search"]
        XCTAssertTrue(submitSearch.waitForExistence(timeout: 5))
        submitSearch.tap()
        XCTAssertTrue(waitUntil { !app.keyboards.firstMatch.exists })
        #endif
        let space = app.buttons[spaceIdentifier]
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
        XCTAssertTrue(waitUntil { accepted.label == "Accepted invocations: 1" || (accepted.value as? String) == "1" }, app.debugDescription)
        let status = app.descendants(matching: .any)
            .matching(identifier: "target-active-space-checklist-operation-status").firstMatch
        reveal(status, in: app)
        XCTAssertTrue(status.exists)
        XCTAssertTrue(waitUntil {
            self.displayedText(status) == "Checklist synchronization: queued — accepted locally"
        }, app.debugDescription)

        // The same exact-Space read-only route works in Project and Inventory.
        // Other-Space and unassigned rows exist in the fixture's scope reader.
        let physicalItem = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(physicalItem, in: app)
        XCTAssertTrue(physicalItem.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["target-physical-item-physical-ui-other-space"].exists)
        XCTAssertFalse(app.buttons["target-physical-item-physical-ui-unassigned"].exists)
        let downloadedCount = app.staticTexts["target-items-downloaded-count"]
        XCTAssertTrue(waitUntil {
            downloadedCount.label == "Downloaded Items: 1"
                || (downloadedCount.value as? String) == "Downloaded Items: 1"
        })
        physicalItem.tap()
        XCTAssertTrue(app.staticTexts["target-item-history-partial"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current test Space"].exists)
        XCTAssertTrue(app.staticTexts["Current downloaded location"].exists)
        if inventory {
            XCTAssertFalse(app.staticTexts["Current test Project"].exists)
        } else {
            XCTAssertTrue(app.staticTexts["Current test Project"].exists)
        }
        app.buttons["target-item-history-done"].tap()
        XCTAssertTrue(physicalItem.waitForExistence(timeout: 5))
        reveal(item, in: app, upwards: false)
        XCTAssertEqual(item.value as? String, "Checked", "Opening history must preserve the current Space checklist state")

        let back = app.buttons["target-active-workspace-back"]
        reveal(back, in: app, upwards: false)
        back.tap()
        reveal(space, in: app)
        XCTAssertTrue(space.waitForExistence(timeout: 5))
        XCTAssertFalse(item.exists)
        XCTAssertFalse(status.exists)
    }

    private func displayedText(_ element: XCUIElement) -> String {
        // Native macOS StaticText exposes its content as AXValue; iOS uses
        // AXLabel. Keep the exact expected text assertion on both platforms.
        #if os(macOS)
        return (element.value as? String) ?? element.label
        #else
        return element.label
        #endif
    }

    private func vendorPickerCancel(in app: XCUIApplication) -> XCUIElement {
        #if os(macOS)
        // Identifiers observed in the native open-panel failure hierarchy.
        return app.sheets["open-panel"].buttons["CancelButton"]
        #else
        // Scope to the actual Files navigation bar observed in native CI.
        return app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons["Cancel"]
        #endif
    }

    private func vendorIncludeControl(row: Int, in app: XCUIApplication) -> XCUIElement {
        let identifier = "target-vendor-pdf-include-\(row)"
        #if os(iOS)
        // SwiftUI exposes a full-width Switch wrapper and a nested UISwitch.
        // The wrapper's center is label whitespace, not the native control.
        return app.switches[identifier].switches.firstMatch
        #else
        return app.descendants(matching: .any)[identifier].firstMatch
        #endif
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        #if os(iOS)
        let list = app.collectionViews.firstMatch
        #elseif os(macOS)
        let list = app.scrollViews.firstMatch
        #endif
        XCTAssertTrue(list.exists)
        for _ in 0..<6 {
            if element.waitForExistence(timeout: 1), element.isHittable { return }
            if upwards { list.swipeUp() } else { list.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() }, object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
