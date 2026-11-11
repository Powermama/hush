# PRD: Native Liquid Glass HUD

## Status

Approved for implementation on macOS 26 and later. The current SwiftUI glass shell must not ship.

## Summary

The floating Hush HUD is a transient functional layer above the user’s current app. On macOS 26 and later, it must use Apple’s native AppKit Liquid Glass composition so the material continuously adapts to content moving behind the panel. Hush must not imitate this behavior with custom blur, opacity, gradients, shaders, or a SwiftUI background modifier.

The foreground HUD content is embedded as the `contentView` of one `NSGlassEffectView`. On earlier supported macOS releases, Hush uses one semantic `NSVisualEffectView` with behind-window blending.

## Problem

The current implementation applies SwiftUI `.glassEffect` to a transparent background inside an `NSHostingView`. In the floating borderless `NSPanel`, this renders like a static translucent shell. When a document scrolls or another color moves behind the HUD, the shell does not convincingly resample and adapt with it.

This conflicts with the intended Liquid Glass behavior and with Apple’s AppKit composition guidance. Apple specifically instructs custom AppKit interfaces to create an `NSGlassEffectView`, assign the foreground view to its `contentView`, and avoid placing glass behind foreground content as a sibling.

## Customer value

- The HUD feels anchored to macOS instead of painted above it.
- Scrolling documents and changing windows remain perceptible through an adaptive functional layer.
- Text stays legible over bright, dark, and visually busy apps.
- Reduce Transparency and Increase Contrast remain controlled by the system.
- The HUD keeps its existing compact shape, states, timing, and placement.

## Goals

1. Render the production HUD through Apple’s native AppKit Liquid Glass API on macOS 26 and later.
2. Make the material visibly respond when underlying content moves or changes.
3. Bind the foreground content and the glass geometry through `contentView`.
4. Preserve the existing 380 by 72 point layout and 18 point continuous corner radius.
5. Preserve Listening, Processing, Signing, Inserted, notice, position, and motion behavior.
6. Use only semantic system colors above glass.
7. Respect system accessibility and appearance settings without Hush-specific simulation.

## Non-goals

- No custom blur, shader, backdrop capture, snapshotting, or color sampling.
- No manual opacity veil or branded tint on the glass shell.
- No SwiftUI `.glassEffect` modifier in the HUD.
- No `NSGlassEffectContainerView` for a single HUD element.
- No redesign of the HUD content, size, controls, or state machine.
- No interactive glass response because the HUD ignores pointer events.

## Apple platform decision

### macOS 26 and later

Use one `NSGlassEffectView` as the native HUD surface:

- `style = .regular`
- `cornerRadius = 18`
- `contentView = NSHostingView(rootView: HushHUDRoot(model: model))`
- no custom `tintColor`

`regular` is required because the HUD contains compact labels and can appear over any application. Apple recommends regular glass when background content may challenge legibility or when a component contains meaningful text. Clear glass is reserved for controls floating over visually rich media and can require an additional dimming layer, which is not appropriate for this general-purpose HUD.

### macOS 15 through 25

Use one `NSVisualEffectView`:

- `material = .hudWindow`
- `blendingMode = .behindWindow`
- `state = .active`
- embed the same `NSHostingView` as its only foreground child
- clip to the same 18 point continuous corner geometry

This is a native compatibility path, not an imitation of Liquid Glass.

## View hierarchy

```text
HUDPanel (clear, nonopaque, nonactivating)
└── NSGlassEffectView or NSVisualEffectView
    └── NSHostingView
        └── HushHUD foreground content
```

The native material view owns the complete visible pill. The SwiftUI view renders only foreground content. Glass must not be a SwiftUI background and must not be a sibling behind the foreground.

## Visual behavior

- The system decides luminance, blur, refraction, contrast, and accessibility adaptation.
- The shell has no custom white border, contrast veil, material tint, or double shadow treatment.
- Existing semantic text colors remain dynamic so AppKit can apply the correct treatments.
- The HUD entrance and exit continue to animate the panel position and visibility. The glass surface and its foreground move as one object.
- State transitions continue inside the embedded content without replacing the native glass view.

## Settings preview

The HUD settings canvas must preview the same native material hierarchy used by the production panel. A static SwiftUI approximation is not acceptable. The preview can place the native HUD above the existing colorful canvas, but the glass surface itself must remain `NSGlassEffectView` on macOS 26 and `NSVisualEffectView` on earlier systems.

## Accessibility

- Verify Reduce Transparency uses the system-provided fallback appearance.
- Verify Increase Contrast preserves legibility without Hush overlays.
- Verify Reduce Motion suppresses or minimizes nonessential entrance and state motion according to the existing system-aware animation policy.
- Foreground labels and symbols use semantic system colors.

## End-to-end acceptance criteria

### LG-001 - Dynamic background response

Given the real floating HUD is visible above a window with moving high-contrast content, when the content scrolls beneath the stationary HUD, then pixels in the glass surface change with the underlying content while foreground glyph pixels remain stable and legible.

### LG-002 - Cross-application behavior

Verify the real HUD above:

1. a bright Microsoft Word document while scrolling;
2. a dark browser page while scrolling;
3. a colorful image while panning or switching windows.

The material must adapt without a stale snapshot, visible lag, or a detached shell.

### LG-003 - Geometry ownership

The `NSGlassEffectView` or compatibility material and its `contentView` must move together during panel entrance, exit, and top or bottom repositioning. No glass may remain at the previous location for a frame.

### LG-004 - State coverage

Listening, Processing, Signing, Inserted, and notice states retain the same geometry and do not recreate or flash the material surface.

### LG-005 - Accessibility and appearance

Light appearance, dark appearance, Reduce Transparency, and Increase Contrast must remain readable using only native system behavior.

### LG-006 - Performance

Scrolling under the visible HUD must remain smooth with no persistent CPU spike, memory growth, or app-side screen capture. Hush never reads or stores the pixels behind the glass.

## Automated verification

- Add a debug-only native HUD journey that places the actual floating `NSPanel` above a moving striped canvas.
- Capture frames before and after the background moves.
- Assert that the glass region changes and the foreground alignment remains unchanged.
- Keep source-level coverage that rejects `.glassEffect` and custom blur layers in the production HUD.
- Run the complete HUD settings journey and Release build after the native composition change.

## Failure and fallback policy

If `NSGlassEffectView` cannot dynamically sample content behind this floating `NSPanel` on a supported macOS 26 build, Hush must use the native `NSVisualEffectView` behind-window material for that configuration. It must not ship a static or simulated Liquid Glass shell.

## Rollout

1. Add the end-to-end moving-background reproduction.
2. Replace the SwiftUI shell with the native AppKit hierarchy.
3. Compare the same journey before and after the change.
4. Validate all HUD states and positions in light and dark appearances.
5. Validate accessibility settings.
6. Run package tests and the Release build.
7. Ship only after LG-001 through LG-006 pass.

## Source guidance

- [Apple Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple Developer Documentation: NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [Apple Developer Documentation: NSGlassEffectView contentView](https://developer.apple.com/documentation/appkit/nsglasseffectview/contentview)
- [WWDC25: Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/)
- [WWDC25: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
