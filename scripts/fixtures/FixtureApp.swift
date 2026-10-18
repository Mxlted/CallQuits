import AppKit

private func fixtureLog(_ event: String) {
    print(String(format: "[%.6f] %@", ProcessInfo.processInfo.systemUptime, event))
    fflush(stdout)
}

// Browser-style hit testing can expose a rendering group beside the semantic
// tab group. Keep the real NSButton and its normal action in the tab hierarchy.
private final class FixtureTabCloseButton: NSButton {
    weak var renderingHit: NSAccessibilityElement?

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        renderingHit ?? super.accessibilityHitTest(point)
    }
}

private final class FixtureTabRenderingElement: NSAccessibilityElement {
    weak var tabGroup: NSView?

    override func accessibilityFrame() -> NSRect { tabGroup?.accessibilityFrame() ?? .zero }
    override func accessibilityWindow() -> Any? { tabGroup?.window }
    override func accessibilityTopLevelUIElement() -> Any? { tabGroup?.window }
}

private final class FixtureTabStrip: NSStackView {
    private let tabGroup: NSView
    private let renderingHit = FixtureTabRenderingElement()

    init(tabGroup: NSView, closeButton: FixtureTabCloseButton) {
        self.tabGroup = tabGroup
        super.init(frame: .zero)
        addArrangedSubview(tabGroup)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        renderingHit.tabGroup = tabGroup
        renderingHit.setAccessibilityRole(.group)
        renderingHit.setAccessibilityParent(self)
        renderingHit.setAccessibilityChildren([])
        closeButton.renderingHit = renderingHit
    }

    required init?(coder: NSCoder) { nil }

    override func accessibilityChildren() -> [Any]? { [tabGroup, renderingHit] }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        if tabGroup.accessibilityFrame().contains(point) {
            return renderingHit
        }
        return super.accessibilityHitTest(point)
    }
}

// A disposable app that deliberately stays running after its last window closes.
// All its document state is in memory; no user documents are opened or written.
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var controllers: [FixtureWindowController] = []
    var nextNumber = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        fixtureLog("application launched")
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit CallQuits Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newItem = fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow), keyEquivalent: "n")
        newItem.target = self
        let newTab = fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        newTab.target = self
        let closeTab = fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        closeTab.target = self
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        NSApp.mainMenu = menu
        newWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidHide(_ notification: Notification) { fixtureLog("application hidden") }
    func applicationDidUnhide(_ notification: Notification) { fixtureLog("application unhidden") }
    func applicationWillTerminate(_ notification: Notification) { fixtureLog("application will terminate") }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        fixtureLog("graceful quit requested")
        let dirtyWindows = controllers.compactMap(\.window).filter(\.isDocumentEdited)
        guard let first = dirtyWindows.first else { return .terminateNow }
        guard dirtyWindows.allSatisfy({ $0.attachedSheet == nil }) else {
            fixtureLog("quit canceled: sheet present")
            return .terminateCancel
        }
        let alert = NSAlert()
        alert.messageText = "Save remaining disposable documents?"
        alert.informativeText = "There are \(dirtyWindows.count) unsaved documents. Cancel must keep the app running after a normal quit request. No actual files are written."
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        alert.beginSheetModal(for: first) { response in
            let shouldQuit = response != .alertSecondButtonReturn
            fixtureLog(shouldQuit ? "quit sheet accepted" : "quit sheet canceled")
            if shouldQuit { dirtyWindows.forEach { $0.isDocumentEdited = false } }
            sender.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }

    @objc func newWindow() {
        let controller = FixtureWindowController(number: nextNumber, owner: self)
        nextNumber += 1
        controllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        fixtureLog("window opened")
    }

    @objc func newTab() { controllers.first { $0.window === NSApp.keyWindow }?.addTab() }
    @objc func closeTab() { controllers.first { $0.window === NSApp.keyWindow }?.closeTab() }
}

final class FixtureWindowController: NSWindowController, NSWindowDelegate {
    weak var fixtureOwner: FixtureDelegate?
    var allowCloseOnce = false
    var shouldReplace = false
    var shouldHideOnClose = false
    private var tabCount = 1
    private let tabLabel = NSTextField(labelWithString: "Tabs: 1")

