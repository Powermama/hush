# Persona wheel user journey

## Goal

A user has one shortcut that only records and a second shortcut that opens a visual persona selector. The Persona row in the menu bar opens the same selector. The selected persona, including `No persona`, remains active until the user changes it.

## State flow

```text
Ready
  -> user presses the persona shortcut or clicks Persona in the menu bar
Persona wheel open at the pointer
  -> user chooses a persona or No persona
Selection becomes active
  -> user holds and releases the dictation shortcut
Transcript uses the active selection and is inserted
  -> wrong persona was selected
User selects the Hush output and opens the Compose shortcut
  -> Restore Original or apply another persona
Corrected message replaces the selected output
  -> selection remains active
Ready
```

## Experience invariants

- The dictation shortcut only controls recording. It never opens or changes the persona selector.
- The persona shortcut only opens or closes the selector. It never starts recording.
- The Persona menu-bar row and persona shortcut share one action and always produce the same outcome.
- The wheel always includes `No persona`, even when personas are available.
- The selector always uses one complete ring with a transparent center, giving Hush a stable and recognizable interaction shape at every density. Small libraries distribute their choices generously around the circle. Larger libraries keep six primary slots: `No persona`, four personas including the active persona, and `More`. The `More` button opens a compact searchable popover containing every persona.
- Every persona receives a local automatic SF Symbol inferred from its name and instructions. A user can override it from the persona editor or return to `Auto`; existing saved personas remain in automatic mode without migration work.
- The Personas library communicates the active persona through the selected card's border, aurora tint, and icon color. It does not repeat that state with an `Active` text label, preserving space for the persona instructions.
- The selector stays neutral Liquid Glass. Only the active option carries Hush's full processing aurora, while every resting option remains the same size. Hover grows the complete option as one circle and adds a quiet background wash; hovering the active option slightly brightens its aurora. Labels and symbols retain adaptive system contrast over light and dark content.
- Persona selection is persistent and visible in the menu bar. `No persona` is a first-class active selection, not the same as disabling or unloading the local AI provider.
- Persona choice is captured when recording starts. Later selector or Settings changes cannot alter a recording that is already processing.
- Voice recorded inside the Hush composer remains plain. Fine Tune stays an explicit post-recording action inside the composer.
- Hush retains the plain pre-AI transcript under the configured local history policy. Reopening a retained refined message exposes `Previously refined`, `Restore Original`, and every available Fine Tune persona.
- If Persona AI is off or unavailable, either selector entry point opens Settings on the Personas page instead of presenting disabled controls.
- Escape, clicking outside the wheel, or pressing the persona shortcut again closes it without changing the active selection.

## Scenarios

### PW-001 - Open the selector independently

Given Hush is ready, when the user presses the persona shortcut or clicks Persona in the menu bar, then Hush opens a complete circular selector at the pointer without starting a recording. The circle and transparent center remain consistent whether the user has a small or large persona library.

### PW-002 - Select the active persona

Given Persona AI is ready and the wheel is open, when the user chooses a persona, then Hush closes the wheel, makes that persona active, and confirms `<persona> active`.

### PW-003 - Record with the active selection

Given a persona is active, when the user records, then Hush captures that persona at recording start and applies it to the transcript. The persona remains active for later dictations until changed.

### PW-004 - Return to no persona

Given a persona is active, when the user chooses `No persona`, then Hush preserves the local AI provider but inserts locally cleaned transcripts without persona rewriting until another persona is selected.

### PW-005 - Recover from the wrong persona

Given a dictated Hush output was refined with the wrong persona and remains in local history, when the user selects that output and opens the Compose shortcut, then Hush reopens the complete retained message. The user can restore the plain pre-AI transcript or apply another persona, then replace the exact selected output. If the destination text changed, Hush copies the correction instead of overwriting unrelated text.

### PW-006 - Set up unavailable personas

Given Persona AI is off or unavailable, when the user presses the persona shortcut or clicks Persona in the menu bar, then Hush opens Settings on the Personas page and focuses setup instead of showing a disabled selector.

### PW-007 - Reach a large persona library

Given more personas exist than fit cleanly in the radial selector, when the wheel opens, then Hush keeps `No persona`, the active persona, representative nearby personas, and one full-size `More` control directly visible. Choosing `More` opens a native searchable popover containing every persona. The active option never disappears into overflow, and adding profiles never creates overlapping circles or clipped labels.

### PW-008 - Manage personas without configuration clutter

Given the user opens Hush AI > Personas, the page presents a two-column library of persona cards rather than a permanently exposed settings form. Clicking a card activates it immediately, and the selected styling communicates that state without a redundant label. Choosing `Edit` or `Add Persona` opens a dedicated native sheet containing name, icon, instructions, creativity, and an unsaved test area. Cancel discards the draft, while Save commits it once. Automatic icons remain the default and a curated manual SF Symbol is optional. The Writing engine section below the library expands and collapses. It owns Download, Use and Remove controls for the Qwen engines and Use for Apple Intelligence. There is no separate global model catalogue; removal explains effects on both Personas and Assistant, which share the same files. Built-in descriptions are concise, while modified or custom personas display their actual instructions. Native selection buttons expose the selected state to accessibility.

## Test mapping

| Journey | Automated evidence |
| --- | --- |
| PW-001 | `PersonaWheelJourneyTests.testRealAppPersonaShortcutOpensSelector` presses the registered shortcut in the running app. `testMenuBarPersonaRowOpensSelector` verifies the menu-bar entry point. |
| PW-002 | `PersonaWheelJourneyTests.testDedicatedShortcutPersonaJourney` verifies both safe and persona choices, selects a persona, and verifies active-state confirmation. |
| PW-003 | The Release app build verifies the captured processing selection through the transcription pipeline. |
| PW-004 | `PersonaWheelJourneyTests.testDedicatedShortcutPersonaJourney` verifies the required no-persona control is present. Escape and outside-click dismissal are verified manually. |
| PW-005 | `TextContextMatcherTests` covers retained-output recovery, pre-AI source propagation, and exact destination replacement. The Release app build covers `Previously refined`, `Restore Original`, and re-refinement in the native composer. |
| PW-006 | `PersonaWheelJourneyTests.testPersonaShortcutOpensPersonaSettingsWhenProfilesAreOff` and `testMenuBarPersonaRowOpensSettingsWhenProfilesAreOff` verify both unavailable-state routes. |
| PW-007 | `PersonaWheelJourneyTests.testSmallPersonaSetUsesFullCircle` verifies that small libraries retain the complete circle. `testDedicatedShortcutPersonaJourney` verifies the six-choice ring. `testOverflowKeepsActivePersonaVisibleAndOffersEveryPersona` verifies the active-persona priority, six-slot cap, full-size `More` affordance, searchable overflow popover, and hidden-persona selection. |
| PW-008 | `PersonaWheelJourneyTests.testPersonaLibraryUsesFocusedEditorSheet` verifies the focused library, selected-card-only state treatment, edit sheet, icon control, test affordance, Save and Cancel actions, and clean Add Persona journey. `PersonaIconResolverTests` verifies automatic inference, manual overrides, and backward-compatible saved profiles. |

Settings redesign mapping: `PermissionJourneyTests.testPersonasUsesSharedModelsAndKeepsStyleEditing` and `testAISettingsInDarkAppearance` exercise the separate Hush AI pages and capture both appearances.
