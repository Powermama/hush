//
//  HushHUD.swift
//  hush. - floating dictation HUD (SwiftUI)
//
//  One shape, four states: listening, processing, signing, and inserted, plus a
//  neutral notice slot for messages and errors ("Loading model...", "Copied",
//  permission prompts). Hosted in the borderless HUD panel via NSHostingView
//  (see RecordingHUDController). macOS 13+; the app targets 15.
//
//  Design spec: 380x72, corner radius 18. Everything is drawn as vectors.
//  no image assets, no external packages.
//
//  Component map:
//    HushHUD          - foreground content inside Apple's AppKit material
//    HushBadge        - the 42pt stateful app-icon square
//    HushMark         - the four-bar Hush logo
//    HushCheck        - the inserted checkmark
//    HushLabel        - two stacked lines, one slot per state
//    HushWaveform     - live voice or local processing activity
//    HushProofStatus  - a visually distinct encrypted-signing state
//    HushSignature    - the inserted Hush attribution
//    HUDModel         - ObservableObject the AppKit controller drives
//    HushHUDRoot      - binds the model to the view
//

import AppKit
import Combine
import SwiftUI

// MARK: - Design tokens (mirror the web build 1:1)

enum HUDPalette {
    static let ink    = Color(hex: 0x1D1D1F)
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let green  = Color(hex: 0x34C759)
    static let red    = Color(hex: 0xFF3B30)
    static let proofAccent = Color(hex: 0xA99DFF)

    /// Aurora - the brand's only colour. "Voice / thinking" moments.
    static let aurora = AngularGradient(
        gradient: Gradient(colors: [
            Color(hex: 0xA8E6CF), Color(hex: 0xFFB3D1), Color(hex: 0xC9B8FF),
            Color(hex: 0x9EC9FF), Color(hex: 0xA8E6CF)
        ]),
        center: .center, angle: .degrees(210)
    )
    static let auroraBar = LinearGradient(
        colors: [Color(hex: 0xFFB3C7), Color(hex: 0xC9B8FF), Color(hex: 0x9EC9FF)],
        startPoint: .top, endPoint: .bottom
    )
    static let proofAura = LinearGradient(
        colors: [Color(hex: 0x9EC9FF), Color(hex: 0xC9B8FF)],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )
}

public enum HushState: Equatable { case listening, processing, signing, inserted, notice }

// MARK: - Model (driven by RecordingHUDController)

@MainActor
final class HUDModel: ObservableObject {
    static let barCount = 28

    @Published var state: HushState = .listening
    @Published var seconds: Int = 0
    @Published var wordCount: Int = 0
    @Published var targetApp: String = "your app"
    @Published var message: String = ""
    @Published var isError: Bool = false
    @Published var isVerified: Bool = false
    /// Bumped each time a new recording starts. Bound to the view's `.id` so
    /// SwiftUI rebuilds the HUD fresh instead of cross-fading from a lingering
    /// notice (e.g. "No speech detected") into "Listening".
    @Published var session: Int = 0
    /// Rolling history of real mic levels (newest at the end), 0…1, shaped so
    /// room silence reads as a flat line and speech pushes the bars up.
    @Published var levels: [CGFloat] = Array(repeating: 0, count: HUDModel.barCount)

    /// Feed one raw level per audio buffer. Gate + γ-curve match the old HUD so
    /// ambient noise stays flat while quiet speech still moves the bars.
    func pushLevel(_ raw: CGFloat) {
        // Gate ambient noise to a flat line, then boost: a low γ lifts quiet
        // speech and a gain term makes normal talking fill most of the bar
        // height (louder still reads clearly taller, capped at 1).
        let gate: CGFloat = 0.02
        let gain: CGFloat = 1.7
        let clamped = min(max(raw, 0), 1)
        let shaped = clamped <= gate ? 0 : min(1, pow((clamped - gate) / (1 - gate), 0.45) * gain)
        levels.removeFirst()
        levels.append(shaped)
    }

    func resetLevels() { levels = Array(repeating: 0, count: HUDModel.barCount) }
}

struct HushHUDRoot: View {
    @ObservedObject var model: HUDModel
    var body: some View {
        HushHUD(state: model.state, seconds: model.seconds, wordCount: model.wordCount,
                targetApp: model.targetApp, message: model.message,
                isError: model.isError, isVerified: model.isVerified, levels: model.levels)
            .id(model.session)
    }
}

// MARK: - Public HUD

public struct HushHUD: View {
    public var state: HushState
    public var seconds: Int
    public var wordCount: Int
    public var targetApp: String
    public var message: String
    public var isError: Bool
    public var isVerified: Bool
    public var levels: [CGFloat]

    @State private var badgeScale: CGFloat = 1

    public init(state: HushState, seconds: Int = 0, wordCount: Int = 34,
                targetApp: String = "Mail", message: String = "",
                isError: Bool = false, isVerified: Bool = false, levels: [CGFloat] = []) {
        self.state = state; self.seconds = seconds; self.wordCount = wordCount
        self.targetApp = targetApp; self.message = message
        self.isError = isError; self.isVerified = isVerified; self.levels = levels
    }

