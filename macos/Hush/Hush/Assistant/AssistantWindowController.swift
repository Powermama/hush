import AppKit
import SwiftUI

@MainActor
final class AssistantWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var cursor: AssistantCursorController?
    private var interruptionMonitor: Any?
    private(set) var session: AssistantSession?
    var onSettings: (() -> Void)?

    var focusedVoiceSessionID: UUID? {
        guard panel?.isKeyWindow == true, let session else { return nil }
        return session.destination.context.id
    }

    var canRecordRequest: Bool { session?.canSubmit == true }

    func receiveTranscript(_ text: String, sessionID: UUID) {
        session?.receiveTranscript(text, contextID: sessionID)
    }

    func open(from application: NSRunningApplication?) {
        close()
        do {
            let destination = try MailAssistantDestination.capture(from: application)
            let provider = Settings.shared.llmProvider
            present(destination: destination, generator: AssistantLocalGenerator(provider: provider),
                    modelName: provider == .qwen35_2b || provider == .qwen35_4b ? provider.displayName : "Model setup needed")
        } catch {
            present(content: AnyView(AssistantUnavailableView(message: error.localizedDescription, onSettings: { [weak self] in
                self?.onSettings?()
            })))
        }
    }

    func present(destination: any AssistantDestination, generator: any AssistantGenerating, modelName: String) {
        close()
        let session = AssistantSession(destination: destination, generator: generator)
        self.session = session
        interruptionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != MailAssistantDestination.pasteEventMarker else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.cursor?.hide()
                if (event.type == .keyDown && event.keyCode == 53) || self.session?.isBusy == true { self.session?.stop() }
            }
        }
        cursor = AssistantCursorController()
        session.onTargetVisibilityChange = { [weak self, weak destination] visible in
            guard let self else { return }
            if visible, let frame = destination?.targetFrame { self.cursor?.show(at: frame) }
            else { self.cursor?.hide() }
        }
        present(content: AnyView(AssistantView(session: session, modelName: modelName,
                                             onSettings: { [weak self] in self?.onSettings?() })))
        if let frame = destination.targetFrame { cursor?.show(at: frame) }
    }

    private func present(content: AnyView) {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let panel = AssistantPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: min(640, frame.height - 100)),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Hey Hush"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.minSize = NSSize(width: 380, height: 480)
        panel.contentView = NSHostingView(rootView: content)
        panel.delegate = self
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if let session = self.session { session.stop() }
            else { self.close() }
        }
        panel.setAccessibilityIdentifier("hush.assistant.window")
        panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 448, y: frame.maxY - 56))
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        if let interruptionMonitor { NSEvent.removeMonitor(interruptionMonitor); self.interruptionMonitor = nil }
        session?.stop()
        session = nil
        cursor?.hide()
        cursor = nil
        panel?.close()
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        session?.stop()
        cursor?.hide()
        if let interruptionMonitor { NSEvent.removeMonitor(interruptionMonitor); self.interruptionMonitor = nil }
    }
}

