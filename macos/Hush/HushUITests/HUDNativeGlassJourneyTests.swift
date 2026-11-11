import AppKit
import XCTest

final class HUDNativeGlassJourneyTests: XCTestCase {
    func testHUDRemainsVisibleInFullScreenSpace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-native-hud-glass", "--hud-spaces"]
        app.launch()
        defer { app.terminate() }
        let status = app.staticTexts["hush.hudSpaceStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let visible = NSPredicate(format: "value CONTAINS 'HUD visible'")
        expectation(for: visible, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        app.buttons["Toggle full screen"].click()
        let fullScreen = NSPredicate(format: "value CONTAINS 'Full screen: true; HUD visible'")
        expectation(for: fullScreen, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Listening HUD in full screen Space"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Toggle full screen"].click()
        expectation(for: NSPredicate(format: "value CONTAINS 'Full screen: false; HUD visible'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
    }

    func testGlassSurfaceRespondsToMovingContent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-native-hud-glass"]
        app.launch()

        let surface = app.descendants(matching: .any)["hush.nativeGlassSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5), "The real native HUD surface did not appear")

        let firstFrame = surface.screenshot()
        let backgroundMoved = expectation(description: "Moving background advanced")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            backgroundMoved.fulfill()
        }
        wait(for: [backgroundMoved], timeout: 2)
        let secondFrame = surface.screenshot()

        let firstAttachment = XCTAttachment(screenshot: firstFrame)
        firstAttachment.name = "Native glass before background motion"
        firstAttachment.lifetime = .keepAlways
        add(firstAttachment)

        let secondAttachment = XCTAttachment(screenshot: secondFrame)
        secondAttachment.name = "Native glass after background motion"
        secondAttachment.lifetime = .keepAlways
        add(secondAttachment)

        XCTAssertNotEqual(
            firstFrame.pngRepresentation,
            secondFrame.pngRepresentation,
            "The native glass surface remained a stale snapshot while content moved behind it"
        )
    }
}
