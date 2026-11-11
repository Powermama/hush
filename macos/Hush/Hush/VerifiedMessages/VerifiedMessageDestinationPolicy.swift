import AppKit

enum VerifiedMessageDestinationMode: String, Codable, Sendable, CaseIterable {
    case smart
    case everywhere

    var displayName: String {
        switch self {
        case .smart: "Smart"
        case .everywhere: "Everywhere"
        }
    }
}

struct VerifiedMessageAppException: Codable, Equatable, Hashable, Sendable {
    let bundleIdentifier: String
    let displayName: String

    init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

struct VerifiedMessageWebsiteException: Codable, Equatable, Hashable, Sendable {
    let host: String

    init?(host: String) {
        guard let normalized = Self.normalized(host) else { return nil }
        self.host = normalized
    }

    nonisolated static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let urlValue = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URL(string: urlValue)?.host(percentEncoded: false)?
            .trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func matches(_ candidateHost: String) -> Bool {
        guard let candidate = Self.normalized(candidateHost) else { return false }
        return candidate == host || candidate.hasSuffix(".\(host)")
    }
}

enum VerifiedMessageDestinationSuppression: Equatable, Sendable {
    case terminal(applicationName: String)
    case exception(applicationName: String)
    case website(host: String)
    case browserAddressOrSearch
    case secureField

    var notice: String {
        switch self {
        case .terminal(let applicationName), .exception(let applicationName):
            "Signature hidden in \(applicationName)"
        case .website(let host):
            "Signature hidden on \(host)"
        case .browserAddressOrSearch:
            "Signature hidden in browser search"
        case .secureField:
            "Signature hidden in secure field"
        }
    }
}

enum VerifiedMessageDestinationDecision: Equatable, Sendable {
    case allowed
    case hidden(VerifiedMessageDestinationSuppression)

    var allowsProof: Bool {
        self == .allowed
    }

    var suppression: VerifiedMessageDestinationSuppression? {
        guard case .hidden(let reason) = self else { return nil }
        return reason
    }
}

enum VerifiedMessageDestinationPolicy {
    private static let terminalBundleIdentifiers = Set([
        "co.zeit.hyper",
        "com.apple.terminal",
        "com.github.wez.wezterm",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.warp-stable",
        "io.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "org.tabby",
    ])

    static func decision(
        mode: VerifiedMessageDestinationMode,
        exceptions: [VerifiedMessageAppException],
        websiteExceptions: [VerifiedMessageWebsiteException] = [],
        bundleIdentifier: String?,
        applicationName: String?,
        isSecureField: Bool,
        websiteHost: String? = nil,
        isBrowserAddressOrSearchField: Bool = false
    ) -> VerifiedMessageDestinationDecision {
        if isSecureField {
            return .hidden(.secureField)
        }
        if isBrowserAddressOrSearchField {
            return .hidden(.browserAddressOrSearch)
        }
        if mode == .smart,
           let websiteHost,
           websiteExceptions.contains(where: { $0.matches(websiteHost) }) {
            return .hidden(.website(
                host: VerifiedMessageWebsiteException.normalized(websiteHost) ?? websiteHost
            ))
        }
        guard mode == .smart,
              let normalizedBundleIdentifier = normalized(bundleIdentifier) else {
            return .allowed
        }
        let resolvedName = applicationName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "this terminal"
        if isKnownTerminal(normalizedBundleIdentifier) {
            return .hidden(.terminal(applicationName: resolvedName))
        }
        if let exception = exceptions.first(where: {
            normalized($0.bundleIdentifier) == normalizedBundleIdentifier
        }) {
            return .hidden(.exception(applicationName: exception.displayName))
        }
        return .allowed
    }

    static func isKnownTerminal(_ bundleIdentifier: String) -> Bool {
        guard let normalizedBundleIdentifier = normalized(bundleIdentifier) else { return false }
        return terminalBundleIdentifiers.contains(normalizedBundleIdentifier)
    }

    private static func normalized(_ bundleIdentifier: String?) -> String? {
        guard let normalized = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty else { return nil }
        return normalized
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@MainActor
enum FocusedDestinationInspector {
    struct Context: Equatable, Sendable {
        let isSecureField: Bool
        let websiteHost: String?
        let isBrowserAddressOrSearchField: Bool
    }

    private static let browserBundleIdentifiers = Set([
        "com.apple.safari",
        "com.brave.browser",
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.microsoft.edgemac",
        "com.operasoftware.opera",
        "company.thebrowser.browser",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
    ])

    static func context(for application: NSRunningApplication? = nil) -> Context {
        let isBrowser = application?.bundleIdentifier
            .map { browserBundleIdentifiers.contains($0.lowercased()) } ?? false
        guard PermissionsChecker.isAccessibilityGranted,
              let focusedElement = focusedElement() else {
            return Context(
                isSecureField: false,
                websiteHost: nil,
                isBrowserAddressOrSearchField: false
            )
        }

        let isSecureField = stringAttribute(kAXSubroleAttribute, from: focusedElement)
            == "AXSecureTextField"
        guard isBrowser else {
            return Context(
                isSecureField: isSecureField,
                websiteHost: nil,
                isBrowserAddressOrSearchField: false
            )
        }

        let ancestors = ancestorChain(from: focusedElement)
        let webArea = ancestors.first {
            stringAttribute(kAXRoleAttribute, from: $0) == "AXWebArea"
        }
        let isInsideWebContent = webArea != nil
        let focusedRole = stringAttribute(kAXRoleAttribute, from: focusedElement)
        let isTextControl = focusedRole.map {
            ["AXTextField", "AXComboBox", "AXSearchField"].contains($0)
        } ?? false
        let isBrowserAddressOrSearchField = isTextControl && !isInsideWebContent
        let websiteHost = webArea.flatMap(websiteHost(from:))
            ?? application.flatMap(websiteHostFromFocusedWindow)

        return Context(
            isSecureField: isSecureField,
            websiteHost: websiteHost,
            isBrowserAddressOrSearchField: isBrowserAddressOrSearchField
        )
    }

    static func isSecureTextField() -> Bool {
        context(for: NSWorkspace.shared.frontmostApplication).isSecureField
    }

    private static func focusedElement() -> AXUIElement? {
        guard PermissionsChecker.isAccessibilityGranted else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(focusedValue, to: AXUIElement.self)
    }

    private static func websiteHostFromFocusedWindow(
        _ application: NSRunningApplication
    ) -> String? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let window = elementAttribute(kAXFocusedWindowAttribute, from: appElement) else {
            return nil
        }
        return websiteHost(from: window)
    }

    private static func ancestorChain(from element: AXUIElement) -> [AXUIElement] {
        var result = [element]
        var current = element
        for _ in 0..<12 {
            guard let parent = elementAttribute(kAXParentAttribute, from: current) else { break }
            result.append(parent)
            current = parent
        }
        return result
    }

    private static func websiteHost(from element: AXUIElement) -> String? {
        for attribute in ["AXURL", kAXDocumentAttribute] {
            guard let value = attributeValue(attribute, from: element) else { continue }
            let url: URL?
            if let candidate = value as? URL {
                url = candidate
            } else if let candidate = value as? String {
                url = URL(string: candidate)
            } else {
                url = nil
            }
            if let host = url?.host(percentEncoded: false) {
                return VerifiedMessageWebsiteException.normalized(host)
            }
        }
        return nil
    }

    private static func elementAttribute(
        _ name: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = attributeValue(name, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        attributeValue(name, from: element) as? String
    }

    private static func attributeValue(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
