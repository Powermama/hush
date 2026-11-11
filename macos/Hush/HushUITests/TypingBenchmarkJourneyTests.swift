import XCTest

final class TypingBenchmarkJourneyTests: XCTestCase {
    func testTypingBenchmarkKeepsThePassageAsThePrimaryTask() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-time-saved", "--preview-typing-test"]
        app.launch()
        app.activate()

        XCTAssertTrue(app.staticTexts["Typing benchmark"].waitForExistence(timeout: 6))
        let passage = app.staticTexts["hush.typing.passage"]
        XCTAssertTrue(passage.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(passage.frame.width, 700)
        let currentWord = app.staticTexts["hush.typing.current-word"]
        XCTAssertTrue(currentWord.waitForExistence(timeout: 2))
        let firstWord = textValue(of: currentWord)
        XCTAssertFalse(firstWord.isEmpty)
        let input = app.textFields["hush.typing.input"]
        XCTAssertTrue(input.exists)
        keepScreenshot(named: "Typing Benchmark 01 Ready")

        input.typeText(firstWord)
        XCTAssertTrue(app.staticTexts["Correct mistakes as you go for a more realistic result."].waitForExistence(timeout: 2))
        XCTAssertNotEqual(textValue(of: currentWord), firstWord)
        let characterFeedback = app.staticTexts["hush.typing.character-feedback"]
        XCTAssertEqual(textValue(of: characterFeedback), "\(firstWord.count) correct · 0 mistakes")
        keepScreenshot(named: "Typing Benchmark 02 Space Marker")

        let nextWord = textValue(of: currentWord)
        input.typeText(" ")
        XCTAssertEqual(textValue(of: characterFeedback), "\(firstWord.count + 1) correct · 0 mistakes")
        let incorrectCharacter = nextWord.first == "x" ? "q" : "x"
        input.typeText(incorrectCharacter)
        XCTAssertEqual(textValue(of: characterFeedback), "\(firstWord.count + 1) correct · 1 mistake")
        keepScreenshot(named: "Typing Benchmark 03 Character Error")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func textValue(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }
}