@MainActor
private final class AssistantPanel: NSPanel {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

private struct AssistantView: View {
    @ObservedObject var session: AssistantSession
    let modelName: String
    let onSettings: () -> Void
    @State private var copied = false
    @FocusState private var requestFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays").font(.system(size: 23, weight: .medium)).foregroundStyle(Color(nsColor: DesignTokens.brand500))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hey Hush").font(.system(size: 21, weight: .semibold))
                    Text("A little help, right here.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("PREVIEW").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "envelope").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.destination.context.applicationName).fontWeight(.medium)
                    Text(session.destination.context.destinationName).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "scope").foregroundStyle(Color(nsColor: DesignTokens.brand500))
                    .accessibilityLabel("Destination bound")
            }
            .padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text("What would you like to write?").font(.system(size: 13, weight: .medium))
                TextField("Write a friendly reply confirming…", text: $session.request, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.plain).padding(11)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(.primary.opacity(0.13), lineWidth: 1))
                    .focused($requestFocused).accessibilityIdentifier("hush.assistant.request")
                    .disabled(!session.canSubmit)
                HStack {
                    Text("Type, or use your dictation shortcut.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(session.proposal == nil ? "Write draft" : "Revise") { copied = false; session.submit(session.request) }
                        .accessibilityIdentifier("hush.assistant.generate")
                        .disabled(session.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.canSubmit)
                }
            }

            if let draft = session.proposal, draft.decision == .draft {
                ScrollView {
                    Text(draft.plainText).textSelection(.enabled).font(.system(size: 14)).lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .accessibilityIdentifier("hush.assistant.draft")
                }
                .frame(minHeight: 100, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.08), lineWidth: 1))
            } else {
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 9) {
                if session.isBusy { ProgressView().controlSize(.small) }
                else { Image(systemName: session.phase == .complete ? "checkmark.circle" : "info.circle").foregroundStyle(.secondary) }
                Text(session.status).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hush.assistant.status")
            }
            HStack {
                if let proposal = session.proposal, proposal.decision == .draft {
                    Button(copied ? "Copied" : "Copy draft") {
                        if let item = try? AssistantDraftRenderer.pasteboardItem(proposal) {
                            NSPasteboard.general.clearContents()
                            copied = NSPasteboard.general.writeObjects([item])
                        }
                    }.accessibilityIdentifier("hush.assistant.copy")
                        .disabled(session.phase == .applying)
                }
                Spacer()
                if session.isBusy {
                    Button("Stop", role: .cancel) { session.stop() }.accessibilityIdentifier("hush.assistant.stop")
                } else {
                    Button("Insert into Mail") { session.insert() }.buttonStyle(.borderedProminent)
                        .disabled(!session.canInsert).accessibilityIdentifier("hush.assistant.insert")
                }
            }
            Divider()
            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                Text("On this Mac").fontWeight(.medium)
                Spacer()
                Button(modelName, action: onSettings).buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.system(size: 11))
        }
        .padding(22).frame(minWidth: 380, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { requestFocused = true }
        .onExitCommand { session.stop() }
    }
}

private struct AssistantUnavailableView: View {
    let message: String
    let onSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "cursorarrow.rays").font(.system(size: 32)).foregroundStyle(Color(nsColor: DesignTokens.brand500))
            Text("Hey Hush").font(.system(size: 25, weight: .semibold))
            Text("Start in your email").font(.headline)
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("hush.assistant.unavailable")
            Text("This preview writes and inserts email drafts in Apple Mail. Open it with Control + Fn while the email body is focused.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Button("Open Hush settings", action: onSettings)
            Spacer()
            Label("Writing stays on this Mac", systemImage: "lock.shield").font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(28).frame(minWidth: 380, minHeight: 480).background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A separate noninteractive pointer. It never moves or intercepts the user's cursor.
@MainActor
private final class AssistantCursorController {
    private var panel: NSPanel?
    func show(at accessibilityFrame: CGRect) {
        guard let mainDisplay = NSScreen.screens.first else { return }
        let point = NSPoint(x: accessibilityFrame.minX + 8,
                            y: mainDisplay.frame.maxY - accessibilityFrame.minY - 36)
        let panel = self.panel ?? NSPanel(contentRect: NSRect(x: point.x, y: point.y, width: 72, height: 30),
                                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView:
            HStack(spacing: 4) {
                Image(systemName: "cursorarrow").font(.system(size: 14, weight: .semibold))
                Text("hush").font(.system(size: 11, weight: .semibold))
            }.foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color(nsColor: DesignTokens.brand500), in: Capsule())
                .accessibilityLabel("Hush email destination")
        )
        panel.setFrameOrigin(point)
        panel.orderFrontRegardless()
        self.panel = panel
    }
    func hide() { panel?.orderOut(nil) }
}
