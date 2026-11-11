import XCTest

final class AssistantJourneyTests: XCTestCase {
    func testSequenceShowsElapsedWorkAndEscapeStopsNextStep() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global", "--preview-assistant-sequence", "--preview-assistant-progress"]
        app.launch()
        defer { app.terminate() }
        let microphone = app.buttons["hush.companion.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.click()
        let progress = app.staticTexts["hush.companion.progress"]
        let waiting = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@", "Step 2", "2s"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [waiting], timeout: 7), .completed)
        XCTAssertEqual(app.staticTexts["hush.companion.status"].value as? String, "Choosing the next action")
        screenshotCompanion("Hush - checked sequence progress", app)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(app.textViews["hush.assistant.fixture.body"].value as? String, "Search results: First music video")
        XCTAssertFalse(app.buttons["hush.companion.apply"].exists)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
            object: app.descendants(matching: .any)["hush.companion.cursor"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
    }

    func testOneSpokenGoalContinuesAfterFreshObservation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global", "--preview-assistant-sequence"]
        app.launch()
        defer { app.terminate() }
        let microphone = app.buttons["hush.companion.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.click()
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Video opened"),
            object: app.textViews["hush.assistant.fixture.body"])
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["hush.companion.apply"].exists)
    }

    func testDevelopmentTraceExplainsFailedInsertion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hush-diagnostic-journey-\(UUID())")
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        app.launchEnvironment["HUSH_ASSISTANT_TRACE_ROOT"] = root.path
        app.launchArguments = ["--preview-assistant-global", "--preview-assistant-missing-target", "--assistant-diagnostics"]
        app.launch()
        let microphone = app.buttons["hush.companion.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.click()
        let failure = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Let's check the destination"),
            object: app.staticTexts["hush.companion.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [failure], timeout: 5), .completed)
        let reportReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let directory = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first,
                  let report = try? String(contentsOf: directory.appendingPathComponent("trace.json"), encoding: .utf8) else { return false }
            return report.contains("action.failed") && report.contains("unsupportedEditor") && report.contains("turn.finished")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reportReady], timeout: 3), .completed)
        let directory = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        XCTAssertTrue(try String(contentsOf: directory.appendingPathComponent("transcript.txt"), encoding: .utf8).contains("Write a reply to Tom"))
        for name in ["context.json", "replay.json", "reply.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path), name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("model-screen.png").path))
        XCTAssertFalse((app.textViews["hush.assistant.fixture.body"].value as? String ?? "").contains("Tomorrow at 10"))
    }

    func testEscapeDismissesStoppedCursorFromAnotherApp() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global"]
        app.launch()
        let cursor = app.descendants(matching: .any)["hush.companion.cursor"]
        XCTAssertTrue(cursor.waitForExistence(timeout: 5))
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let stop = app.buttons["hush.companion.stop"]
        stop.click()
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Stopped'"),
                                                object: app.staticTexts["hush.companion.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 2), .completed)
        if stop.exists { stop.click() }
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cursor)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
    }

    func testCursorFollowsMouseAndCompletionDisappears() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global"]
        app.launch(); app.activate()
        let cursor = app.dialogs["hush.companion.cursor.window"]
        XCTAssertTrue(cursor.waitForExistence(timeout: 5))
        let source = app.windows["Working app fixture"]
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).hover()
        let first = source.frame
        let followsFirst = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(cursor.frame.minX - (first.minX + first.width * 0.1 + 8)) < 15
        }, object: cursor)
        XCTAssertEqual(XCTWaiter.wait(for: [followsFirst], timeout: 3), .completed)
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).hover()
        let followsSecond = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(cursor.frame.minX - (first.minX + first.width * 0.9 + 8)) < 15
        }, object: cursor)
        XCTAssertEqual(XCTWaiter.wait(for: [followsSecond], timeout: 3), .completed)
        app.buttons["hush.companion.microphone"].click()
        let inserted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "Tomorrow at 10"),
            object: app.textViews["hush.assistant.fixture.body"])
        XCTAssertEqual(XCTWaiter.wait(for: [inserted], timeout: 5), .completed)
        let fades = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cursor)
        XCTAssertEqual(XCTWaiter.wait(for: [fades], timeout: 5), .completed)
    }

    func testSpeechBubbleIsReadOnlyAndEscapeStopsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global", "--preview-assistant-speaking", "--preview-dark-appearance"]
        app.launch(); app.activate()
        let microphone = app.buttons["hush.companion.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.click()
        let speech = app.staticTexts["hush.companion.speech"]
        XCTAssertTrue(speech.waitForExistence(timeout: 4))
        XCTAssertFalse(app.textFields["hush.companion.prompt"].exists)
        screenshotCompanion("Hush - spoken reply bubble", app, detail: true)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(speech.exists)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
            object: app.descendants(matching: .any)["hush.companion.cursor"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
    }

    func testCursorIsTheDefaultSurface() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["hush.companion.cursor"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["hush.companion.surface"].exists)
        XCTAssertFalse(app.buttons["hush.companion.preview"].exists)
        XCTAssertFalse(app.buttons["hush.companion.apply"].exists)
        XCTAssertFalse(app.buttons["hush.companion.type"].exists)
        XCTAssertFalse(app.textFields["hush.companion.prompt"].exists)
    }
    func testGlobalEntryDoesNotRequireMail() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["hush.companion.cursor"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["hush.assistant.unavailable"].exists)
        XCTAssertFalse(app.windows["hush.assistant.window"].exists)
        XCTAssertTrue(app.buttons["hush.companion.microphone"].exists)
        XCTAssertLessThan(app.dialogs["hush.companion.cursor.window"].frame.height, 80)
        screenshotCompanion("Hush coworker - compact entry", app)
    }

    func testSpokenTurnFollowUpAndInsertion() throws {
        try verifySpokenFollowUp(misclassifiedAsWrite: false)
    }

    func testEscapeStartsFreshInReusedEditor() throws {
        try verifyConversationReset(clickEscape: false)
    }

    func testEscapeButtonStartsFreshInReusedEditor() throws {
        try verifyConversationReset(clickEscape: true)
    }

    private func verifyConversationReset(clickEscape: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global", "--preview-assistant-reset"]
        app.launch(); app.activate()
        defer { app.terminate() }
        guard app.wait(for: .runningForeground, timeout: 5) else {
            XCTFail("The working-app fixture must own focus before keyboard testing")
            return
        }
        let microphone = app.buttons["hush.companion.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.click()
        let body = app.textViews["hush.assistant.fixture.body"]
        let first = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "Tomorrow at 10 works for me."), object: body)
        guard XCTWaiter.wait(for: [first], timeout: 6) == .completed else {
            XCTFail("The initial draft must be verified before testing reset")
            return
        }
        if !clickEscape {
            let faded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                object: app.descendants(matching: .any)["hush.companion.cursor"])
            guard XCTWaiter.wait(for: [faded], timeout: 10) == .completed else {
                XCTFail("The completed cursor should fade while retaining conversation")
                return
            }
        }
        // Notes can reuse its editor when opening another note. Replace the
        // fixture's contents to reproduce that same native-editor identity.
        guard app.state == .runningForeground else { XCTFail("The fixture lost keyboard focus"); return }
        app.buttons["hush.fixture.new-note"].click()
        XCTAssertEqual(body.value as? String, "")
        if clickEscape { app.buttons["hush.companion.stop"].click() }
        else { app.typeKey(.escape, modifierFlags: []) }
        app.buttons["hush.fixture.voice"].click() // Same voice entry after the cursor fades.
        let fresh = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Hi Tom,\n\nTomorrow at 10 works for me."), object: body)
        XCTAssertEqual(XCTWaiter.wait(for: [fresh], timeout: 6), .completed)
        XCTAssertFalse((body.value as? String ?? "").contains("lovely"))
    }

    func testFollowUpMisclassifiedAsWriteStillReplacesOnlyTheVerifiedText() throws {
        try verifySpokenFollowUp(misclassifiedAsWrite: true)
    }

    private func verifySpokenFollowUp(misclassifiedAsWrite: Bool) throws {
        let app = XCUIApplication()
        let traceRoot = FileManager.default.temporaryDirectory.appendingPathComponent("hush-followup-test-\(UUID())")
        app.launchEnvironment["HUSH_ASSISTANT_TRACE_ROOT"] = traceRoot.path
        defer {
            if let files = try? FileManager.default.contentsOfDirectory(at: traceRoot, includingPropertiesForKeys: nil) {
                for directory in files {
                    if let data = try? Data(contentsOf: directory.appendingPathComponent("trace.json")) {
                        let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                        evidence.name = "Synthetic follow-up trace"; evidence.lifetime = .deleteOnSuccess; add(evidence)
                    }
                }
            }
            try? FileManager.default.removeItem(at: traceRoot)
        }
        app.launchArguments = ["--preview-assistant-global", "--preview-dark-appearance", "--assistant-diagnostics"]
        if misclassifiedAsWrite { app.launchArguments.append("--preview-assistant-write-followup") }
        app.launch()
        app.activate()
        let microphone = app.buttons["hush.companion.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.click()
        let body = app.textViews["hush.assistant.fixture.body"]
        let first = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Hi Tom,\n\nTomorrow at 10 works for me.\n\nKind regards,\nAlex"), object: body)
        XCTAssertEqual(XCTWaiter.wait(for: [first], timeout: 6), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["hush.companion.surface"].exists)
        microphone.click() // Next spoken turn: "Make it warmer".
        let revised = "Hi Tom,\n\nThat sounds lovely. Tomorrow at 10 works for me!\n\nKind regards,\nAlex"
        let inserted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", revised), object: body)
        XCTAssertEqual(XCTWaiter.wait(for: [inserted], timeout: 6), .completed)
        XCTAssertFalse(app.buttons["hush.companion.apply"].exists)
        XCTAssertFalse(app.buttons["hush.companion.preview"].exists)
        screenshotCompanion("Hush coworker - draft updated", app)
    }

    func testClarificationContinuesByVoiceWithoutAForm() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global", "--preview-assistant-question"]
        app.launch(); app.activate()
        let microphone = app.buttons["hush.companion.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.click()
        let question = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Your turn"),
                                                 object: app.staticTexts["hush.companion.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [question], timeout: 5), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["hush.companion.surface"].exists)
        XCTAssertFalse(app.textFields["hush.companion.prompt"].exists)
        screenshotCompanion("Hush coworker - awaiting spoken answer", app)
        microphone.click()
        let body = app.textViews["hush.assistant.fixture.body"]
        let inserted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "Tomorrow at 10 works for me."), object: body)
        XCTAssertEqual(XCTWaiter.wait(for: [inserted], timeout: 6), .completed)
    }

    func testCoworkerEscapeCancelsLateReply() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant-global", "--preview-assistant-slow"]
        app.launch(); app.activate()
        let microphone = app.buttons["hush.companion.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.click()
        let thinking = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Choosing the next action"),
                                                 object: app.staticTexts["hush.companion.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [thinking], timeout: 4), .completed)
        app.typeKey(.escape, modifierFlags: [])
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Stopped'"),
                                                object: app.staticTexts["hush.companion.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed)
        let noLateEdit = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "\n\nKind regards,\nAlex"),
                                                  object: app.textViews["hush.assistant.fixture.body"])
        noLateEdit.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [noLateEdit], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["hush.companion.apply"].exists)
    }

    private func screenshotCompanion(_ name: String, _ app: XCUIApplication, detail: Bool = false) {
        let window = app.dialogs[detail ? "hush.companion.window" : "hush.companion.cursor.window"]
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testReviewAndFormattedInsertionPreserveSignatureInLightAppearance() throws {
        let app = launch("--preview-light-appearance")
        let request = app.textFields["hush.assistant.request"]
        XCTAssertTrue(request.waitForExistence(timeout: 6))
        request.click()
        request.typeText("Write a friendly reply with the plan")
        app.buttons["hush.assistant.generate"].click()
        XCTAssertTrue(app.staticTexts["hush.assistant.draft"].waitForExistence(timeout: 5))
        let body = app.textViews["hush.assistant.fixture.body"]
        XCTAssertEqual(body.value as? String, "\n\nKind regards,\nAlex")
        screenshot("Hey Hush Light - Review")
        app.buttons["hush.assistant.insert"].click()
        XCTAssertTrue(waitForStatus("Inserted and checked in Mail. Ready for you to review and send.", in: app))
        let result = try XCTUnwrap(body.value as? String)
        XCTAssertTrue(result.contains("• Review the proposal together.\n• Confirm the next steps."))
        XCTAssertTrue(result.hasSuffix("\n\nKind regards,\nAlex"))
        XCTAssertFalse(app.buttons["hush.assistant.insert"].isEnabled)
        screenshot("Hey Hush Light - Verified insertion")
    }

    func testStaleDestinationNeverReceivesDraft() throws {
        let app = launch("--preview-dark-appearance")
        let request = app.textFields["hush.assistant.request"]
        XCTAssertTrue(request.waitForExistence(timeout: 6))
        request.click()
        request.typeText("Write a friendly reply")
        app.buttons["hush.assistant.generate"].click()
        XCTAssertTrue(app.staticTexts["hush.assistant.draft"].waitForExistence(timeout: 5))
        app.buttons["hush.assistant.fixture.change"].click()
        app.buttons["hush.assistant.insert"].click()
        XCTAssertTrue(waitForStatus("The destination changed. Reopen Hush from the email body to bind it again.", in: app))
        XCTAssertEqual(app.textViews["hush.assistant.fixture.body"].value as? String, "A newer draft typed by the user.")
        screenshot("Hey Hush Dark - Changed destination")
    }

    func testEscapeStopsGenerationAndTruncatedOutputCannotBeInserted() throws {
        let app = launch("--preview-dark-appearance")
        let request = app.textFields["hush.assistant.request"]
        XCTAssertTrue(request.waitForExistence(timeout: 6))
        request.click()
        request.typeText("Write a slow reply")
        app.buttons["hush.assistant.generate"].click()
        XCTAssertTrue(app.buttons["hush.assistant.stop"].waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForStatus("Stopped. Your email has not been changed.", in: app))
        request.click()
        request.typeKey("a", modifierFlags: .command)
        request.typeText("invalid")
        app.buttons["hush.assistant.generate"].click()
        XCTAssertTrue(waitForStatus("The model did not produce a complete draft. Try a shorter, more specific request.", in: app))
        XCTAssertFalse(app.buttons["hush.assistant.insert"].isEnabled)
        XCTAssertEqual(app.textViews["hush.assistant.fixture.body"].value as? String, "\n\nKind regards,\nAlex")
    }

    private func launch(_ appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-assistant", appearance]
        app.launch()
        app.activate()
        return app
    }

    private func waitForStatus(_ text: String, in app: XCUIApplication) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text),
                                                    object: app.staticTexts["hush.assistant.status"])
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().windows["hush.assistant.window"].screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
