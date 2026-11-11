import XCTest

final class SelectionEditorJourneyTests: XCTestCase {
    func testComposerRemainsLegibleInLightAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-selection-editor", "--preview-light-appearance"]
        app.launch()
        app.activate()

        XCTAssertTrue(app.staticTexts["Editing in Slack"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.textViews["hush.editor.compose.text"].exists)
        keepScreenshot(named: "Selection Editor Light 01 Compose")

        app.buttons["Edit with AI"].click()
        XCTAssertTrue(app.staticTexts["What would you like to do with this text?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textViews["hush.editor.ai.prompt"].exists)
        keepScreenshot(named: "Selection Editor Light 02 AI")
    }

    func testComposerRemainsLegibleInDarkAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-selection-editor", "--preview-dark-appearance"]
        app.launch()
        app.activate()

        XCTAssertTrue(app.staticTexts["Editing in Slack"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.textViews["hush.editor.compose.text"].exists)
        keepScreenshot(named: "Selection Editor Dark 01 Compose")

        app.buttons["Edit with AI"].click()
        XCTAssertTrue(app.staticTexts["What would you like to do with this text?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textViews["hush.editor.ai.prompt"].exists)
        keepScreenshot(named: "Selection Editor Dark 02 AI")
    }

    func testComposeAndConversationalAIKeepExplicitVersions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-selection-editor"]
        app.launch()
        app.activate()

        XCTAssertTrue(app.staticTexts["Editing in Slack"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Edit with AI"].exists)
        XCTAssertTrue(app.textViews["hush.editor.compose.text"].exists)
        keepScreenshot(named: "Selection Editor 01 Compose")

        app.buttons["Edit with AI"].click()
        XCTAssertTrue(app.staticTexts["What would you like to do with this text?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["hush.editor.ai.persona.none"].exists)
        let modelSelector = app.buttons["hush.editor.ai.model"]
        XCTAssertTrue(modelSelector.exists)
        XCTAssertTrue(modelSelector.label.contains("AI model"))
        modelSelector.click()
        XCTAssertTrue(app.menuItems.firstMatch.waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.popUpButtons["hush.editor.persona"].exists)
        let contextualSuggestion = app.descendants(matching: .any)["hush.editor.ai.context"]
        XCTAssertTrue(contextualSuggestion.waitForExistence(timeout: 2))
        keepScreenshot(named: "Selection Editor 02 AI Composer Empty")

        let microphone = app.buttons["hush.editor.ai.microphone"]
        XCTAssertTrue(microphone.exists)
        microphone.click()
        let voiceStatus = app.staticTexts["hush.editor.ai.voice.status"]
        XCTAssertTrue(voiceStatus.waitForExistence(timeout: 2))
        XCTAssertEqual(voiceStatus.label, "Listening…")
        keepScreenshot(named: "Selection Editor 03 Inline Voice Listening")
        microphone.click()
        XCTAssertTrue(waitForLabel("Transcribing on this Mac…", on: voiceStatus, timeout: 2))
        keepScreenshot(named: "Selection Editor 04 Inline Voice Processing")

        let prompt = app.textViews["hush.editor.ai.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 2))
        prompt.click()
        prompt.typeText("Make it shorter")
        XCTAssertFalse(app.buttons["hush.editor.ai.send"].exists)
        keepScreenshot(named: "Selection Editor 05 AI Composer Typed")
        let compactPromptHeight = prompt.frame.height
        prompt.typeKey(.return, modifierFlags: [.shift])
        XCTAssertTrue(prompt.value as? String == "Make it shorter\n")
        XCTAssertGreaterThan(prompt.frame.height, compactPromptHeight + 4)
        keepScreenshot(named: "Selection Editor 06 AI Composer Expanded")
        prompt.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(prompt.value as? String == "Make it shorter")
        prompt.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["I made it shorter while keeping the original meaning."].waitForExistence(timeout: 2))
        let thinking = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "hush.editor.ai.thinking."
        )).firstMatch
        XCTAssertTrue(thinking.waitForExistence(timeout: 2))
        XCTAssertTrue(thinking.label.contains("Thought for"))
        thinking.click()
        XCTAssertTrue(app.staticTexts[
            "Reviewed “Make it shorter” against the current text, applied the requested change, and checked the new version for completeness."
        ].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.staticTexts["People can test the microphone during onboarding, making hush easier to understand."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["What would you like to do with this text?"].exists)
        let firstMetadata = app.staticTexts["hush.editor.ai.artifact.1.metadata"]
        XCTAssertTrue(firstMetadata.waitForExistence(timeout: 2))
        XCTAssertTrue(firstMetadata.label.contains("tokens"))
        XCTAssertTrue(firstMetadata.label.contains("s · On this Mac"))

        prompt.click()
        prompt.typeText("What would you improve?")
        prompt.typeKey(.return, modifierFlags: [])
        let advice = app.staticTexts.matching(NSPredicate(
            format: "label == %@",
            "I would make the opening more direct, shorten the middle sentence, and end with the user benefit so the idea feels more confident."
        )).firstMatch
        XCTAssertTrue(advice.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["hush.editor.ai.artifact.2"].exists)

        prompt.click()
        prompt.typeText("Make it friendly")
        prompt.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["I made the tone friendlier and more natural."].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.staticTexts["People can try the microphone during onboarding, so hush feels natural from the very first moment."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["hush.editor.ai.artifact.2"].exists)
        XCTAssertTrue(app.buttons["hush.editor.accept"].label.contains("Accept current text"))

        prompt.click()
        prompt.typeText("Translate to English")
        prompt.typeKey(.return, modifierFlags: [])
        let incompleteResponseSheet = app.sheets.firstMatch
        XCTAssertTrue(incompleteResponseSheet.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["hush.editor.ai.artifact.3"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@",
            "<output>"
        )).firstMatch.exists)
        incompleteResponseSheet.buttons["OK"].click()
        keepScreenshot(named: "Selection Editor 02 Stateful AI Chat")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForLabel(_ label: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
