import ApplicationServices
import Cocoa

let pollInterval: TimeInterval = 5
let debugMode = CommandLine.arguments.contains("--debug")

let watchedBundleIDs = [
    "com.apple.notificationcenterui",
    "com.apple.NotificationCenter",
    "com.apple.SoftwareUpdateNotificationManager",
    "com.apple.UserNotificationCenter",
]

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    print("[\(formatter.string(from: Date()))] \(message)")
}

func debug(_ message: String) {
    if debugMode { log("[debug] \(message)") }
}

func checkAccessibility() {
    if AXIsProcessTrusted() { return }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    print("Accessibility permission required.")
    print("Grant access in: System Settings > Privacy & Security > Accessibility")
    print("Then re-run this tool.")
    exit(1)
}

func getAXAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return value
}

func getAXChildren(_ element: AXUIElement) -> [AXUIElement] {
    guard let value = getAXAttribute(element, kAXChildrenAttribute),
          let children = value as? [AXUIElement] else { return [] }
    return children
}

func getAXRole(_ element: AXUIElement) -> String? {
    getAXAttribute(element, kAXRoleAttribute) as? String
}

func getAXTitle(_ element: AXUIElement) -> String? {
    getAXAttribute(element, kAXTitleAttribute) as? String
}

func getAXSubrole(_ element: AXUIElement) -> String? {
    getAXAttribute(element, kAXSubroleAttribute) as? String
}

func getAXValue(_ element: AXUIElement) -> String? {
    getAXAttribute(element, kAXValueAttribute) as? String
}

let dismissTitles = ["later", "close", "not now", "remind", "dismiss", "cancel"]
let updateKeywords = ["update", "available", "install", "restart", "tonight", "software"]

func collectAllText(_ element: AXUIElement, depth: Int = 0) -> String {
    if depth > 10 { return "" }
    var text = (getAXTitle(element) ?? "") + " " + (getAXValue(element) ?? "")
    for child in getAXChildren(element) {
        text += " " + collectAllText(child, depth: depth + 1)
    }
    return text
}

func getAXDescription(_ element: AXUIElement) -> String? {
    getAXAttribute(element, kAXDescriptionAttribute) as? String
}

func buttonLabel(_ element: AXUIElement) -> String {
    let title = getAXTitle(element) ?? ""
    if !title.isEmpty { return title.lowercased() }
    let desc = getAXDescription(element) ?? ""
    if !desc.isEmpty { return desc.lowercased() }
    return (getAXValue(element) ?? "").lowercased()
}

func collectAllButtons(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    var results: [AXUIElement] = []
    if depth > 10 { return results }
    if getAXRole(element) == kAXButtonRole as String {
        results.append(element)
    }
    for child in getAXChildren(element) {
        results.append(contentsOf: collectAllButtons(child, depth: depth + 1))
    }
    return results
}

func findDismissButton(_ element: AXUIElement) -> AXUIElement? {
    let buttons = collectAllButtons(element)
    if buttons.isEmpty { return nil }
    for button in buttons {
        let label = buttonLabel(button)
        if !label.isEmpty, dismissTitles.contains(where: { label.contains($0) }) {
            return button
        }
    }
    return buttons.last
}

func elementLooksLikeUpdateNotification(_ element: AXUIElement) -> Bool {
    let text = collectAllText(element).lowercased()
    return updateKeywords.filter { text.contains($0) }.count >= 2
}

func dumpTree(_ element: AXUIElement, indent: Int = 0, maxDepth: Int = 8) {
    if indent > maxDepth { return }
    let prefix = String(repeating: "  ", count: indent)
    let role = getAXRole(element) ?? "?"
    let title = getAXTitle(element) ?? ""
    let subrole = getAXSubrole(element) ?? ""
    let value = getAXValue(element) ?? ""
    if !title.isEmpty || !value.isEmpty || role == "AXButton" || role == "AXWindow" || role == "AXGroup" || role == "AXStaticText" {
        debug("\(prefix)[\(role)] title=\"\(title)\" sub=\"\(subrole)\" val=\"\(value)\"")
    }
    for child in getAXChildren(element) {
        dumpTree(child, indent: indent + 1, maxDepth: maxDepth)
    }
}

func scanAndDismiss() -> Bool {
    for bundleID in watchedBundleIDs {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            if debugMode {
                debug("Scanning \(bundleID) (pid \(pid))")
                dumpTree(appElement)
            }
            let candidates: [AXUIElement] =
                (getAXAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] ?? []) +
                getAXChildren(appElement)
            for el in candidates {
                if tryDismissElement(el, context: bundleID) { return true }
            }
        }
    }
    return false
}

func tryDismissElement(_ element: AXUIElement, context: String) -> Bool {
    if elementLooksLikeUpdateNotification(element) {
        debug("Found update-related content in \(context)")
        if let button = findDismissButton(element) {
            let label = buttonLabel(button)
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            log("Dismissed update notification (clicked '\(label.isEmpty ? "last button" : label)' in \(context))")
            return true
        }
        debug("Found update text but no buttons in \(context)")
    }
    return false
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var pollTimer: Timer?
    var lastTriggeredItem: NSMenuItem!

    func applicationDidFinishLaunching(_: Notification) {
        checkAccessibility()
        setupStatusBar()
        log("Scanning every \(Int(pollInterval))s for update notifications... (debug=\(debugMode))")
        _ = scanAndDismiss()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            if scanAndDismiss() {
                self?.updateLastTriggered()
            }
        }
    }

    func updateLastTriggered() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lastTriggeredItem.title = "Last triggered: \(formatter.string(from: Date()))"
    }

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.slash", accessibilityDescription: "NoUpdate")
        }
        let menu = NSMenu()

        let titleItem = NSMenuItem()
        let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        titleItem.attributedTitle = NSAttributedString(string: "NoUpdate", attributes: [.font: boldFont])
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let descItem = NSMenuItem(title: "Dismisses macOS update notifications", action: nil, keyEquivalent: "")
        descItem.isEnabled = false
        menu.addItem(descItem)

        menu.addItem(NSMenuItem.separator())

        lastTriggeredItem = NSMenuItem(title: "Last triggered: Never", action: nil, keyEquivalent: "")
        lastTriggeredItem.isEnabled = false
        menu.addItem(lastTriggeredItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
