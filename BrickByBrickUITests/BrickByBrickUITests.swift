#if os(iOS)
import XCTest
import UIKit

final class BrickByBrickUITests: XCTestCase {
    /// Uses the app's separate UI-test collection, so tests never open or reset real sets.
    private static func testApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-appLanguage", "english", "-AppleLanguages", "(en)"]
        return app
    }

    @MainActor func testCollectionExportAndImportControls() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = Self.testApp()
        defer { app.terminate() }
        app.launch()
        openPracticeChecklist(app)
        app.buttons["BackButton"].firstMatch.tap()
        app.buttons["appSettings"].tap()
        let export = app.buttons["exportCollection"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        for _ in 0..<4 where !export.isHittable { app.swipeUp() }
        export.tap()
        XCTAssertTrue(app.buttons["shareCollection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveCollectionFile"].exists)
        saveScreenshot(app, named: "Collection export")
        app.buttons["Done"].firstMatch.tap()
        let importer = app.buttons["importCollection"]
        for _ in 0..<4 where !importer.isHittable { app.swipeUp() }
        importer.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 5))
        saveScreenshot(app, named: "Collection import picker")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["importCollection"].exists)
    }

    @MainActor func testIPadRotationGridAndQuantitySheet() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Tablet layout test")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = Self.testApp()
        app.launch()
        openPracticeChecklist(app)
        XCTAssertTrue(app.buttons["Checklist options"].waitForExistence(timeout: 5))
        app.buttons["Checklist options"].tap()
        app.buttons["Reset checklist"].tap()
        app.buttons["Reset checklist"].tap()
        XCTAssertTrue(app.buttons["plus-1"].isHittable, "The first brick action should be visible without scrolling past a banner")
        XCTAssertTrue(app.buttons["plus-2"].isHittable)
        XCTAssertEqual(app.buttons["plus-1"].frame.midY, app.buttons["plus-2"].frame.midY, accuracy: 2,
                       "iPad portrait should have two columns, including iPad mini")
        saveScreenshot(app, named: "iPad checklist portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: landscape, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        let first = app.descendants(matching: .any)["quantity-1"]
        let second = app.descendants(matching: .any)["quantity-2"]
        if !first.isHittable { app.swipeUp() }
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(second.isHittable)
        XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 2, "Wide windows should show two columns")
        XCTAssertGreaterThan(second.frame.minX, first.frame.maxX)
        XCTAssertLessThanOrEqual(second.frame.maxX, app.frame.maxX, "The right column must fit in the app window")
        saveScreenshot(app, named: "iPad checklist landscape")

        app.buttons["part-options-1"].tap()
        app.buttons["Set quantity…"].tap()
        let input = app.textFields["quantityInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "3")
        XCUIDevice.shared.orientation = .portrait
        // On iOS 27 the sheet's accessibility frames stay at their pre-rotation positions, so taps
        // and isHittable probe the board behind it. Prove the editor still works by saving with Return.
        XCTAssertTrue(input.waitForExistence(timeout: 5), "The editor should stay open after rotation")
        XCTAssertEqual(input.value as? String, "3")
        saveScreenshot(app, named: "iPad quantity editor")
        app.typeText("\n")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "3 of 8 found")).firstMatch.waitForExistence(timeout: 5))

        app.buttons["BackButton"].firstMatch.tap()
        let settings = app.buttons["appSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings should open from the gear on the Sets page")
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["catalogSettings"].firstMatch.waitForExistence(timeout: 5))
        saveScreenshot(app, named: "iPad settings portrait")
    }

    @MainActor private func openPracticeChecklist(_ app: XCUIApplication) {
        // Saved cards live in a lazy grid, so they only exist once scrolled near; at large
        // text sizes they can start well below the screen. Scroll until either entry appears.
        let latest = app.descendants(matching: .any)["saved-set-sample-1"]
        let sample = app.buttons["sampleSet"]
        XCTAssertTrue(app.buttons["appSettings"].waitForExistence(timeout: 5))
        for _ in 0..<10 where !(latest.exists && latest.isHittable) && !(sample.exists && sample.isHittable) {
            app.swipeUp()
        }
        if latest.exists && latest.isHittable {
            XCTAssertFalse(sample.exists)
            latest.tap()
        } else {
            XCTAssertTrue(sample.isHittable, "Neither the saved practice set nor the practice entry was reachable")
            sample.tap()
            let start = app.buttons["startChecklist"]
            for _ in 0..<5 where !start.isHittable { app.swipeUp() }
            start.tap()
        }
    }

    @MainActor private func saveScreenshot(_ app: XCUIApplication, named name: String) {
        // Capture the display directly: application screenshots may retain the old
        // crop rectangle after iPad rotation and produce a clipped attachment.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testSampleChecklistPersistsAndFilters() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = Self.testApp()
        app.launch()
        openPracticeChecklist(app)
        let options = app.buttons["Checklist options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        app.buttons["Reset checklist"].tap()
        app.buttons["Reset checklist"].tap()
        let plus = app.buttons["plus-1"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["undo-1"].isEnabled)
        XCTAssertEqual(app.descendants(matching: .any)["quantity-1"].value as? String, "8 to find")
        plus.tap()
        plus.tap()
        XCTAssertEqual(app.descendants(matching: .any)["quantity-1"].value as? String, "6 to find")
        app.buttons["undo-1"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["quantity-1"].value as? String, "7 to find")
        plus.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "2 of 8 found")).firstMatch.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["saved-set-sample-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sampleSet"].exists)
        app.descendants(matching: .any)["saved-set-sample-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "2 of 8 found")).firstMatch.waitForExistence(timeout: 5))
        let originalPosition = app.buttons["part-options-1"].frame.minY
        for _ in 0..<6 { app.buttons["plus-1"].tap() }
        XCTAssertEqual(app.descendants(matching: .any)["quantity-1"].value as? String, "All found")
        XCTAssertFalse(app.buttons["plus-1"].exists, "Completed cards cannot add too many pieces")
        XCTAssertEqual(app.buttons["part-options-1"].frame.minY, originalPosition, accuracy: 2,
                       "Completing a brick should keep its card in place")
        saveScreenshot(app, named: "Brick board completed card")
        app.buttons["undo-1"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["quantity-1"].value as? String, "1 to find")
        XCTAssertTrue(app.buttons["plus-1"].isHittable)
        app.buttons["part-options-1"].tap()
        app.buttons["check-1"].tap()
        app.buttons["boardFilters"].tap()
        app.buttons["Still missing"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["quantity-1"].exists)
        app.buttons["Found"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quantity-1"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Checklist after relaunch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testBoardAtAccessibilityTextSize() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = Self.testApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openPracticeChecklist(app)
        let options = app.buttons["Checklist options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        app.buttons["Reset checklist"].tap()
        app.buttons["Reset checklist"].tap()
        let plus = app.buttons["plus-1"]
        for _ in 0..<5 where !plus.isHittable { app.swipeUp() }
        XCTAssertTrue(plus.isHittable)
        XCTAssertGreaterThanOrEqual(plus.frame.height, 44)
        XCTAssertLessThanOrEqual(plus.frame.maxX, app.frame.maxX)
        plus.tap()
        XCTAssertEqual(app.descendants(matching: .any)["quantity-1"].value as? String, "7 to find")
        saveScreenshot(app, named: "Brick board accessibility text")
    }
}

#endif
