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

enum MonitoringState: Equatable {
    case permissionNeeded, paused, running, unavailable

    var message: String {
        switch self {
        case .permissionNeeded: "Accessibility access needed"
        case .paused: "Paused"
        case .running: "Ready for your next close"
        case .unavailable: "Couldn’t start click monitoring"
        }
    }
}

struct LoginStatusPresentation: Equatable {
    let enabled: Bool
    let message: String?

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled:
            enabled = true
            message = nil
        case .requiresApproval:
            enabled = true
            message = "Approve CallQuits in System Settings → General → Login Items."
        case .notRegistered:
            enabled = false
            message = nil
        case .notFound:
            enabled = false
            message = "macOS couldn’t find the login item. Open CallQuits from your Applications folder and try again."
        @unknown default:
            enabled = false
            message = "Login item status is unavailable. Check System Settings → General → Login Items."
        }
    }
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
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var monitoringState: MonitoringState = .permissionNeeded
    var monitorRunning: Bool { monitoringState == .running }
    var statusMessage: String { monitoringState.message }
    var canRetryMonitoring: Bool { enabled && accessibilityGranted && !monitorRunning }
    @Published var activity: [ActivityEntry] = []
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue, !updatingLoginStatus else { return }
            updateLaunchAtLogin()
        }
    }
    @Published var loginMessage: String?

    var onConfigurationChange: (() -> Void)?
    var onMonitoringRetry: (() -> Void)?
    private let defaults: UserDefaults
    private let readAccessibility: () -> Bool
    private let readLoginStatus: () -> SMAppService.Status
    private var updatingLoginStatus = false

    init(defaults: UserDefaults = .standard,
         readAccessibility: @escaping () -> Bool = { AXIsProcessTrusted() },
         readLoginStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status }) {
        self.defaults = defaults
        self.readAccessibility = readAccessibility
        self.readLoginStatus = readLoginStatus
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
        let loginStatus = LoginStatusPresentation(readLoginStatus())
        launchAtLogin = loginStatus.enabled
        loginMessage = loginStatus.message
        accessibilityGranted = readAccessibility()
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
        updateAccessibility(readAccessibility())
    }

    private func updateAccessibility(_ granted: Bool) {
        guard granted != accessibilityGranted else { return }
        accessibilityGranted = granted
        record(granted ? "Accessibility access granted." : "Accessibility access is unavailable.")
        onConfigurationChange?()
    }

    @discardableResult
    func refreshLoginStatus() -> SMAppService.Status {
        let status = readLoginStatus()
        let presentation = LoginStatusPresentation(status)
        updatingLoginStatus = true
        launchAtLogin = presentation.enabled
        loginMessage = presentation.message
        updatingLoginStatus = false
        return status
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        updateAccessibility(AXIsProcessTrustedWithOptions(options))
        if !accessibilityGranted { openAccessibilitySettings() }
    }

    func retryMonitoring() {
        refreshPermission()
        guard canRetryMonitoring else { return }
        onMonitoringRetry?()
    }

    func setMonitoringState(_ state: MonitoringState) {
        guard monitoringState != state else { return }
        monitoringState = state
        switch state {
        case .running: record("Click monitoring is ready.")
        case .unavailable: record("Click monitoring is unavailable. Retry monitoring in Settings.")
        case .paused: record("Click monitoring is paused.")
        case .permissionNeeded: break // The permission transition already has an Activity entry.
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
            } else {
                try SMAppService.mainApp.unregister()
            }
            if refreshLoginStatus() == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            refreshLoginStatus()
            loginMessage = "Couldn't update login items. Open CallQuits from your Applications folder and try again."
            record("Login item settings could not be updated.")
        }
    }
}
