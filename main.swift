import ApplicationServices
import Cocoa
import ServiceManagement

let pollInterval: TimeInterval = 5
let debugMode = CommandLine.arguments.contains("--debug")
setvbuf(stdout, nil, _IOLBF, 0)

let watchedBundleIDs = [
    "com.apple.notificationcenterui",
    "com.apple.SoftwareUpdateNotificationManager",
    "com.apple.UserNotificationCenter",
]

let updateOnlyBundleID = "com.apple.SoftwareUpdateNotificationManager"

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    print("[\(formatter.string(from: Date()))] \(message)")
}

func debug(_ message: String) {
    if debugMode { log("[debug] \(message)") }
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
let dangerTitles = ["install", "restart", "update", "upgrade", "download", "tonight"]
let updateAnchors = ["update", "upgrade"]
let updateKeywords = ["update", "upgrade", "available", "install", "restart", "tonight", "software"]

func collectAllText(_ element: AXUIElement, depth: Int = 0) -> String {
    if depth > 10 { return "" }
    var text = (getAXTitle(element) ?? "") + " " + (getAXValue(element) ?? "")
        + " " + (getAXDescription(element) ?? "")
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
    for button in buttons {
        let label = buttonLabel(button)
        if label.isEmpty { continue }
        if dangerTitles.contains(where: { label.contains($0) }) { continue }
        if dismissTitles.contains(where: { label.contains($0) }) {
            return button
        }
    }
    debug("No dismiss button among: \(buttons.map(buttonLabel))")
    return nil
}

func elementLooksLikeUpdateNotification(_ element: AXUIElement) -> Bool {
    let text = collectAllText(element).lowercased()
    guard updateAnchors.contains(where: { text.contains($0) }) else { return false }
    return updateKeywords.filter { text.contains($0) }.count >= 2
}

let notificationSubroles = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]

func collectNotificationElements(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    if depth > 10 { return [] }
    if let subrole = getAXSubrole(element), notificationSubroles.contains(subrole) {
        return [element]
    }
    return getAXChildren(element).flatMap { collectNotificationElements($0, depth: depth + 1) }
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
            _ = AXUIElementSetMessagingTimeout(appElement, 1.0)
            if debugMode {
                debug("Scanning \(bundleID) (pid \(pid))")
                dumpTree(appElement)
            }
            for candidate in getAXChildren(appElement) {
                if getAXRole(candidate) == kAXMenuBarRole as String { continue }
                let notifications = collectNotificationElements(candidate)
                let targets = notifications.isEmpty ? [candidate] : notifications
                for target in targets {
                    if tryDismissElement(target, context: bundleID) { return true }
                }
            }
        }
    }
    return false
}

func tryDismissElement(_ element: AXUIElement, context: String) -> Bool {
    let isUpdate = context == updateOnlyBundleID || elementLooksLikeUpdateNotification(element)
    guard isUpdate else { return false }
    debug("Found update-related content in \(context)")
    guard let button = findDismissButton(element) else {
        debug("Found update text but no dismiss button in \(context)")
        return false
    }
    let label = buttonLabel(button)
    let err = AXUIElementPerformAction(button, kAXPressAction as CFString)
    guard err == .success else {
        debug("Press failed (AXError \(err.rawValue)) on '\(label)' in \(context)")
        return false
    }
    log("Dismissed update notification (clicked '\(label)' in \(context))")
    return true
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var pollTimer: Timer?
    var lastTriggeredItem: NSMenuItem!
    let scanQueue = DispatchQueue(label: "com.local.NoUpdate.scan")

    func applicationDidFinishLaunching(_: Notification) {
        if !UserDefaults.standard.bool(forKey: "launchAtLoginDisabled"),
           SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        setupStatusBar()
        if AXIsProcessTrusted() {
            startScanning()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            log("Waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility)...")
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                if AXIsProcessTrusted() {
                    self?.pollTimer?.invalidate()
                    self?.startScanning()
                }
            }
        }
    }

    func startScanning() {
        log("Scanning every \(Int(pollInterval))s for update notifications... (debug=\(debugMode))")
        runScan()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.runScan()
        }
    }

    func runScan() {
        scanQueue.async { [weak self] in
            if scanAndDismiss() {
                DispatchQueue.main.async { self?.updateLastTriggered() }
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

        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            UserDefaults.standard.set(true, forKey: "launchAtLoginDisabled")
        } else {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(false, forKey: "launchAtLoginDisabled")
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
