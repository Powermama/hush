import XCTest

final class PermissionJourneyTests: XCTestCase {
    func testLandingShowsWorkflowsAndModelsStayInContext() {
        let app = launch("--preview-hush-ai", "--preview-light-appearance")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Open Live Write"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Assistant"].exists)
        XCTAssertFalse(app.staticTexts["Model library"].exists)
        XCTAssertFalse(app.staticTexts["Kokoro"].exists)
        XCTAssertFalse(app.scrollViews.firstMatch.buttons["Live Write"].exists) // No duplicate sidebar entry.
        attach(app, "hush AI - light")
        app.buttons["Permissions"].click()
        XCTAssertTrue(app.staticTexts["Microphone"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Screen Recording"].exists)
        app.buttons["hush AI"].click()
        app.buttons["Open Assistant"].click()
        XCTAssertTrue(app.switches["hush.assistant.enabled"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Screen Recording"].exists)
        XCTAssertTrue(app.staticTexts["hush.assistant.screen.status"].exists)
        // The AI model comes first as its own list, ChatGPT last; listening and voice follow.
        XCTAssertTrue(app.staticTexts["AI model"].exists)
        XCTAssertTrue(app.staticTexts["Required models"].exists)
        XCTAssertTrue(app.staticTexts["ChatGPT"].exists)
        XCTAssertTrue(app.staticTexts["Kokoro"].exists)
        XCTAssertTrue(app.staticTexts["hush.assistant.privacy"].exists)
        XCTAssertTrue(app.staticTexts["hush.assistant.local-processing"].exists)
        XCTAssertFalse(app.buttons["Test voice"].exists)
        attach(app, "Assistant - light")
        app.buttons["control-center-back"].click()
        XCTAssertTrue(app.buttons["Open Live Write"].waitForExistence(timeout: 3))
    }

    func testLiveWriteUsesSharedModelsAndKeepsOptionalPersonas() {
        let app = launch("--preview-hush-ai", "--preview-light-appearance")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Open Live Write"].waitForExistence(timeout: 5))
        app.buttons["Open Live Write"].click()
        XCTAssertTrue(app.staticTexts["What it does"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.radioButtons["Polish"].exists)
        XCTAssertTrue(app.staticTexts["Writing engine"].exists)
        attach(app, "Live Write - light")
        app.buttons["Edit Polish"].click()
        XCTAssertTrue(app.staticTexts["Make this persona yours"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].click()
        app.buttons["Add Persona"].click()
        XCTAssertTrue(app.menuItems["Clean Up My Words"].waitForExistence(timeout: 2))
        app.menuItems["Clean Up My Words"].click()
        XCTAssertTrue(app.staticTexts["Create a persona"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["Apple Intelligence"].exists)
        XCTAssertTrue(app.staticTexts["ChatGPT"].exists, "The ChatGPT plan is one of the engines")
        let model = modelControl("qwen35_4b", in: app)
        XCTAssertTrue(model.exists)
        reveal(model, in: app)
        attach(app, "Live Write - engines expanded")
        if model.label == "More options for Qwen 3.5 4B" {
            model.click()
            app.menuItems["Remove Qwen 3.5 4B…"].click()
            XCTAssertTrue(app.staticTexts["Remove Qwen 3.5 4B?"].waitForExistence(timeout: 3))
            app.sheets.buttons["Cancel"].click()
        }
    }

    func testAISettingsInDarkAppearance() {
        let app = launch("--preview-hush-ai", "--preview-dark-appearance")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Open Live Write"].waitForExistence(timeout: 5))
        attach(app, "hush AI - dark")
        app.buttons["Open Live Write"].click()
        XCTAssertTrue(app.radioButtons["Polish"].waitForExistence(timeout: 3))
        attach(app, "Live Write - dark")
        reveal(modelControl("qwen35_4b", in: app), in: app)
        attach(app, "Live Write - engines dark")
        app.buttons["control-center-back"].click()
        app.buttons["Open Assistant"].click()
        XCTAssertTrue(app.switches["hush.assistant.enabled"].waitForExistence(timeout: 3))
        attach(app, "Assistant - dark")
    }

    func testCompactWindowKeepsNavigationAndModelsReachable() {
        let app = launch("--preview-hush-ai", "--preview-light-appearance", "--preview-compact-window")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Open Assistant"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Live Write"].isHittable)
        attach(app, "hush AI - compact")
        XCTAssertTrue(app.staticTexts["hush.ai.assistant.status"].exists)
        app.buttons["Open Assistant"].click()
        let voice = modelControl("kokoro", in: app)
        reveal(voice, in: app)
        XCTAssertTrue(voice.isHittable)
        attach(app, "Assistant - models compact")
    }

    func testOneSetupButtonCanCancelAndResume() {
        let app = launch("--preview-assistant-settings", "--preview-light-appearance", "--preview-assistant-setup-flow", "-assistant.enabled.v1", "YES")
        defer { app.terminate() }
        let setup = app.buttons["hush.assistant.action"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.click()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.buttons["Resume setup"].waitForExistence(timeout: 4))
        app.buttons["Resume setup"].click()
        XCTAssertTrue(app.staticTexts["Ready. Hold Control + Fn in any app to talk."].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["Cancel"].isHittable)
        XCTAssertFalse(setup.isHittable)
        attach(app, "Assistant - setup completed fixture")
    }

    func testKokoroRemovalExplainsEffectAndCanBeCancelled() throws {
        let app = launch("--preview-assistant-settings", "--preview-light-appearance")
        defer { app.terminate() }
        let voice = modelControl("kokoro", in: app)
        XCTAssertTrue(voice.waitForExistence(timeout: 5))
        guard voice.label == "More options for Kokoro" else { throw XCTSkip("Requires existing local Kokoro files; never downloads test assets.") }
        for _ in 0..<4 where !voice.isHittable { app.scrollViews.element(boundBy: 1).swipeUp() }
        voice.click()
        attach(app, "Kokoro - native model menu")
        app.menuItems["Remove Kokoro…"].click()
        XCTAssertTrue(app.staticTexts["Remove Kokoro?"].waitForExistence(timeout: 3))
        attach(app, "Kokoro - removal confirmation")
        app.sheets.buttons["Cancel"].click()
        XCTAssertFalse(app.staticTexts["Remove Kokoro?"].exists)
        XCTAssertEqual(voice.label, "More options for Kokoro")
    }

    func testKokoroShowsExplicitFilePercentage() {
        let app = launch("--preview-assistant-settings", "--preview-light-appearance", "--preview-kokoro-download")
        defer { app.terminate() }
        let progress = app.staticTexts["Downloading voice file 3 · 62%"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        reveal(progress, in: app)
        attach(app, "Assistant - download percentage fixture")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.scrollViews.element(boundBy: 1).swipeUp() }
        for _ in 0..<8 where !element.isHittable { app.scrollViews.element(boundBy: 1).swipeDown() }
    }

    private func modelControl(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "hush.ai.model.\(id)").firstMatch
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
