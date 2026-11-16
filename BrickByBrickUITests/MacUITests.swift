#if os(macOS)
import XCTest

final class MacUITests: XCTestCase {
    @MainActor func testPracticeChecklistEditingAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-ui-testing", "-appLanguage", "english", "-AppleLanguages", "(en)"]
        app.launch()
        app.activate()
        let latest = app.descendants(matching: .any)["saved-set-sample-1"]
        if latest.waitForExistence(timeout: 2) {
            XCTAssertFalse(app.buttons["sampleSet"].exists)
            latest.click()
        } else {
            let sample = app.buttons["sampleSet"]
            XCTAssertTrue(sample.waitForExistence(timeout: 10))
            sample.click()
            let start = app.buttons["startChecklist"]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            start.click()
        }
        let options = app.descendants(matching: .any)["part-options-1"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.click()
        app.menuItems["Set quantity…"].click()
        let input = app.textFields["quantityInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeKey("a", modifierFlags: .command)
        input.typeText("3")
        app.buttons["Save"].click()

        let quantity = app.descendants(matching: .any)["quantity-1"]
        XCTAssertTrue(quantity.label.hasPrefix("3 of 8 found"), quantity.debugDescription)
        app.buttons["plus-1"].click()
        XCTAssertTrue(quantity.label.hasPrefix("4 of 8 found"), quantity.debugDescription)
        app.buttons["undo-1"].click()
        XCTAssertTrue(quantity.label.hasPrefix("3 of 8 found"), quantity.debugDescription)
        XCTAssertEqual(app.buttons["plus-1"].frame.midY, app.buttons["plus-2"].frame.midY, accuracy: 2)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "macOS brick board"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launch()
        app.activate()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sampleSet"].exists)
        let homeScreenshot = XCTAttachment(screenshot: app.screenshot())
        homeScreenshot.name = "Home with latest saved set"
        homeScreenshot.lifetime = .keepAlways
        add(homeScreenshot)
        app.buttons["appSettings"].click()
        XCTAssertTrue(app.secureTextFields["apiKeyInput"].waitForExistence(timeout: 5), "The gear should open Settings")
        app.typeKey("w", modifierFlags: .command)
        latest.click()
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertTrue(quantity.label.hasPrefix("3 of 8 found"), quantity.debugDescription)
    }
}
#endif
