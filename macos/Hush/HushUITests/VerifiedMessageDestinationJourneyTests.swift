import XCTest

final class VerifiedMessageDestinationJourneyTests: XCTestCase {
    func testSmartDestinationExceptionsStayCompactAndManageWebsites() throws {
        let usesLiveWebsiteIcon = ProcessInfo.processInfo.environment["HUSH_LIVE_FAVICON_E2E"] == "1"
        let websiteHost = usesLiveWebsiteIcon ? "apple.com" : "hush-destination-test.example"
        let app = XCUIApplication()
        app.launchArguments = [
            "--preview-verified-messages",
            "-verifiedMessages.enabled.v1", "YES",
            "-verifiedMessages.destinationMode.v1", "smart",
        ]
        if !usesLiveWebsiteIcon {
            app.launchArguments.append("--website-icon-test-fixture")
        }
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Where signatures appear"].waitForExistence(timeout: 5),
            "Typed with hush should expose destination controls in its existing settings page"
        )
        XCTAssertTrue(app.staticTexts["Signature destinations"].exists)
        XCTAssertTrue(app.popUpButtons["hush.verified.destinationMode"].exists)

        let manage = app.buttons["hush.verified.destinationExceptions"]
        XCTAssertTrue(manage.exists)
        manage.click()

        XCTAssertTrue(app.staticTexts["Destination Exceptions"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Sensitive destinations"].exists)
        XCTAssertTrue(app.staticTexts["Automatic"].exists)
        XCTAssertTrue(app.staticTexts["Terminal apps and browser address or search fields"].exists)

        let addApps = app.buttons["hush.verified.addException"]
        XCTAssertEqual(addApps.label, "Add Apps\u{2026}")
        addApps.click()
        XCTAssertTrue(
            app.staticTexts["Select multiple apps with Command-click or Shift-click."].waitForExistence(
                timeout: 2
            ),
            "The native Applications picker should make multi-selection discoverable"
        )
        let picker = app.sheets.containing(
            .staticText,
            identifier: "Select multiple apps with Command-click or Shift-click."
        ).firstMatch
        XCTAssertTrue(picker.exists)
        let appSearch = picker.searchFields.firstMatch
        XCTAssertTrue(appSearch.exists, "The app picker should expose native application search")
        appSearch.click()
        appSearch.typeText("Calculator")
        let calculatorResult = picker.textFields.matching(
            NSPredicate(format: "value == %@", "Calculator.app")
        ).firstMatch
        XCTAssertTrue(
            calculatorResult.waitForExistence(timeout: 5),
            "Searching the app picker should return matching installed applications"
        )
        calculatorResult.click()
        picker.buttons["Add Apps"].click()
        XCTAssertTrue(
            app.staticTexts["Calculator"].waitForExistence(timeout: 2),
            "An application selected through search should be added to the exception list"
        )
        let removeCalculator = app.buttons["Remove Calculator"]
        XCTAssertTrue(removeCalculator.exists)
        removeCalculator.click()

        let website = app.textFields["hush.verified.websiteField"]
        XCTAssertTrue(website.exists)
        website.click()
        website.typeText(websiteHost)
        app.buttons["hush.verified.addWebsite"].click()

        XCTAssertTrue(
            app.staticTexts[websiteHost].waitForExistence(timeout: 2),
            "A website exception should be visible immediately after it is added"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "hush.verified.websiteIcon.\(websiteHost)"
            ].waitForExistence(timeout: usesLiveWebsiteIcon ? 10 : 2),
            "The website's fetched icon should replace the generic globe"
        )

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Verified Message destination exceptions"
        attachment.lifetime = .keepAlways
        add(attachment)

        let remove = app.buttons["Remove \(websiteHost)"]
        XCTAssertTrue(remove.exists)
        remove.click()
        XCTAssertFalse(app.staticTexts[websiteHost].exists)
    }
}
