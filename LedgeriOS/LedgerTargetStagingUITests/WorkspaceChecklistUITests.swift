import XCTest
import CoreText
import PDFKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
final class WorkspaceChecklistUITests: XCTestCase {
    func testLocalAccountOnboardingThroughExistingGate() throws {
        try exerciseLocalAccountEntry(signOutOnly: false)
    }

    func testLocalEmptyAccountSignOutSurvivesRelaunch() throws {
        try exerciseLocalAccountEntry(signOutOnly: true)
    }

    private func exerciseLocalAccountEntry(signOutOnly: Bool) throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LEDGER_ONBOARDING_UI"] == "1", let email = env["LEDGER_ONBOARDING_EMAIL"],
              let password = env["LEDGER_ONBOARDING_PASSWORD"], email.hasSuffix("@ledger-tests.invalid") else {
            throw XCTSkip("Run the isolated local onboarding harness with --ui")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        let passwordPrompt = addUIInterruptionMonitor(withDescription: "Decline saving the disposable QA password") { alert in
            let decline = alert.buttons["Not Now"]
            guard decline.exists else { return false }
            decline.tap()
            return true
        }
        defer { removeUIInterruptionMonitor(passwordPrompt) }
        app.launch()
        defer { app.terminate() }
        func signIn() {
            let emailField = app.textFields["Email"]
            XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Do not replace an existing local session")
            emailField.tap(); emailField.typeText(email)
            let passwordField = app.secureTextFields["Password"]
            passwordField.tap(); passwordField.typeText(password + "\n")
            let signInButtons = app.buttons.matching(identifier: "Sign In")
            XCTAssertEqual(signInButtons.count, 2) // Mode selector, then submit.
            signInButtons.element(boundBy: 1).tap()
            XCTAssertTrue(app.buttons["Create Account"].waitForExistence(timeout: 15))
            // The password dialog may be owned by a system process, absent from
            // this app's hierarchy. A benign interaction invokes the monitor.
            app.staticTexts["target-staging-banner"].tap()
        }
        signIn()
        if signOutOnly {
            app.buttons["Sign Out"].tap()
            XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Create Account"].exists)
            app.terminate()
            app.launch()
            XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Create Account"].exists)
            return
        }
        app.buttons["Create Account"].tap()
        let account = app.buttons["My account"]
        XCTAssertTrue(account.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["target-account-settings"].exists, "Creation must not auto-select")
        account.tap()
        let settings = app.buttons["target-account-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        reveal(settings, in: app, within: app.scrollViews["target-workspace-scroll"])
        settings.tap()
        let categories = app.buttons["target-settings-budget-categories"]
        XCTAssertTrue(categories.waitForExistence(timeout: 5))
        categories.tap()
        for name in ["Furnishings", "Install", "Design Fee", "Storage & Receiving"] {
            XCTAssertTrue(app.buttons["Edit \(name)"].waitForExistence(timeout: 10))
        }
    }

    private nonisolated let failureScreenshotLock = NSLock()
    #if os(macOS)
    private var isolatedPermissionMonitor: NSObjectProtocol?

    override func setUpWithError() throws {
        try super.setUpWithError()
        // The CI failure screenshot proves report/print discovery can interrupt
        // later, unrelated fixtures. Reuse the narrowly scoped existing handler;
        // do not grant permission or change a developer's desktop preferences.
        if ProcessInfo.processInfo.environment["LEDGER_ISOLATED_CI_CLIPBOARD"] == "true" {
            isolatedPermissionMonitor = installOfflinePDFPermissionHandler()
        }
    }

    override func tearDownWithError() throws {
        if let isolatedPermissionMonitor { removeUIInterruptionMonitor(isolatedPermissionMonitor) }
        isolatedPermissionMonitor = nil
        try super.tearDownWithError()
    }
    #endif

    override func record(_ issue: XCTIssue) {
        guard ProcessInfo.processInfo.environment["LEDGER_ISOLATED_CI_CLIPBOARD"] == "true",
              issue.type == .assertionFailure, Thread.isMainThread,
              failureScreenshotLock.try() else {
            super.record(issue)
            return
        }
        defer { failureScreenshotLock.unlock() }
        // Attach to the issue itself so xcresulttool --only-failures exports
        // the image. Do not capture a developer's desktop during local QA.
        // Only Sendable image bytes cross actor isolation. XCTIssue and this
        // XCTestCase remain in record's original context on newer compilers.
        let imageData = MainActor.assumeIsolated { XCUIScreen.main.screenshot().pngRepresentation }
        let attachment = XCTAttachment(data: imageData, uniformTypeIdentifier: "public.png")
        attachment.name = "Failure screen"
        attachment.lifetime = .keepAlways
        var captured = issue
        captured.attachments.append(attachment)
        super.record(captured)
    }

    func testTransactionImagePinKeepsDetailsAndClearsOnWithdrawal() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-browser", "--ledger-ui-test-transaction-attachments"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["$100.00"].waitForExistence(timeout: 10))
        app.staticTexts["$100.00"].coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photo 1.png")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        let pin = app.buttons["target-transaction-image-pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        let panel = app.descendants(matching: .any)["target-transaction-pinned-panel"].firstMatch
        let unpin = app.buttons["target-transaction-pinned-image-unpin"]
        XCTAssertTrue(unpin.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["target-transaction-images-done"].exists)
        let counter = app.staticTexts["target-transaction-pinned-images-counter"]
        XCTAssertTrue(waitUntil { self.displayedText(counter) == "1 of 2" })
        app.buttons["target-transaction-pinned-images-next"].tap()
        XCTAssertTrue(waitUntil { self.displayedText(counter) == "2 of 2" })
        app.buttons["target-transaction-pinned-images-previous"].tap()
        XCTAssertTrue(waitUntil { self.displayedText(counter) == "1 of 2" })
        XCTAssertTrue(panel.frame.height > 100)
        let detail = app.scrollViews["target-transaction-detail-scroll"].firstMatch
        XCTAssertTrue(detail.exists)
        #if os(iOS)
        XCTAssertLessThan(panel.frame.maxY, detail.frame.maxY)
        let resize = app.descendants(matching: .any)["pinned-image-layout-resize"].firstMatch
        let renderedImage = panel.images["target-item-image-rendered"]
        let initialHeight = renderedImage.frame.height
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: resize.frame.midX, dy: resize.frame.midY))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 70)))
        // The container includes the ignored top safe area; a collapsing
        // navigation title can offset its growth. Measure the rendered image.
        XCTAssertTrue(waitUntil { renderedImage.frame.height > initialHeight + 10 },
            "Resize: initial \(initialHeight), final \(renderedImage.frame.height), value \(String(describing: resize.value)); \(app.debugDescription)")
        #endif
        reveal(photo, in: app, within: detail)
        photo.tap()
        XCTAssertTrue(app.buttons["target-transaction-images-done"].waitForExistence(timeout: 5))
        app.buttons["target-transaction-images-done"].tap()
        XCTAssertTrue(unpin.waitForExistence(timeout: 5), "Gallery close retains the pin")
        unpin.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        let pdf = app.staticTexts["Vendor receipt.pdf"].firstMatch
        reveal(pdf, in: app, within: detail)
        pdf.tap()
        let pinPDF = app.buttons["Pin PDF for reference"]
        XCTAssertTrue(pinPDF.waitForExistence(timeout: 5))
        pinPDF.tap()
        let pinnedPDF = app.descendants(matching: .any)["target-transaction-pinned-pdf"].firstMatch
        XCTAssertTrue(pinnedPDF.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { pinnedPDF.value as? String == "1 PDF pages" })
        XCTAssertFalse(app.buttons["Close PDF"].exists)
        XCTAssertFalse(app.buttons["target-transaction-pinned-images-next"].exists,
            "PDF pages use PDFKit, not photo navigation")
        unpin.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        reveal(photo, in: app, within: detail)
        photo.tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        XCTAssertTrue(unpin.waitForExistence(timeout: 5))
        app.buttons["Withdraw attachment access"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "No pinned pixels after withdrawal")
        XCTAssertTrue(app.staticTexts["Transaction Unavailable"].waitForExistence(timeout: 5))
    }

    #if os(iOS)
    func testCaptureBatchRetainsFailureAfterLaterSuccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-capture-batch"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Add Attachment"].waitForExistence(timeout: 10))
        app.buttons["Add Attachment"].tap()
        XCTAssertTrue(app.buttons["Photo Library"].waitForExistence(timeout: 5))
        app.buttons["Photo Library"].tap()
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(photos.element(boundBy: 1).waitForExistence(timeout: 10), app.debugDescription)
        photos.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        photos.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.navigationBars["Photos"].buttons["Done"].tap()
        let result = app.staticTexts["capture-batch-result"]
        XCTAssertTrue(waitUntil { self.displayedText(result) == "Attempts: 2; accepted: 1" }, app.debugDescription)
        XCTAssertTrue(app.staticTexts["capture-batch-error"].exists)
        XCTAssertEqual(displayedText(app.staticTexts["capture-batch-error"]), "First attachment refused by test callback")
        XCTAssertTrue(app.buttons["Add Attachment"].isEnabled)
    }

    func testTransactionPDFCaptureSurvivesAppRestart() throws {
        try exerciseTransactionPDFCapture(source: "Files")
    }

    func testTransactionDedicatedPDFCaptureSurvivesAppRestart() throws {
        try exerciseTransactionPDFCapture(source: "PDF")
    }

    private func exerciseTransactionPDFCapture(source: String) throws {
        continueAfterFailure = false
        guard let directory = ProcessInfo.processInfo.environment["LEDGER_UI_TEST_FILES_DIRECTORY"],
              directory.contains("/CoreSimulator/Devices/"), directory.hasSuffix("/File Provider Storage") else {
            throw XCTSkip("Requires the explicitly selected disposable simulator's Files directory")
        }
        let fileName = "Ledger receipt \(UUID().uuidString).pdf"
        let file = URL(fileURLWithPath: directory).appendingPathComponent(fileName)
        try syntheticVendorPDF(lines: ["Synthetic Ledger attachment"]).write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-capture", "--capture-fixture-id=\(UUID().uuidString)"]
        app.launch()
        defer { app.terminate() }
        let add = app.buttons["Add Attachment"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), app.debugDescription)
        add.tap()
        let files = app.buttons[source]
        XCTAssertTrue(files.waitForExistence(timeout: 5), app.debugDescription)
        files.tap()
        let browse = app.buttons["Browse"].firstMatch
        if browse.waitForExistence(timeout: 5) { browse.tap() }
        let local = app.staticTexts["On My iPhone"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 5), app.debugDescription)
        local.tap()
        let document = app.cells[file.deletingPathExtension().lastPathComponent + ", pdf"].firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 5), app.debugDescription)
        document.tap()
        let open = app.buttons["Open"].firstMatch
        if open.waitForExistence(timeout: 2) { open.tap() }
        let pending = app.descendants(matching: .any)["target-transaction-attachment-pending"].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(pending.waitForExistence(timeout: 15), app.debugDescription)
        let attachment = app.staticTexts[fileName].firstMatch
        XCTAssertTrue(attachment.exists, app.debugDescription)
        attachment.tap()
        let viewer = app.descendants(matching: .any)["target-transaction-pdf-viewer"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitUntil { viewer.value as? String == "1 PDF pages" }, app.debugDescription)
        app.buttons["Close PDF"].tap()
    }

    func testTransactionDocumentPickerCancellation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-capture", "--capture-fixture-id=\(UUID().uuidString)"]
        app.launch()
        defer { app.terminate() }
        let add = app.buttons["Add Attachment"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), app.debugDescription)
        for source in ["Files", "PDF"] {
            add.tap()
            let option = app.buttons[source]
            XCTAssertTrue(option.waitForExistence(timeout: 5), app.debugDescription)
            option.tap()
            let cancel = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
            cancel.tap()
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(add.isEnabled)
            XCTAssertFalse(app.descendants(matching: .any)["target-transaction-attachment-pending"].exists)
            XCTAssertFalse(app.staticTexts["capture-ui-error"].exists)
        }
    }

    func testExpensePhotoSaveForLaterSurvivesAppRestart() throws {
        try verifyExpensePhotoRecovery(editing: false)
    }

    func testExpenseEditPhotoSaveForLaterSurvivesAppRestart() throws {
        try verifyExpensePhotoRecovery(editing: true)
    }

    private func verifyExpensePhotoRecovery(editing: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-capture", "--ledger-ui-test-expense-capture",
            "--capture-fixture-id=\(UUID().uuidString)"]
        if editing { app.launchArguments.append("--ledger-ui-test-expense-edit-capture") }
        app.launch()
        defer { app.terminate() }
        let create = app.buttons[editing ? "Edit Expense" : "New Expense"]
        XCTAssertTrue(create.waitForExistence(timeout: 15), app.debugDescription)
        create.tap()
        let vendor = app.textFields["Vendor"]
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        if !editing { vendor.tap(); vendor.typeText("Retained photo expense") }
        let form = app.descendants(matching: .any)["target-expense-form"]
        let add = app.buttons["Add receipt"]
        reveal(add, in: app, within: form.scrollViews.firstMatch); add.tap()
        app.buttons["Photo Library"].tap()
        let photo = app.images["PXGGridLayout-Info"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), app.debugDescription)
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let confirm = app.navigationBars["Photos"].buttons["Done"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let remove = app.buttons["Remove selection"]
        XCTAssertTrue(remove.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["Save for later"].tap()
        let unfinished = app.buttons["capture-unfinished-expense"]
        XCTAssertTrue(unfinished.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(unfinished.waitForExistence(timeout: 15), app.debugDescription)
        unfinished.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(vendor.value as? String, editing ? "Original expense" : "Retained photo expense")
        XCTAssertFalse(app.buttons["Retry receipt recovery"].exists)
        if editing {
            app.buttons["Save"].tap()
            let pending = app.staticTexts["capture-expense-edit-pending"]
            XCTAssertTrue(pending.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(unfinished.exists)
            app.terminate(); app.launch()
            XCTAssertTrue(pending.waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertFalse(unfinished.exists)
            return
        }
        app.buttons["Save for later"].tap()
        XCTAssertTrue(unfinished.waitForExistence(timeout: 5))
    }

    func testTransactionPhotoCaptureSurvivesAppRestart() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let fixtureID = UUID().uuidString
        app.launchArguments = ["--ledger-ui-test-transaction-capture", "--capture-fixture-id=\(fixtureID)"]
        app.launch()
        defer { app.terminate() }
        let add = app.buttons["Add Attachment"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), app.debugDescription)
        add.tap()
        let library = app.buttons["Photo Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5), app.debugDescription)
        library.tap()
        // The disposable simulator library is seeded before this focused test.
        // This uses the system Photos picker, not an injected capture callback.
        let photo = app.images["PXGGridLayout-Info"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), app.debugDescription)
        // This system picker reports an invalid AX hit point for its visible
        // image tile. Tap the observed tile center, not a guessed screen offset.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let confirm = app.navigationBars["Photos"].buttons["Done"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        let pending = app.descendants(matching: .any)["target-transaction-attachment-pending"].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 15), app.debugDescription)
        pending.tap()
        XCTAssertTrue(app.buttons["target-transaction-images-done"].waitForExistence(timeout: 5), app.debugDescription)
        let image = app.images["target-item-image-rendered"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["target-transaction-images-done"].tap()
        app.buttons["Simulate rejected upload"].tap()
        let rejected = app.descendants(matching: .any)["target-transaction-attachment-rejected"].firstMatch
        XCTAssertTrue(rejected.waitForExistence(timeout: 5), app.debugDescription)
        let recovery = app.descendants(matching: .any).matching(NSPredicate(format:
            "label CONTAINS %@", "Originals are saved on this device. Open an attachment to share a copy.")).firstMatch
        XCTAssertTrue(recovery.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(rejected.waitForExistence(timeout: 15), app.debugDescription)
        rejected.tap()
        XCTAssertTrue(app.buttons["target-transaction-images-done"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(image.waitForExistence(timeout: 5), app.debugDescription)
        let copy = app.buttons["target-transaction-image-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(waitUntil { copy.value as? String == "Copied" }, app.debugDescription)
        app.buttons["target-transaction-images-done"].tap()
        add.tap()
        let paste = app.buttons["Paste Image"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), app.debugDescription)
        paste.tap()
        let pasted = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Pasted Image.'")).firstMatch
        XCTAssertTrue(pasted.waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(pasted.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["Verify local originals"].tap()
        XCTAssertTrue(app.staticTexts["capture-originals-verified"].waitForExistence(timeout: 10), app.debugDescription)
    }
    #endif

    func testTransactionAttachmentsUseExistingPDFAndImageViewers() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-browser", "--ledger-ui-test-transaction-attachments"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["$100.00"].waitForExistence(timeout: 10))
        app.staticTexts["$100.00"].coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        let pdf = app.staticTexts["Vendor receipt.pdf"].firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        pdf.tap()
        let pdfViewer = app.descendants(matching: .any)["target-transaction-pdf-viewer"]
        XCTAssertTrue(pdfViewer.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { pdfViewer.value as? String == "1 PDF pages" }, app.debugDescription)
        #if os(iOS)
        app.buttons["Share PDF"].tap()
        let activity = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(waitUntil { activity.exists || app.alerts["Attachment"].exists })
        XCTAssertTrue(activity.exists, app.debugDescription)
        let dismissShare = app.otherElements["PopoverDismissRegion"].firstMatch
        XCTAssertTrue(waitUntil { dismissShare.isHittable })
        dismissShare.tap()
        XCTAssertTrue(activity.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share PDF"].waitForExistence(timeout: 5))
        #endif
        app.buttons["Close PDF"].tap()
        let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photo 1.png")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["target-transaction-image-viewer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["target-item-image-rendered"].waitForExistence(timeout: 5))
        #if os(iOS)
        let share = app.buttons["target-transaction-image-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(activity.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitUntil { dismissShare.isHittable })
        dismissShare.tap()
        XCTAssertTrue(activity.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { share.isEnabled })
        XCTAssertTrue(app.buttons["target-transaction-image-save"].exists)
        XCTAssertFalse(app.alerts["Attachment"].exists, "Canceling Share is not an export error")
        #endif
        app.buttons["target-transaction-images-done"].tap()
        app.buttons["target-transaction-attachments-other"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photo 0.png")).firstMatch.waitForExistence(timeout: 5))
        transactionDetailBack(in: app).tap()
        app.buttons["Withdraw access"].tap()
        XCTAssertTrue(app.staticTexts["Transactions are unavailable."].waitForExistence(timeout: 5))
    }

    #if os(macOS)
    func testTransactionImageSavesOriginalThroughMacPicker() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-browser", "--ledger-ui-test-transaction-attachments"]
        app.launch()
        defer { app.terminate() }
        let amount = app.staticTexts["$100.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        reveal(amount, in: app)
        amount.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photo 1.png")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        let save = app.buttons["target-transaction-image-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let panel = app.windows["save-panel"]
        let cancel = panel.buttons["CancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(waitUntil { save.isEnabled })
        XCTAssertFalse(app.alerts["Attachment"].exists)
        save.tap()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-image-save-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Native Save panel grants the app access to this explicitly selected destination.
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = panel.sheets["GoToWindow"].textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 5), app.debugDescription)
        path.typeKey("a", modifierFlags: .command)
        path.typeText(directory.path + "/")
        app.typeKey(.return, modifierFlags: [])
        let confirm = panel.buttons["OKButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let destination = directory.appendingPathComponent("Photo 1.png")
        XCTAssertTrue(waitUntil { FileManager.default.fileExists(atPath: destination.path) })
        let expected = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH1sAAAAASUVORK5CYII="))
        XCTAssertEqual(try Data(contentsOf: destination), expected)
        XCTAssertTrue(app.buttons["target-transaction-images-done"].exists)
        XCTAssertFalse(app.alerts["Attachment"].exists)
    }
    #endif

    func testTransactionBrowserPartialListAndExistingDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-browser"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["target-transactions-partial"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Select all"].exists, "Inventory does not gain Project-only controls")
        XCTAssertTrue(app.staticTexts["1 item"].exists, "Card counts currently linked Items, not historical membership")
        XCTAssertTrue(app.staticTexts["Receipt balanced"].exists)
        XCTAssertTrue(app.staticTexts["$100.00"].exists)
        app.staticTexts["$100.00"].coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        XCTAssertTrue(transactionDetailBack(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Notes"].exists)
        XCTAssertTrue(app.buttons["Details"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format:
            "label CONTAINS %@ OR value CONTAINS %@", "Company card", "Company card")).firstMatch.exists)
        for value in ["Subtotal", "$92.50", "Tax Rate", "8.125%"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format:
                "label == %@ OR value == %@", value, value)).firstMatch.exists,
                "Itemized detail preserves recorded metadata: \(value)")
        }
        app.buttons["Notes"].tap()
        app.buttons["Notes"].tap()
        transactionDetailBack(in: app).tap()
        app.buttons["Filter Transactions"].tap()
        guard app.buttons["Receipt Audit"].waitForExistence(timeout: 5) else {
            XCTFail("Filter hierarchy: \(app.debugDescription)")
            return
        }
        app.buttons["Receipt Audit"].tap()
        XCTAssertTrue(app.buttons["Mismatch"].waitForExistence(timeout: 5))
        app.buttons["Mismatch"].tap()
        app.buttons["Close menu"].tap()
        XCTAssertTrue(app.staticTexts["target-transactions-no-match"].waitForExistence(timeout: 5))
        app.buttons["Filter Transactions"].tap()
        app.buttons["Reset Filters"].tap()
        app.buttons["Close menu"].tap()
        XCTAssertTrue(app.staticTexts["Receipt balanced"].waitForExistence(timeout: 5))
        app.buttons["Search"].tap()
        let search = app.textFields["Search transactions..."]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("no matching vendor")
        XCTAssertTrue(app.staticTexts["target-transactions-no-match"].waitForExistence(timeout: 5))
        app.buttons["Withdraw access"].tap()
        XCTAssertTrue(app.staticTexts["Transactions are unavailable."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["$100.00"].exists)
    }

    func testTransactionBrowserProjectPaymentUsesExistingDetailWithoutVendorAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-browser", "--project-payment"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["target-transactions-partial"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Select all"].exists)
        XCTAssertTrue(app.staticTexts["Client payment"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["1 item"].exists, "Client payment card uses retained Item membership without vendor receipt evidence")
        app.staticTexts["$100.00"].coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        XCTAssertTrue(transactionDetailBack(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Notes"].exists && app.buttons["Details"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["target-vendor-receipt-audit"].exists,
            "Client payment detail must not start vendor receipt audit")
        XCTAssertFalse(app.staticTexts["Subtotal"].exists)
        XCTAssertFalse(app.staticTexts["Tax Rate"].exists)
        transactionDetailBack(in: app).tap()
        app.buttons["Withdraw access"].tap()
        XCTAssertTrue(app.staticTexts["Transactions are unavailable."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["$100.00"].exists)
    }

    func testPaymentItemsKeepFrozenInvoiceAndOpenExistingHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-browser", "--project-payment", "--ledger-ui-test-payment-history"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["$100.00"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2 items"].exists, "Closed link and frozen line for one chair count it once")
        app.staticTexts["$100.00"].coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        XCTAssertTrue(transactionDetailBack(in: app).waitForExistence(timeout: 5))
        let scroll = app.scrollViews["target-transaction-detail-scroll"].firstMatch
        for _ in 0..<9 {
            if app.staticTexts["Invoice Total"].isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Frozen chair at collection"].exists)
        XCTAssertTrue(app.staticTexts["Delivery at collection"].exists)
        XCTAssertTrue(app.staticTexts["$45.00"].exists, "Frozen total stays separate from payment cash")
        XCTAssertFalse(app.descendants(matching: .any)["target-vendor-receipt-audit"].exists)
        let chair = app.staticTexts["Historical chair"].firstMatch
        for _ in 0..<7 {
            if chair.isHittable { break }
            scroll.swipeDown()
        }
        XCTAssertTrue(chair.isHittable)
        chair.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 8, dy: 0)).tap()
        XCTAssertTrue(app.staticTexts["target-item-detail-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Same physical Item"].exists)
        XCTAssertTrue(app.staticTexts["Other Project"].exists)
        let billing = app.descendants(matching: .any)["target-item-invoice-line-frozen-item-line"].firstMatch
        let historyScroll = app.scrollViews["target-item-detail-scroll"].firstMatch
        for _ in 0..<7 {
            if billing.isHittable { break }
            historyScroll.swipeUp()
        }
        XCTAssertTrue(billing.isHittable)
        XCTAssertTrue(billing.label.contains("INV-001"))
        XCTAssertTrue(billing.label.contains("40.00"), "Show Item billing amount, not whole payment")
    }

    func testTransactionRelatedItemsOpenExistingPhysicalHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-browser"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["$100.00"].waitForExistence(timeout: 10))
        app.staticTexts["$100.00"].coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        XCTAssertTrue(transactionDetailBack(in: app).waitForExistence(timeout: 5))
        let scroll = app.scrollViews["target-transaction-detail-scroll"].firstMatch
        func show(_ element: XCUIElement) {
            for _ in 0..<8 {
                if element.exists && element.isHittable { return }
                scroll.swipeUp()
            }
            XCTAssertTrue(element.isHittable, "Related Item must be reachable\n\(app.debugDescription)")
        }
        let linkedPrice = app.staticTexts["$60.00"].firstMatch
        show(linkedPrice)
        linkedPrice.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        XCTAssertTrue(app.staticTexts["target-item-detail-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current lamp"].exists)
        app.buttons["target-item-history-done"].tap()
        // CollapsibleSection's button label includes its Item-count badge.
        let sold = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sold Items")).firstMatch
        show(sold); sold.tap()
        let historicalPrice = app.staticTexts["$40.00"].firstMatch
        show(historicalPrice)
        historicalPrice.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        XCTAssertTrue(app.staticTexts["target-item-detail-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Historical chair"].exists)
        let location = app.staticTexts["target-item-detail-current-location"]
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(location), "Other Project")
        app.buttons["target-item-history-done"].tap()
        XCTAssertTrue(transactionDetailBack(in: app).exists, "Closing Item returns to its Transaction")
    }

    func testTransactionRelatedItemGroupExpandsAndKeepsPhysicalIdentity() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-browser", "--ledger-ui-test-transaction-groups"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["$100.00"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2 items"].exists)
        app.staticTexts["$100.00"].coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        XCTAssertTrue(transactionDetailBack(in: app).waitForExistence(timeout: 5))
        let scroll = app.scrollViews["target-transaction-detail-scroll"].firstMatch
        let group = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Current lamp")).firstMatch
        for _ in 0..<8 {
            if group.exists && group.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(group.isHittable)
        XCTAssertTrue(group.label.contains("$60.00"), "Grouped button includes exact receipt total: \(group.label)")
        XCTAssertTrue(group.label.contains("Multiple spaces"))
        XCTAssertTrue(group.label.contains("Copy display vendor"), "Summary uses the first Item with image evidence")
        XCTAssertFalse(app.staticTexts["1/2"].exists)
        group.tap()
        let second = app.staticTexts["2/2"].firstMatch
        for _ in 0..<5 {
            if second.exists && second.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(second.isHittable)
        second.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        XCTAssertTrue(app.staticTexts["target-item-detail-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current lamp"].exists)
        app.buttons["target-item-history-done"].tap()
        XCTAssertTrue(transactionDetailBack(in: app).exists)
    }

    func testReusedTransactionCardControlsAndLabels() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-card"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["$100.00"].waitForExistence(timeout: 10))
        for label in ["Purchase", "Sep 13, 2026", "Business Inventory", "Furnishings", "Existing card notes"] {
            XCTAssertTrue(app.staticTexts[label].exists, label)
        }
        // The existing ID row combines its caption/value for accessibility.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format:
            "label CONTAINS %@ OR value CONTAINS %@", "transaction-fixture", "transaction-fixture")).firstMatch.exists)
        let state = app.staticTexts["transaction-card-actions"]
        func expectState(_ expected: String) {
            let predicate = NSPredicate(format: "label == %@ OR value == %@", expected, expected)
            expectation(for: predicate, evaluatedWith: state)
            waitForExpectations(timeout: 5)
        }
        app.buttons["Select Fixture vendor"].tap()
        expectState("Selected: yes; opened: 0; copied: no")
        app.buttons["Add bookmark"].tap()
        XCTAssertTrue(app.buttons["Remove bookmark"].exists)
        expectState("Selected: yes; opened: 0; copied: no")
        app.buttons["More options"].tap()
        XCTAssertTrue(app.buttons["Copy ID"].waitForExistence(timeout: 5))
        app.buttons["Copy ID"].tap()
        expectState("Selected: yes; opened: 0; copied: yes")
        // FindableText supports text selection on macOS. Open from the card's
        // trailing padding, not the text-selection surface.
        app.staticTexts["$100.00"].coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0)).tap()
        expectState("Selected: yes; opened: 1; copied: yes")
    }

    func testReusedTransactionAuditPanelExactEvidenceAndApplicability() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-transaction-audit"]
        app.launch()
        defer { app.terminate() }
        let status = app.staticTexts["transaction-audit-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        #if os(macOS)
        XCTAssertEqual(status.value as? String, "Difference: -$0.01")
        #else
        XCTAssertEqual(status.label, "Difference: -$0.01")
        #endif
        XCTAssertTrue(app.staticTexts["Other receipt lines — net: $0.50"].exists)
        XCTAssertTrue(app.staticTexts["Sold items (1): $20.00"].exists)
        app.buttons["Use exact total"].tap()
        XCTAssertTrue(app.staticTexts["Balanced"].waitForExistence(timeout: 5))
        app.buttons["Remove Item price"].tap()
        XCTAssertTrue(app.staticTexts["Receipt details incomplete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Physical Item total: Unknown"].exists)
        XCTAssertTrue(app.staticTexts["Historical chair"].exists)
        for kind in ["General", "Fee", "Itemized"] {
            app.buttons["Edit Category"].tap()
            XCTAssertTrue(app.buttons[kind].waitForExistence(timeout: 5))
            app.buttons[kind].tap()
            app.buttons["Save"].tap()
            XCTAssertTrue(app.staticTexts["Current category: \(kind.lowercased())"].waitForExistence(timeout: 5))
            if kind == "Itemized" { XCTAssertTrue(status.waitForExistence(timeout: 5)) }
            else { XCTAssertFalse(status.exists) }
        }
        app.buttons["Restore Item price"].tap()
        XCTAssertTrue(app.staticTexts["Balanced"].waitForExistence(timeout: 5))
    }

    func testPendingInvoicesShowLocalStatusAndWithdraw() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-pending-invoice", "--ledger-ui-test-expense-withdrawal"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let section = app.buttons["Invoices"].firstMatch
        reveal(section, in: app); section.tap()
        let queued = app.descendants(matching: .any)["target-pending-invoice-pending-queued"].firstMatch
        reveal(queued, in: app)
        XCTAssertTrue(queued.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved on device — pending sync"].exists)
        let rejected = app.descendants(matching: .any)["target-pending-invoice-pending-rejected"].firstMatch
        reveal(rejected, in: app)
        XCTAssertTrue(rejected.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not saved to server — needs review"].exists)
        #if os(iOS)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Live Invoices are unavailable."].waitForExistence(timeout: 5))
        XCTAssertFalse(queued.exists)
        XCTAssertFalse(rejected.exists)
        #endif
    }

    func testCreateInvoiceReusesSelectionAndReviewForm() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-create-invoice", "--ledger-ui-test-invoice-create-retry"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let add = app.buttons["Add Invoices"]
        reveal(add, in: app); add.tap()
        let source = app.buttons["invoice-source-expense-expense-ui-test"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next"].isEnabled)
        let search = app.textFields["Search items, project costs, and charges..."]
        search.tap(); search.typeText("Example budget category")
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); app.buttons["Next"].tap()
        let name = app.textFields["Phase 1 — Furnishings"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Client Invoice")
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Back", "target-active-workspace-back")).firstMatch.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        app.buttons["Create Invoice"].tap()
        XCTAssertTrue(app.staticTexts["Invoice was not accepted on this device. Check the current billable records and try again."].waitForExistence(timeout: 5))
        app.buttons["Create Invoice"].tap()
        XCTAssertTrue(app.staticTexts["Invoice saved on this device (queued)."].waitForExistence(timeout: 5))
        let saved = app.staticTexts["Client Invoice"].firstMatch
        reveal(saved, in: app)
        XCTAssertTrue(saved.exists)
        XCTAssertTrue(app.staticTexts["Saved on device — pending sync"].exists)
    }

    func testEditInvoiceReusesSelectionReviewAndRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-live-invoice",
            "--ledger-ui-test-edit-invoice", "--ledger-ui-test-invoice-create-retry"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let section = app.buttons["Invoices"].firstMatch
        reveal(section, in: app); section.tap()
        let row = app.descendants(matching: .any)["target-invoicing-invoice-live-invoice-ui-test"].firstMatch
        reveal(row, in: app); row.tap()
        let edit = app.buttons["target-edit-invoice"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let source = app.buttons["invoice-source-expense-expense-ui-test"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next"].isEnabled)
        source.tap(); XCTAssertFalse(app.buttons["Next"].isEnabled)
        source.tap(); app.buttons["Next"].tap()
        let name = app.textFields["Phase 1 — Furnishings"]
        XCTAssertEqual(name.value as? String, "Live Invoice")
        name.tap(); name.typeText(" revised")
        app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.staticTexts["Invoice was not accepted on this device. Check the current billable records and try again."].waitForExistence(timeout: 5))
        app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.staticTexts["Invoice edit saved on this device — waiting to sync."].waitForExistence(timeout: 5))
        XCTAssertFalse(edit.isEnabled)
    }

    func testLiveInvoiceUsesExistingListAndReport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-live-invoice", "--ledger-ui-test-expense-withdrawal"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let section = app.buttons["Invoices"].firstMatch
        reveal(section, in: app); section.tap()
        let row = app.descendants(matching: .any)["target-invoicing-invoice-live-invoice-ui-test"].firstMatch
        reveal(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let sent = app.buttons["Sent"].firstMatch
        reveal(sent, in: app); sent.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["target-live-invoice-preview"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Invoice Total"].exists)
        XCTAssertTrue(app.staticTexts["Receipt vendor"].exists)
        XCTAssertTrue(waitUntil { app.buttons["target-invoice-download"].isEnabled })
        #if os(iOS)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Invoice unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Invoice Total"].exists)
        #endif
    }

    func testInvoiceReviewRespondsToSourceChangeAndAccessLoss() throws {
        try checkInvoiceReviewChanges(editing: false)
    }

    func testInvoiceEditRespondsToChangesAndAccessLoss() throws {
        try checkInvoiceReviewChanges(editing: true)
    }

    private func checkInvoiceReviewChanges(editing: Bool) throws {
        #if os(iOS)
        continueAfterFailure = false
        for change in editing ? ["source", "header", "withdrawal"] : ["source", "withdrawal"] {
            let withdrawal = change == "withdrawal"
            let app = XCUIApplication()
            app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-create-invoice",
                withdrawal ? "--ledger-ui-test-expense-withdrawal" : "--ledger-ui-test-invoice-source-change"]
            if editing { app.launchArguments += ["--ledger-ui-test-live-invoice", "--ledger-ui-test-edit-invoice"] }
            if change == "header" { app.launchArguments.append("--ledger-ui-test-invoice-header-change") }
            app.launch(); defer { app.terminate() }
            let project = app.buttons["target-active-project-card-project-ui-test"]
            XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
            let invoicing = app.buttons["target-project-invoicing"]
            reveal(invoicing, in: app); invoicing.tap()
            if editing {
                let section = app.buttons["Invoices"].firstMatch
                reveal(section, in: app); section.tap()
                let row = app.descendants(matching: .any)["target-invoicing-invoice-live-invoice-ui-test"].firstMatch
                reveal(row, in: app); row.tap()
                let edit = app.buttons["target-edit-invoice"]
                XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
            } else {
                let add = app.buttons["Add Invoices"]
                reveal(add, in: app); add.tap()
            }
            let source = app.buttons["invoice-source-expense-expense-ui-test"]
            XCTAssertTrue(source.waitForExistence(timeout: 5))
            if !editing { source.tap() }
            XCTAssertTrue(app.staticTexts["$125.50"].firstMatch.exists, app.debugDescription)
            app.buttons["Next"].tap()
            XCTAssertTrue(app.textFields["Phase 1 — Furnishings"].waitForExistence(timeout: 5))
            XCUIDevice.shared.press(.home); app.activate()
            if withdrawal {
                XCTAssertTrue(app.textFields["Phase 1 — Furnishings"].waitForNonExistence(timeout: 5))
                XCTAssertFalse(app.buttons["Create Invoice"].exists)
                if editing {
                    XCTAssertFalse(app.buttons["Save Changes"].exists)
                    XCTAssertTrue(app.staticTexts["Invoice unavailable"].waitForExistence(timeout: 5))
                } else {
                    let invoices = app.buttons["Invoices"].firstMatch
                    reveal(invoices, in: app); invoices.tap()
                    XCTAssertTrue(app.staticTexts["Live Invoices are unavailable."].waitForExistence(timeout: 5), app.debugDescription)
                }
            } else if change == "header" {
                XCTAssertTrue(app.staticTexts["This Invoice changed. Close this form and reopen it to review the latest version."].waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
            } else {
                XCTAssertTrue(app.staticTexts["Billable records changed. Review your selection before saving."].waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertTrue(app.buttons["Next"].exists)
                XCTAssertTrue(app.staticTexts["$125.51"].firstMatch.exists)
                XCTAssertFalse(app.textFields["Phase 1 — Furnishings"].exists)
            }
        }
        #endif
    }

    func testCollectedInvoicesUseExistingPipelineControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-paid-expense", "--ledger-ui-test-expense-withdrawal"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let section = app.buttons["Invoices"].firstMatch
        #if os(macOS)
        let invoiceScroll = app.sheets.firstMatch.scrollViews.firstMatch
        XCTAssertTrue(invoiceScroll.waitForExistence(timeout: 5))
        reveal(section, in: app, within: invoiceScroll)
        #else
        reveal(section, in: app)
        #endif
        section.tap()
        let row = app.descendants(matching: .any)["target-invoicing-invoice-paid-expense-invoice"].firstMatch
        #if os(macOS)
        // In the CI-sized sheet, expanding Invoices does not bring its lazy
        // rows into the viewport. Scroll the foreground sheet, not the project.
        reveal(row, in: app, fullyInsideScrollView: true, within: invoiceScroll)
        #endif
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["INV-UI-001"].exists)
        let sent = app.buttons["Sent"].firstMatch
        reveal(sent, in: app); sent.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No matching live Invoices in downloaded data."].waitForExistence(timeout: 5))
        app.buttons["Paid"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["Invoice Total"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Design studio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Showing saved business profile."].exists)
        XCTAssertTrue(app.staticTexts["INV-UI-001"].exists)
        let notes = app.textViews.matching(NSPredicate(format: "value == %@ OR label == %@", "Invoice notes", "Invoice notes")).firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        #if os(iOS)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Invoice unavailable"].waitForExistence(timeout: 5), "Withdrawn financial data cannot remain in the open preview")
        XCTAssertFalse(app.staticTexts["Invoice Total"].exists)
        XCTAssertFalse(app.buttons["target-invoice-download"].isEnabled)
        #endif
    }

    func testCollectedInvoiceDownloadCancellation() throws {
        try exerciseCollectedInvoiceDownload(save: false)
    }
    func testLiveInvoiceDownloadCancellation() throws {
        try exerciseCollectedInvoiceDownload(save: false, live: true)
    }

    func testCollectedInvoiceDownloadSave() throws {
        try exerciseCollectedInvoiceDownload(save: true)
    }

    func testLiveInvoiceDownloadSave() throws {
        try exerciseCollectedInvoiceDownload(save: true, live: true)
    }

    #if os(macOS)
    func testCollectedInvoiceSaveRevalidationFailureAndRetry() throws {
        try exerciseCollectedInvoiceDownload(save: true, retry: true)
    }
    #endif

    func testFeeCreationUsesExistingFormAndShowsPendingResult() throws {
        try exerciseFeeCreation(retry: false)
    }

    func testFeeCategorySelectionAndExactRetry() throws {
        try exerciseFeeCreation(retry: true)
    }

    func testFeeGroupShowsConfiguredTotalAndCreatesInstallment() throws {
        try exerciseFeeCreation(retry: false, fromGroup: true)
    }

    func testFeeCreationClosesOnFinancialAccessLoss() throws {
        #if os(iOS)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-create-fee",
                               "--ledger-ui-test-expense-withdrawal"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let add = app.buttons["Add Fees"]
        reveal(add, in: app); add.tap()
        let label = app.textFields["Design fee 1 of 3"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap(); label.typeText("Unsaved private installment")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(label.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add Installment"].exists)
        XCTAssertFalse(app.buttons["Add Fees"].exists)
        XCTAssertFalse(app.staticTexts["Unsaved private installment"].exists)
        #endif
    }

    private func exerciseFeeCreation(retry: Bool, fromGroup: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-create-fee"]
        if retry { app.launchArguments.append("--ledger-ui-test-fee-retry") }
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        if fromGroup {
            let fees = app.buttons.matching(identifier: "Fees").element(boundBy: 1)
            reveal(fees, in: app); fees.tap()
            let group = app.buttons.containing(.staticText, identifier: "Design Fee").firstMatch
            XCTAssertTrue(group.waitForExistence(timeout: 5)); group.tap()
            XCTAssertTrue(app.staticTexts["Total $300.00"].exists)
            let add = app.buttons["Add Installment"]
            reveal(add, in: app); add.tap()
        } else {
            let add = app.buttons["Add Fees"]
            reveal(add, in: app); add.tap()
        }
        if retry {
            let retainer = app.buttons["Retainer"]
            XCTAssertTrue(retainer.waitForExistence(timeout: 5)); retainer.tap()
        }
        // The modal precedes the group's same-named background button in the hierarchy.
        let save = app.buttons["Add Installment"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertFalse(save.isEnabled)
        let label = app.textFields["Design fee 1 of 3"]
        label.tap(); label.typeText("First design installment")
        let amount = app.textFields["$2,500"]
        amount.tap(); amount.typeText("100")
        XCTAssertTrue(save.isEnabled); save.tap()
        if retry {
            XCTAssertTrue(app.staticTexts["Installment exceeds the fee total or could not be saved."].waitForExistence(timeout: 5))
            #if os(iOS)
            XCUIDevice.shared.press(.home); app.activate()
            #endif
            XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        }
        XCTAssertTrue(app.staticTexts["First design installment"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved on device — pending sync"].firstMatch.exists)
    }

    func testFeesBrowseUsesFrozenInvoiceRows() throws {
        try exerciseFeeBrowsing(archived: false)
    }

    func testArchivedFeesRemainVisibleWithoutCreation() throws {
        try exerciseFeeBrowsing(archived: true)
    }

    func testFeeSearchAndStatusPreserveWholeCategoryTotals() throws {
        try exerciseFeeBrowsing(archived: false, checkFilters: true)
    }

    private func exerciseFeeBrowsing(archived: Bool, checkFilters: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-paid-expense", "--ledger-ui-test-long-invoice"]
        if archived { app.launchArguments.append("--ledger-ui-test-archived-fees") }
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        // The first Fees button is the source filter; the second opens the section.
        let fees = app.buttons.matching(identifier: "Fees").element(boundBy: 1)
        reveal(fees, in: app); fees.tap()
        let group = app.buttons.containing(.staticText, identifier: "Design Fee").firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5)); group.tap()
        XCTAssertTrue(app.staticTexts["Invoice row 000 <original>"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Paid"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Canonical Fee browsing is not connected yet."].exists)
        if archived { XCTAssertFalse(app.buttons["Add Fees"].exists) }
        if checkFilters {
            let total = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Total ")).firstMatch.label
            let search = app.textFields["Search receivables..."]
            search.tap(); search.typeText("Invoice row 000")
            XCTAssertTrue(app.staticTexts["Invoice row 000 <original>"].firstMatch.exists)
            XCTAssertFalse(app.staticTexts["Invoice row 001 <original>"].exists)
            XCTAssertTrue(app.staticTexts[total].exists, "Filtering must not shrink the group total")
            app.buttons["Filter receivables"].tap()
            XCTAssertTrue(app.buttons["Paid"].waitForExistence(timeout: 5)); app.buttons["Paid"].tap()
            app.buttons["Close menu"].tap()
            XCTAssertTrue(app.staticTexts[total].exists)
            app.buttons["Filter receivables"].tap()
            app.buttons["Available"].tap(); app.buttons["Close menu"].tap()
            XCTAssertTrue(app.staticTexts["No matching Fees in downloaded data."].waitForExistence(timeout: 5))
            app.buttons["Filter receivables"].tap(); app.buttons["Clear"].tap(); app.buttons["Close menu"].tap()
            XCTAssertTrue(app.staticTexts[total].waitForExistence(timeout: 5))
        }
    }

    private func exerciseCollectedInvoiceDownload(save: Bool, retry: Bool = false, live: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", live ? "--ledger-ui-test-live-invoice" : "--ledger-ui-test-paid-expense"]
        if save && !live { app.launchArguments.append("--ledger-ui-test-long-invoice") }
        if retry { app.launchArguments.append("--ledger-ui-test-invoice-export-retry") }
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let section = app.buttons["Invoices"].firstMatch
        #if os(macOS)
        let invoiceScroll = app.sheets.firstMatch.scrollViews.firstMatch
        XCTAssertTrue(invoiceScroll.waitForExistence(timeout: 5))
        reveal(section, in: app, within: invoiceScroll)
        #else
        reveal(section, in: app)
        #endif
        section.tap()
        let row = app.descendants(matching: .any)[live ? "target-invoicing-invoice-live-invoice-ui-test" : "target-invoicing-invoice-paid-expense-invoice"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let download = app.buttons["target-invoice-download"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Invoice Total"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Net Amount Due"].exists)
        XCTAssertTrue(app.staticTexts["Shipping"].firstMatch.waitForExistence(timeout: 5),
            "Invoice lines should use the downloaded category name")
        let paymentText = live ? "Not collected." : "Collected by Purchase paid-expense-payment"
        let paymentEvidence = app.descendants(matching: .any)["invoice-report-provenance"].firstMatch
        XCTAssertTrue(paymentEvidence.waitForExistence(timeout: 5),
            "The Invoice must retain its actual collection Purchase connection")
        XCTAssertTrue(paymentEvidence.label.contains(paymentText) ||
            (paymentEvidence.value as? String)?.contains(paymentText) == true)
        XCTAssertTrue(waitUntil { download.isEnabled }); download.tap()
        if save {
            #if os(macOS)
            for attempt in 0..<(retry ? 2 : 1) {
            let panel = app.windows["save-panel"]
            let name = panel.textFields["saveAsNameTextField"]
            XCTAssertTrue(name.waitForExistence(timeout: 15))
            let fileName = live ? "invoice-UI Test Project" : "invoice-INV-UI-001"
            XCTAssertTrue((name.value as? String)?.hasPrefix(fileName) == true)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-invoice-save-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            app.typeKey("g", modifierFlags: [.command, .shift])
            let path = panel.sheets["GoToWindow"].textFields["PathTextField"]
            XCTAssertTrue(path.waitForExistence(timeout: 5))
            path.typeKey("a", modifierFlags: [.command])
            path.typeText(directory.path + "/")
            app.typeKey(.return, modifierFlags: [])
            panel.buttons["OKButton"].tap()
            let destination = directory.appendingPathComponent(fileName + ".pdf")
            if retry && attempt == 0 {
                let failure = app.sheets["alert"]
                XCTAssertTrue(failure.waitForExistence(timeout: 5))
                XCTAssertTrue(failure.staticTexts["Invoice download failed"].exists)
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path),
                    "Rejected save-time authorization must not write the destination")
                failure.buttons["action-button-1"].tap()
                XCTAssertTrue(waitUntil { download.isEnabled })
                download.tap()
                continue
            }
            XCTAssertTrue(waitUntil { FileManager.default.fileExists(atPath: destination.path) })
            let document = try XCTUnwrap(PDFDocument(url: destination))
            let savedPDF = XCTAttachment(contentsOfFile: destination)
            savedPDF.name = "Invoice saved PDF"
            savedPDF.lifetime = .keepAlways
            add(savedPDF)
            let text = try XCTUnwrap(document.string).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            XCTAssertTrue(text.contains("Invoice Total") && !text.contains("Net Amount Due"))
            if live {
                XCTAssertGreaterThanOrEqual(document.pageCount, 1)
                // The shared report stylesheet renders category table headings uppercase.
                for expected in ["Live Invoice", "Receipt vendor", "SHIPPING", "125.50", "Sent outside Ledger", "live-invoice-ui-test", "not collected"] {
                    XCTAssertTrue(text.contains(expected), "Missing live Invoice content: \(expected)")
                }
                XCTAssertFalse(text.contains("paid-expense-payment"))
            } else {
            XCTAssertGreaterThan(document.pageCount, 1)
            for index in 0..<80 {
                XCTAssertTrue(text.contains(String(format: "Invoice row %03d", index)))
            }
            XCTAssertTrue(text.contains("90,071,992,547,615.22"))
            XCTAssertTrue(text.contains("Invoice Total") && !text.contains("Net Amount Due"))
            XCTAssertTrue(text.contains("paid-expense-payment"))
            XCTAssertTrue(text.contains("invoice-ui-test-v1"))
            XCTAssertTrue(text.contains("Last completed sync (UTC milliseconds): 1000"))
            XCTAssertTrue(text.contains("Report read (UTC milliseconds):"))
            XCTAssertTrue(text.contains("Accounting: collected-invoice-v1"))
            }
            }
            #else
            let saveButton = app.buttons["Save"].firstMatch
            XCTAssertTrue(saveButton.waitForExistence(timeout: 15), app.debugDescription)
            saveButton.tap()
            #endif
        } else {
            #if os(iOS)
            let picker = app.otherElements["Browse View (Picker)"].firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 15), app.debugDescription)
            // Files exposes the More button as an extra "Cancel" element on
            // this OS. Dismiss the actual native sheet from its top edge.
            let top = picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            top.press(forDuration: 0.1, thenDragTo: picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
            #else
            let cancel = app.windows["save-panel"].buttons["CancelButton"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 15), app.debugDescription)
            cancel.tap()
            #endif
        }
        XCTAssertTrue(waitUntil { download.isEnabled }, app.debugDescription)
        #if os(macOS)
        XCTAssertFalse(app.sheets["alert"].exists)
        #else
        XCTAssertFalse(app.alerts["Invoice download failed"].exists)
        #endif
    }

    func testExpenseEditingReusesFormAndKeepsPendingSeparate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let expense = app.buttons["target-invoicing-expense-expense-ui-test"]
        reveal(expense, in: app); XCTAssertTrue(expense.waitForExistence(timeout: 5)); expense.tap()
        let edit = app.buttons["target-expense-edit"]
        reveal(edit, in: app); XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let vendor = app.textFields["Vendor"]
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        XCTAssertEqual(vendor.value as? String, "Receipt vendor")
        vendor.tap(); vendor.typeText(" updated")
        XCTAssertEqual(vendor.value as? String, "Receipt vendor updated")
        XCTAssertEqual(app.textFields["0.00"].value as? String, "125.50")
        app.buttons["Save"].tap()
        let pending = app.staticTexts["Edit saved on this device — waiting to sync"]
        reveal(pending, in: app); XCTAssertTrue(pending.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Receipt vendor updated"].exists)
        XCTAssertTrue(app.staticTexts["Receipt vendor"].exists)
        XCTAssertFalse(app.buttons["target-expense-edit"].exists)
    }

    func testCollectedExpenseCannotOpenEditForm() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-paid-expense", "--ledger-ui-test-paid-expense-saved-edit"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let expense = app.buttons["target-invoicing-expense-expense-ui-test"]
        reveal(expense, in: app); XCTAssertTrue(expense.waitForExistence(timeout: 5)); expense.tap()
        XCTAssertTrue(app.staticTexts["Receipt vendor"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["target-expense-edit"].exists)
        let retained = app.staticTexts.matching(NSPredicate(format: "label == %@",
            "This Expense was collected after your edit was saved. Your saved details and receipt files are retained; they have not changed the collected Invoice.")).firstMatch
        reveal(retained, in: app)
        XCTAssertTrue(retained.exists)
    }

    func testPaidExpenseUsesExistingInvoicingStatusFilter() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-paid-expense"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        XCTAssertTrue(app.buttons["Expenses"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Expenses"].firstMatch.tap()
        #if os(macOS)
        let paidExpense = app.buttons["target-invoicing-expense-expense-ui-test"]
        XCTAssertTrue(waitUntil { paidExpense.label.contains(", Paid,") })
        XCTAssertFalse(paidExpense.label.contains("Invoice status unavailable"))
        #else
        XCTAssertTrue(app.staticTexts["Paid"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Invoice status unavailable"].exists)
        #endif
        app.buttons["Filter receivables"].tap()
        XCTAssertTrue(app.buttons["Paid"].waitForExistence(timeout: 5)); app.buttons["Paid"].tap()
        app.buttons["Close menu"].tap()
        XCTAssertTrue(app.buttons["target-invoicing-expense-expense-ui-test"].waitForExistence(timeout: 5))
        #if os(macOS)
        XCTAssertTrue(paidExpense.label.contains(", Paid,"))
        #else
        XCTAssertTrue(app.staticTexts["Paid"].exists)
        #endif
    }

    func testExpenseInvoiceStatusFilters() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-expense-statuses", "--ledger-ui-test-item-invoice-statuses"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app)
        XCTAssertTrue(invoicing.waitForExistence(timeout: 5)); invoicing.tap()
        app.buttons["Expenses"].firstMatch.tap()
        for status in ["Available", "Created", "Sent"] {
            app.buttons["Filter receivables"].tap()
            let label = status == "Created" ? "On Created Invoice" : status
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5))
            app.buttons[label].tap()
            app.buttons["Close menu"].tap()
            for candidate in ["available", "created", "sent"] {
                let row = app.buttons["target-invoicing-expense-expense-\(candidate)"]
                if candidate == status.lowercased() {
                    XCTAssertTrue(row.waitForExistence(timeout: 5))
                } else {
                    XCTAssertFalse(row.exists)
                }
            }
        }
        app.buttons["Items"].firstMatch.tap()
        for status in ["Available", "Created", "Sent"] {
            app.buttons["Filter receivables"].tap()
            app.buttons[status == "Created" ? "On Created Invoice" : status].tap()
            app.buttons["Close menu"].tap()
            for candidate in ["Available", "Created", "Sent"] {
                let title = app.staticTexts["\(candidate) chair"]
                if candidate == status { XCTAssertTrue(title.waitForExistence(timeout: 5)) }
                else { XCTAssertFalse(title.exists) }
            }
        }
    }

    func testInvoicingReusesSourceAndSearchControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app)
        XCTAssertTrue(invoicing.waitForExistence(timeout: 5))
        invoicing.tap()
        #if os(macOS)
        let vendor = app.buttons["target-invoicing-expense-expense-ui-test"]
        let expenseRow = app.buttons["target-invoicing-expense-expense-ui-test"]
        let invoicingScroll = app.sheets.firstMatch.scrollViews.firstMatch
        XCTAssertTrue(invoicingScroll.waitForExistence(timeout: 5))
        reveal(expenseRow, in: app, fullyInsideScrollView: true, within: invoicingScroll)
        XCTAssertTrue(expenseRow.label.contains("Receipt vendor"))
        XCTAssertTrue(expenseRow.label.contains("Invoice status unavailable"))
        #else
        let vendor = app.staticTexts["Receipt vendor"]
        XCTAssertTrue(app.staticTexts["Invoice status unavailable"].exists)
        #endif
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        app.buttons["target-invoicing-expense-expense-ui-test"].tap()
        XCTAssertTrue(app.staticTexts["Shipping"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Delivery"].exists)
        XCTAssertTrue(app.staticTexts["No receipts attached."].exists)
        app.navigationBars.buttons["Invoicing"].tap()
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        let search = app.textFields["Search receivables..."]
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("no matching vendor")
        XCTAssertTrue(app.staticTexts["No matching Expenses in downloaded data."].waitForExistence(timeout: 5))
        XCTAssertFalse(vendor.exists)
        app.buttons["Items"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No matching Item charges in downloaded data."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No matching Expenses in downloaded data."].exists)
        app.buttons["Filter receivables"].tap()
        XCTAssertTrue(app.buttons["Paid"].waitForExistence(timeout: 5))
        app.buttons["Paid"].tap()
        app.buttons["Close menu"].tap()
        app.buttons["Expenses"].firstMatch.tap()
        let unavailable = app.staticTexts["Some Expense Invoice statuses are unavailable; only confirmed matching Expenses are shown."]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        app.buttons["Filter receivables"].tap()
        app.buttons["Clear"].tap()
        XCTAssertFalse(app.buttons["Clear"].exists)
        app.buttons["Close menu"].tap()
        XCTAssertTrue(app.staticTexts["No matching Expenses in downloaded data."].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label == %@", "Expenses")).element(boundBy: 1).tap()
        XCTAssertFalse(app.staticTexts["No matching Expenses in downloaded data."].exists)
        app.buttons["target-invoicing-close"].tap()
        XCTAssertTrue(invoicing.waitForExistence(timeout: 5))
    }

    #if os(iOS)
    func testOpenExpenseEditWithdrawsWithFinancialAccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-expense-withdrawal"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let expense = app.buttons["target-invoicing-expense-expense-ui-test"]
        reveal(expense, in: app); XCTAssertTrue(expense.waitForExistence(timeout: 5)); expense.tap()
        let edit = app.buttons["target-expense-edit"]
        reveal(edit, in: app); XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let vendor = app.textFields["Vendor"]
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        XCTAssertEqual(vendor.value as? String, "Receipt vendor")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(vendor.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["target-expense-edit"].exists)
        XCTAssertFalse(app.staticTexts["Receipt vendor"].exists)
    }

    func testOpenExpenseFormWithdrawsWithFinancialAccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-unfinished-expense",
            "--ledger-ui-test-expense-withdrawal"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let unfinished = app.buttons["target-unfinished-expense-unfinished-expense"]
        XCTAssertTrue(unfinished.waitForExistence(timeout: 5))
        reveal(unfinished, in: app, fullyInsideScrollView: true,
            within: app.scrollViews.containing(.button, identifier: "target-unfinished-expense-unfinished-expense").firstMatch)
        unfinished.tap()
        let vendor = app.textFields["Vendor"]
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        XCTAssertEqual(vendor.value as? String, "Saved unfinished vendor")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(vendor.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Expense access is unavailable. Previously saved work remains on this device."].waitForExistence(timeout: 5))
        XCTAssertFalse(unfinished.exists)
        XCTAssertFalse(app.buttons["Add Expenses"].exists)
        XCTAssertFalse(app.buttons["Save for later"].exists)
    }

    func testUnfinishedReceiptFailureRetainsEntryAndOffersRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-unfinished-expense", "--ledger-ui-test-unfinished-receipt-failure"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let unfinished = app.buttons["target-unfinished-expense-unfinished-expense"]
        XCTAssertTrue(unfinished.waitForExistence(timeout: 5)); unfinished.tap()
        let retry = app.buttons["Retry receipt recovery"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        XCTAssertNotEqual(app.textFields["Vendor"].value as? String, "Saved unfinished vendor")
        let form = app.descendants(matching: .any)["target-expense-form"]
        reveal(retry, in: app, within: form.scrollViews.firstMatch); retry.tap()
        XCTAssertTrue(app.staticTexts["The receipt is still unavailable. Its saved reference is retained; no Expense was submitted."].waitForExistence(timeout: 5))
        app.buttons["Save for later"].tap()
        XCTAssertTrue(unfinished.waitForExistence(timeout: 5))
    }

    func testUnfinishedExpenseReopensExistingForm() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-unfinished-expense"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let unfinished = app.buttons["target-unfinished-expense-unfinished-expense"]
        XCTAssertTrue(unfinished.waitForExistence(timeout: 5)); unfinished.tap()
        let vendor = app.textFields["Vendor"]
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        XCTAssertEqual(vendor.value as? String, "Saved unfinished vendor")
        XCTAssertEqual(app.textFields["0.00"].value as? String, "125.50")
        let retain = app.buttons["Save for later"]
        XCTAssertTrue(retain.waitForExistence(timeout: 5)); XCTAssertTrue(retain.isEnabled); retain.tap()
        XCTAssertTrue(unfinished.waitForExistence(timeout: 5))
    }

    func testPendingExpensesAreDistinctFromDownloadedExpenses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-pending-expenses", "--ledger-ui-test-expense-withdrawal"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        XCTAssertTrue(app.staticTexts["Saved on device — pending sync"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not saved to server — needs review"].exists)
        XCTAssertTrue(app.buttons["target-invoicing-expense-expense-ui-test"].exists)
        app.buttons["target-pending-expense-pending-rejected"].tap()
        XCTAssertTrue(app.staticTexts["Retained draft"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This Expense was rejected. Your original details are retained below. Closing this view does not discard or resolve it."].exists)
        XCTAssertFalse(app.buttons["Retry Save"].exists)
        app.buttons["Receipt 1"].tap()
        let viewer = app.descendants(matching: .any)["target-expense-pdf-viewer"]
        XCTAssertTrue(waitUntil { viewer.value as? String == "1 PDF pages" })
        app.buttons["Close PDF"].tap()
        XCTAssertTrue(app.staticTexts["Retained draft"].waitForExistence(timeout: 5))
        app.buttons["Receipt 2"].tap()
        XCTAssertTrue(app.images["target-item-image-rendered"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.images["target-item-image-rendered"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Expense details are unavailable."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Retained draft"].exists)
    }

    func testExpenseExportUsesNativeShareAndCancelsCleanly() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let expense = app.buttons["target-invoicing-expense-expense-ui-test"]
        XCTAssertTrue(expense.waitForExistence(timeout: 5)); expense.tap()
        let export = app.buttons["target-expense-export"]
        reveal(export, in: app)
        XCTAssertTrue(export.waitForExistence(timeout: 5)); export.tap()
        let activity = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        let dismissShare = app.otherElements["PopoverDismissRegion"].firstMatch
        XCTAssertTrue(waitUntil { dismissShare.isHittable }); dismissShare.tap()
        XCTAssertTrue(activity.waitForNonExistence(timeout: 5))
        XCTAssertTrue(export.waitForExistence(timeout: 5)); XCTAssertTrue(export.isEnabled)
        XCTAssertFalse(app.alerts["Export failed"].exists)
    }

    func testExpenseWithoutReceiptPersistsCurrentFormBeforeSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-expense-recovery-save"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let add = app.buttons["Add Expenses"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let vendor = app.textFields["Vendor"]
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        vendor.tap(); vendor.typeText("Canceled vendor")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Expense saved on this device (queued). It appears here after sync."].exists)
        add.tap()
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        XCTAssertNotEqual(vendor.value as? String, "Canceled vendor")
        XCTAssertTrue(vendor.waitForExistence(timeout: 5)); vendor.tap(); vendor.typeText("Current vendor")
        let amount = app.textFields["0.00"]
        amount.tap(); amount.typeText("125.50")
        app.buttons["target-expense-category"].tap()
        app.buttons["Shipping"].firstMatch.tap()
        XCTAssertEqual(vendor.value as? String, "Current vendor")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Expense saved on this device (queued). It appears here after sync."].waitForExistence(timeout: 5))
    }

    #endif

    func testExpenseCreationUsesExistingFormAndRejectsInvalidAmount() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-expense-lines"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let add = app.buttons["Add Expenses"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let vendor = app.textFields["Vendor"]
        XCTAssertTrue(vendor.waitForExistence(timeout: 5)); vendor.tap(); vendor.typeText("Shipping vendor")
        XCTAssertEqual(vendor.value as? String, "Shipping vendor")
        let amount = app.textFields["0.00"]
        amount.tap(); amount.typeText("0")
        XCTAssertEqual(amount.value as? String, "0")
        #if os(iOS)
        let form = app.descendants(matching: .any)["target-expense-form"]
        let draftIdentity = form.value as? String
        app.buttons["target-expense-category"].tap()
        app.buttons["Shipping"].firstMatch.tap()
        XCTAssertEqual(form.value as? String, draftIdentity, "Category selection must preserve the same form instance")
        let formScroll = form.scrollViews.firstMatch
        #else
        app.popUpButtons["target-expense-category"].tap()
        app.menuItems["Shipping"].tap()
        // The workspace and Invoicing sheet also expose scroll views. Use the
        // Expense form's own scroll view, identified by its Vendor field.
        let formScroll = app.scrollViews.containing(.textField, identifier: "Vendor").firstMatch
        #endif
        XCTAssertEqual(vendor.value as? String, "Shipping vendor")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Enter a positive amount with no more than two decimal places."].waitForExistence(timeout: 5))
        amount.tap(); amount.typeText("125.50")
        let addLine = app.buttons["Add receipt line"]
        reveal(addLine, in: app, fullyInsideScrollView: true, within: formScroll); addLine.tap()
        let wording = app.textFields["Receipt wording"]
        // Adding a row must succeed before trying to scroll to its fields.
        XCTAssertTrue(wording.waitForExistence(timeout: 2), "Add receipt line did not create a row")
        reveal(wording, in: app, within: formScroll); wording.tap(); wording.typeText("Delivery")
        let lineAmount = app.textFields["Line amount"]
        reveal(lineAmount, in: app, within: formScroll); lineAmount.tap(); lineAmount.typeText("10.25")
        #if os(iOS)
        lineAmount.typeText("\n")
        #endif
        let effect = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'target-expense-line-effect-'")).firstMatch
        reveal(effect, in: app, fullyInsideScrollView: true, within: formScroll)
        let decrease = effect.descendants(matching: .any).matching(NSPredicate(format: "label == 'Decrease'")).firstMatch
        XCTAssertTrue(decrease.exists)
        decrease.tap()
        let quantity = app.textFields["Quantity"]
        reveal(quantity, in: app, fullyInsideScrollView: true, within: formScroll); quantity.tap(); quantity.typeText("-2")
        #if os(iOS)
        quantity.typeText("\n")
        #endif
        reveal(addLine, in: app, fullyInsideScrollView: true, within: formScroll); addLine.tap()
        let removeExtra = app.buttons.matching(identifier: "Remove line").element(boundBy: 1)
        reveal(removeExtra, in: app, fullyInsideScrollView: true, within: formScroll); removeExtra.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "Remove line").count, 1)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Expense saved on this device (queued). It appears here after sync."].waitForExistence(timeout: 5))
    }

    func testUnfinishedExpenseRequiresAvailableBudgetCategory() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-unfinished-expense",
            "--ledger-ui-test-expense-missing-category"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let unfinished = app.buttons["target-unfinished-expense-unfinished-expense"]
        XCTAssertTrue(unfinished.waitForExistence(timeout: 5)); unfinished.tap()
        let restoredVendor = app.textFields.matching(NSPredicate(format: "value == %@", "Saved unfinished vendor")).firstMatch
        XCTAssertTrue(restoredVendor.waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Choose an available budget category before saving."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Expense saved on this device (queued). It appears here after sync."].exists)
        #if os(macOS)
        app.popUpButtons["target-expense-category"].tap()
        app.menuItems["Shipping"].tap()
        #else
        app.buttons["target-expense-category"].tap()
        app.buttons["Shipping"].firstMatch.tap()
        #endif
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Expense saved on this device (queued). It appears here after sync."].waitForExistence(timeout: 5))
    }

    #if os(iOS)
    func testExpenseReceiptsReuseViewersAndWithdrawAccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-expense-receipts", "--ledger-ui-test-expense-withdrawal"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let invoicing = app.buttons["target-project-invoicing"]
        reveal(invoicing, in: app); invoicing.tap()
        let expense = app.buttons["target-invoicing-expense-expense-ui-test"]
        XCTAssertTrue(expense.waitForExistence(timeout: 5)); expense.tap()
        let pdf = app.staticTexts["Receipt 1"].firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 5)); pdf.tap()
        let viewer = app.descendants(matching: .any)["target-expense-pdf-viewer"]
        XCTAssertTrue(waitUntil { viewer.value as? String == "1 PDF pages" })
        app.buttons["Close PDF"].tap()
        let image = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Receipt image 2")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5)); image.tap()
        XCTAssertTrue(app.images["target-item-image-rendered"].waitForExistence(timeout: 5))
        app.buttons["target-expense-gallery-images-done"].tap()
        XCTAssertTrue(pdf.waitForExistence(timeout: 5)); pdf.tap()
        XCTAssertTrue(waitUntil { viewer.value as? String == "1 PDF pages" })
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(viewer.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Expense details are unavailable."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Shipping"].exists)
    }
    #endif

    func testClientSummaryPhysicalPreviewAndIncompleteShare() throws {
        continueAfterFailure = false
        for incomplete in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
            if incomplete { app.launchArguments.append("--ledger-ui-test-report-incomplete") }
            app.launch()
            defer { app.terminate() }
            let project = app.buttons["target-active-project-card-project-ui-test"]
            XCTAssertTrue(project.waitForExistence(timeout: 10))
            project.tap()
            let report = app.buttons["target-client-report-open"]
            reveal(report, in: app)
            XCTAssertTrue(report.waitForExistence(timeout: 5))
            report.tap()
            let share = app.buttons["target-client-report-share"]
            XCTAssertTrue(share.waitForExistence(timeout: 5))
            if incomplete {
                XCTAssertTrue(app.staticTexts["target-client-report-incomplete"].waitForExistence(timeout: 5))
                XCTAssertFalse(share.isEnabled)
            } else {
                let item = app.descendants(matching: .any).matching(identifier: "target-client-report-item-report-ui-chair").firstMatch
                XCTAssertTrue(item.waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Client: Report Client"].exists)
                XCTAssertTrue(waitUntil { share.isEnabled })
                #if os(iOS)
                share.tap()
                let activity = app.otherElements["ActivityListView"].firstMatch
                let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
                XCTAssertTrue(activity.waitForExistence(timeout: 10))
                XCTAssertTrue(waitUntil { dismiss.isHittable })
                dismiss.tap()
                XCTAssertTrue(activity.waitForNonExistence(timeout: 5))
                XCTAssertTrue(waitUntil { share.isEnabled })
                #endif
            }
            app.buttons["target-client-report-refresh"].tap()
            XCTAssertTrue(share.waitForExistence(timeout: 5))
        }
    }

    func testCategorySettingsCreateEditArchiveRestoreAndCancel() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["target-account-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let categories = app.buttons["target-settings-budget-categories"]
        XCTAssertTrue(categories.waitForExistence(timeout: 5))
        categories.tap()
        XCTAssertTrue(app.buttons["Edit Furnishings"].waitForExistence(timeout: 5))

        app.buttons["Add Category"].tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        func text(_ value: String) -> XCUIElement {
            app.windows.firstMatch.staticTexts
                .matching(NSPredicate(format: "label == %@ OR value == %@", value, value)).firstMatch
        }
        app.buttons["Create"].tap()
        XCTAssertTrue(text("Name is required").waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Furnishings")
        app.buttons["Create"].tap()
        XCTAssertTrue(text("A category with this name already exists").waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Furnishings".count))
        name.typeText("Lighting")
        XCTAssertTrue(app.buttons["General"].exists)
        XCTAssertTrue(app.buttons["Fee"].exists)
        app.buttons["Itemized"].tap()
        #if os(macOS)
        let excluded = app.checkBoxes["category-exclude-overall-budget"]
        #else
        let excluded = app.switches["category-exclude-overall-budget"].firstMatch
        #endif
        excluded.tap()
        app.buttons["Create"].tap()
        let edit = app.buttons["Edit Lighting"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Lighting")
        XCTAssertEqual((excluded.value as? NSNumber)?.intValue ?? Int(excluded.value as? String ?? ""), 1)
        app.buttons["General"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))

        app.buttons["Archive Lighting"].tap()
        #if os(macOS)
        app.sheets.buttons["Archive"].firstMatch.tap()
        #else
        let confirmArchive = app.buttons["Archive"]
        XCTAssertTrue(confirmArchive.waitForExistence(timeout: 5), app.debugDescription)
        confirmArchive.tap()
        #endif
        let restore = app.buttons["Unarchive"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertFalse(edit.exists)
        restore.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(restore.exists)

        #if os(iOS)
        app.buttons["Reorder Lighting"].press(forDuration: 0.8,
            thenDragTo: app.buttons["Reorder Furnishings"])
        #else
        app.activate()
        XCTAssertTrue(waitUntil { app.state == .runningForeground })
        XCTAssertTrue(app.buttons["category-name-Lighting"].isHittable)
        // macOS moves the native List row, not the Edit button inside it.
        // Start in the row inset and drop above the first row's insertion edge.
        let dragStart = app.buttons["category-name-Lighting"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: -8, dy: 0))
        let dragEnd = app.buttons["category-name-Furnishings"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: -8, dy: -6))
        dragStart.press(forDuration: 0.8, thenDragTo: dragEnd)
        #endif
        XCTAssertTrue(waitUntil { edit.frame.minY < app.buttons["Edit Furnishings"].frame.minY },
            "Reorder must change the visible category order")

        app.buttons["Add Category"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Discard this category")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Edit Discard this category"].exists)
    }

    func testDownloadedAccountEntryWithoutOnlineSession() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-offline-entry", "--ledger-ui-test-entry-id=\(UUID().uuidString)"]
        app.launch()
        defer {
            if app.buttons["offline-entry-cleanup"].exists { app.buttons["offline-entry-cleanup"].tap() }
            app.terminate()
        }
        let account = app.buttons["Offline Test Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["offline-entry-selected"].exists, "Even one downloaded Account requires explicit selection")
        let signIn = app.buttons["Sign In"]
        reveal(signIn, in: app, within: app.scrollViews["target-account-entry-scroll"])
        signIn.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        let downloaded = app.buttons["Use Downloaded Accounts"]
        reveal(downloaded, in: app, within: app.scrollViews["target-account-entry-scroll"])
        downloaded.tap()
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        XCTAssertTrue(app.staticTexts["Offline selection verified"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(account.waitForExistence(timeout: 10), "The next process must restore the protected admission")
        XCTAssertFalse(app.staticTexts["offline-entry-selected"].exists)
        account.tap()
        XCTAssertTrue(app.staticTexts["Offline selection verified"].waitForExistence(timeout: 5))
        app.buttons["offline-entry-cleanup"].tap()
        XCTAssertTrue(app.staticTexts["offline-entry-cleaned"].waitForExistence(timeout: 5))
    }

    func testSettingsSignOutPreservesSettingsWhenPendingWorkRefuses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-settings-signout"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["target-account-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let signOut = app.buttons["target-settings-sign-out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        XCTAssertTrue(app.staticTexts["target-settings-sign-out-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(signOut.isEnabled)
        app.buttons["target-account-settings-done"].tap()
        XCTAssertTrue(app.staticTexts["target-ui-signout-called"].waitForExistence(timeout: 5))
        XCTAssertTrue(settings.exists)
    }

    func testLiveOfflineSettingsSignOutReturnsToSignIn() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-offline-entry", "--ledger-ui-test-entry-live-signout",
            "--ledger-ui-test-transaction-capture", "--ledger-ui-test-entry-id=\(UUID().uuidString)"]
        app.launch()
        defer { app.terminate() }
        let account = app.buttons["Offline Test Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        let settings = app.buttons["target-account-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        reveal(settings, in: app, within: app.scrollViews["target-workspace-scroll"])
        settings.tap()
        let signOut = app.buttons["target-settings-sign-out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Sign In"].exists)
        XCTAssertFalse(account.exists)
        XCTAssertFalse(settings.exists)
        XCTAssertFalse(app.buttons["Use Downloaded Accounts"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))
        XCTAssertFalse(account.exists)
        XCTAssertFalse(app.buttons["Use Downloaded Accounts"].exists)
    }

    func testApprovedSignOutRecoveryBeforeOfflineEntryAfterRestart() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-offline-entry", "--ledger-ui-test-entry-live-signout",
            "--ledger-ui-test-entry-approved-recovery", "--ledger-ui-test-transaction-capture",
            "--ledger-ui-test-entry-id=\(UUID().uuidString)"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["offline-entry-interrupted-ready"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Offline Test Account"].exists)
        XCTAssertFalse(app.buttons["Use Downloaded Accounts"].exists)
        XCTAssertFalse(app.buttons["Retry"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Offline Test Account"].exists)
    }

    func testLivePendingWorkCancelAndConfirmedDiscard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-offline-entry", "--ledger-ui-test-entry-live-signout",
            "--ledger-ui-test-transaction-capture", "--ledger-ui-test-entry-id=\(UUID().uuidString)"]
        app.launch()
        defer { app.terminate() }
        let account = app.buttons["Offline Test Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        let name = app.textFields["target-client-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Unsynced logout test\n")
        app.buttons["target-create-client"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Unsynced logout test — queued locally")).firstMatch.waitForExistence(timeout: 10))
        let settings = app.buttons["target-account-settings"]
        reveal(settings, in: app, within: app.scrollViews["target-workspace-scroll"])
        settings.tap()
        let syncSignOut = app.buttons["target-pending-sync-sign-out"]
        reveal(syncSignOut, in: app, within: app.descendants(matching: .any)["target-settings-form"].firstMatch)
        syncSignOut.tap()
        let cancelSignOut = app.buttons["Cancel Sign Out"]
        XCTAssertTrue(cancelSignOut.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sign In"].exists)
        cancelSignOut.tap()
        XCTAssertTrue(waitUntil { syncSignOut.isEnabled })
        let discard = app.buttons["target-pending-discard-sign-out"]
        reveal(discard, in: app, within: app.descendants(matching: .any)["target-settings-form"].firstMatch)
        XCTAssertTrue(discard.isEnabled)
        discard.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 queued operations")).firstMatch.exists)
        app.alerts.buttons["Keep My Work"].tap()
        XCTAssertTrue(discard.exists)
        discard.tap()
        app.alerts.buttons["Discard and Sign Out"].tap()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))
        XCTAssertFalse(account.exists)
    }

    func testSyncFirstUIEndsOnlyAfterFreshSummaryClears() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-sync-signout-completion"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["target-account-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let sync = app.buttons["target-pending-sync-sign-out"]
        reveal(sync, in: app, within: app.descendants(matching: .any)["target-settings-form"].firstMatch)
        XCTAssertTrue(sync.isEnabled)
        sync.tap()
        XCTAssertTrue(app.staticTexts["target-ui-signout-called"].waitForExistence(timeout: 10))
        XCTAssertFalse(settings.exists)
    }

    func testStaleDiscardConfirmationRequiresFreshReview() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-stale-discard"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["target-account-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let discard = app.buttons["target-pending-discard-sign-out"]
        let form = app.descendants(matching: .any)["target-settings-form"].firstMatch
        reveal(discard, in: app, within: form)
        discard.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Discard and Sign Out"].tap()
        XCTAssertTrue(app.staticTexts["target-pending-session-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(discard.isEnabled)
        XCTAssertFalse(app.staticTexts["target-ui-signout-called"].exists)
        app.buttons["target-account-settings-done"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }

    func testLeavingSettingsCancelsSyncFirstWaiting() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-sync-signout-dismiss"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["target-account-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let sync = app.buttons["target-pending-sync-sign-out"]
        reveal(sync, in: app, within: app.descendants(matching: .any)["target-settings-form"].firstMatch)
        sync.tap()
        XCTAssertTrue(app.buttons["Cancel Sign Out"].waitForExistence(timeout: 5))
        app.buttons["target-account-settings-done"].tap()
        let reads = app.staticTexts["target-ui-summary-reads"]
        XCTAssertTrue(reads.waitForExistence(timeout: 5))
        let count = try XCTUnwrap(reads.value as? String)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in reads.value as? String != count }, object: nil)
        changed.isInverted = true
        wait(for: [changed], timeout: 3)
        XCTAssertFalse(app.staticTexts["target-ui-signout-called"].exists)
        XCTAssertTrue(settings.exists)
    }

    func testDownloadedAccountEntryBlocksIncompleteLogoutRecovery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-offline-entry",
            "--ledger-ui-test-entry-incomplete-cleanup", "--ledger-ui-test-entry-id=\(UUID().uuidString)"]
        app.launch()
        defer {
            if app.buttons["offline-entry-cleanup"].exists { app.buttons["offline-entry-cleanup"].tap() }
            app.terminate()
        }
        let message = app.staticTexts["Ledger could not finish the previous sign-out. Retry before opening downloaded Accounts."]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Offline Test Account"].exists)
        app.buttons["Retry"].tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Offline Test Account"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(message.waitForExistence(timeout: 10), "An incomplete cleanup remains locked across restart")
        XCTAssertFalse(app.buttons["Offline Test Account"].exists)
    }

    func testCategoryEditorClosesWhenCategoryAccessIsWithdrawn() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-category-withdraw-on-save"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["target-account-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let categories = app.buttons["target-settings-budget-categories"]
        XCTAssertTrue(categories.waitForExistence(timeout: 5))
        categories.tap()
        let edit = app.buttons["Edit Design Fee"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Design Fee")
        app.buttons["General"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(waitUntil { !app.buttons["Save"].exists }, "Withdrawn category must dismiss its cached editor")
        XCTAssertTrue(app.buttons["Add Category"].waitForExistence(timeout: 5))
        XCTAssertFalse(edit.exists)
        XCTAssertFalse(app.staticTexts["Design Fee"].exists)
        XCTAssertFalse(app.textFields.matching(NSPredicate(format: "value == %@", "Design Fee")).firstMatch.exists)
    }

    func testInlineCategoryCreationPreservesProjectDraft() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-inline-category"]
        app.launch()
        defer { app.terminate() }
        let name = app.textFields["target-project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Keep this Project draft")
        #if os(macOS)
        app.popUpButtons["target-project-existing-client"].tap()
        app.menuItems["UI Test Client"].tap()
        #else
        app.buttons["target-project-existing-client"].tap()
        app.buttons["UI Test Client"].tap()
        #endif
        let next = app.buttons["target-project-next"]
        XCTAssertTrue(waitUntil { next.isEnabled })
        next.tap()
        let add = app.buttons["target-project-add-category"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { add.isEnabled })
        add.tap()
        let categoryName = app.textFields.firstMatch
        XCTAssertTrue(categoryName.waitForExistence(timeout: 5))
        categoryName.tap()
        categoryName.typeText("Inline Lighting")
        app.buttons["Create"].tap()
        func categoryText(_ name: String) -> XCUIElement {
            app.windows.firstMatch.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR value == %@", name, name)).firstMatch
        }
        XCTAssertTrue(categoryText("Inline Lighting").waitForExistence(timeout: 5), app.windows.firstMatch.debugDescription)
        reveal(next, in: app)
        next.tap()
        // Budget entry lists selected categories only: the new category must be
        // selected without losing the original category or submitting a Project.
        XCTAssertTrue(app.textFields["target-project-allocation-category-ui-test"].waitForExistence(timeout: 5), app.windows.firstMatch.debugDescription)
        XCTAssertTrue(categoryText("Inline Lighting").waitForExistence(timeout: 5))
        XCTAssertTrue(categoryText("Furnishings").exists)
        reveal(app.buttons["target-project-secondary-action"], in: app)
        app.buttons["target-project-secondary-action"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5), app.windows.firstMatch.debugDescription)
        reveal(app.buttons["target-project-secondary-action"], in: app)
        app.buttons["target-project-secondary-action"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.windows.firstMatch.debugDescription)
        XCTAssertEqual(name.value as? String, "Keep this Project draft")
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "0")
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
        reveal(report, in: app)
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(name), "Design studio")
        XCTAssertTrue(app.staticTexts["No business logo"].exists)
        let share = app.buttons["target-property-report-share"]
        // Profile and report load independently. Wait for report readiness,
        // then check the actual control; a slow XCUI snapshot must not consume
        // a separate five-second enabled-predicate deadline.
        XCTAssertTrue(app.descendants(matching: .any)["target-property-report-totals"]
            .waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isEnabled, app.debugDescription)
    }

    func testProjectTransactionExportWatchCompletionDisablesExport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-workspace-transactions",
            "--ledger-ui-test-export-watch-finish"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let options = app.buttons["target-project-options"].firstMatch
        reveal(options, in: app, upwards: false, fullyInsideScrollView: true)
        options.tap()
        let openExport = app.buttons["Export Transactions"]
        XCTAssertTrue(openExport.waitForExistence(timeout: 5))
        openExport.tap()
        XCTAssertTrue(app.staticTexts["Project Transactions are unavailable."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["1 transaction will be exported"].exists)
        XCTAssertTrue(app.buttons["Export"].exists)
        XCTAssertFalse(app.buttons["Export"].isEnabled)
    }

    func testProjectTransactionExportScopeFieldsAndShareCancellation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-workspace-transactions"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        func openExport(expectedCount: Int) {
            let options = app.buttons["target-project-options"].firstMatch
            reveal(options, in: app, upwards: false, fullyInsideScrollView: true)
            options.tap()
            let export = app.buttons["Export Transactions"]
            XCTAssertTrue(export.waitForExistence(timeout: 5))
            export.tap()
            let description = "\(expectedCount) transaction\(expectedCount == 1 ? "" : "s") will be exported"
            XCTAssertTrue(app.staticTexts[description].waitForExistence(timeout: 5))
        }
        openExport(expectedCount: 1)
        let source = app.buttons["transaction-export-field-source"]
        XCTAssertEqual(source.value as? String, "Selected")
        app.buttons["Select All"].tap()
        XCTAssertTrue(app.buttons["Reset to Default"].exists)
        app.buttons["Reset to Default"].tap()
        XCTAssertEqual(source.value as? String, "Selected")
        app.buttons["Cancel"].tap()

        let transactions = app.buttons["target-project-transactions"]
        reveal(transactions, in: app)
        transactions.tap()
        XCTAssertTrue(app.staticTexts["Client payment"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Search"].tap()
        let search = app.textFields["Search transactions..."]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("no matching fixture")
        XCTAssertTrue(app.staticTexts["target-transactions-no-match"].waitForExistence(timeout: 5))
        openExport(expectedCount: 0)
        app.buttons["Cancel"].tap()
        let back = app.buttons["target-active-workspace-back"]
        reveal(back, in: app, upwards: false); back.tap()

        // Leaving Transactions restores all-Project semantics, not its no-match set.
        openExport(expectedCount: 1)
        let images = app.buttons["transaction-export-field-receiptImages"]
        let fields = app.scrollViews.containing(.button, identifier: "transaction-export-field-source").firstMatch
        func showField(_ field: XCUIElement) {
            #if os(iOS)
            // Controlled drags avoid overshooting checkboxes in this short sheet.
            for _ in 0..<10 {
                if field.isHittable { break }
                let distance = fields.frame.midY - field.frame.midY
                let limit = fields.frame.height * 0.35
                let center = fields.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                center.press(forDuration: 0.05, thenDragTo: center.withOffset(
                    CGVector(dx: 0, dy: max(-limit, min(limit, distance)))))
            }
            XCTAssertTrue(field.isHittable, app.debugDescription)
            #else
            reveal(field, in: app, fullyInsideScrollView: true, within: fields)
            #endif
        }
        showField(images)
        XCTAssertEqual(images.value as? String, "Not selected")
        images.tap()
        app.buttons["Export"].tap()
        XCTAssertTrue(app.staticTexts["Receipt Images export is not implemented yet. Deselect it to export the other fields."]
            .waitForExistence(timeout: 5))
        showField(images)
        images.tap()
        XCTAssertEqual(images.value as? String, "Not selected")
        let categories = app.buttons["transaction-export-field-itemCategories"]
        showField(categories); categories.tap()
        XCTAssertEqual(categories.value as? String, "Selected")
        // This fixture now supplies current Item categories for its Project
        // payment. Missing attribution remains covered by the value tests.
        app.buttons["Export"].tap()
        #if os(iOS)
        let activity = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        let dismissShare = app.otherElements["PopoverDismissRegion"].firstMatch
        XCTAssertTrue(waitUntil { dismissShare.isHittable })
        dismissShare.tap()
        XCTAssertTrue(activity.waitForNonExistence(timeout: 5))
        #else
        // The native picker first appears as a popover inside Ledger while
        // services load. Cancel that actual presentation without assuming a
        // separate ShareSheetUI process has already launched.
        let share = app.popovers.firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(share.buttons["Copy"].waitForExistence(timeout: 10),
            "Wait for native services to load before keyboard cancellation")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(share.waitForNonExistence(timeout: 5))
        #endif
        XCTAssertTrue(waitUntil { app.buttons["target-project-options"].firstMatch.isEnabled })
        XCTAssertFalse(app.alerts["Export failed"].exists)
        openExport(expectedCount: 1)
        app.buttons["Cancel"].tap()
    }

    func testHostedEntryDownloadsAuthorizedProject() throws {
        let configuration = ProcessInfo.processInfo.environment
        guard configuration["LEDGER_HOSTED_QA_ENTRY"] == "1" else {
            throw XCTSkip("Requires the explicitly authorized hosted Ledger private QA copy")
        }
        let email = try XCTUnwrap(configuration["LEDGER_HOSTED_QA_EMAIL"])
        let password = try XCTUnwrap(configuration["LEDGER_HOSTED_QA_PASSWORD"])
        XCTAssertEqual(email, "upload-owner-4b1e9766-5791-48a9-a7b1-15a541807e64@ledger-tests.invalid")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch() // Real entry and live providers; no fixture arguments or injected admission.
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "targetStaging"))
            .firstMatch.waitForExistence(timeout: 10))
        let emailField = app.textFields["Email"]
        // A cached Account can remain accessible without an online session.
        // This hosted test must sign in, not mistake that offline entry for live sync.
        if !emailField.exists, app.buttons["Sign In"].exists {
            app.buttons["Sign In"].tap()
        }
        if emailField.waitForExistence(timeout: 3) {
            emailField.tap(); emailField.typeText(email)
            app.secureTextFields["Password"].tap()
            app.secureTextFields["Password"].typeText(password)
            let submit = try XCTUnwrap(app.buttons.matching(identifier: "Sign In").allElementsBoundByIndex.last)
            reveal(submit, in: app, within: app.scrollViews["target-account-entry-scroll"])
            submit.tap()
        }
        let account = app.buttons["PRIVATE REAL-DATA COPY — partial import"]
        XCTAssertTrue(account.waitForExistence(timeout: 20))
        let savePassword = app.sheets["Save Password?"]
        if savePassword.waitForExistence(timeout: 3) { savePassword.buttons["Not Now"].tap() }
        account.tap()
        let project = app.buttons["target-active-project-card-realcopy-b9d236394770-project-b9d236394770249424e87c90"]
        XCTAssertTrue(project.waitForExistence(timeout: 30), app.debugDescription)
        reveal(project, in: app)
        project.tap()
        XCTAssertTrue(app.descendants(matching: .any)["target-items-downloaded-count"]
            .waitForExistence(timeout: 30), app.debugDescription)
        // Exact current-placement count from the retained, non-overwritten QA copy.
        // A first local empty snapshot is not completion of its live download.
        XCTAssertTrue(app.staticTexts["Downloaded Items: 623"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["target-items-downloaded-empty"].exists)
        if let transactionID = configuration["LEDGER_HOSTED_QA_CAPTURE_TRANSACTION"] {
            XCTAssertEqual(transactionID, "realcopy-b9d236394770-transaction-883c52f8ca114ce0e2515aa0")
            let transactions = app.buttons["target-project-transactions"]
            let workspace = app.scrollViews["target-workspace-scroll"]
            if !transactions.isHittable {
                // A full-page swipe overshoots this short header on the long Item list.
                let start = workspace.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let delta = max(-200, min(200, workspace.frame.midY - transactions.frame.midY))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)))
            }
            XCTAssertTrue(transactions.isHittable)
            transactions.tap()
            let searchButton = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@",
                "target-transaction-browser-controls", "Search")).firstMatch
            reveal(searchButton, in: app)
            searchButton.tap()
            let search = app.textFields["Search transactions..."]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap(); search.typeText(transactionID)
            searchButton.tap()
            let transaction = app.staticTexts.matching(identifier: "target-transaction-" + transactionID).firstMatch
            reveal(transaction, in: app)
            XCTAssertTrue(transaction.waitForExistence(timeout: 15))
            transaction.tap()
            // The shared section gives its header and content the same identifier.
            // Select the content, not the first matching header button.
            let receipts = app.otherElements["target-transaction-attachments-receipts"].firstMatch
            let add = receipts.buttons["Add Attachment"]
            let detail = app.scrollViews["target-transaction-detail-scroll"]
            XCTAssertTrue(detail.waitForExistence(timeout: 10))
            reveal(add, in: app, within: detail)
            XCTAssertTrue(add.waitForExistence(timeout: 15))
            add.tap()
            app.buttons["Photo Library"].tap()
            let photo = app.images["PXGGridLayout-Info"].firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 10))
            photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            app.navigationBars["Photos"].buttons["Done"].tap()
            // The reviewed section starts empty. Open its actual captured photo;
            // do not require a transient pending overlay to win a network race.
            let captured = receipts.images.firstMatch
            XCTAssertTrue(captured.waitForExistence(timeout: 15), app.debugDescription)
            captured.tap()
            let pin = app.buttons["target-transaction-image-pin"]
            XCTAssertTrue(pin.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.images["target-item-image-rendered"].firstMatch.waitForExistence(timeout: 10))
            pin.tap()
            let panel = app.descendants(matching: .any)["target-transaction-pinned-panel"].firstMatch
            XCTAssertTrue(panel.waitForExistence(timeout: 10))
            XCTAssertTrue(panel.images["target-item-image-rendered"].firstMatch.waitForExistence(timeout: 10))
            // No simulated completion: the separate server read must confirm publication.
            let pending = app.descendants(matching: .any)["target-transaction-attachment-pending"].firstMatch
            XCTAssertTrue(waitUntil { !pending.exists }, app.debugDescription)
            XCTAssertFalse(app.descendants(matching: .any)["target-transaction-attachment-rejected"].exists)
            XCTAssertTrue(panel.images["target-item-image-rendered"].firstMatch.exists)
            return
        }
        if let itemID = configuration["LEDGER_HOSTED_QA_MEDIA_ITEM"] {
            // Optional live-media verification, not a new gallery/gesture test.
            XCTAssertTrue(itemID.hasPrefix("realcopy-b9d236394770-item-"))
            let name = try XCTUnwrap(configuration["LEDGER_HOSTED_QA_MEDIA_SEARCH"])
            let search = app.textFields["target-items-search"]
            reveal(search, in: app)
            search.tap(); search.typeText(name + "\n")
            let item = app.buttons["target-physical-item-\(itemID)"]
            reveal(item, in: app, fullyInsideScrollView: true)
            XCTAssertTrue(item.waitForExistence(timeout: 10))
            item.tap()
            openItemImages(in: app)
            XCTAssertTrue(app.images["target-item-image-rendered"].firstMatch.waitForExistence(timeout: 20))
            XCTAssertFalse(app.staticTexts["target-item-images-unavailable"].exists)
            XCTAssertFalse(app.staticTexts["target-item-images-incomplete"].exists)
        }
    }

    func testNormalLocalEntryRestoresWorkspace() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_NORMAL_LOCAL_ENTRY"] == "1" else {
            throw XCTSkip("Requires the local build and an existing disposable local signed-in account")
        }
        let transactionID = try XCTUnwrap(ProcessInfo.processInfo.environment["LEDGER_NORMAL_LOCAL_TRANSACTION"])
        XCTAssertTrue(transactionID.hasPrefix("upload-http-transaction-"))
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch() // No fixture entry, injected admission, or alternate workspace.
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "targetLocal"))
            .firstMatch.waitForExistence(timeout: 10))
        if let email = ProcessInfo.processInfo.environment["LEDGER_NORMAL_LOCAL_EMAIL"] {
            XCTAssertTrue(email.hasSuffix("@ledger-tests.invalid"))
            let password = try XCTUnwrap(ProcessInfo.processInfo.environment["LEDGER_NORMAL_LOCAL_PASSWORD"])
            let emailField = app.textFields["Email"]
            XCTAssertTrue(emailField.waitForExistence(timeout: 10))
            emailField.tap(); emailField.typeText(email)
            app.secureTextFields["Password"].tap()
            app.secureTextFields["Password"].typeText(password)
            let submit = try XCTUnwrap(app.buttons.matching(identifier: "Sign In").allElementsBoundByIndex.last)
            reveal(submit, in: app, within: app.scrollViews["target-account-entry-scroll"])
            submit.tap()
        }
        let account = app.buttons["Synthetic Primary Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        let savePassword = app.sheets["Save Password?"]
        if savePassword.waitForExistence(timeout: 3) { savePassword.buttons["Not Now"].tap() }
        let inventory = app.buttons["target-business-inventory-card"]
        reveal(inventory, in: app)
        XCTAssertTrue(inventory.waitForExistence(timeout: 10))
        inventory.tap()
        XCTAssertTrue(app.descendants(matching: .any)["target-inventory-section"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["target-inventory-section"].buttons["Transactions"].tap()
        if ProcessInfo.processInfo.environment["LEDGER_NORMAL_LOCAL_EXPECT_REMOVAL"] == "1" {
            let row = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                "target-transaction-upload-http-", "$0.01")).firstMatch
            reveal(row, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            row.tap()
            XCTAssertTrue(transactionDetailBack(in: app).waitForExistence(timeout: 10))
            print("LEDGER_NORMAL_LOCAL_READY_FOR_REMOVAL")
            XCTAssertTrue(app.descendants(matching: .any)["target-workspace-access-removed"]
                .waitForExistence(timeout: 60), app.debugDescription)
            XCTAssertFalse(transactionDetailBack(in: app).exists)
            XCTAssertFalse(row.exists)
            return
        }
        let searchButton = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@",
            "target-transaction-browser-controls", "Search")).firstMatch
        reveal(searchButton, in: app)
        searchButton.tap()
        let search = app.textFields["Search transactions..."]
        reveal(search, in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText(transactionID)
        searchButton.tap() // Collapse the existing search UI and dismiss its keyboard; retain the filter.
        let transaction = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@",
            "target-transaction-" + transactionID, "$0.01")).firstMatch
        reveal(transaction, in: app)
        XCTAssertTrue(transaction.waitForExistence(timeout: 15))
        transaction.tap()
        let pdf = app.staticTexts["Original receipt.pdf"].firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 15))
        pdf.tap()
        let viewer = app.descendants(matching: .any)["target-transaction-pdf-viewer"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { viewer.value as? String == "1 PDF pages" }, app.debugDescription)
        app.buttons["Close PDF"].tap()
        transactionDetailBack(in: app).tap()
        XCTAssertTrue(transaction.waitForExistence(timeout: 10))
        transaction.tap()
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        pdf.tap()
        XCTAssertTrue(viewer.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { viewer.value as? String == "1 PDF pages" }, app.debugDescription)
        app.buttons["Close PDF"].tap()
    }

    func testNormalLocalRemovedWorkspaceCannotReopen() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_NORMAL_LOCAL_REMOVAL_REOPEN"] == "1" else {
            throw XCTSkip("Requires the retained workspace from a completed local live-removal test")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "targetLocal"))
            .firstMatch.waitForExistence(timeout: 10))
        let account = app.buttons["Synthetic Primary Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 15))
        account.tap()
        XCTAssertTrue(app.descendants(matching: .any)["target-workspace-access-removed"]
            .waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["target-business-inventory-card"].exists)
        XCTAssertFalse(app.textFields["target-client-name"].exists)
    }

    func testWorkspaceTransactionEntryBackReentryAndRemoval() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-workspace-transactions",
                               "--ledger-ui-test-reset-inventory-section"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let transactions = app.buttons["target-project-transactions"]
        let back = app.buttons["target-active-workspace-back"]
        for _ in 0..<2 {
            reveal(transactions, in: app)
            transactions.tap()
            XCTAssertTrue(app.staticTexts["Client payment"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Select all"].exists)
            app.buttons["Select all"].tap()
            let amount = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@",
                "target-transaction-transaction-browser-fixture", "$100.00")).firstMatch
            reveal(amount, in: app, fullyInsideScrollView: true)
            amount.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: 8, dy: 0)).tap()
            XCTAssertTrue(transactionDetailBack(in: app).waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.descendants(matching: .any)["target-vendor-receipt-audit"].exists)
            transactionDetailBack(in: app).tap()
            XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 5), app.debugDescription)
            reveal(back, in: app, upwards: false)
            back.tap()
            XCTAssertTrue(transactions.waitForExistence(timeout: 5))
        }
        back.tap()
        let inventory = app.buttons["target-business-inventory-card"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 5))
        inventory.tap()
        #if os(macOS)
        app.radioButtons["Transactions"].tap()
        #else
        app.segmentedControls.buttons["Transactions"].tap()
        #endif
        XCTAssertTrue(app.staticTexts["Fixture vendor"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Client payment"].exists)
        XCTAssertFalse(app.buttons["Select all"].exists, "Inventory must not acquire Project-only controls")
        let remove = app.buttons["target-ui-fixture-remove-account"]
        reveal(remove, in: app, upwards: false)
        remove.tap()
        XCTAssertTrue(app.descendants(matching: .any)["target-workspace-access-removed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Fixture vendor"].exists)
        XCTAssertFalse(app.staticTexts["$100.00"].exists)
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
        try XCTSkipIf(true, "D-029 retires vendor invoice importers; retained historical test, not conversion scope")
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

    private nonisolated func installOfflinePDFPermissionHandler() -> NSObjectProtocol {
        addUIInterruptionMonitor(withDescription: "Deny unrelated Ledger local-network discovery") { dialog in
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
        try XCTSkipIf(true, "D-029 retires vendor invoice importers; retained historical test, not conversion scope")
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
        try XCTSkipIf(true, "D-029 retires vendor invoice importers; retained historical test, not conversion scope")
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
        try XCTSkipIf(true, "D-029 retires vendor invoice importers; retained historical test, not conversion scope")
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
        try XCTSkipIf(true, "D-029 retires vendor invoice importers; retained historical test, not conversion scope")
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

    func testPropertyManagementIOSPDFCopyCompletion() throws {
        executionTimeAllowance = 120
        try exercisePropertyManagementIOSCopy(identifier: "target-property-report-share", expectedPayload: "PDF content received")
    }

    func testPropertyManagementIOSCSVCopyCompletion() throws {
        executionTimeAllowance = 120
        try exercisePropertyManagementIOSCopy(identifier: "target-property-report-csv", expectedPayload: "CSV content received")
    }

    private func exercisePropertyManagementIOSCopy(identifier: String, expectedPayload: String) throws {
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
        UIPasteboard.general.items = []
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
        XCTAssertTrue(app.otherElements["ActivityListView"].firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(busy.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitUntil { button.isEnabled }, app.debugDescription)
        XCTAssertFalse(failure.exists)
        app.buttons["Done"].tap()
        let paste = app.buttons["target-ui-fixture-paste-report"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        XCTAssertTrue(paste.isEnabled)
        paste.tap()
        let result = app.staticTexts["target-ui-fixture-paste-result"]
        XCTAssertTrue(waitUntil { result.label == expectedPayload }, app.debugDescription)
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

    func testDownloadedItemAccountingFilter() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let filters = app.descendants(matching: .any).matching(identifier: "target-items-filters").firstMatch
        let count = app.staticTexts["target-items-downloaded-count"]
        let selected = app.staticTexts["target-items-selected-count"]
        func choose(_ facet: String, _ option: String) {
            reveal(filters, in: app, fullyInsideScrollView: true)
            filters.tap()
            #if os(macOS)
            let submenu = app.menuItems[facet]
            XCTAssertTrue(submenu.waitForExistence(timeout: 5))
            submenu.tap()
            let choice = submenu.menuItems[option]
            #else
            let submenu = app.buttons[facet]
            XCTAssertTrue(submenu.waitForExistence(timeout: 5))
            submenu.tap()
            let choice = app.buttons[option]
            #endif
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
        }
        func expectCount(_ value: Int, selected selectedValue: Int? = nil) {
            XCTAssertTrue(waitUntil { self.displayedText(count) == "Matching Items: \(value) of 3 downloaded" })
            if let selectedValue {
                XCTAssertTrue(waitUntil { self.displayedText(selected) == "\(selectedValue) selected" })
            }
        }
        let selectAll = app.buttons["target-items-select-all"]
        reveal(selectAll, in: app, fullyInsideScrollView: true)
        selectAll.tap()
        choose("Accounting", "Accounted For") // All-except removes the one accounted chair.
        expectCount(2, selected: 2)
        XCTAssertFalse(app.buttons["target-physical-item-physical-ui-chair"].exists)
        choose("Accounting", "None")
        expectCount(0, selected: 0)
        choose("Accounting", "Unaccounted For")
        expectCount(0) // Missing relationship evidence cannot prove Unaccounted For.
        choose("Accounting", "Accounting status unknown")
        expectCount(2)
        choose("Accounting", "Accounted For") // OR within the facet.
        expectCount(3)
        choose("Bookmark", "Not Bookmarked") // AND across facets leaves the bookmarked chair.
        expectCount(1)
        reveal(app.buttons["target-physical-item-physical-ui-chair"], in: app, fullyInsideScrollView: true)
        XCTAssertTrue(app.buttons["target-physical-item-physical-ui-chair"].waitForExistence(timeout: 5))
        let clear = app.buttons["target-items-filters-clear"]
        reveal(clear, in: app, fullyInsideScrollView: true)
        clear.tap()
        XCTAssertTrue(waitUntil { self.displayedText(count) == "Downloaded Items: 3" })
        XCTAssertFalse(clear.exists)

        // A separate complete fixture proves actual Unaccounted rows, not an
        // interpretation of absent/partial evidence. No production connection.
        app.terminate()
        app.launchArguments.append("--ledger-ui-test-complete-item-accounting")
        app.launch()
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        choose("Accounting", "None")
        choose("Accounting", "Unaccounted For")
        expectCount(2)
        choose("Accounting", "All")
        XCTAssertTrue(waitUntil { self.displayedText(count) == "Downloaded Items: 3" })

        app.terminate()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-reset-inventory-scope"]
        app.launch()
        let inventory = app.buttons["target-business-inventory-card"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 10))
        inventory.tap()
        reveal(filters, in: app, fullyInsideScrollView: true)
        filters.tap()
        #if os(macOS)
        XCTAssertTrue(app.menuItems["Bookmark"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["Accounting"].exists)
        #else
        XCTAssertTrue(app.buttons["Bookmark"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Accounting"].exists)
        #endif
    }

    func testDownloadedItemImageEvidenceFilter() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let filters = app.descendants(matching: .any).matching(identifier: "target-items-filters").firstMatch
        func choose(_ option: String) {
            reveal(filters, in: app, fullyInsideScrollView: true)
            filters.tap()
            #if os(macOS)
            let facet = app.menuItems["Image"]
            XCTAssertTrue(facet.waitForExistence(timeout: 5))
            facet.tap()
            facet.menuItems[option].tap()
            #else
            let facet = app.buttons["Image"]
            XCTAssertTrue(facet.waitForExistence(timeout: 5))
            facet.tap()
            app.buttons[option].tap()
            #endif
        }
        for (label, itemId, evidence) in [
            ("No Image", "physical-ui-chair", "No Image"),
            ("Has Image", "physical-ui-other-space", "1 image"),
            ("Image information unavailable", "physical-ui-unassigned", "Image information unavailable")
        ] {
            choose("None")
            choose(label)
            let item = app.buttons["target-physical-item-\(itemId)"]
            reveal(item, in: app, fullyInsideScrollView: true)
            XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
            let count = app.staticTexts["target-items-downloaded-count"]
            XCTAssertTrue(waitUntil { self.displayedText(count) == "Matching Items: 1 of 3 downloaded" })
            XCTAssertEqual(displayedText(app.staticTexts["target-item-image-count-\(itemId)"]), evidence)
            let clear = app.buttons["target-items-filters-clear"]
            reveal(clear, in: app, fullyInsideScrollView: true)
            clear.tap()
        }
    }

    func testUninvoicedReturnCancelAndConfirm() throws {
        try exerciseUninvoicedReturn(retry: false)
    }

    func testUninvoicedReturnRetainsExactRequestForRetry() throws {
        try exerciseUninvoicedReturn(retry: true)
    }

    private func exerciseUninvoicedReturn(retry: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        if retry { app.launchArguments.append("--ledger-ui-test-return-retry") }
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true); item.tap()
        func openReturn() {
            let actions = app.descendants(matching: .any)["target-item-detail-actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 5)); actions.tap()
            #if os(macOS)
            let action = app.menuItems["Return to Inventory"]
            #else
            let action = app.buttons["Return to Inventory"]
            #endif
            XCTAssertTrue(action.waitForExistence(timeout: 5)); action.tap()
            XCTAssertTrue(app.buttons["Confirm Return"].waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntil { app.buttons["Confirm Return"].isEnabled })
        }
        openReturn()
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "0")
        openReturn()
        app.buttons["Confirm Return"].tap()
        if retry {
            let error = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@",
                "Could not confirm this return", "Could not confirm this return")).firstMatch
            XCTAssertTrue(error.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntil { app.buttons["Confirm Return"].isEnabled })
            app.buttons["Confirm Return"].tap()
        }
        let done = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "target-return-form", "Done")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Confirm Return"].isEnabled)
        XCTAssertTrue(waitUntil { self.displayedText(app.staticTexts["target-return-status"]).contains("saved on this device") })
        done.tap()
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    func testUninvoicedBulkReturnAndUnavailableSelection() throws {
        continueAfterFailure = false
        for unavailable in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-bulk-return"]
            if unavailable { app.launchArguments.append("--ledger-ui-test-return-unavailable") }
            app.launch()
            defer { app.terminate() }
            let project = app.buttons["target-active-project-card-project-ui-test"]
            XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
            let select = app.buttons["target-items-select-all"]
            reveal(select, in: app, fullyInsideScrollView: true); select.tap()
            let action = app.buttons["target-items-return"]
            reveal(action, in: app, fullyInsideScrollView: true); action.tap()
            let confirm = app.buttons["Confirm Return"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            if unavailable {
                XCTAssertFalse(confirm.isEnabled)
                app.buttons["Cancel"].tap()
                XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "0")
            } else {
                XCTAssertTrue(waitUntil { confirm.isEnabled }); confirm.tap()
                XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
                XCTAssertFalse(confirm.isEnabled)
                app.buttons["Done"].tap()
                XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
            }
        }
    }

    func testUninvoicedReturnHistoryUsesExistingItemDetail() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-inventory-space",
                               "--ledger-ui-test-return-history", "--ledger-ui-test-reset-inventory-section"]
        app.launch()
        defer { app.terminate() }
        let inventory = app.buttons["target-business-inventory-card"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 10)); inventory.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true); item.tap()
        let scroll = app.scrollViews["target-item-detail-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let link = app.staticTexts.matching(NSPredicate(format:
            "identifier == %@ AND (label == %@ OR value == %@)",
            "target-item-history-returned-inventory",
            "Returned before invoicing · original charge return-ui-charge",
            "Returned before invoicing · original charge return-ui-charge")).firstMatch
        reveal(link, in: app, fullyInsideScrollView: true, within: scroll)
        XCTAssertEqual(displayedText(link), "Returned before invoicing · original charge return-ui-charge")
        XCTAssertTrue(app.staticTexts["target-item-history-partial"].exists)
    }

    func testInventorySaleReviewCancelAndConfirm() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-inventory-space",
                               "--ledger-ui-test-reset-inventory-section"]
        app.launch()
        defer { app.terminate() }
        let inventory = app.buttons["target-business-inventory-card"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 10))
        inventory.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true)
        item.tap()
        func openSale() {
            let actions = app.descendants(matching: .any)["target-item-detail-actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 5))
            actions.tap()
            #if os(macOS)
            let sale = app.menuItems["Sell to Project"]
            #else
            let sale = app.buttons["Sell to Project"]
            #endif
            XCTAssertTrue(sale.waitForExistence(timeout: 5))
            sale.tap()
            let project = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "UI Test Project")).firstMatch
            XCTAssertTrue(project.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Archived UI Test Project"].exists)
            project.tap()
        }
        openSale()
        let field = app.textFields["0.00"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("125.50")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["USD 125.50"].waitForExistence(timeout: 5))
        app.buttons["sale-step-back"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "125.50")
        app.buttons["sale-step-close"].tap()
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "0")
        openSale()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("125.50")
        app.buttons["Continue"].tap()
        app.buttons["Confirm Sale"].tap()
        XCTAssertTrue(app.staticTexts["target-sale-status"].waitForExistence(timeout: 5))
        app.buttons["sale-step-close"].tap()
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    #if os(iOS)
    func testInventorySaleReviewChangesRequireFreshReview() throws {
        try exerciseSaleReviewChange(withdraws: false)
    }
    func testInventorySaleReviewWithdrawalBlocksConfirmation() throws {
        try exerciseSaleReviewChange(withdraws: true)
    }
    private func exerciseSaleReviewChange(withdraws: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-inventory-space",
            "--ledger-ui-test-reset-inventory-section", withdraws ? "--ledger-ui-test-sale-review-withdraws" : "--ledger-ui-test-sale-review-changes"]
        app.launch()
        defer { app.terminate() }
        let inventory = app.buttons["target-business-inventory-card"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 10)); inventory.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true); item.tap()
        app.descendants(matching: .any)["target-item-detail-actions"].tap()
        app.buttons["Sell to Project"].tap()
        let project = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "UI Test Project")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5)); project.tap()
        let field = app.textFields["0.00"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("125.50")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Confirm Sale"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        if withdraws {
            XCTAssertTrue(app.staticTexts["Sale review is unavailable. Item location or purchase-cost access may have changed."].waitForExistence(timeout: 5))
            XCTAssertFalse(project.exists)
        } else {
            XCTAssertTrue(project.waitForExistence(timeout: 5))
        }
        XCTAssertFalse(app.buttons["Confirm Sale"].exists)
        XCTAssertFalse(app.staticTexts["USD 125.50"].exists)
        if !withdraws {
            project.tap()
            XCTAssertTrue(app.staticTexts["USD 250.00"].waitForExistence(timeout: 5))
        }
        app.buttons["sale-step-close"].tap()
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "0")
    }
    #endif

    func testInventoryPendingSalePresentation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-inventory-space",
                               "--ledger-ui-test-pending-sale"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(app.staticTexts["target-item-pending-sale-physical-ui-chair"].exists)
        item.tap()
        XCTAssertTrue(app.staticTexts["target-item-detail-pending-sale"].waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(app.staticTexts["target-item-detail-current-location"]), "UI Test Project · Sale pending sync")
        XCTAssertEqual(displayedText(app.staticTexts["target-item-detail-space"]), "Not assigned to a Space")
        let actions = app.descendants(matching: .any)["target-item-detail-actions"]
        actions.tap()
        #if os(macOS)
        XCTAssertFalse(app.menuItems["Sell to Project"].exists)
        #else
        XCTAssertFalse(app.buttons["Sell to Project"].exists)
        #endif
    }

    func testInventoryBulkSaleUsesOneCommand() throws {
        try exerciseInventoryBulkSale(alreadyAccepted: false)
    }

    func testInventorySaleAlreadyAcceptedDoesNotOfferRetry() throws {
        try exerciseInventoryBulkSale(alreadyAccepted: true)
    }

    private func exerciseInventoryBulkSale(alreadyAccepted: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-bulk-sale",
                               "--ledger-ui-test-reset-inventory-section"]
        if alreadyAccepted { app.launchArguments.append("--ledger-ui-test-sale-already-accepted") }
        app.launch()
        defer { app.terminate() }
        let inventory = app.buttons["target-business-inventory-card"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 10))
        inventory.tap()
        let select = app.buttons["target-items-select-all"]
        reveal(select, in: app, fullyInsideScrollView: true)
        select.tap()
        let sale = app.buttons["target-items-sell"]
        reveal(sale, in: app, fullyInsideScrollView: true)
        sale.tap()
        let project = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "UI Test Project")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.tap()
        XCTAssertTrue(app.buttons["Confirm Sale"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "USD 125.50").count, 3)
        app.buttons["Confirm Sale"].tap()
        if alreadyAccepted {
            XCTAssertTrue(app.staticTexts["target-sale-already-accepted"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Retry Sale"].exists)
            XCTAssertFalse(app.buttons["Confirm Sale"].exists)
            app.buttons["sale-step-close"].tap()
            XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "0")
            return
        }
        XCTAssertTrue(app.staticTexts["target-sale-status"].waitForExistence(timeout: 5))
        app.buttons["sale-step-close"].tap()
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    func testDownloadedItemReadOnlyDetails() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-detail-copy"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true)
        item.tap()
        let scroll = app.scrollViews["target-item-detail-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for (id, expected) in [
            ("name", "Downloaded test chair"), ("current-location", "Current test Project"),
            ("budget-category", "Furniture"),
            ("accounting", "Accounted For"),
            ("space", "Current test Space"),
            ("notes", "Keep the woven seat dry.\nPlace beside the window."),
            ("description", "Oak chair with woven seat"), ("source", "Original vendor"),
            ("current-source", "Design Inventory"),
            ("sku", "CHAIR-001"), ("workflow", "To Purchase"), ("bookmark", "Yes"),
            ("created", "2026-09-01T11:00:00Z")
        ] {
            let field = id == "space" ? app.buttons["target-item-detail-space"]
                : app.staticTexts["target-item-detail-\(id)"]
            reveal(field, in: app, fullyInsideScrollView: true, within: scroll)
            XCTAssertEqual(displayedText(field), expected)
        }
        for (section, fieldID) in [("notes", "notes"), ("details", "sku")] {
            let toggle = app.buttons["target-item-detail-\(section)-section"]
            reveal(toggle, in: app, fullyInsideScrollView: true, within: scroll)
            XCTAssertEqual(toggle.value as? String, "Expanded")
            toggle.tap()
            let field = app.staticTexts["target-item-detail-\(fieldID)"]
            XCTAssertTrue(field.waitForNonExistence(timeout: 5))
            toggle.tap()
            XCTAssertTrue(field.waitForExistence(timeout: 5))
        }
        let history = app.staticTexts["target-item-history-partial"]
        reveal(history, in: app, fullyInsideScrollView: true, within: scroll)
        XCTAssertEqual(displayedText(history),
            "Downloaded locations and available return links. Older history may be missing. This is not a payment or refund ledger.")
        let actions = app.descendants(matching: .any)
            .matching(identifier: "target-item-detail-actions").firstMatch
        XCTAssertTrue(actions.exists)
        let exerciseClipboard = ProcessInfo.processInfo.environment["LEDGER_ISOLATED_CI_CLIPBOARD"] == "true"
        if exerciseClipboard {
            actions.tap()
            #if os(macOS)
            let copyID = app.menuItems["Copy ID"]
            #else
            let copyID = app.buttons["Copy ID"]
            #endif
            XCTAssertTrue(copyID.waitForExistence(timeout: 5))
            copyID.tap()
        }
        app.buttons["target-item-history-done"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        if exerciseClipboard {
            #if os(macOS)
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), "physical-ui-chair")
            #else
            assertPastedItemIDs("physical-ui-chair", in: app)
            #endif
        }
    }

    func testItemDetailBookmarkQueuesExactlyOnce() throws {
        try exerciseItemBookmark(retry: false)
    }

    func testBulkItemStatusCancelAndSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-detail-copy",
                               "--ledger-ui-test-bulk-status"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let chair = app.buttons["target-item-select-physical-ui-chair"]
        reveal(chair, in: app, fullyInsideScrollView: true); chair.tap()
        let second = app.buttons["target-item-select-physical-ui-unassigned"]
        reveal(second, in: app, fullyInsideScrollView: true); second.tap()
        let change = app.buttons["target-items-change-status"]
        reveal(change, in: app, fullyInsideScrollView: true); change.tap()
        XCTAssertTrue(app.buttons["Returned"].waitForExistence(timeout: 5))
        app.buttons["Returned"].tap(); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        change.tap()
        XCTAssertTrue(app.buttons["Returned"].waitForExistence(timeout: 5))
        app.buttons["Returned"].tap(); app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this device. Waiting to sync; you can close this form."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    func testItemDetailBookmarkRetriesSameEdit() throws {
        try exerciseItemBookmark(retry: true)
    }

    func testItemDetailBookmarkRejectionRetainsWork() throws {
        try exerciseItemBookmark(retry: false, rejected: true)
    }

    func testItemDetailBookmarkAppliedWaitsForDownload() throws {
        try exerciseItemBookmark(retry: false, applied: true)
    }

    func testItemDetailBookmarkDownloadedResultReenablesEditing() throws {
        try exerciseItemBookmark(retry: false, applied: true, readback: true)
    }

    private func exerciseItemBookmark(retry: Bool, rejected: Bool = false,
                                      applied: Bool = false, readback: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-detail-copy"]
        if retry { app.launchArguments.append("--ledger-ui-test-bookmark-retry") }
        if rejected { app.launchArguments.append("--ledger-ui-test-bookmark-rejected") }
        if applied { app.launchArguments.append("--ledger-ui-test-bookmark-applied") }
        if readback { app.launchArguments.append("--ledger-ui-test-bookmark-readback") }
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true); item.tap()
        let bookmark = app.buttons["target-item-detail-bookmark-toggle"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        XCTAssertEqual(bookmark.label, "Remove bookmark")
        bookmark.tap()
        if retry {
            let retryButton = app.buttons["Retry bookmark change"]
            XCTAssertTrue(retryButton.waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
            retryButton.tap()
        }
        if readback {
            XCTAssertTrue(waitUntil { bookmark.label == "Add bookmark" && bookmark.isEnabled })
            XCTAssertFalse(app.staticTexts["target-item-bookmark-pending"].exists)
        } else {
            XCTAssertTrue(app.staticTexts["target-item-bookmark-pending"].waitForExistence(timeout: 5))
            XCTAssertFalse(bookmark.isEnabled)
            XCTAssertEqual(bookmark.label, "Remove bookmark")
        }
        if rejected {
            XCTAssertTrue(app.staticTexts["Bookmark change was not applied. Saved work is retained for review."].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Retry bookmark change"].exists)
            XCTAssertEqual(bookmark.label, "Remove bookmark")
        }
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    func testItemStatusEditorCancelUnchangedAndSave() throws {
        try exerciseItemStatusEditor(selection: "Returned")
    }

    func testItemStatusEditorExplicitClear() throws {
        try exerciseItemStatusEditor(selection: "Clear Status")
    }

    private func exerciseItemStatusEditor(selection: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-detail-copy"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true); item.tap()
        func openEditor() {
            app.buttons["target-item-detail-actions"].tap()
            app.buttons["Change Status"].tap()
            XCTAssertTrue(app.buttons["To Purchase"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["To Purchase"].value as? String, "Selected")
        }
        openEditor(); app.buttons[selection].tap(); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor(); app.buttons["To Purchase"].tap(); app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor(); app.buttons[selection].tap()
        XCTAssertEqual(app.buttons[selection].value as? String, "Selected")
        app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this device. Waiting to sync; you can close this form."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    func testItemNotesEditorCancelUnchangedAndSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-detail-copy"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true); item.tap()
        func openEditor() {
            let edit = app.buttons["target-item-edit-notes"]
            reveal(edit, in: app, fullyInsideScrollView: true); edit.tap()
            XCTAssertTrue(app.textViews["target-item-notes-entry"].waitForExistence(timeout: 5))
        }
        openEditor(); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor(); app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor()
        let field = app.textViews["target-item-notes-entry"]
        field.tap()
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        #else
        field.press(forDuration: 1)
        let selectAll = app.menuItems["Select All"].firstMatch
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap() }
        else {
            let button = app.buttons["Select All"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 2)); button.tap()
        }
        #endif
        field.typeText("Updated notes")
        XCTAssertEqual(field.value as? String, "Updated notes")
        app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this device. Waiting to sync; you can close this form."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    func testItemDetailsEditorCancelUnchangedAndSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-detail-copy"]
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true); item.tap()
        func openEditor() {
            let menu = app.buttons["target-item-detail-actions"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5)); menu.tap()
            app.buttons["Edit Name and SKU"].tap()
            XCTAssertTrue(app.textFields["Item name"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields["Item name"].value as? String, "Downloaded test chair")
            XCTAssertEqual(app.textFields["Barcode or SKU number"].value as? String, "CHAIR-001")
        }
        openEditor(); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor(); app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor()
        let field = app.textFields["Item name"]
        field.tap()
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        #else
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Downloaded test chair".count))
        #endif
        field.typeText("Updated chair"); app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this device. Waiting to sync; you can close this form."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    func testItemPriceEditorCancelUnchangedAndNormalizedSave() throws {
        try exerciseItemPriceEditor(retry: false)
    }
    func testInventoryPriceEditorZero() throws { try exerciseItemPriceEditor(retry: false, inventory: true) }
    func testInventoryPriceEditorClear() throws { try exerciseItemPriceEditor(retry: false, inventory: true, clear: true) }

    func testItemMarketValueCancelUnchangedAndSave() throws { try exerciseItemMarketValue(clear: false) }
    func testItemMarketValueExplicitClear() throws { try exerciseItemMarketValue(clear: true) }

    private func exerciseItemMarketValue(clear: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-detail-copy", "--ledger-ui-test-market-edit"]
        if clear { app.launchArguments.append("--ledger-ui-test-market-clear") }
        app.launch(); defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true); item.tap()
        func openEditor() {
            app.buttons["target-item-detail-actions"].tap()
            app.buttons["Edit Market Value"].tap()
            XCTAssertTrue(app.textFields["0.00"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields["0.00"].value as? String, "12.50")
        }
        openEditor(); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor(); app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor()
        let field = app.textFields["0.00"]
        field.tap()
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command); field.typeKey(.delete, modifierFlags: [])
        #else
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        #endif
        if !clear { field.typeText("15.00") }
        app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this device. Waiting to sync; you can close this form."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    func testItemPriceEditorRetriesSameAcceptedEdit() throws {
        try exerciseItemPriceEditor(retry: true)
    }

    func testItemPriceEditorDoesNotAdoptNewRevisionForOldText() throws {
        try exerciseItemPriceEditor(retry: false, changed: true)
    }

    private func exerciseItemPriceEditor(retry: Bool, changed: Bool = false, inventory: Bool = false, clear: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-detail-copy"]
        if inventory {
            app.launchArguments += ["--ledger-ui-test-inventory-space", "--ledger-ui-test-reset-inventory-section", "--ledger-ui-test-inventory-price"]
        }
        if clear { app.launchArguments.append("--ledger-ui-test-inventory-price-clear") }
        if retry { app.launchArguments.append("--ledger-ui-test-price-retry") }
        if changed { app.launchArguments.append("--ledger-ui-test-price-changed") }
        app.launch()
        defer { app.terminate() }
        let project = app.buttons[inventory ? "target-business-inventory-card" : "target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true); item.tap()
        let scroll = app.scrollViews["target-item-detail-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let edit = app.buttons["target-item-edit-price"]
        func openEditor() {
            reveal(edit, in: app, fullyInsideScrollView: true, within: scroll); edit.tap()
            XCTAssertTrue(app.textFields["0.00"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields["0.00"].value as? String, "2.50")
        }
        openEditor()
        if changed {
            XCTAssertTrue(app.staticTexts["This Item changed while the editor was open. Close and reopen it to review the updated price."].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
            XCTAssertFalse(app.textFields["0.00"].isEnabled)
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
            return
        }
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor()
        app.buttons["Save Changes"].tap()
        XCTAssertTrue(app.buttons["Save Changes"].waitForNonExistence(timeout: 5))
        openEditor()
        let field = app.textFields["0.00"]
        field.tap()
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        #else
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        #endif
        if !clear { field.typeText(inventory ? "0.00" : "1.00") }
        if !inventory {
            XCTAssertTrue(app.staticTexts["The project price will be raised to 2.00 to match the purchase cost."].waitForExistence(timeout: 5))
        }
        app.buttons["Save Changes"].tap()
        if retry {
            XCTAssertTrue(app.staticTexts["The edit could not be confirmed. Save Changes retries the same edit."].waitForExistence(timeout: 5))
            XCTAssertFalse(field.isEnabled)
            XCTAssertTrue(app.buttons["Save Changes"].isEnabled)
            app.buttons["Save Changes"].tap()
        }
        XCTAssertTrue(app.staticTexts["Saved on this device. Waiting to sync; you can close this form."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
        app.buttons["Close"].firstMatch.tap()
        // The existing fixture counter detects accidental writes on Cancel/no-op.
        XCTAssertEqual(app.staticTexts["target-ui-fixture-acceptance-count"].value as? String, "1")
    }

    func testItemOpensAssignedProjectSpaceAndReturns() throws {
        try exerciseItemSpaceLink(inventory: false, archived: false)
    }

    func testItemOpensArchivedInventorySpaceReadOnlyAndReturns() throws {
        try exerciseItemSpaceLink(inventory: true, archived: true)
    }

    private func exerciseItemSpaceLink(inventory: Bool, archived: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        if inventory {
            app.launchArguments += ["--ledger-ui-test-inventory-space", "--ledger-ui-test-reset-inventory-section"]
        }
        if archived { app.launchArguments.append("--ledger-ui-test-linked-space-archived") }
        if !inventory {
            app.launchArguments += ["--ledger-ui-test-category-unavailable", "--ledger-ui-test-accounting-unavailable"]
        }
        app.launch()
        defer { app.terminate() }
        let workspace = app.buttons[inventory ? "target-business-inventory-card" : "target-active-project-card-project-ui-test"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        workspace.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app, fullyInsideScrollView: true)
        item.tap()
        let link = app.buttons["target-item-detail-space"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(link), "Current test Space")
        let category = app.staticTexts["target-item-detail-budget-category"]
        let accounting = app.staticTexts["target-item-detail-accounting"]
        if inventory {
            XCTAssertFalse(category.exists, "Inventory must not display an old Project's category")
            XCTAssertFalse(accounting.exists, "Inventory must not display an old Project's accounting association")
        } else {
            XCTAssertEqual(displayedText(category), "Category unavailable",
                "Missing category evidence is not an uncategorized Item")
            XCTAssertEqual(displayedText(accounting), "Accounting information unavailable",
                "Missing accounting evidence must not imply Unaccounted For or Paid")
        }
        reveal(link, in: app, fullyInsideScrollView: true,
            within: app.scrollViews["target-item-detail-scroll"])
        link.tap()
        let name = app.staticTexts["target-item-space-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(name), "UI Test Space")
        XCTAssertEqual(app.staticTexts["target-item-space-archived"].exists, archived)
        let checklistItem = app.buttons["target-active-space-checklist-item-checklist-ui-test-item-ui-test"]
        XCTAssertTrue(checklistItem.waitForExistence(timeout: 5))
        if archived {
            XCTAssertFalse(checklistItem.isEnabled, "Historical navigation must not allow archived Space edits")
        } else {
            XCTAssertTrue(waitUntil { checklistItem.isEnabled })
            checklistItem.tap()
            XCTAssertTrue(waitUntil { checklistItem.value as? String == "Checked" })
        }
        let refreshSpace = app.buttons["target-referenced-space-refresh"]
        refreshSpace.tap()
        refreshSpace.tap()
        app.buttons["target-item-space-back"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5), "Back restores the originating Item")
        XCTAssertEqual(displayedText(app.staticTexts["target-item-detail-name"]), "Downloaded test chair")
        app.buttons["target-item-history-done"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
    }

    func testDownloadedItemImageGallery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-images"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app)
        let thumbnail = app.descendants(matching: .any)
            .matching(identifier: "target-item-thumbnail-physical-ui-chair").firstMatch
        reveal(thumbnail, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(waitUntil {
            (thumbnail.value as? String) == "Downloaded" || thumbnail.label == "Item thumbnail, Downloaded"
        }, app.debugDescription)
        XCTAssertEqual(thumbnail.frame.width, 108, accuracy: 1)
        XCTAssertEqual(thumbnail.frame.height, 108, accuracy: 1)
        item.tap()
        let images = app.buttons["target-item-images-open"]
        XCTAssertTrue(images.waitForExistence(timeout: 5))
        openItemImages(in: app)
        let rendered = app.images["target-item-image-rendered"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 10), app.debugDescription)
        revealImageControls(in: app)
        assertImageCounter("1 of 2", in: app)
        let imageFrame = rendered.frame
        let gallery = app.descendants(matching: .any)["target-item-image-viewer"]
        XCTAssertTrue(waitUntil { (gallery.value as? String) == "Image controls hidden" },
            "Controls auto-hide at fit zoom\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["target-item-images-done"].isHittable)
        XCTAssertTrue(app.buttons["target-item-image-pin"].isHittable)
        XCTAssertEqual(rendered.frame.width, imageFrame.width, accuracy: 1)
        XCTAssertEqual(rendered.frame.height, imageFrame.height, accuracy: 1)
        revealImageControls(in: app)
        rendered.tap()
        XCTAssertTrue(waitUntil { (gallery.value as? String) == "Image controls hidden" },
            "Single tap hides controls without dismissing")
        revealImageControls(in: app)
        let zoomOut = app.buttons["target-item-image-zoom-out"]
        let resetZoom = app.buttons["target-item-image-zoom-reset"]
        XCTAssertFalse(zoomOut.isEnabled)
        tapImageControl("target-item-image-zoom-in", in: app)
        XCTAssertTrue(resetZoom.waitForExistence(timeout: 5))
        let zoom = app.staticTexts["target-item-image-zoom-level"]
        XCTAssertTrue(waitUntil { zoom.label == "1.5×" || (zoom.value as? String) == "1.5×" })
        tapImageControl("target-item-image-zoom-reset", in: app)
        XCTAssertTrue(waitUntil { !zoomOut.isEnabled && !resetZoom.exists })
        #if os(macOS)
        rendered.doubleClick()
        #else
        rendered.doubleTap()
        #endif
        XCTAssertTrue(waitUntil { zoom.label == "2.5×" || (zoom.value as? String) == "2.5×" })
        let hiddenWhileZoomed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (gallery.value as? String) == "Image controls hidden" },
            object: nil)
        hiddenWhileZoomed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [hiddenWhileZoomed], timeout: 2.5), .completed,
            "Controls must remain visible while zoomed")
        tapImageControl("target-item-image-zoom-reset", in: app)
        XCTAssertTrue(waitUntil { zoomOut.exists && !zoomOut.isEnabled })
        tapImageControl("target-item-image-zoom-in", in: app)
        tapImageControl("target-item-images-next", in: app)
        assertImageCounter("2 of 2", in: app)
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        revealImageControls(in: app)
        XCTAssertTrue(zoomOut.exists && !zoomOut.isEnabled && !resetZoom.exists)
        // Both directions wrap through the source set, as in the shipped viewer.
        tapImageControl("target-item-images-next", in: app)
        assertImageCounter("1 of 2", in: app)
        tapImageControl("target-item-images-previous", in: app)
        assertImageCounter("2 of 2", in: app)
        tapImageControl("target-item-images-next", in: app)
        assertImageCounter("1 of 2", in: app)
        let pin = app.buttons["target-item-image-pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        let unpin = app.buttons["target-item-image-unpin"]
        XCTAssertTrue(unpin.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["target-item-images-done"].exists)
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        let historyRefresh = app.buttons["target-item-history-refresh"]
        XCTAssertTrue(historyRefresh.isHittable)
        historyRefresh.tap()
        XCTAssertTrue(unpin.exists)
        openItemImages(in: app)
        XCTAssertTrue(app.buttons["target-item-images-done"].waitForExistence(timeout: 5))
        app.buttons["target-item-images-done"].tap()
        XCTAssertTrue(unpin.waitForExistence(timeout: 5), "Opening and closing the gallery retains the existing pin")
        XCTAssertTrue(historyRefresh.waitForExistence(timeout: 5), "The parent Item route remains open")
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        openItemImages(in: app)
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        // Select and pin another reference without an intermediate unpin.
        tapImageControl("target-item-images-next", in: app)
        assertImageCounter("2 of 2", in: app)
        pin.tap()
        XCTAssertTrue(unpin.waitForExistence(timeout: 5))
        let pinnedCount = app.staticTexts["target-pinned-images-counter"]
        XCTAssertTrue(waitUntil { pinnedCount.label == "2 of 2" || (pinnedCount.value as? String) == "2 of 2" })
        app.buttons["target-pinned-images-next"].tap()
        XCTAssertTrue(waitUntil { pinnedCount.label == "1 of 2" || (pinnedCount.value as? String) == "1 of 2" })
        openItemImages(in: app)
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        tapImageControl("target-item-images-next", in: app)
        assertImageCounter("2 of 2", in: app)
        pin.tap()
        XCTAssertTrue(waitUntil { pinnedCount.label == "2 of 2" || (pinnedCount.value as? String) == "2 of 2" })
        unpin.tap()
        XCTAssertTrue(waitUntil { !unpin.exists && !rendered.exists })
        openItemImages(in: app)
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(rendered.frame.height, 40, "Gallery must retain a usable image after unpinning")
        let done = app.buttons["target-item-images-done"]
        XCTAssertTrue(done.isHittable, "Gallery close must not be clipped after unpinning")
        #if os(macOS)
        // A macOS application accessibility element is not its window bounds.
        let galleryWindow = app.windows.containing(.button, identifier: "target-item-images-done").firstMatch
        XCTAssertTrue(galleryWindow.exists)
        XCTAssertTrue(galleryWindow.frame.contains(done.frame), "Gallery close stays inside its window")
        #else
        XCTAssertTrue(app.frame.contains(done.frame), "Gallery close stays inside the app window")
        #endif
        done.tap()
        XCTAssertTrue(images.waitForExistence(timeout: 5))
        XCTAssertTrue(rendered.waitForNonExistence(timeout: 5), "Closing the unpinned gallery removes its image")
    }

    #if os(iOS)
    func testDownloadedItemImagePhotosDenied() throws {
        try exerciseItemPhotosSaving(allow: false)
    }

    func testDownloadedItemImagePhotosSaved() throws {
        try exerciseItemPhotosSaving(allow: true)
    }

    func testTransactionImagePhotosDenied() throws {
        try exerciseItemPhotosSaving(allow: false, transaction: true)
    }

    func testTransactionImagePhotosSaved() throws {
        try exerciseItemPhotosSaving(allow: true, transaction: true)
    }

    private func exerciseItemPhotosSaving(allow: Bool, transaction: Bool = false) throws {
        // The existing CI flag identifies the disposable simulator. Never
        // reset a developer's Photos permissions or save into their library.
        guard ProcessInfo.processInfo.environment["LEDGER_ISOLATED_CI_CLIPBOARD"] == "true" else {
            throw XCTSkip("Photos permission/save checks require the disposable CI simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = transaction
            ? ["--ledger-ui-test-transaction-browser", "--ledger-ui-test-transaction-attachments"]
            : ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-images"]
        app.launch()
        defer { app.terminate(); app.resetAuthorizationStatus(for: .photos) }
        if transaction {
            XCTAssertTrue(app.staticTexts["$100.00"].waitForExistence(timeout: 10))
            app.staticTexts["$100.00"].coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: 8, dy: 0)).tap()
            let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photo 1.png")).firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 5))
            photo.tap()
        } else {
            let project = app.buttons["target-active-project-card-project-ui-test"]
            XCTAssertTrue(project.waitForExistence(timeout: 10))
            project.tap()
            let item = app.buttons["target-physical-item-physical-ui-chair"]
            reveal(item, in: app, fullyInsideScrollView: true)
            item.tap()
            openItemImages(in: app)
        }
        XCTAssertTrue(app.images["target-item-image-rendered"].waitForExistence(timeout: 10))
        let save = app.buttons[transaction ? "target-transaction-image-save" : "target-item-image-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = system.alerts.firstMatch
        XCTAssertTrue(permission.waitForExistence(timeout: 10), system.debugDescription)
        XCTAssertTrue(permission.staticTexts.matching(NSPredicate(format:
            "label CONTAINS[c] %@", "Photos")).firstMatch.exists)
        let choices = permission.buttons.matching(NSPredicate(format: allow
            ? "label CONTAINS[c] 'Allow' AND NOT (label BEGINSWITH[c] 'Don')"
            : "label CONTAINS[c] 'Allow' AND label BEGINSWITH[c] 'Don'"))
        XCTAssertEqual(choices.count, 1, system.debugDescription)
        choices.firstMatch.tap()
        let result = app.alerts["Image"]
        XCTAssertTrue(result.waitForExistence(timeout: 15), app.debugDescription)
        let expected = allow ? "Image saved to Photos."
            : "Allow Ledger to add photos in Settings, then try saving again."
        XCTAssertTrue(result.staticTexts[expected].waitForExistence(timeout: 5), app.debugDescription)
        result.buttons["OK"].tap()
        XCTAssertTrue(result.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { save.isEnabled })
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "target-item-image-exporting").firstMatch.exists)
        XCTAssertTrue(app.images["target-item-image-rendered"].waitForExistence(timeout: 5))
        if !allow {
            // Denied access stays explicit on retry, without another OS prompt.
            save.tap()
            XCTAssertTrue(result.waitForExistence(timeout: 5))
            XCTAssertTrue(result.staticTexts[expected].waitForExistence(timeout: 5))
            result.buttons["OK"].tap()
            XCTAssertTrue(result.waitForNonExistence(timeout: 5))
            XCTAssertTrue(waitUntil { save.isEnabled })
        }
    }

    func testDownloadedItemImageSwipeNavigationAndDismissal() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-images"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let item = app.buttons["target-physical-item-physical-ui-chair"]
        reveal(item, in: app)
        item.tap()
        let open = app.buttons["target-item-images-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        openItemImages(in: app)
        let viewer = app.otherElements["target-item-image-viewer"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(viewer.frame.height, app.frame.height * 0.85,
            "The iPhone viewer must occupy the screen, not a partial-height sheet")
        let share = app.buttons["target-item-image-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        let activity = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10), app.debugDescription)
        let dismissShare = app.otherElements["PopoverDismissRegion"].firstMatch
        XCTAssertTrue(waitUntil { dismissShare.isHittable }, app.debugDescription)
        dismissShare.tap()
        XCTAssertTrue(activity.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { share.isEnabled })
        XCTAssertFalse(app.alerts["Image"].exists, "Canceling Share is not an export error")
        let rendered = app.images["target-item-image-rendered"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 10))
        let count = app.staticTexts["target-item-images-counter"]
        rendered.swipeLeft()
        XCTAssertTrue(waitUntil { self.displayedText(count) == "2 of 2" })
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        rendered.swipeRight()
        XCTAssertTrue(waitUntil { self.displayedText(count) == "1 of 2" })
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        let fitFrame = rendered.frame
        let viewportCenter = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: fitFrame.midX, dy: fitFrame.midY))
        rendered.pinch(withScale: 2, velocity: 1)
        let zoomOut = app.buttons["target-item-image-zoom-out"]
        XCTAssertTrue(waitUntil { zoomOut.isEnabled }, "Native pinch must enlarge the image")
        tapImageControl("target-item-image-zoom-reset", in: app)
        XCTAssertTrue(waitUntil { !zoomOut.isEnabled })
        rendered.doubleTap()
        let zoom = app.staticTexts["target-item-image-zoom-level"]
        XCTAssertTrue(waitUntil { self.displayedText(zoom) == "2.5×" })
        let zoomedX = rendered.frame.minX
        viewportCenter.press(forDuration: 0.05,
            thenDragTo: viewportCenter.withOffset(CGVector(dx: -60, dy: 0)))
        XCTAssertTrue(waitUntil { abs(rendered.frame.minX - zoomedX) > 10 },
            "Zoomed drag must actually move the image")
        viewportCenter.press(forDuration: 0.05,
            thenDragTo: viewportCenter.withOffset(CGVector(dx: 0, dy: 100)))
        XCTAssertEqual(displayedText(count), "1 of 2", "Zoomed drags must pan, not page or dismiss")
        XCTAssertTrue(app.buttons["target-item-images-done"].exists)
        tapImageControl("target-item-image-zoom-reset", in: app)
        // Reset starts the real auto-hide timer. Verify the native image's
        // persistent zoom value, not a label that correctly disappears at fit.
        XCTAssertTrue(waitUntil { (rendered.value as? String) == "1.0× zoom" },
            "Reset must return the native image to fit, even after controls hide")
        let start = rendered.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 50)))
        XCTAssertTrue(app.buttons["target-item-images-done"].exists, "Short drag must snap back")
        rendered.swipeDown()
        XCTAssertTrue(waitUntil { !app.buttons["target-item-images-done"].exists })
        XCTAssertTrue(open.exists)
        openItemImages(in: app)
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        app.buttons["target-item-image-pin"].tap()
        let unpin = app.buttons["target-item-image-unpin"]
        XCTAssertTrue(unpin.waitForExistence(timeout: 5))
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        rendered.swipeLeft()
        let pinnedCount = app.staticTexts["target-pinned-images-counter"]
        XCTAssertTrue(waitUntil { self.displayedText(pinnedCount) == "2 of 2" })
        rendered.swipeDown()
        XCTAssertTrue(unpin.exists, "Vertical swipe must not dismiss the pinned reference\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["target-item-history-partial"].exists,
                      "The enclosing Item route must remain open after dragging its pinned image")
    }
    #endif

    private func openItemImages(in app: XCUIApplication) {
        let images = app.buttons["target-item-images-open"]
        let scroll = app.scrollViews["target-item-detail-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        reveal(images, in: app, fullyInsideScrollView: true, within: scroll)
        images.tap()
    }

    private func revealImageControls(in app: XCUIApplication) {
        let zoomIn = app.buttons["target-item-image-zoom-in"]
        // A pinned reference may remain in the accessibility tree underneath
        // this gallery. Interact with the full-screen viewer, never that image.
        // SwiftUI exposes this container as Group on macOS and Other on iOS.
        let viewer = app.descendants(matching: .any)["target-item-image-viewer"]
        let image = viewer.images["target-item-image-rendered"]
        XCTAssertTrue(image.exists || image.waitForExistence(timeout: 5))
        // Start a fresh visibility interval. Reusing controls near the end of
        // their timeout races XCTest's snapshot and event-delivery overhead.
        // Exercise the real hide/reveal gestures; do not disable auto-hide.
        // SwiftUI can retain faded controls in the accessibility tree, even
        // reporting them as hittable. Observe the gallery's visibility state;
        // subsequent control taps still verify the actual interaction.
        if (viewer.value as? String) == "Image controls visible" {
            image.tap()
            XCTAssertTrue(waitUntil { (viewer.value as? String) == "Image controls hidden" },
                "Single tap hides image controls\n\(app.debugDescription)")
        }
        image.tap()
        // XCTest's built-in existence wait polls at roughly one second. That
        // consumes most of this control's 2.2-second visibility window before
        // event delivery even starts. Poll just this transient control promptly;
        // retain the real app timer and the same five-second failure deadline.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (viewer.value as? String) == "Image controls visible" && zoomIn.isHittable { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("Single tap reveals image controls; viewer value=\(String(describing: viewer.value)), image frame=\(image.frame), image hittable=\(image.isHittable), zoom button exists=\(zoomIn.exists)\n\(app.debugDescription)")
    }

    private func assertImageCounter(_ expected: String, in app: XCUIApplication) {
        revealImageControls(in: app)
        let counter = app.staticTexts["target-item-images-counter"]
        XCTAssertTrue(counter.exists)
        XCTAssertEqual(displayedText(counter), expected)
    }

    private func tapImageControl(_ identifier: String, in app: XCUIApplication) {
        revealImageControls(in: app)
        let control = app.buttons[identifier]
        XCTAssertTrue(control.isHittable, "Image control must be revealed: \(identifier)")
        // Resolve geometry before restarting the 2.2-second visibility window.
        // Element.tap() performs additional AX lookups before dispatch, which
        // can outlast that window on CI and silently tap a now-hidden button.
        // A coordinate tap still exercises hit testing and the real gesture;
        // it avoids those repeated lookups. Never retry the action (Next wraps).
        let frame = control.frame
        XCTAssertFalse(frame.isEmpty)
        let point = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        revealImageControls(in: app)
        point.tap()
    }

    func testDownloadedItemGroupsAndImmediateSource() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_ISOLATED_CI_CLIPBOARD"] == "true" else {
            throw XCTSkip("Item Copy checks use only the disposable CI clipboard")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist", "--ledger-ui-test-item-groups",
                               "--ledger-ui-test-reset-inventory-section"]
        app.launch()
        defer { app.terminate() }
        let inventory = app.buttons["target-business-inventory-card"]
        XCTAssertTrue(inventory.waitForExistence(timeout: 10))
        inventory.tap()
        let expand = app.buttons["target-item-group-expand-group-a"]
        reveal(expand, in: app)
        XCTAssertTrue(expand.exists)
        XCTAssertTrue(expand.label.contains("×2") || (expand.value as? String)?.contains("×2") == true)
        let first = app.buttons["target-physical-item-group-a"]
        let second = app.buttons["target-physical-item-group-b"]
        let other = app.buttons["target-physical-item-group-c"]
        XCTAssertFalse(first.exists)
        XCTAssertFalse(second.exists)
        reveal(other, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(other.exists)
        let source = app.staticTexts["target-item-source-group-a"]
        reveal(source, in: app, upwards: false, fullyInsideScrollView: true)
        XCTAssertTrue(source.label == "Design Inventory" || (source.value as? String) == "Design Inventory")
        let groupSelect = app.buttons["target-item-group-select-group-a"]
        #if os(iOS)
        XCTAssertGreaterThanOrEqual(groupSelect.frame.width, 44)
        XCTAssertGreaterThanOrEqual(groupSelect.frame.height, 44)
        #endif
        groupSelect.tap()
        let count = app.staticTexts["target-items-selected-count"]
        XCTAssertTrue(waitUntil { count.label == "2 selected" || (count.value as? String) == "2 selected" })
        let copyIDs = app.buttons["target-items-copy-ids"]
        reveal(copyIDs, in: app, fullyInsideScrollView: true)
        copyIDs.tap()
        #if os(macOS)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "group-a\ngroup-b")
        #else
        assertPastedItemIDs("group-a\ngroup-b", in: app)
        #endif
        reveal(count, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(waitUntil { self.displayedText(count) == "2 selected" })
        reveal(expand, in: app, fullyInsideScrollView: true)
        expand.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        expand.tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 5))
        XCTAssertFalse(second.exists)
        XCTAssertTrue(other.exists)
        expand.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        reveal(second, in: app)
        second.tap()
        XCTAssertTrue(waitUntil { count.label == "1 selected" || (count.value as? String) == "1 selected" })
        XCTAssertFalse(app.staticTexts["target-item-history-partial"].exists)
        reveal(groupSelect, in: app)
        groupSelect.tap()
        XCTAssertTrue(waitUntil { count.label == "2 selected" || (count.value as? String) == "2 selected" })
        let filters = app.descendants(matching: .any).matching(identifier: "target-items-filters").firstMatch
        reveal(filters, in: app, fullyInsideScrollView: true)
        filters.tap()
        #if os(macOS)
        app.menuItems["Source"].tap()
        XCTAssertFalse(app.menuItems["Store"].exists)
        app.menuItems["Design Inventory"].tap()
        #else
        app.buttons["Source"].tap()
        XCTAssertFalse(app.buttons["Store"].exists)
        app.buttons["Design Inventory"].tap()
        #endif
        XCTAssertTrue(expand.waitForNonExistence(timeout: 5))
        XCTAssertTrue(other.exists)
        XCTAssertTrue(waitUntil { count.label == "0 selected" || (count.value as? String) == "0 selected" })
        app.buttons["target-items-filters-clear"].tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        reveal(count, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(waitUntil { count.label == "0 selected" || (count.value as? String) == "0 selected" })
        if !first.exists {
            reveal(expand, in: app, fullyInsideScrollView: true)
            expand.tap()
            XCTAssertTrue(first.waitForExistence(timeout: 5))
        }
        // Menus must belong to the clicked Item, not another thumbnail or
        // the last Item sharing this native List cell.
        let retryThumbnail = app.buttons["target-item-thumbnail-retry-group-c"]
        reveal(retryThumbnail, in: app, fullyInsideScrollView: true)
        #if os(iOS)
        XCTAssertGreaterThanOrEqual(retryThumbnail.frame.width, 44)
        XCTAssertGreaterThanOrEqual(retryThumbnail.frame.height, 44)
        #endif
        retryThumbnail.tap()
        XCTAssertTrue(other.exists)
        for (row, expected) in [(other, "group-c"), (first, "group-a")] {
            reveal(row, in: app, fullyInsideScrollView: true)
            #if os(macOS)
            row.rightClick()
            let copyID = app.menuItems["Copy ID"]
            #else
            row.press(forDuration: 1)
            let copyID = app.buttons["Copy ID"]
            #endif
            XCTAssertTrue(copyID.waitForExistence(timeout: 5), app.debugDescription)
            copyID.tap()
            #if os(macOS)
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected)
            #else
            assertPastedItemIDs(expected, in: app)
            #endif
        }
        reveal(count, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(waitUntil { self.displayedText(count) == "0 selected" })
    }

    #if os(iOS)
    private func assertPastedItemIDs(_ expected: String, in app: XCUIApplication) {
        // Reuse the explicit native paste receiver used by report Copy tests.
        // Reading UIPasteboard.string in the background runner blocked CI until
        // its five-minute timeout; this exercises actual copied bytes instead.
        let paste = app.buttons["target-ui-fixture-paste-report"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        XCTAssertTrue(paste.isEnabled)
        paste.tap()
        let result = app.staticTexts["target-ui-fixture-paste-result"]
        XCTAssertTrue(waitUntil { self.displayedText(result) == expected }, app.debugDescription)
    }
    #endif

    func testDownloadedItemWorkflowStatusAndBookmarkFilters() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ledger-ui-test-workspace-checklist"]
        app.launch()
        defer { app.terminate() }
        let project = app.buttons["target-active-project-card-project-ui-test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let chair = app.buttons["target-physical-item-physical-ui-chair"]
        let returned = app.buttons["target-physical-item-physical-ui-other-space"]
        let unset = app.buttons["target-physical-item-physical-ui-unassigned"]
        reveal(chair, in: app)
        let status = app.staticTexts["target-item-workflow-status-physical-ui-chair"]
        XCTAssertTrue(waitUntil {
            status.label == "Workflow: To Purchase" || (status.value as? String) == "Workflow: To Purchase"
        })
        XCTAssertTrue(app.images["target-item-bookmark-physical-ui-chair"].exists)
        let filters = app.descendants(matching: .any).matching(identifier: "target-items-filters").firstMatch
        func choose(_ facet: String, _ option: String) {
            // MenuButton can report hittable while clipped at the viewport edge;
            // require a real visible control before opening its native submenu.
            reveal(filters, in: app, fullyInsideScrollView: true)
            filters.tap()
            #if os(macOS)
            XCTAssertTrue(app.menuItems[facet].waitForExistence(timeout: 5), app.debugDescription)
            app.menuItems[facet].tap()
            let choice = app.menuItems[facet].menuItems[option]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
            choice.tap()
            #else
            XCTAssertTrue(app.buttons[facet].waitForExistence(timeout: 5), app.debugDescription)
            app.buttons[facet].tap()
            XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 5), app.debugDescription)
            app.buttons[option].tap()
            #endif
        }
        choose("Bookmark", "Not Bookmarked") // All-except: only the bookmarked chair remains.
        XCTAssertTrue(chair.waitForExistence(timeout: 5))
        XCTAssertFalse(returned.exists)
        XCTAssertFalse(unset.exists)
        choose("Workflow Status", "To Purchase")
        XCTAssertTrue(app.staticTexts["target-items-no-match"].waitForExistence(timeout: 5))
        app.buttons["target-items-filters-clear"].tap()
        choose("Workflow Status", "None")
        choose("Workflow Status", "Returned")
        XCTAssertTrue(returned.waitForExistence(timeout: 5))
        XCTAssertFalse(chair.exists)
        XCTAssertFalse(unset.exists)
        choose("Workflow Status", "Not Set") // Only mode: OR within the facet.
        XCTAssertTrue(unset.waitForExistence(timeout: 5))
        reveal(returned, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(returned.exists)
        choose("Bookmark", "Bookmarked")
        reveal(unset, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(unset.exists) // Absent source bookmark retains Not Bookmarked behavior.
        reveal(returned, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(returned.exists)
        app.buttons["target-items-filters-clear"].tap()
        reveal(chair, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(chair.waitForExistence(timeout: 5))
        XCTAssertTrue(returned.exists)
        XCTAssertTrue(unset.exists)
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
        XCTAssertTrue(app.buttons["target-items-group-accountedFor"].exists)
        reveal(app.buttons["target-items-group-relationshipEvidenceIncomplete"], in: app, fullyInsideScrollView: true)
        XCTAssertTrue(app.buttons["target-items-group-relationshipEvidenceIncomplete"].exists)
        XCTAssertFalse(app.buttons["target-items-group-unaccountedFor"].exists)
        let itemSearch = app.textFields["target-items-search"]
        reveal(itemSearch, in: app, fullyInsideScrollView: true)
        itemSearch.tap()
        itemSearch.typeText("no matching item")
        #if os(iOS)
        app.keyboards.buttons["Search"].tap()
        #endif
        XCTAssertTrue(app.staticTexts["target-items-no-match"].waitForExistence(timeout: 5))
        XCTAssertFalse(item.exists)
        app.buttons["target-items-search-clear"].tap()
        reveal(item, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        let itemFilters = app.descendants(matching: .any).matching(identifier: "target-items-filters").firstMatch
        let selectedCount = app.staticTexts["target-items-selected-count"]
        func assertSelectedCount(_ count: Int) {
            // Clearing filters can enlarge the enclosing list cell and move
            // this label offscreen. Read the visible count, not a stale AX row.
            reveal(selectedCount, in: app, fullyInsideScrollView: true)
            XCTAssertTrue(waitUntil {
                selectedCount.label == "\(count) selected" || (selectedCount.value as? String) == "\(count) selected"
            }, app.debugDescription)
        }
        let chairSelection = app.buttons["target-item-select-physical-ui-chair"]
        reveal(chairSelection, in: app)
        #if os(iOS)
        XCTAssertGreaterThanOrEqual(chairSelection.frame.width, 44)
        XCTAssertGreaterThanOrEqual(chairSelection.frame.height, 44)
        #endif
        chairSelection.tap()
        assertSelectedCount(1)
        let unassignedSelectionRow = app.buttons["target-physical-item-physical-ui-unassigned"]
        reveal(unassignedSelectionRow, in: app)
        unassignedSelectionRow.tap()
        assertSelectedCount(2)
        XCTAssertFalse(app.staticTexts["target-item-history-partial"].exists)
        let clearSelection = app.buttons["target-items-selection-clear"]
        reveal(clearSelection, in: app)
        clearSelection.tap()
        assertSelectedCount(0)
        let selectAll = app.buttons["target-items-select-all"]
        reveal(selectAll, in: app, fullyInsideScrollView: true)
        #if os(iOS)
        XCTAssertGreaterThanOrEqual(selectAll.frame.height, 44 - 0.000001,
            "Select all needs a usable touch target (allowing floating-point coordinate rounding)")
        #endif
        selectAll.tap()
        assertSelectedCount(3)
        reveal(selectAll, in: app, fullyInsideScrollView: true)
        selectAll.tap()
        assertSelectedCount(0)
        reveal(selectAll, in: app, fullyInsideScrollView: true)
        selectAll.tap()
        assertSelectedCount(3)
        reveal(itemFilters, in: app)
        itemFilters.tap()
        #if os(macOS)
        app.menuItems["SKU"].tap()
        app.menuItems["No SKU"].tap()
        #else
        app.buttons["SKU"].tap()
        app.buttons["No SKU"].tap()
        #endif
        XCTAssertTrue(item.waitForNonExistence(timeout: 5))
        assertSelectedCount(1)
        XCTAssertTrue(app.buttons["target-physical-item-physical-ui-unassigned"].exists)
        app.buttons["target-items-filters-clear"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        assertSelectedCount(1) // Clearing filters does not restore discarded selections.
        reveal(unassignedSelectionRow, in: app)
        unassignedSelectionRow.tap()
        assertSelectedCount(0)
        XCTAssertFalse(app.staticTexts["target-item-history-partial"].exists)
        func chooseItemSpace(_ choice: String) {
            reveal(itemFilters, in: app, fullyInsideScrollView: true)
            itemFilters.tap()
            #if os(macOS)
            app.menuItems["Space"].tap()
            app.menuItems["Space"].menuItems[choice].tap()
            #else
            app.buttons["Space"].tap()
            app.buttons[choice].tap()
            #endif
        }
        reveal(selectAll, in: app, fullyInsideScrollView: true)
        selectAll.tap()
        assertSelectedCount(3)
        chooseItemSpace("None")
        XCTAssertTrue(app.staticTexts["target-items-no-match"].waitForExistence(timeout: 5))
        assertSelectedCount(0)
        chooseItemSpace("Empty test Space")
        XCTAssertTrue(app.staticTexts["target-items-no-match"].exists)
        chooseItemSpace("Archived test Space — archived")
        XCTAssertTrue(app.buttons["target-physical-item-physical-ui-other-space"].waitForExistence(timeout: 5))
        XCTAssertFalse(item.exists)
        XCTAssertFalse(unassignedSelectionRow.exists)
        chooseItemSpace("None")
        chooseItemSpace("No Space")
        XCTAssertTrue(unassignedSelectionRow.waitForExistence(timeout: 5))
        XCTAssertFalse(item.exists)
        XCTAssertFalse(app.buttons["target-physical-item-physical-ui-other-space"].exists)
        app.buttons["target-items-filters-clear"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        let unknownGroup = "target-items-group-relationshipEvidenceIncomplete"
        let disclosure = app.buttons[unknownGroup]
        reveal(disclosure, in: app)
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5), app.debugDescription)
        disclosure.tap()
        let elsewhere = app.buttons["target-physical-item-physical-ui-other-space"]
        let unassigned = app.buttons["target-physical-item-physical-ui-unassigned"]
        XCTAssertTrue(elsewhere.waitForNonExistence(timeout: 5))
        XCTAssertFalse(unassigned.exists)
        disclosure.tap()
        reveal(elsewhere, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(elsewhere.waitForExistence(timeout: 5))
        for (choice, unassignedFirst) in [("Oldest first", false), ("Newest first", true),
                                         ("Name A–Z", false), ("Name Z–A", true)] {
            let sort = app.descendants(matching: .any).matching(identifier: "target-items-sort").firstMatch
            reveal(sort, in: app, fullyInsideScrollView: true)
            sort.tap()
            #if os(macOS)
            app.menuItems[choice].tap()
            #else
            app.buttons[choice].tap()
            #endif
            reveal(elsewhere, in: app)
            XCTAssertTrue(unassigned.waitForExistence(timeout: 5))
            XCTAssertEqual(unassigned.frame.minY < elsewhere.frame.minY, unassignedFirst, app.debugDescription)
        }
        reveal(item, in: app)
        item.tap()
        XCTAssertTrue(app.staticTexts["target-item-history-partial"].waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(app.staticTexts["target-item-detail-current-location"]), "Current test Project")
        XCTAssertTrue(app.staticTexts["Business Inventory"].exists)
        XCTAssertTrue(app.staticTexts["Space name not downloaded"].exists)
        app.buttons["target-item-history-refresh"].tap()
        XCTAssertTrue(app.staticTexts["Current downloaded location"].waitForExistence(timeout: 5))
        app.buttons["target-item-history-done"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        let refresh = app.buttons["target-items-refresh"]
        reveal(refresh, in: app)
        refresh.tap()
        reveal(item, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        reveal(chairSelection, in: app)
        chairSelection.tap()
        assertSelectedCount(1)
        reveal(refresh, in: app, fullyInsideScrollView: true)
        refresh.tap()
        reveal(item, in: app, fullyInsideScrollView: true)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        reveal(selectedCount, in: app)
        assertSelectedCount(1) // Loading is not evidence that the selected Item was deleted.
        let remove = app.buttons["target-ui-fixture-remove-account"]
        reveal(remove, in: app, upwards: false)
        remove.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "target-workspace-access-removed").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(item.exists)
        XCTAssertFalse(refresh.exists)
        XCTAssertFalse(selectedCount.exists)
        XCTAssertFalse(selectAll.exists)
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
        // Let XCTest own disappearance polling rather than nesting its retrying
        // accessibility query inside a separate predicate timeout.
        let keyboardDismissed = app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
        if !keyboardDismissed {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Space search keyboard dismissal failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(keyboardDismissed)
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
        let expander = app.buttons["target-active-space-checklists-section"]
        XCTAssertTrue(expander.exists, app.debugDescription)
        #if os(iOS)
        XCTAssertGreaterThanOrEqual(expander.frame.height, 44)
        #endif
        let item = app.buttons["target-active-space-checklist-item-checklist-ui-test-item-ui-test"]
        // Exercise both directions regardless of the initial expansion state.
        if !item.exists {
            reveal(expander, in: app, fullyInsideScrollView: true)
            expander.tap()
        }
        reveal(item, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        reveal(expander, in: app, fullyInsideScrollView: true)
        expander.tap()
        XCTAssertTrue(waitUntil { !item.exists })
        reveal(expander, in: app, fullyInsideScrollView: true)
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
        let itemFilters = app.descendants(matching: .any).matching(identifier: "target-items-filters").firstMatch
        reveal(itemFilters, in: app)
        itemFilters.tap()
        #if os(macOS)
        XCTAssertTrue(app.menuItems["Name"].exists)
        XCTAssertFalse(app.menuItems["Space"].exists)
        app.typeKey(.escape, modifierFlags: [])
        #else
        XCTAssertTrue(app.buttons["Name"].exists)
        XCTAssertFalse(app.buttons["Space"].exists)
        // Choosing the already-active All option dismisses the native menu
        // without targeting the system status bar or changing the result set.
        app.buttons["Name"].tap()
        app.buttons["All"].tap()
        XCTAssertTrue(app.buttons["Name"].waitForNonExistence(timeout: 5))
        #endif
        reveal(physicalItem, in: app)
        physicalItem.tap()
        XCTAssertTrue(app.staticTexts["target-item-history-partial"].waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(app.buttons["target-item-detail-space"]), "Current test Space")
        XCTAssertTrue(app.staticTexts["Current downloaded location"].exists)
        if inventory {
            XCTAssertEqual(displayedText(app.staticTexts["target-item-detail-current-location"]), "Business Inventory")
        } else {
            XCTAssertEqual(displayedText(app.staticTexts["target-item-detail-current-location"]), "Current test Project")
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

    private func transactionDetailBack(in app: XCUIApplication) -> XCUIElement {
        #if os(iOS)
        return app.buttons["BackButton"].firstMatch
        #else
        return app.buttons["Done"]
        #endif
    }

    private func displayedText(_ element: XCUIElement) -> String {
        // Native macOS StaticText exposes content as AXValue, but Buttons use
        // AXLabel (their AXValue may be an empty string). Do not treat an empty
        // StaticText value as missing: exact empty-content assertions stay exact.
        #if os(macOS)
        if element.elementType == .button { return element.label }
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

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true,
                        fullyInsideScrollView: Bool = false, within scrollView: XCUIElement? = nil) {
        #if os(iOS)
        let workspace = app.scrollViews["target-workspace-scroll"]
        let list = scrollView ?? (workspace.exists ? workspace : app.collectionViews.firstMatch)
        #elseif os(macOS)
        let list = scrollView ?? app.scrollViews.firstMatch
        #endif
        XCTAssertTrue(list.exists)
        for _ in 0..<6 {
            // XCTest's predicate wait polls after a second even for rows
            // already present. Keep that wait only for genuinely missing rows.
            if element.exists || element.waitForExistence(timeout: 1) {
                // macOS can report a TextField hittable when only its bottom
                // few pixels intersect the list; tapping its clipped center
                // then focuses the Outline instead of the input.
                if fullyInsideScrollView {
                    // A fully visible first row may touch the scroll view's
                    // top edge. An inset incorrectly makes it unrevealable.
                    // AppKit reports some LabeledContent text one point
                    // outside the scroll frame despite fully visible pixels.
                    let viewport = list.frame.insetBy(dx: -1, dy: -1)
                    if viewport.contains(element.frame), element.isHittable { return }
                    #if os(macOS)
                    // A full swipe overshoots this short field in the 366-point
                    // CI viewport and alternates between opposite clipped edges.
                    // Move by the measured distance instead of another page.
                    list.scroll(byDeltaX: 0, deltaY: viewport.midY - element.frame.midY)
                    #else
                    if element.frame.midY < viewport.midY { list.swipeDown() }
                    else { list.swipeUp() }
                    #endif
                    continue
                }
                if element.isHittable { return }
                // Once a row exists, scroll toward its measured position.
                // Repeating swipeUp after overshooting a short Item row moves
                // it farther above the viewport on every attempt.
                if !element.frame.isEmpty {
                    let viewport = list.frame.insetBy(dx: 0, dy: 2)
                    #if os(macOS)
                    list.scroll(byDeltaX: 0, deltaY: viewport.midY - element.frame.midY)
                    #else
                    if element.frame.midY < viewport.midY { list.swipeDown() }
                    else { list.swipeUp() }
                    #endif
                    continue
                }
            }
            #if os(macOS)
            // Drag-style swipes may activate a row while searching for an
            // offscreen element. Use a wheel event, as in the measured path.
            list.scroll(byDeltaX: 0, deltaY: upwards ? -list.frame.height * 0.6 : list.frame.height * 0.6)
            #else
            if upwards { list.swipeUp() } else { list.swipeDown() }
            #endif
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
        if fullyInsideScrollView {
            XCTAssertTrue(list.frame.insetBy(dx: -1, dy: -1).contains(element.frame), app.debugDescription)
        }
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() }, object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
