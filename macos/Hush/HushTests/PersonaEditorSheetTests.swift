import AppKit
import Testing
@testable import Hush

@Suite("Persona editor sheet", .serialized)
@MainActor
struct PersonaEditorSheetTests {
    private let profile = Profile(
        id: UUID(),
        name: "Strukturierung",
        systemPrompt: "Structure the message into short paragraphs.",
        creativity: 0.3,
        iconName: nil
    )

    /// The editor as the persona page presents it: the content of a 540 x 480 sheet.
    private func presentEditor(profile: Profile? = nil, appearance: NSAppearance.Name = .aqua) -> (NSWindow, PersonaEditorSheetController) {
        let editor = PersonaEditorSheetController(profile: profile ?? self.profile, isNew: false, aiReady: false, canDelete: true)
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentViewController = editor
        window.layoutIfNeeded()
        editor.view.layoutSubtreeIfNeeded()
        return (window, editor)
    }

    private func instructions(in view: NSView) throws -> NSTextView {
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.accessibilityIdentifier() == "hush.personaEditor.instructions" { return text }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        return try #require(find(view))
    }

    /// Scroll bars always shown (System Settings, or a mouse attached) narrow the box; overlay ones do not.
    @Test("The instructions fill their box, show the persona's text and take typing", arguments: [NSScroller.Style.overlay, .legacy], ["", "Structure the message into short paragraphs."])
    func instructionsAreEditable(scrollers: NSScroller.Style, prompt: String) throws {
        var profile = profile
        profile.systemPrompt = prompt
        let (window, editor) = presentEditor(profile: profile)
        let text = try instructions(in: editor.view)
        let scroll = try #require(text.enclosingScrollView)
        scroll.scrollerStyle = scrollers
        editor.view.layoutSubtreeIfNeeded()

        #expect(scroll.contentSize.width > 400)
        #expect(abs(text.frame.width - scroll.contentSize.width) < 1)
        #expect(text.frame.height >= scroll.contentSize.height - 1)
        #expect(text.string == profile.systemPrompt)
        let container = try #require(text.textContainer)
        let layout = try #require(text.layoutManager)
        #expect(container.size.width > 400, "The text must wrap at the box's width, not at zero")
        layout.ensureLayout(for: container)
        if !prompt.isEmpty {
            #expect(layout.usedRect(for: container).width > 100, "The persona's instructions must be laid out where they can be seen")
        }

        #expect(window.makeFirstResponder(text))
        text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
        text.insertText(" Keep it brief.", replacementRange: text.selectedRange())
        #expect(text.string == prompt + " Keep it brief.")
        // A click anywhere in the box lands in the text, not in empty scroll view.
        let middle = scroll.contentView.convert(NSPoint(x: scroll.contentSize.width / 2, y: scroll.contentSize.height - 8), to: nil)
        #expect(editor.view.hitTest(editor.view.convert(middle, from: nil)) === text)
    }

    @Test("Switching between dark and light redraws the sheet and its instructions box")
    func followsAppearanceChanges() throws {
        let (window, editor) = presentEditor(appearance: .darkAqua)
        let box = try #require(try instructions(in: editor.view).enclosingScrollView?.superview as? ControlCenterFieldBackgroundView)
        func colors() -> (CGColor?, CGColor?) { (editor.view.layer?.backgroundColor, box.layer?.backgroundColor) }
        let dark = colors()

        window.appearance = NSAppearance(named: .aqua)
        editor.view.layoutSubtreeIfNeeded()
        let light = colors()

        var expected: (CGColor, CGColor)!
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            expected = (ControlCenterStyle.contentBackground.cgColor, ControlCenterStyle.softFill.cgColor)
        }
        #expect(light.0 == expected.0)
        #expect(light.1 == expected.1)
        #expect(light.0 != dark.0)
        #expect(light.1 != dark.1)
    }
}
