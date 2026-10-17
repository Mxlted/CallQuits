import AppKit
import SwiftUI

@main
struct CallQuitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            Text("CallQuits").font(.headline)
            Text(model.statusMessage)
            Divider()
            Toggle("Enable CallQuits", isOn: $model.enabled)
            if !model.accessibilityGranted {
                Button("Allow Accessibility…") { model.requestAccessibility() }
            } else if model.canRetryMonitoring {
                Button("Retry monitoring") { model.retryMonitoring() }
            }
            Button("Settings…") { appDelegate.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit CallQuits") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: model.monitorRunning ? "xmark.circle.fill" : "xmark.circle")
                .accessibilityLabel("CallQuits: \(model.statusMessage)")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel.shared
    private var monitor: CloseMonitor?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.refreshPermission()
        model.refreshLoginStatus()
        monitor = CloseMonitor(model: model)
        monitor?.start()

        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if !hasLaunched || !model.accessibilityGranted { showSettings() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshPermission()
        model.refreshLoginStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 830, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "CallQuits Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 780, height: 600)
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("CallQuitsSettings")
            settingsWindow = window
        }
        model.refreshPermission()
        model.refreshLoginStatus()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
