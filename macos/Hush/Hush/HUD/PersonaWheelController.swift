import AppKit
import SwiftUI

enum PersonaWheelSelection: Sendable {
    case noPersona
    case profile(Profile)
}

private enum PersonaWheelLayout {
    static let panelSize = NSSize(width: 400, height: 400)
}

/// Owns the pointer-anchored persona selector. It is independent from the
/// recording HUD so opening it can never start, stop, or delay recording.
@MainActor
final class PersonaWheelController {
    private var window: PersonaWheelPanel?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?

    var isVisible: Bool { window?.isVisible == true }

    func toggle(
        profiles: [Profile],
        activeProfileID: UUID,
        personaEnabled: Bool,
        personasAvailable: Bool,
        onSelect: @escaping @MainActor (PersonaWheelSelection) -> Void
    ) {
        if isVisible {
            hide()
            return
        }
        show(
            profiles: profiles,
            activeProfileID: activeProfileID,
            personaEnabled: personaEnabled,
            personasAvailable: personasAvailable,
            onSelect: onSelect
        )
    }

    func show(
        profiles: [Profile],
        activeProfileID: UUID,
        personaEnabled: Bool,
        personasAvailable: Bool,
        onSelect: @escaping @MainActor (PersonaWheelSelection) -> Void
    ) {
        hide()

        let panelSize = PersonaWheelLayout.panelSize

        let wheel = PersonaWheelView(
            profiles: profiles,
            activeProfileID: activeProfileID,
            personaEnabled: personaEnabled,
            personasAvailable: personasAvailable
        ) { [weak self] selection in
            self?.hide()
            onSelect(selection)
        }
        let hostingView = NSHostingView(rootView: wheel)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)

        let panel = PersonaWheelPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.onCancel = { [weak self] in self?.hide() }
        panel.setFrameOrigin(origin(near: NSEvent.mouseLocation, panelSize: panelSize))
        window = panel

        installDismissMonitors(for: panel)
        panel.makeKeyAndOrderFront(nil)
        panel.alphaValue = 0
        panel.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.94, y: 0.94))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.contentView?.animator().layer?.setAffineTransform(.identity)
        }
    }

    func hide() {
        removeDismissMonitors()
        guard let panel = window else { return }
        window = nil
        panel.orderOut(nil)
    }

    private func origin(near pointer: NSPoint, panelSize: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var x = pointer.x - panelSize.width / 2
        var y = pointer.y - 28
        x = min(max(x, visible.minX), visible.maxX - panelSize.width)
        y = min(max(y, visible.minY), visible.maxY - panelSize.height)
        return NSPoint(x: x, y: y)
    }

    private func installDismissMonitors(for panel: NSPanel) {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self, weak panel] _ in
            guard let self, let panel else { return }
            let point = NSEvent.mouseLocation
            if !panel.frame.contains(point) {
                Task { @MainActor in self.hide() }
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            if !self.belongsToPanel(event.window, panel: panel) {
                self.hide()
            }
            return event
        }
    }

    private func belongsToPanel(_ window: NSWindow?, panel: NSPanel) -> Bool {
        guard let window else { return false }
        if window === panel { return true }

        var parent = window.parent
        while let current = parent {
            if current === panel { return true }
            parent = current.parent
        }
        return panel.childWindows?.contains(where: { $0 === window }) == true
    }

    private func removeDismissMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    deinit {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    }
}

@MainActor
private final class PersonaWheelPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private struct PersonaWheelView: View {
    struct Option: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let selection: PersonaWheelSelection?
        let isSelected: Bool
        let isEnabled: Bool