    public var body: some View {
        HStack(spacing: 14) {
            HushBadge(state: state, isError: isError)
                .scaleEffect(badgeScale)                 // "bloom" on entering .processing

            if state == .notice {
                Text(message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isError ? HUDPalette.red : HUDPalette.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HushLabel(state: state, seconds: seconds,
                          wordCount: wordCount, targetApp: targetApp)
                    .frame(width: 116, alignment: .leading)
                    .foregroundStyle(HUDPalette.primary)

                ZStack(alignment: .trailing) {
                    HushWaveform(state: state, levels: levels)
                        .opacity(state == .listening || state == .processing ? 1 : 0)
                    HushProofStatus()
                        .opacity(state == .signing ? 1 : 0)
                        .offset(x: state == .signing ? 0 : 8)
                    HushSignature()
                        .opacity(state == .inserted ? 1 : 0)
                        .offset(x: state == .inserted ? 0 : 8)
                }
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 18)
        .frame(width: 380, height: 72)
        .animation(.easeInOut(duration: 0.35), value: state)
        .task(id: state) {
            if state == .processing || state == .signing {
                badgeScale = 0.92
                withAnimation(.easeOut(duration: 0.6)) { badgeScale = 1 }
            } else {
                badgeScale = 1
            }
        }
    }

}

// MARK: - Badge (the hush app icon, made stateful)

struct HushBadge: View {
    var state: HushState
    var isError: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(baseFill)
            AuroraFill().opacity(state == .processing ? 1 : 0)
            if state == .inserted {
                HushCheck()
            } else if state == .signing {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                HushMark(pulse: state == .processing)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HUDPalette.proofAura, lineWidth: 1)
                .opacity(state == .signing ? 0.65 : 0)
        )
        .shadow(color: glowColor, radius: glowRadius)
        .animation(.easeInOut(duration: 0.45), value: state)
    }

    private var baseFill: Color {
        switch state {
        case .inserted: return HUDPalette.green
        case .notice:   return isError ? HUDPalette.red : HUDPalette.ink
        default:        return HUDPalette.ink
        }
    }
    private var glowColor: Color {
        switch state {
        case .processing: return Color(hex: 0xC9B8FF).opacity(0.55)
        case .signing:    return HUDPalette.proofAccent.opacity(0.5)
        case .inserted:   return HUDPalette.green.opacity(0.35)
        case .notice:     return isError ? HUDPalette.red.opacity(0.35) : .clear
        case .listening:  return .clear
        }
    }
    private var glowRadius: CGFloat { (state == .listening) ? 0 : 22 }
}

/// Rotating aurora clipped inside the badge.
private struct AuroraFill: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7 * 360
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HUDPalette.aurora)
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(angle))
        }
    }
}

// MARK: - The hush mark (four bars, exact logo proportions)

struct HushMark: View {
    var color: Color = .white
    var pulse: Bool = false
    private let ratios: [CGFloat] = [16.0/36, 36.0/36, 22.0/36, 10.0/36]
    private let maxHeight: CGFloat = 22

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let s = pulse ? (0.72 + 0.28 * (0.5 + 0.5 * sin(t * 3.1 + Double(i) * 0.9))) : 1
                    Capsule().fill(color).frame(width: 3, height: maxHeight * ratios[i] * s)
                }
            }
            .frame(height: maxHeight)
        }
    }
}

/// Inserted checkmark, drawn on appear.
struct HushCheck: View {
    @State private var progress: CGFloat = 0
    var body: some View {
        CheckShape()
            .trim(from: 0, to: progress)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(width: 20, height: 20)
            .onAppear {
                progress = 0
                withAnimation(.easeOut(duration: 0.34).delay(0.12)) { progress = 1 }
            }
    }
    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.width * x / 24, y: rect.height * y / 24)
            }
            var path = Path()
            path.move(to: p(4, 12)); path.addLine(to: p(9, 17)); path.addLine(to: p(20, 6))
            return path
        }
    }
}

// MARK: - Label (two stacked lines, one slot per state)

struct HushLabel: View {
    var state: HushState
    var seconds: Int
    var wordCount: Int
    var targetApp: String

    var body: some View {
        ZStack(alignment: .leading) {
            listening.modifier(Slot(active: state == .listening))
            processing.modifier(Slot(active: state == .processing))
            signing.modifier(Slot(active: state == .signing))
            inserted.modifier(Slot(active: state == .inserted))
        }
    }

    private var listening: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Listening").font(.system(size: 14.5, weight: .semibold))
            HStack(spacing: 5) {
                RecDot()
                Text(timecode).font(.system(size: 11, design: .monospaced)).foregroundColor(HUDPalette.secondary)
            }
        }
    }
    private var processing: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Processing").font(.system(size: 14.5, weight: .semibold))
            Text("on-device").font(.system(size: 11)).foregroundColor(HUDPalette.secondary)
        }
    }
    private var signing: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Securing proof").font(.system(size: 14.5, weight: .semibold))
            Text("on this Mac").font(.system(size: 11)).foregroundColor(HUDPalette.secondary)
        }
    }
    private var inserted: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(wordCount) words")
                .font(.system(size: 14.5, weight: .semibold))
                .monospacedDigit()
            Text("inserted into \(targetApp)")
                .font(.system(size: 11))
                .foregroundColor(HUDPalette.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
    private var timecode: String { String(format: "0:%02d", seconds) }

    private struct Slot: ViewModifier {
        var active: Bool
        func body(content: Content) -> some View {
            content.opacity(active ? 1 : 0).offset(y: active ? 0 : 4)
        }
    }
}

