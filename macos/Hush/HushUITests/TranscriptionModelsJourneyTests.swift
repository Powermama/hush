import XCTest

/// TM-001, TM-002, TM-005 from docs/user-journeys/transcription-models.md, driven through
/// the real settings window and the live dictation coordinator.
///
/// Requires Parakeet Redux on this Mac (run FluidAudioTranscriberIntegrationTests first,
/// or download it once from Settings). The journey activates Redux, so it changes the
/// selected model in the app's defaults.
final class TranscriptionModelsJourneyTests: XCTestCase {
    func testUserOpensParakeetAndActivatesADownloadedModel() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-didCompleteOnboarding", "YES",
            "--open-transcription-settings",
        ]
        app.launch()

        let hero = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Active model, '"))
            .firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "The active model card is missing")

        let parakeet = app.buttons["Parakeet models"]
        XCTAssertTrue(parakeet.waitForExistence(timeout: 5), "The Parakeet engine card is missing")
        XCTAssertTrue(app.buttons["Whisper models"].exists, "The Whisper engine card is missing")
        parakeet.click()

        XCTAssertTrue(app.staticTexts["Parakeet Ultra"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["25 languages · Sep 2026"].exists)
        XCTAssertTrue(app.staticTexts["603 MB"].exists)
        XCTAssertTrue(app.staticTexts["Parakeet Redux"].exists)

        let info = app.buttons["About Parakeet Ultra"]
        XCTAssertTrue(info.exists, "Model rows have no info button")
        info.click()
        let license = app.staticTexts["CC-BY-4.0"]
        XCTAssertTrue(license.waitForExistence(timeout: 3), "The model details popover did not open")
        let details = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        details.name = "Parakeet Ultra details popover"
        details.lifetime = .keepAlways
        add(details)
        app.typeKey(.escape, modifierFlags: [])

        let useRedux = app.buttons["Use Parakeet Redux"]
        if useRedux.waitForExistence(timeout: 3) {
            useRedux.click()
        }

        let back = app.buttons["control-center-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "The engine page has no back button")
        XCTAssertEqual(back.title, "Transcription")
        back.click()

        let activeRedux = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Active model, Parakeet Redux'"))
            .firstMatch
        XCTAssertTrue(activeRedux.waitForExistence(timeout: 10), "Redux did not become the active model")
        let ready = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Active model, Parakeet Redux' AND label ENDSWITH 'Ready'"))
            .firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 120), "Redux never reached Ready")

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Transcription overview with Parakeet Redux active"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
