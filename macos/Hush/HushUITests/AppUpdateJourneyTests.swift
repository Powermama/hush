import XCTest

final class AppUpdateJourneyTests: XCTestCase {
    func testTesterCanRequestAnUpdateFromTheMenuBar() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-didCompleteOnboarding", "YES",
            "--update-ui-test",
            "--activate-update-row-for-testing",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["hush updates are ready"].waitForExistence(timeout: 5),
            "The menu-bar update action did not reach the native update journey"
        )
        XCTAssertTrue(app.buttons["OK"].exists)
    }
}