/// Pulsing red recording dot.
struct RecDot: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Circle().fill(HUDPalette.red).frame(width: 6, height: 6)
                .opacity(0.35 + 0.65 * (0.5 + 0.5 * sin(t * 4.4)))
        }
    }
}

// MARK: - Waveform (28 bars, mic-reactive while listening and aurora while processing)

struct HushWaveform: View {
    var state: HushState
    /// Rolling real-mic history (used by the listening state).
    var levels: [CGFloat] = []
    private let count = HUDModel.barCount

    var body: some View {
        if state == .processing {
            // Synthetic aurora sweep because there is no live audio during processing.
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                bars { i in
                    let v = 0.5 + 0.5 * sin(t * 3.5 - Double(i) * 0.55)
                    return 8 + CGFloat(v) * 28
                }
            }
        } else {
            // Listening: heights come straight from the real mic levels, so the
            // wave is flat in silence and rises with your voice. Smoothed between
            // the ~10 Hz audio buffers by animating on `levels`.
            bars { i in
                let lvl = i < levels.count ? levels[i] : 0
                return 3 + lvl * 35
            }
            .animation(.easeOut(duration: 0.13), value: levels)
        }
    }

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(spacing: 3.5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(barFill).frame(width: 3, height: height(i))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 38, alignment: .center)
    }

    private var barFill: AnyShapeStyle {
        state == .processing
            ? AnyShapeStyle(HUDPalette.auroraBar)
            : AnyShapeStyle(HUDPalette.primary.opacity(0.82))
    }
}

// MARK: - Private proof status (signing only)

struct HushProofStatus: View {
    private let symbols = ["lock.fill", "signature", "checkmark.seal.fill"]

    var body: some View {
        TimelineView(.animation) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate * 1.7)
            let activeStep = tick % symbols.count

            HStack(spacing: 7) {
                ForEach(symbols.indices, id: \.self) { index in
                    proofStep(symbol: symbols[index], isActive: index == activeStep)

                    if index < symbols.count - 1 {
                        Capsule(style: .continuous)
                            .fill(HUDPalette.secondary.opacity(0.18))
                            .frame(width: 14, height: 1.5)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func proofStep(symbol: String, isActive: Bool) -> some View {
        ZStack {
            Circle()
                .fill(HUDPalette.primary.opacity(isActive ? 0.09 : 0.04))
            Circle()
                .strokeBorder(HUDPalette.primary.opacity(0.08), lineWidth: 0.75)
            Circle()
                .strokeBorder(HUDPalette.proofAura, lineWidth: 0.75)
                .opacity(isActive ? 0.65 : 0)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    isActive
                        ? AnyShapeStyle(HUDPalette.proofAura)
                        : AnyShapeStyle(HUDPalette.secondary.opacity(0.72))
                )
        }
        .frame(width: 28, height: 28)
        .scaleEffect(isActive ? 1 : 0.92)
        .shadow(color: isActive ? HUDPalette.proofAccent.opacity(0.22) : .clear, radius: 8)
        .animation(.smooth(duration: 0.35), value: isActive)
    }
}

// MARK: - Signature (inserted only): aurora divider + wordmark

struct HushSignature: View {
    var body: some View {
        HStack(spacing: 14) {
            LinearGradient(
                colors: [.clear, Color(hex: 0xFFB3C7), Color(hex: 0xC9B8FF), Color(hex: 0x9EC9FF), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 1, height: 28)

            HStack(spacing: 0) {
                Text("powered by ")
                    .foregroundColor(HUDPalette.secondary)
                Text("hush.").foregroundColor(HUDPalette.primary).fontWeight(.bold)
            }
            .font(.system(size: 11.5, weight: .medium))
        }
    }
}

// MARK: - Color(hex:)

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue:  Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

// MARK: - Preview

#if DEBUG
struct HushHUD_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            gallery
                .preferredColorScheme(.light)
                .previewDisplayName("Light")
            gallery
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark")
        }
    }

    private static var gallery: some View {
        VStack(spacing: 28) {
            HushHUD(state: .listening, seconds: 9,
                    levels: (0..<HUDModel.barCount).map { i in 0.2 + 0.6 * abs(sin(Double(i) * 0.5)) })
            HushHUD(state: .processing)
            HushHUD(state: .signing)
            HushHUD(
                state: .inserted,
                wordCount: 34,
                targetApp: "Mail",
                isVerified: true
            )
            HushHUD(state: .notice, message: "Loading model…")
            HushHUD(state: .notice, message: "Microphone access denied", isError: true)
        }
        .padding(60)
        .background(Color(nsColor: .windowBackgroundColor))
        .previewLayout(.sizeThatFits)
    }
}
#endif
