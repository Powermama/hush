import AppKit
import ApplicationServices

/// Bounded public AX reads. Only one visible page is accepted as the current document.
@MainActor
struct CoworkerBrowserState {
    let url: URL?
    let tabCount: Int?
    var page: AXUIElement? = nil
    var loaded: Bool? = nil
    var hasPageContents = false

    var documentReady: Bool { page != nil && loaded != false && hasPageContents }

    /// Stable semantic content, excluding browser chrome, search suggestions and
    /// editable values. SPA URLs/AXLoaded may change before the main content does.
    func contentFingerprint() -> [String] {
        guard let page else { return [] }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(150))
        var stack: [(AXUIElement, Bool)] = [(page, false)]
        var visited = Set<CFHashCode>(), main: [String] = [], fallback: [String] = []
        var sawMain = false
        while let (node, insideMain) = stack.popLast(), visited.count < 350, ContinuousClock.now < deadline {
            guard visited.insert(CFHash(node)).inserted,
                  CoworkerAX.attribute("AXHidden", node) as? Bool != true else { continue }
            let role = CoworkerAX.string(kAXRoleAttribute, node) ?? ""
            let subrole = CoworkerAX.string(kAXSubroleAttribute, node) ?? ""
            guard !["AXLandmarkNavigation", "AXLandmarkBanner", "AXLandmarkSearch"].contains(subrole),
                  ![kAXComboBoxRole, kAXTextFieldRole, kAXTextAreaRole, "AXListBox", "AXMenu"].contains(role) else { continue }
            let inMain = insideMain || subrole == "AXLandmarkMain"
            sawMain = sawMain || inMain
            if ["AXLink", "AXHeading", kAXStaticTextRole].contains(role) {
                let label = CoworkerAX.label(node)
                let value = CoworkerAX.string(kAXValueAttribute, node) ?? ""
                let url = (CoworkerAX.attribute(kAXURLAttribute, node) as? URL)?.absoluteString ?? ""
                let token = [role, String(label.prefix(180)), String(value.prefix(180)), url].joined(separator: "|")
                if !label.isEmpty || !value.isEmpty || !url.isEmpty {
                    if inMain { main.append(token) }
                    else if role == "AXLink" { fallback.append(token) }
                }
            }
            if main.count >= 24 { break }
            if let children = CoworkerAX.attribute(kAXChildrenAttribute, node) as? [AXUIElement] {
                stack.append(contentsOf: children.prefix(350).reversed().map { ($0, inMain) })
            }
        }
        return Array((sawMain ? main : fallback).prefix(24))
    }

    static func isTab(role: String, subrole: String?, insideTabGroup: Bool) -> Bool {
        // Safari's tab buttons are siblings of the content tab group. Chromium
        // also exposes radio buttons inside a tab group. Neither needs a title.
        subrole == "AXTabButton" || (insideTabGroup && role == kAXRadioButtonRole)
    }

    static func read(_ window: AXUIElement) -> Self {
        var queue: [(AXUIElement, Bool)] = [(window, false)]
        var index = 0, tabs = 0, urls = Set<URL>(), visited = Set<CFHashCode>()
        var truncated = false
        var pages: [AXUIElement] = []
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(200))
        while index < queue.count, index < 300, ContinuousClock.now < deadline {
            let (node, inTabs) = queue[index]; index += 1
            guard visited.insert(CFHash(node)).inserted,
                  CoworkerAX.attribute("AXHidden", node) as? Bool != true else { continue }
            let role = CoworkerAX.string(kAXRoleAttribute, node) ?? ""
            if role == "AXWebArea" {
                pages.append(node)
                if let url = CoworkerAX.attribute(kAXURLAttribute, node) as? URL { urls.insert(url) }
                continue
            }
            if isTab(role: role, subrole: CoworkerAX.string(kAXSubroleAttribute, node), insideTabGroup: inTabs) {
                tabs += 1
                continue // Do not inspect every tab's close button and favicon.
            }
            if let children = CoworkerAX.attribute(kAXChildrenAttribute, node) as? [AXUIElement] {
                let available = max(0, 300 - queue.count)
                truncated = truncated || children.count > available
                queue.append(contentsOf: children.prefix(available).map { ($0, inTabs || role == "AXTabGroup") })
            }
        }
        let complete = !truncated && index == queue.count && ContinuousClock.now < deadline
        let page = complete && pages.count == 1 ? pages.first : nil
        return .init(url: page != nil && urls.count == 1 ? urls.first : nil,
                     tabCount: complete && tabs > 0 ? tabs : nil,
                     page: page,
                     loaded: page.flatMap { CoworkerAX.attribute("AXLoaded", $0) as? Bool },
                     hasPageContents: page.map { !(CoworkerAX.attribute(kAXChildrenAttribute, $0) as? [AXUIElement] ?? []).isEmpty } ?? false)
    }

    static func insidePage(_ element: AXUIElement, window: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        var foundPage = false
        for _ in 0..<24 {
            guard let node = current else { return false }
            if CFEqual(node, window) { return foundPage }
            if CoworkerAX.string(kAXRoleAttribute, node) == "AXWebArea" { foundPage = true }
            current = CoworkerAX.element(kAXParentAttribute, node)
        }
        return false
    }
}

/// A URL match and an old, populated AXWebArea are not a completed SPA transition.
/// Require fresh content to settle across observations, without a fixed page-load sleep.
struct CoworkerPageReadiness {
    let previous: [String]
    private var candidate: [String] = []
    private var since: Duration?

    init(previous: [String]) { self.previous = previous }

    mutating func observe(documentReady: Bool, urlMatches: Bool, content: [String], elapsed: Duration,
                          requiresContentChange: Bool) -> Bool {
        guard documentReady, urlMatches, !content.isEmpty,
              !requiresContentChange || previous.isEmpty || content != previous else {
            candidate = []; since = nil
            return false
        }
        if candidate != content { candidate = content; since = elapsed }
        return since.map { elapsed - $0 >= .milliseconds(350) } ?? false
    }
}
