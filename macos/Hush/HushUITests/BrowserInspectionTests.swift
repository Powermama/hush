import AppKit
import ApplicationServices
import XCTest

final class BrowserInspectionTests: XCTestCase {
    func testSafariTabStructure() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HUSH_BROWSER_INSPECT"] == "1")
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        XCTAssertTrue(safari.windows.firstMatch.exists)
        print("[browser-inspect] AX trusted: \(AXIsProcessTrusted())")
        // Read-only native inspection. Omit titles, labels and page content from output.
        let tree = safari.windows.firstMatch.debugDescription
        for line in tree.components(separatedBy: .newlines).prefix(240) {
            let structural = line.components(separatedBy: ", identifier:")[0]
                .components(separatedBy: ", label:")[0]
                .components(separatedBy: ", value:")[0]
                .components(separatedBy: ", title:")[0]
            print("[browser-inspect] \(structural)")
        }
    }
}
