import AppKit
import ApplicationServices
#if canImport(CallQuitsCore)
import CallQuitsCore
#endif
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct AppException: Identifiable, Codable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: "enabled")
            onConfigurationChange?()
        }
    }
    @Published var behavior: CloseBehavior {
        didSet {
            guard behavior != oldValue else { return }
            defaults.set(behavior == .everyWindow, forKey: "quitOnAnyWindow")
            onConfigurationChange?()
        }
    }
    @Published var forceQuitEnabled: Bool {
        didSet {
            guard forceQuitEnabled != oldValue else { return }
            defaults.set(forceQuitEnabled, forKey: "forceQuitEnabled")
            onConfigurationChange?()
        }
    }
    @Published var exclusions: [AppException] {
        didSet {
            guard exclusions != oldValue else { return }
            if let data = try? JSONEncoder().encode(exclusions) {
                defaults.set(data, forKey: "excludedApplications")
            }
            onConfigurationChange?()
        }
    }
    @Published var accessibilityGranted = false
    @Published var monitorRunning = false
    @Published var statusMessage = "Waiting for Accessibility access"
    @Published var activity: [ActivityEntry] = []
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue, !updatingLoginStatus else { return }
            updateLaunchAtLogin()
        }
    }
    @Published var loginMessage: String?

    var onConfigurationChange: (() -> Void)?
    private let defaults: UserDefaults
    private var updatingLoginStatus = false

    private init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        defaults.register(defaults: ["enabled": true, "quitOnAnyWindow": false, "forceQuitEnabled": false])
        enabled = defaults.bool(forKey: "enabled")
        behavior = defaults.bool(forKey: "quitOnAnyWindow") ? .everyWindow : .lastWindow
        forceQuitEnabled = defaults.bool(forKey: "forceQuitEnabled")
        if let data = defaults.data(forKey: "excludedApplications"),
           let saved = try? JSONDecoder().decode([AppException].self, from: data) {
            exclusions = saved
        } else {
            exclusions = Self.defaultExceptions
        }
        let loginStatus = SMAppService.mainApp.status
        launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        if loginStatus == .requiresApproval {
            loginMessage = "Approve CallQuits in System Settings → General → Login Items."
        }
        accessibilityGranted = AXIsProcessTrusted()
    }

    static let defaultExceptions = [
        AppException(bundleID: "com.apple.Music", name: "Music"),
        AppException(bundleID: "com.spotify.client", name: "Spotify"),
        AppException(bundleID: "com.apple.mail", name: "Mail"),
        AppException(bundleID: "com.apple.MobileSMS", name: "Messages"),
        AppException(bundleID: "com.apple.FaceTime", name: "FaceTime"),
        AppException(bundleID: "com.apple.Terminal", name: "Terminal"),
        AppException(bundleID: "com.googlecode.iterm2", name: "iTerm")
    ]

    func refreshPermission() {
        let granted = AXIsProcessTrusted()
        let changed = granted != accessibilityGranted
        accessibilityGranted = granted
        if changed {
            record(granted ? "Accessibility access granted." : "Accessibility access is unavailable.")
            onConfigurationChange?()
        }
        updatingLoginStatus = true
        let loginStatus = SMAppService.mainApp.status
        launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        if loginStatus == .requiresApproval {
            loginMessage = "Approve CallQuits in System Settings → General → Login Items."
        } else if loginStatus == .enabled {
            loginMessage = nil
        }
        updatingLoginStatus = false
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if accessibilityGranted {
            onConfigurationChange?()
        } else {
            openAccessibilitySettings()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func record(_ message: String) {
        activity.insert(ActivityEntry(message: message), at: 0)
        if activity.count > 80 { activity.removeLast(activity.count - 80) }
    }

    func isExcluded(_ bundleID: String) -> Bool {
        exclusions.contains { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    func addException() {
        let panel = NSOpenPanel()
        panel.title = "Keep an application running"
        panel.message = "CallQuits will leave this app's close buttons alone."
        panel.prompt = "Add exception"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            guard !isExcluded(bundleID) else { continue }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            exclusions.append(AppException(bundleID: bundleID, name: name))
        }
        exclusions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    loginMessage = "Approve CallQuits in System Settings → General → Login Items."
                    SMAppService.openSystemSettingsLoginItems()
                } else {
                    loginMessage = nil
                }
            } else {
                try SMAppService.mainApp.unregister()
                loginMessage = nil
            }
        } catch {
            updatingLoginStatus = true
            let loginStatus = SMAppService.mainApp.status
            launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
            updatingLoginStatus = false
            loginMessage = "Couldn't update login items. Open CallQuits from your Applications folder and try again."
            record("Login item settings could not be updated.")
        }
    }
}
