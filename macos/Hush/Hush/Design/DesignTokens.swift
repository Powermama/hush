import AppKit
import QuartzCore

/// Hush's native macOS color system.
///
/// Neutral graphite surfaces carry the interface. A restrained cool aurora identifies
/// the brand and communicates active selection without competing with content.
///
/// Hush uses a cool aurora family for branded interaction. Graphite and semantic
/// system colors carry most of the interface; lilac, blue, rose, and mint appear
/// only where they communicate activity, selection, or product identity.
@MainActor
enum DesignTokens {

    // MARK: - Dark surfaces - neutral graphite

    static let surface         = NSColor(srgbRed: 0x1F/255, green: 0x20/255, blue: 0x24/255, alpha: 1)
    static let surfaceLight    = NSColor(srgbRed: 0x29/255, green: 0x2B/255, blue: 0x30/255, alpha: 1)
    static let surfaceLighter  = NSColor(srgbRed: 0x33/255, green: 0x36/255, blue: 0x3C/255, alpha: 1)
    static let surfaceBorder   = NSColor(srgbRed: 0x3C/255, green: 0x40/255, blue: 0x48/255, alpha: 1)

    // MARK: - Light surfaces - cool neutral

    static let paper           = NSColor(srgbRed: 0xF8/255, green: 0xF9/255, blue: 0xFB/255, alpha: 1)
    static let paperDeep       = NSColor(srgbRed: 0xF0/255, green: 0xF2/255, blue: 0xF6/255, alpha: 1)
    static let paperBorder     = NSColor(srgbRed: 0xE2/255, green: 0xE5/255, blue: 0xEB/255, alpha: 1)

    /// Pure white card on paper — used for the onboarding step rows (site `bg-white`).
    static let card            = NSColor.white

    // MARK: - Ink (text on paper) — `--color-ink` / `--color-muted` / `--color-soft`

    static let ink             = NSColor(srgbRed: 0x20/255, green: 0x21/255, blue: 0x26/255, alpha: 1)
    static let inkDim          = NSColor(srgbRed: 0x64/255, green: 0x67/255, blue: 0x70/255, alpha: 1)
    static let inkMute         = NSColor(srgbRed: 0xA2/255, green: 0xA6/255, blue: 0xB0/255, alpha: 1)

    // MARK: - Text on dark

    static let text            = NSColor(srgbRed: 0xEC/255, green: 0xEC/255, blue: 0xEA/255, alpha: 1)
    static let textDim         = NSColor(srgbRed: 0xA7/255, green: 0xA8/255, blue: 0xA1/255, alpha: 1)
    static let textMute        = NSColor(srgbRed: 0x7C/255, green: 0x7D/255, blue: 0x77/255, alpha: 1)

    // MARK: - Brand - cool aurora

    static let brand300        = NSColor(srgbRed: 0xA8/255, green: 0x9D/255, blue: 0xFF/255, alpha: 1)
    static let brand500        = NSColor(srgbRed: 0x79/255, green: 0x6D/255, blue: 0xE8/255, alpha: 1)
    static let brandGlow       = NSColor(srgbRed: 0x79/255, green: 0x6D/255, blue: 0xE8/255, alpha: 0.30)
    static let auroraRose      = NSColor(srgbRed: 0xFF/255, green: 0xB3/255, blue: 0xD1/255, alpha: 1)
    static let auroraBlue      = NSColor(srgbRed: 0x9E/255, green: 0xC9/255, blue: 0xFF/255, alpha: 1)
    static let auroraMint      = NSColor(srgbRed: 0xA8/255, green: 0xE6/255, blue: 0xCF/255, alpha: 1)
    static let lilac           = NSColor(srgbRed: 0xDD/255, green: 0xD8/255, blue: 0xFF/255, alpha: 1)
    /// Compatibility name for older call sites. This is cool rose, never orange.
    static let peach           = auroraRose

    // MARK: - Semantic — `--color-success` green

    static let good            = NSColor(srgbRed: 0x33/255, green: 0xB3/255, blue: 0x6B/255, alpha: 1)
    static let goodInk         = NSColor(srgbRed: 0x2A/255, green: 0x8F/255, blue: 0x57/255, alpha: 1)
    static let info            = NSColor(srgbRed: 0x6F/255, green: 0xA8/255, blue: 0xDC/255, alpha: 1)
    static let danger          = NSColor(srgbRed: 0xE0/255, green: 0x65/255, blue: 0x4E/255, alpha: 1)

    // MARK: - Icon-circle gradients (HUD)

    static let doneStart       = NSColor(srgbRed: 0x6C/255, green: 0xD2/255, blue: 0x9A/255, alpha: 1)
    static let doneEnd         = NSColor(srgbRed: 0x33/255, green: 0xB3/255, blue: 0x6B/255, alpha: 1)
    static let recHi           = NSColor(srgbRed: 0xFF/255, green: 0x75/255, blue: 0x91/255, alpha: 1)
    static let recLo           = NSColor(srgbRed: 0xE5/255, green: 0x48/255, blue: 0x64/255, alpha: 1)
    static let errHi           = NSColor(srgbRed: 0xF0/255, green: 0x8A/255, blue: 0x75/255, alpha: 1)
    static let errLo           = NSColor(srgbRed: 0xE0/255, green: 0x65/255, blue: 0x4E/255, alpha: 1)

    // MARK: - Radii

    static let radiusSm: CGFloat       = 6
    static let radius:   CGFloat       = 10
    static let radiusLg: CGFloat       = 14
    static let radiusXl: CGFloat       = 18

    // MARK: - Animation timing

    /// `cubic-bezier(0.22, 1, 0.36, 1)` — refreshed ease-out (handoff §1).
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
    /// `cubic-bezier(0.65, 0, 0.35, 1)` — ease-in-out.
    static let easeIn  = CAMediaTimingFunction(controlPoints: 0.65, 0.0, 0.35, 1.0)

    static let durFast: TimeInterval = 0.14
    static let durBase: TimeInterval = 0.22
    static let durSlow: TimeInterval = 0.36

    // MARK: - Helpers

    static func brandGradientColors() -> [CGColor] { [auroraBlue.cgColor, brand500.cgColor] }
    static func recordingGradientColors() -> [CGColor] { [recHi.cgColor, recLo.cgColor] }
    static func errorGradientColors() -> [CGColor] { [errHi.cgColor, errLo.cgColor] }
    static func doneGradientColors() -> [CGColor] { [doneStart.cgColor, doneEnd.cgColor] }
    /// Vertical paper gradient — used as the onboarding/settings window background.
    static func paperGradientColors() -> [CGColor] { [paper.cgColor, paperDeep.cgColor] }
}