    init(number: Int, owner: FixtureDelegate) {
        self.fixtureOwner = owner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Disposable document \(number)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameOrigin(NSPoint(x: window.frame.minX + CGFloat((number - 1) % 5) * 28,
                                      y: window.frame.minY - CGFloat((number - 1) % 5) * 28))

        let title = NSTextField(labelWithString: "CallQuits test fixture")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString:
            "Safe to quit. Everything here is disposable and stored only in memory. This app normally stays running after its last window closes.")
        detail.textColor = .secondaryLabelColor
        let dirty = NSButton(checkboxWithTitle: "Unsaved changes — ask before closing", target: self, action: #selector(toggleDirty(_:)))
        let replace = NSButton(checkboxWithTitle: "Open a replacement window after closing", target: self, action: #selector(toggleReplacement(_:)))
        let hide = NSButton(checkboxWithTitle: "Hide application instead of closing", target: self, action: #selector(toggleHideOnClose(_:)))
        let new = NSButton(title: "New Window (⌘N)", target: owner, action: #selector(FixtureDelegate.newWindow))
        let sheet = NSButton(title: "Show Blocking Sheet", target: self, action: #selector(showSheet))
        let buttons = NSStackView(views: [new, sheet])
        buttons.spacing = 12
        // Native AX tab hierarchy with a Close child, matching a browser's tab strip.
        let tabClose = FixtureTabCloseButton(title: "Close", target: self, action: #selector(closeTab))
        let tab = NSStackView(views: [tabLabel, tabClose])
        tab.setAccessibilityElement(true)
        tab.setAccessibilityRole(.radioButton)
        let tabs = NSStackView(views: [tab])
        tabs.setAccessibilityElement(true)
        tabs.setAccessibilityRole(.tabGroup)
        let tabRow = NSStackView(views: [FixtureTabStrip(tabGroup: tabs, closeButton: tabClose), NSButton(title: "New Tab (⌘T)", target: self, action: #selector(addTab))])
        tabRow.spacing = 12
        let hint = NSTextField(wrappingLabelWithString:
            "Try multiple windows, minimize one, move one to another Space, cancel a save, drag away from the red button, or use ⌘W. The File menu still works when no window is open.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, detail, tabRow, dirty, replace, hide, buttons, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)
        ])
        window.minSize = NSSize(width: 540, height: 480)
    }

    required init?(coder: NSCoder) { nil }

    @objc func addTab() {
        tabCount += 1
        tabLabel.stringValue = "Tabs: \(tabCount)"
        fixtureLog("tab opened")
    }

    @objc func closeTab() {
        fixtureLog("tab close requested")
        if tabCount > 1 {
            tabCount -= 1
            tabLabel.stringValue = "Tabs: \(tabCount)"
            fixtureLog("tab closed; window remains")
        } else {
            window?.performClose(nil)
        }
    }

    @objc func toggleDirty(_ sender: NSButton) { window?.isDocumentEdited = sender.state == .on }
    @objc func toggleReplacement(_ sender: NSButton) { shouldReplace = sender.state == .on }
    @objc func toggleHideOnClose(_ sender: NSButton) { shouldHideOnClose = sender.state == .on }

    @objc func showSheet() {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "A sheet is open"
        alert.informativeText = "CallQuits must leave this app running while the sheet is present."
        alert.addButton(withTitle: "Dismiss")
        alert.beginSheetModal(for: window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        fixtureLog("window close requested")
        guard sender.attachedSheet == nil else {
            fixtureLog("close canceled: sheet present")
            return false
        }
        if allowCloseOnce {
            allowCloseOnce = false
            return completeCleanClose()
        }
        guard sender.isDocumentEdited else { return completeCleanClose() }
        let alert = NSAlert()
        alert.messageText = "Save this disposable document?"
        alert.informativeText = "No actual file is written. Cancel must keep this window and app open."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        alert.beginSheetModal(for: sender) { [weak self] response in
            fixtureLog(response == .alertSecondButtonReturn ? "close sheet canceled" : "close sheet accepted")
            guard response != .alertSecondButtonReturn, let self else { return }
            sender.isDocumentEdited = false
            self.allowCloseOnce = true
            sender.performClose(nil)
        }
        return false
    }

    private func completeCleanClose() -> Bool {
        guard shouldHideOnClose else { return true }
        fixtureLog("hiding application instead of closing window")
        NSApp.hide(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        fixtureLog("window will close")
        let replace = shouldReplace
        let owner = fixtureOwner
        owner?.controllers.removeAll { $0 === self }
        if replace {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { owner?.newWindow() }
        }
    }
}

let application = NSApplication.shared
let delegate = FixtureDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
