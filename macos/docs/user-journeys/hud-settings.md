# HUD settings journey

This document defines the user-visible contract for previewing and positioning the floating Hush HUD.

## Journey

1. The user opens **HUD & Menu** from the control center sidebar.
2. The user can enable or disable the floating HUD.
3. The user can select Bottom or Top. The real preview stays in the same scene and moves between its upper and lower regions so the placement change is immediately clear without losing context.
4. The user can preview Listening, Processing, Signing, and Inserted without starting a recording.
5. The selected state remains visible while the user changes the HUD position.

The menu panel is constant and has no preview on this page. Only configurable behavior receives space in the settings canvas.

The live HUD joins all Spaces and other applications' full-screen/Stage Manager groups using AppKit overlay collection behaviors. It never becomes the key window or intercepts clicks. Space and display changes reposition a currently visible HUD on the pointer's display. Top placement uses the menu-bar icon only when it belongs to that display. Dismissal stops the elapsed timer and pending auto-hide; later display notifications cannot revive a dismissed session.

On macOS 26 and later, the production HUD and its settings preview use one native `NSGlassEffectView` with the complete HUD foreground assigned as its `contentView`. The material must adapt continuously as content moves beneath it. On earlier supported systems, both paths use the semantic AppKit HUD material with behind-window blending. Hush does not simulate glass with a custom blur, opacity layer, tint, shader, or SwiftUI glass modifier.

## Acceptance mapping

| ID | Contract | Verification |
|---|---|---|
| HUD-001 | Show floating HUD updates the setting and preview opacity. | Manual control center journey and Release build |
| HUD-002 | Bottom and Top move the same preview between the lower and upper canvas regions. | Manual control center journey and Release build |
| HUD-003 | All four production states can be selected independently of position. | Manual control center journey and Release build |
| HUD-004 | No static menu panel preview is rendered. | Manual control center journey and source inspection |
| HUD-005 | The real floating HUD and settings preview use the same native AppKit glass composition, and moving content beneath the real panel changes the material without detaching it from the foreground. | Native moving-background smoke journey, manual cross-app scroll check, and Release build |
| HUD-006 | Listening remains visible when entering and leaving a full-screen Space. | `HUDNativeGlassJourneyTests.testHUDRemainsVisibleInFullScreenSpace` uses the real HUD and native full-screen transition. Separate desktop, multiple-display and Stage Manager configurations also require manual verification. |
| HUD-007 | Space changes restore an intended-visible panel but do not steal focus or revive a dismissed session. Old auto-hide tasks cannot dismiss a new recording. | `RecordingHUDLifecycleTests` with real AppKit windows and workspace/display notifications |