        var isMore: Bool { selection == nil }
    }

    private static let maximumVisibleOptions = 6
    private let allOptions: [Option]
    private let visibleOptions: [Option]
    private let currentName: String
    private let personasAvailable: Bool
    private let onSelect: @MainActor (PersonaWheelSelection) -> Void
    @State private var hoveredOptionID: String?

    init(
        profiles: [Profile],
        activeProfileID: UUID,
        personaEnabled: Bool,
        personasAvailable: Bool,
        onSelect: @escaping @MainActor (PersonaWheelSelection) -> Void
    ) {
        var options = [Option(
            id: "no-persona",
            name: "No persona",
            symbol: "textformat",
            selection: .noPersona,
            isSelected: !personaEnabled,
            isEnabled: true
        )]
        options.append(contentsOf: profiles.map { profile in
            Option(
                id: profile.id.uuidString,
                name: Self.displayName(for: profile.name),
                symbol: PersonaIconResolver.symbol(for: profile),
                selection: .profile(profile),
                isSelected: personaEnabled && profile.id == activeProfileID,
                isEnabled: personasAvailable
            )
        })
        allOptions = options
        visibleOptions = Self.visibleOptions(from: options)
        currentName = personaEnabled
            ? profiles.first(where: { $0.id == activeProfileID })?.name ?? "No persona"
            : "No persona"
        self.personasAvailable = personasAvailable
        self.onSelect = onSelect
    }

    var body: some View {
        GeometryReader { proxy in
            let center = wheelCenter(in: proxy.size)
            let radius = wheelRadius(in: proxy.size)

            PersonaWheelGlassContainer {
                ZStack {
                    PersonaWheelShellLayer()

                    ForEach(Array(visibleOptions.enumerated()), id: \.element.id) { index, option in
                        let point = position(
                            index: index,
                            count: visibleOptions.count,
                            center: center,
                            radius: radius
                        )
                        if option.isMore {
                            PersonaMoreButton(options: allOptions) { selection in
                                onSelect(selection)
                            } onHover: { hovering in
                                hoveredOptionID = hovering ? option.id : nil
                            }
                            .position(point)
                        } else if let selection = option.selection {
                            PersonaOptionButton(option: option) {
                                onSelect(selection)
                            } onHover: { hovering in
                                hoveredOptionID = hovering ? option.id : nil
                            }
                            .position(point)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: hoveredOptionID == nil
                            ? "checkmark.circle.fill"
                            : "arrow.right.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(nsColor: DesignTokens.brand500))
                        Text(statusText)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 146, height: 32)
                    .modifier(PersonaStatusGlassSurface())
                    .position(center)

                    if !personasAvailable {
                        Text("Enable Persona AI in Settings")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                            .position(
                                x: center.x,
                                y: center.y + 46
                            )
                    }
                }
            }
        }
        .frame(width: PersonaWheelLayout.panelSize.width, height: PersonaWheelLayout.panelSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hush.personaWheel")
        .accessibilityLabel("Persona selector")
        .accessibilityValue("Full circle")
    }

    private static func visibleOptions(from options: [Option]) -> [Option] {
        guard options.count > maximumVisibleOptions else { return options }

        let noPersona = options[0]
        let profileOptions = Array(options.dropFirst())
        var visibleProfiles = Array(profileOptions.prefix(maximumVisibleOptions - 2))

        if let active = profileOptions.first(where: \.isSelected),
           !visibleProfiles.contains(where: { $0.id == active.id }) {
            visibleProfiles.removeLast()
            visibleProfiles.append(active)
            let sourceOrder = Dictionary(
                uniqueKeysWithValues: profileOptions.enumerated().map { ($0.element.id, $0.offset) }
            )
            visibleProfiles.sort {
                sourceOrder[$0.id, default: 0] < sourceOrder[$1.id, default: 0]
            }
        }

        let more = Option(
            id: "more-personas",
            name: "More",
            symbol: "ellipsis",
            selection: nil,
            isSelected: false,
            isEnabled: true
        )
        return [noPersona] + visibleProfiles + [more]
    }

    private func wheelCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func wheelRadius(in size: CGSize) -> CGFloat {
        min(128, size.width * 0.32)
    }

    private func position(
        index: Int,
        count: Int,
        center: CGPoint,
        radius: CGFloat
    ) -> CGPoint {
        let angle = 150 + (360 / Double(count)) * Double(index)
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }

    private var statusText: String {
        guard let hoveredOptionID else {
            return "\(Self.displayName(for: currentName)) active"
        }
        if hoveredOptionID == "more-personas" {
            return "View all personas"
        }
        guard let hovered = visibleOptions.first(where: { $0.id == hoveredOptionID }) else {
            return "\(Self.displayName(for: currentName)) active"
        }
        return "Select \(hovered.name)"
    }

    private static func displayName(for name: String) -> String {
        name.caseInsensitiveCompare("Code comment") == .orderedSame ? "Code" : name
    }

}

private struct PersonaWheelShellLayer: View {
    var body: some View {
        PersonaWheelRingShell()
            .fill(Color.clear)
            .modifier(PersonaWheelGlassSurface())
    }
}

private struct PersonaMoreButton: View {
    let options: [PersonaWheelView.Option]
    let onSelect: (PersonaWheelSelection) -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false
    @State private var isPresented = false
    @State private var searchText = ""

    var body: some View {
        Button {
            searchText = ""
            isPresented = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.86))
                Text("More")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.94))
            }
            .frame(width: 68, height: 68)
            .modifier(PersonaOptionGlassSurface(
                isSelected: false,
                isEnabled: true,
                isHovered: isHovered
            ))
            .scaleEffect(isHovered ? 1.08 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PersonaAllPersonasPopover(
                options: options,
                searchText: $searchText
            ) { selection in
                isPresented = false
                onSelect(selection)
            }
        }
        .onHover {
            isHovered = $0
            onHover($0)
        }
        .accessibilityLabel("More")
        .accessibilityHint("View all personas")
    }
}

