import AppKit
#if canImport(CallQuitsCore)
import CallQuitsCore
#endif
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case behavior = "Behavior"
    case exceptions = "Exceptions"
    case activity = "Activity"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .behavior: "cursorarrow.click"
        case .exceptions: "shield.lefthalf.filled"
        case .activity: "clock.arrow.circlepath"
        }
    }
}

private enum Style {
    static let mint = Color(red: 0.16, green: 0.58, blue: 0.43)
    static let coral = Color(red: 0.91, green: 0.35, blue: 0.31)
    static let border = Color.primary.opacity(0.08)
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pane: SettingsPane = .behavior
    @State private var showForceWarning = false
    @State private var showPermissionHelp = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Style.border).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    switch pane {
                    case .behavior: behaviorContent
                    case .exceptions: exceptionsContent
                    case .activity: activityContent
                    }
                }
                .padding(30)
                .padding(.top, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 600)
        .tint(Style.mint)
        .onAppear {
            model.refreshPermission()
            model.refreshLoginStatus()
        }
        .alert("Restore Accessibility access", isPresented: $showPermissionHelp) {
            Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Keep CallQuits in Applications. After replacing or rebuilding the app, macOS may retain a stale Accessibility entry. Quit CallQuits, remove its old entry in System Settings → Privacy & Security → Accessibility, add the current copy from Applications, enable it, and relaunch. Toggling the old entry alone may not restore access.")
        }
        .alert("Enable Shift-click force quit?", isPresented: $showForceWarning) {
            Button("Enable Force Quit", role: .destructive) { model.forceQuitEnabled = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shift-clicking an app's red close button will force quit the entire app. Unsaved work in every window can be lost. Excluded and protected apps are always left alone.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CallQuits").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("A cleaner goodbye.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 30)

            ForEach(SettingsPane.allCases) { item in
                Button {
                    pane = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).font(.system(size: 14)).frame(width: 18)
                        Text(item.rawValue).font(.system(size: 13, weight: pane == item ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(pane == item ? Style.mint : Color.primary.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(pane == item ? Style.mint.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(pane == item ? [.isSelected] : [])
                .padding(.bottom, 4)
            }

            Spacer(minLength: 30)

            HStack(spacing: 6) {
                Circle()
                    .fill(model.monitorRunning ? Style.mint : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(model.monitorRunning ? "Watching close buttons" : !model.enabled ? "Paused" : model.accessibilityGranted ? "Monitor unavailable" : "Waiting for access")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Divider().padding(.vertical, 14)
            HStack(spacing: 5) {
                Image(systemName: "lock.shield").font(.system(size: 10))
                Text("Private. Local. Yours.").font(.system(size: 10))
            }
            .foregroundStyle(.tertiary)
            Text("CallQuits \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 53)
        .padding(.bottom, 22)
        .frame(width: 188)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR MENU BAR COMPANION")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.tertiary)
                Text(pane.rawValue)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
            }
            Spacer()
            Text(model.monitorRunning ? "ACTIVE" : !model.enabled ? "PAUSED" : !model.accessibilityGranted ? "SETUP NEEDED" : "UNAVAILABLE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(model.monitorRunning ? Style.mint : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(model.monitorRunning ? Style.mint.opacity(0.1) : Color.secondary.opacity(0.08), in: Capsule())
                .padding(.top, 8)
                .accessibilityLabel(model.statusMessage)
        }
    }

    @ViewBuilder
    private var behaviorContent: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Call it quits.")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Close the window.\nLet the app go, too.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
            WindowIllustration()
        }
        .padding(23)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Style.mint.opacity(0.12)))

        if !model.accessibilityGranted { permissionCard }
        if model.canRetryMonitoring { monitoringRecoveryCard }

        SettingsCard {
            SettingRow(symbol: "power", title: "Enable CallQuits", detail: model.statusMessage) {
                Toggle("Enable CallQuits", isOn: $model.enabled).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            VStack(alignment: .leading, spacing: 11) {
                Text("Quit after closing").font(.system(size: 13, weight: .semibold))
                Picker("Quit after closing", selection: $model.behavior) {
                    Text("The last window").tag(CloseBehavior.lastWindow)
                    Text("Any window").tag(CloseBehavior.everyWindow)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.behavior == .lastWindow
                     ? "Quit only when no app windows remain. Minimized windows and windows on other Spaces still count."
                     : "Closing any window asks the entire app to quit, including its other windows. Save prompts remain in control.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(16)
        }

        SettingsCard {
            SettingRow(symbol: "bolt", title: "Shift-click to force quit", detail: "An optional escape hatch. Unsaved work can be lost.") {
                Toggle("Shift-click to force quit", isOn: Binding(
                    get: { model.forceQuitEnabled },
                    set: { requested in
                        if requested { showForceWarning = true } else { model.forceQuitEnabled = false }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Style.coral)
            }
            Divider()
            SettingRow(symbol: "sunrise", title: "Launch at login", detail: model.loginMessage ?? "Ready quietly in your menu bar.") {
                Toggle("Launch at login", isOn: $model.launchAtLogin).labelsHidden().toggleStyle(.switch)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Label("Hold Option while clicking to bypass CallQuits.", systemImage: "option")
            Text("Command- and Control-clicks are left alone. Keyboard shortcuts stay unchanged. If a close is canceled or a dialog appears, CallQuits steps aside.")
            if model.forceQuitEnabled {
                Text("Force quit needs a verified close button. For an unresponsive app, use macOS Force Quit if Shift-click cannot detect it.")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 17))
                .foregroundStyle(.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                Text("One permission, then you're set.").font(.system(size: 13, weight: .semibold))
                Text("Allow Accessibility so CallQuits can recognize an app's actual close button. No screen recording or typing is collected.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Allow Accessibility") { model.requestAccessibility() }.buttonStyle(.borderedProminent)
                    Button("Check again") { model.refreshPermission() }.buttonStyle(.bordered)
                }
                .controlSize(.small)
                .padding(.top, 3)
                Button("Permission recovery help") { showPermissionHelp = true }
                    .buttonStyle(.link)
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.14)))
    }

    private var monitoringRecoveryCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Click monitoring is unavailable", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                Text("Accessibility is allowed, but macOS hasn’t enabled the click monitor. Retry once you’re ready. If it still fails, refresh the permission entry for this copy of CallQuits.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Retry monitoring") { model.retryMonitoring() }
                        .buttonStyle(.borderedProminent)
                    Button("Permission recovery help") { showPermissionHelp = true }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var exceptionsContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Some apps should stick around.")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
            Text("Keep music playing, messages arriving, and terminal sessions alive. These apps keep their usual close-button behavior, including Shift-click.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }

        SettingsCard {
            HStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 23))
                    .foregroundStyle(Style.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Always protected").font(.system(size: 13, weight: .semibold))
                    Text("Finder, CallQuits, and macOS system processes.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(16)
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LEAVE THESE RUNNING")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.addException() } label: {
                    Label("Add app", systemImage: "plus")
                }
                .controlSize(.small)
            }
            SettingsCard {
                if model.exclusions.isEmpty {
                    Text("No extra exceptions. Add an app to keep it running.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else {
                    ForEach(Array(model.exclusions.enumerated()), id: \.element.id) { index, app in
                        HStack(spacing: 12) {
                            ApplicationIcon(bundleID: app.bundleID)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).font(.system(size: 12, weight: .medium))
                                Text(app.bundleID).font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button {
                                model.exclusions.removeAll { $0.id == app.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(app.name) from exceptions")
                            .accessibilityLabel("Remove \(app.name) from exceptions")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        if index < model.exclusions.count - 1 { Divider().padding(.leading, 57) }
                    }
                }
            }
        }
        Text("The starting list is a suggestion. Remove an app whenever you want CallQuits to handle its close button.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var activityContent: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("A little peace of mind.")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Recent actions from this session. No window titles,\ndocument names, or browsing history.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 8)
            if !model.activity.isEmpty {
                Button("Clear") { model.activity.removeAll() }.controlSize(.small)
            }
        }
        if model.activity.isEmpty {
            VStack(spacing: 13) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundStyle(Style.mint)
                Text("All quiet here.").font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("When CallQuits acts, you'll see it here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 65)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        } else {
            SettingsCard {
                ForEach(Array(model.activity.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(Style.mint.opacity(0.7)).frame(width: 6, height: 6).padding(.top, 5)
                        Text(entry.message)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(entry.date, style: .time)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    if index < model.activity.count - 1 { Divider().padding(.leading, 34) }
                }
            }
        }
        Label("Stays on this Mac. Cleared when CallQuits quits.", systemImage: "lock")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Style.border))
    }
}

private struct SettingRow<Control: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            control.controlSize(.small)
        }
        .padding(16)
    }
}

private struct ApplicationIcon: View {
    let bundleID: String

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

private struct WindowIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(Style.mint.opacity(0.09))
                .frame(width: 155, height: 100)
                .rotationEffect(.degrees(7))
                .offset(x: 8, y: 0)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(Style.coral).frame(width: 17, height: 17)
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                    }
                    Circle().fill(Color.orange.opacity(0.55)).frame(width: 9, height: 9)
                    Circle().fill(Style.mint.opacity(0.55)).frame(width: 9, height: 9)
                    Spacer()
                }
                .padding(12)
                Rectangle().fill(Style.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(Color.secondary.opacity(0.13)).frame(width: 64, height: 5)
                    Capsule().fill(Color.secondary.opacity(0.09)).frame(width: 102, height: 5)
                }
                .padding(15)
            }
            .frame(width: 155, height: 100, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Style.border))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
            Image(systemName: "cursorarrow")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.8))
                .rotationEffect(.degrees(-12))
                .offset(x: -39, y: -6)
        }
        .frame(width: 180, height: 120)
        .accessibilityHidden(true)
    }
}
