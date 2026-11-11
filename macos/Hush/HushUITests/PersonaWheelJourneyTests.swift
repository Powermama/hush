import XCTest

final class PersonaWheelJourneyTests: XCTestCase {
    func testRealAppPersonaShortcutOpensSelector() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-didCompleteOnboarding", "YES",
            "--persona-selector-ready-for-testing",
        ]
        app.launch()
        app.activate()

        app.typeKey("p", modifierFlags: .option)

        let wheel = app.descendants(matching: .any)["hush.personaWheel"]
        XCTAssertTrue(
            wheel.waitForExistence(timeout: 3),
            "The registered default persona shortcut did not reveal the persona wheel"
        )
    }

    func testPersonaShortcutOpensPersonaSettingsWhenProfilesAreOff() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-didCompleteOnboarding", "YES",
            "-postprocess.llmProvider", "off",
        ]
        app.launch()
        app.activate()

        app.typeKey("p", modifierFlags: .option)

        XCTAssertTrue(
            app.staticTexts["Personas"].waitForExistence(timeout: 5),
            "The persona shortcut should open the Personas page when Persona AI is off"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["hush.personaWheel"].exists,
            "The selector should not open while Persona AI is off"
        )
    }

    func testPersonaLibraryUsesFocusedEditorSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-didCompleteOnboarding", "YES",
            "-postprocess.llmProvider", "off",
        ]
        app.launch()
        app.activate()
        app.typeKey("p", modifierFlags: .option)

        XCTAssertTrue(app.staticTexts["Choose your style"].waitForExistence(timeout: 5))
        let addButton = app.buttons["Add Persona"]
        let edit = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Edit '")
        ).firstMatch
        XCTAssertTrue(addButton.exists)
        XCTAssertTrue(edit.exists)
        XCTAssertFalse(
            app.staticTexts["Active"].exists,
            "The selected persona card should rely on its highlight instead of a redundant Active label"
        )

        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<3 where !edit.isHittable { scrollView.swipeUp() }

        let libraryAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        libraryAttachment.name = "Focused persona library"
        libraryAttachment.lifetime = .keepAlways
        add(libraryAttachment)

        edit.click()
        XCTAssertTrue(app.staticTexts["Make this persona yours"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["hush.personaEditor.name"].exists)
        XCTAssertTrue(app.buttons["Persona icon"].exists)
        XCTAssertTrue(app.buttons["Try Persona"].exists)
        XCTAssertTrue(app.buttons["Save Changes"].exists)

        let editorAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editorAttachment.name = "Focused persona editor"
        editorAttachment.lifetime = .keepAlways
        add(editorAttachment)

        app.buttons["Cancel"].click()
        XCTAssertFalse(app.staticTexts["Make this persona yours"].exists)

        for _ in 0..<3 where !addButton.isHittable { scrollView.swipeUp() }
        addButton.click()
        XCTAssertTrue(app.staticTexts["Create a persona"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Create Persona"].exists)
        app.buttons["Cancel"].click()
    }

    func testMenuBarPersonaRowOpensSelector() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-didCompleteOnboarding", "YES",
            "--persona-selector-ready-for-testing",
            "--activate-persona-row-for-testing",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["hush.personaWheel"].waitForExistence(timeout: 3),
            "Clicking the Persona toolbar row did not reveal the selector"
        )
    }

    func testMenuBarPersonaRowOpensSettingsWhenProfilesAreOff() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-didCompleteOnboarding", "YES",
            "-postprocess.llmProvider", "off",
            "--activate-persona-row-for-testing",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Personas"].waitForExistence(timeout: 5),
            "Clicking Persona should open the Personas page while Persona AI is off"
        )
        XCTAssertFalse(app.descendants(matching: .any)["hush.personaWheel"].exists)
    }

    func testDedicatedShortcutPersonaJourney() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-persona-wheel"]
        app.launch()

        let wheel = app.descendants(matching: .any)["hush.personaWheel"]
        XCTAssertTrue(
            wheel.waitForExistence(timeout: 5),
            "The persona shortcut did not reveal the persona wheel"
        )
        XCTAssertEqual(
            wheel.frame.width,
            wheel.frame.height,
            accuracy: 1,
            "Six choices should use a balanced circular selector"
        )

        let cleanButton = app.buttons["No persona"]
        let businessButton = app.buttons["Business"]
        XCTAssertTrue(cleanButton.exists, "The wheel must always offer a no-persona path")
        XCTAssertTrue(businessButton.exists, "Available personas must be selectable from the wheel")
        XCTAssertEqual(
            cleanButton.frame.width,
            businessButton.frame.width,
            accuracy: 0.75,
            "The active persona must use background color, not size, to show its resting state"
        )

        businessButton.hover()
        XCTAssertTrue(
            app.staticTexts["Select Business"].waitForExistence(timeout: 2),
            "Hovering a persona should preview its selection state"
        )
        XCTAssertGreaterThan(
            businessButton.frame.width,
            cleanButton.frame.width,
            "Only the hovered persona should grow"
        )

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Persona wheel"
        attachment.lifetime = .keepAlways
        add(attachment)

        businessButton.click()

        let confirmation = app.staticTexts["Business active"]
        XCTAssertTrue(
            confirmation.waitForExistence(timeout: 2),
            "Choosing a persona did not confirm the active recording style"
        )
        XCTAssertFalse(wheel.exists, "The wheel should dismiss as soon as a persona is chosen")
    }

    func testSmallPersonaSetUsesFullCircle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-persona-wheel-small"]
        app.launch()

        let wheel = app.descendants(matching: .any)["hush.personaWheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        XCTAssertEqual(
            wheel.frame.width,
            wheel.frame.height,
            accuracy: 1,
            "A small persona set should use the same complete circle as every other density"
        )
        XCTAssertFalse(app.buttons["More"].exists)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Small persona circle"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testOverflowKeepsActivePersonaVisibleAndOffersEveryPersona() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-persona-wheel-overflow"]
        app.launch()

        let wheel = app.descendants(matching: .any)["hush.personaWheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        XCTAssertEqual(wheel.frame.width, wheel.frame.height, accuracy: 1)
        let product = app.buttons["Product"]
        XCTAssertTrue(
            product.exists,
            "An active persona must remain directly visible even when it falls outside the first slots"
        )
        XCTAssertTrue(product.isSelected)
        XCTAssertEqual(
            product.frame.width,
            app.buttons["No persona"].frame.width,
            accuracy: 0.75,
            "The active overflow persona must use Aurora, not size, in its resting state"
        )
        XCTAssertFalse(
            app.buttons["Legal"].exists,
            "Overflow personas should not crowd the primary ring"
        )

        let more = app.buttons["More"]
        XCTAssertTrue(more.exists)
        more.hover()
        XCTAssertTrue(app.staticTexts["View all personas"].waitForExistence(timeout: 2))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Overflow persona wheel"
        attachment.lifetime = .keepAlways
        add(attachment)

        more.click()

        let search = app.textFields["hush.personaWheel.moreSearch"]
        XCTAssertTrue(
            search.waitForExistence(timeout: 2),
            "More should open a searchable persona library"
        )
        search.click()
        search.typeText("Legal")

        let legal = app.buttons["Legal"]
        XCTAssertTrue(
            legal.waitForExistence(timeout: 2),
            "Search should find every persona hidden from the primary ring"
        )
        XCTAssertFalse(app.buttons["Research"].exists)

        let popoverAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        popoverAttachment.name = "Searchable persona overflow"
        popoverAttachment.lifetime = .keepAlways
        add(popoverAttachment)

        legal.click()
        XCTAssertTrue(app.staticTexts["Legal active"].waitForExistence(timeout: 2))
        XCTAssertFalse(wheel.exists)
    }
}