private struct PersonaAllPersonasPopover: View {
    let options: [PersonaWheelView.Option]
    @Binding var searchText: String
    let onSelect: (PersonaWheelSelection) -> Void

    private var filteredOptions: [PersonaWheelView.Option] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("All personas")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(options.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            TextField("Search personas", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("hush.personaWheel.moreSearch")

            if filteredOptions.isEmpty {
                ContentUnavailableView(
                    "No matching personas",
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredOptions) { option in
                            if let selection = option.selection {
                                Button {
                                    onSelect(selection)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: option.symbol)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(option.isSelected
                                                ? Color(nsColor: DesignTokens.brand500)
                                                : Color.secondary)
                                            .frame(width: 20)

                                        Text(option.name)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Spacer(minLength: 8)

                                        if option.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(Color(nsColor: DesignTokens.brand500))
                                        }
                                    }
                                    .padding(.horizontal, 9)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(
                                        option.isSelected
                                            ? Color(nsColor: DesignTokens.brand300).opacity(0.16)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!option.isEnabled)
                                .accessibilityLabel(option.name)
                                .accessibilityAddTraits(option.isSelected ? .isSelected : [])
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(filteredOptions.count) * 39, 280))
            }
        }
        .padding(12)
        .frame(width: 252)
    }
}

private struct PersonaWheelGlassContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                content
            }
        } else {
            content
        }
    }
}

/// Uses the system Liquid Glass renderer where available. Controls inside the
/// platter use fills and vibrancy instead of stacking additional glass layers.
private struct PersonaWheelGlassSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.clear, in: PersonaWheelRingShell())
                .overlay {
                    PersonaWheelRingShell()
                        .stroke(Color.primary.opacity(0.14), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        } else {
            content
                .background(.ultraThinMaterial, in: PersonaWheelRingShell())
                .overlay {
                    PersonaWheelRingShell()
                        .stroke(Color.primary.opacity(0.16), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        }
    }
}

private struct PersonaOptionButton: View {
    let option: PersonaWheelView.Option
    let action: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: option.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(option.name)
                    .font(.system(size: 10.5, weight: option.isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(option.isEnabled ? 0.94 : 0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
            }
            .frame(width: 68, height: 68)
            .modifier(PersonaOptionGlassSurface(
                isSelected: option.isSelected,
                isEnabled: option.isEnabled,
                isHovered: isHovered
            ))
            .scaleEffect(optionScale)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
        .onHover {
            isHovered = $0
            onHover($0)
        }
        .accessibilityLabel(option.name)
        .modifier(SelectedAccessibilityTrait(isSelected: option.isSelected))
    }

    private var iconColor: Color {
        if !option.isEnabled { return Color.primary.opacity(0.3) }
        if option.isSelected || isHovered { return Color.primary.opacity(0.94) }
        return Color.primary.opacity(0.82)
    }

    private var optionScale: CGFloat {
        if isHovered && option.isEnabled { return 1.08 }
        return 1
    }
}

private struct PersonaStatusGlassSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 0.7))
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.16), lineWidth: 0.7))
        }
    }
}

