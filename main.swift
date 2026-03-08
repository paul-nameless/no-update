import ApplicationServices
import Cocoa

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    print("[\(formatter.string(from: Date()))] \(message)")
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
    guard let value = getAXAttribute(element, kAXRoleAttribute) else { return nil }
    return value as? String
}

func getAXTitle(_ element: AXUIElement) -> String? {
    guard let value = getAXAttribute(element, kAXTitleAttribute) else { return nil }
    return value as? String
}

func findButtons(_ element: AXUIElement, withTitle search: String) -> [AXUIElement] {
    var results: [AXUIElement] = []
    if getAXRole(element) == kAXButtonRole as String,
       let title = getAXTitle(element),
       title.contains(search)
    {
        results.append(element)
    }
    for child in getAXChildren(element) {
        results.append(contentsOf: findButtons(child, withTitle: search))
    }
    return results
}

func dismissUpdateNotification() {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
        return
    }
    let pid = app.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)
    guard let windowsRef = getAXAttribute(appElement, kAXWindowsAttribute),
          let windows = windowsRef as? [AXUIElement] else { return }
    for window in windows {
        let buttons = findButtons(window, withTitle: "Later")
        if let button = buttons.first {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            log("Clicked 'Remind Me Later'")
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            DispatchQueue.main.async {
                delegate.lastTriggeredItem.title = "Last triggered: \(formatter.string(from: Date()))"
            }
            return
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var observer: AXObserver?
    var lastTriggeredItem: NSMenuItem!

    func applicationDidFinishLaunching(_: Notification) {
        checkAccessibility()
        setupStatusBar()
        dismissUpdateNotification()
        setupObserver()
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

    func setupObserver() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            log("NotificationCenter process not found — retrying on next launch")
            return
        }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        let callback: AXObserverCallback = { _, _, _, _ in
            dismissUpdateNotification()
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let obs = observer else {
            log("Failed to create AXObserver")
            return
        }
        AXObserverAddNotification(obs, appElement, kAXWindowCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        log("Listening for notifications...")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