private struct PersonaOptionGlassSurface: ViewModifier {
    let isSelected: Bool
    let isEnabled: Bool
    let isHovered: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background { stateFill }
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay { stateBorder }
        } else {
            content
                .background {
                    ZStack {
                        Circle().fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                        stateFill
                    }
                }
                .overlay { stateBorder }
                .shadow(color: .black.opacity(isHovered ? 0.12 : 0.06), radius: isHovered ? 8 : 3, y: 2)
        }
    }

    @ViewBuilder
    private var stateFill: some View {
        if isSelected {
            Circle()
                .fill(HUDPalette.aurora)
                .opacity(isHovered ? 0.6 : 0.5)
        } else if isHovered && isEnabled {
            Circle()
                .fill(HUDPalette.proofAura)
                .opacity(0.14)
        }
    }

    @ViewBuilder
    private var stateBorder: some View {
        if isSelected {
            Circle()
                .stroke(HUDPalette.proofAura, lineWidth: 1.3)
                .opacity(0.9)
        } else {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
        }
    }
}

private struct SelectedAccessibilityTrait: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content
        }
    }
}

private struct PersonaWheelRingShell: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2 - 10
        let innerRadius = min(76, outerRadius * 0.42)
        var path = Path()
        path.move(to: CGPoint(x: center.x + outerRadius, y: center.y))
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(360),
            clockwise: false
        )
        path.closeSubpath()
        path.move(to: CGPoint(x: center.x + innerRadius, y: center.y))
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(360),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

#if DEBUG
@MainActor
final class PersonaWheelDebugJourneyController {
    private static let researchProfile = Profile(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        name: "Research",
        systemPrompt: "Structure findings clearly."
    )
    private static let legalProfile = Profile(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        name: "Legal",
        systemPrompt: "Use precise legal language."
    )
    private static let productProfile = Profile(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        name: "Product",
        systemPrompt: "Write concise product copy."
    )

    private let wheel = PersonaWheelController()
    private let window: NSWindow
    private let confirmation = NSTextField(labelWithString: "Persona shortcut pressed")

    init() {
        let content = PersonaWheelDebugBackgroundView()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "hush Persona Wheel"
        window.isRestorable = false
        window.contentView = content

        confirmation.font = .systemFont(ofSize: 22, weight: .semibold)
        confirmation.textColor = .white
        confirmation.alignment = .center
        confirmation.translatesAutoresizingMaskIntoConstraints = false
        confirmation.setAccessibilityLabel("Persona shortcut pressed")
        content.addSubview(confirmation)
        NSLayoutConstraint.activate([
            confirmation.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            confirmation.topAnchor.constraint(equalTo: content.topAnchor, constant: 72),
            confirmation.widthAnchor.constraint(equalToConstant: 500),
        ])
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.showWheel()
        }
    }

    private func showWheel() {
        let arguments = ProcessInfo.processInfo.arguments
        let profiles: [Profile]
        let activeProfileID: UUID
        let personaEnabled: Bool
        if arguments.contains("--preview-persona-wheel-small") {
            profiles = Array(Profile.seededProfiles.prefix(3))
            activeProfileID = Profile.defaultProfileID
            personaEnabled = false
        } else if arguments.contains("--preview-persona-wheel-overflow") {
            profiles = Profile.seededProfiles + [
                Self.researchProfile,
                Self.legalProfile,
                Self.productProfile,
            ]
            activeProfileID = Self.productProfile.id
            personaEnabled = true
        } else {
            profiles = Profile.seededProfiles
            activeProfileID = Profile.defaultProfileID
            personaEnabled = false
        }
        wheel.show(
            profiles: profiles,
            activeProfileID: activeProfileID,
            personaEnabled: personaEnabled,
            personasAvailable: true
        ) { [weak self] selection in
            let message = switch selection {
            case .noPersona: "No persona active"
            case .profile(let profile): "\(profile.name) active"
            }
            self?.confirmation.stringValue = message
            self?.confirmation.setAccessibilityLabel(message)
        }
    }
}

private final class PersonaWheelDebugBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.05, green: 0.08, blue: 0.14, alpha: 1),
            NSColor(srgbRed: 0.22, green: 0.13, blue: 0.27, alpha: 1),
            NSColor(srgbRed: 0.48, green: 0.23, blue: 0.22, alpha: 1),
        ])
        gradient?.draw(in: bounds, angle: -28)
    }
}
#endif
