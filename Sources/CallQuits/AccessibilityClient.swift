import AppKit
import ApplicationServices
#if canImport(CallQuitsCore)
import CallQuitsCore
#endif

/// Used only on CloseMonitor's serial worker queue. No Accessibility IPC runs on the UI thread.
final class AccessibilityClient {
    struct Hit {
        let application: NSRunningApplication
        let appElement: AXUIElement
        let window: AXUIElement
        let initialWindows: [AXUIElement]
        let buttonFrame: CGRect
    }

    private enum ReadError: Error { case unavailable, unexpectedValue, exceededBudget }
    private let system = AXUIElementCreateSystemWide()
    private var deadline: TimeInterval = 0

    init() {
        // The system-wide element sets the default for every AX object in this process.
        AXUIElementSetMessagingTimeout(system, 0.12)
    }

    func closeButton(at point: CGPoint, eventTime: TimeInterval, targetPID: pid_t) -> Hit? {
        deadline = ProcessInfo.processInfo.systemUptime + 0.55
        guard ProcessInfo.processInfo.systemUptime - eventTime < 0.5 else { return nil }
        do {
            var result: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &result) == .success,
                  var button = result else { return nil }
            // Some apps expose a child of the actual button to hit testing.
            for _ in 0..<4 {
                if try value(button, kAXSubroleAttribute, optional: true) as? String == kAXCloseButtonSubrole { break }
                guard let parent = try element(button, kAXParentAttribute) else { return nil }
                button = parent
            }
            guard try string(button, kAXSubroleAttribute) == kAXCloseButtonSubrole,
                  try string(button, kAXRoleAttribute) == kAXButtonRole,
                  try bool(button, kAXEnabledAttribute) == true,
                  let window = try element(button, kAXWindowAttribute),
                  try string(window, kAXRoleAttribute) == kAXWindowRole,
                  try string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
                  try !hasBlockingUI(window),
                  let officialButton = try element(window, kAXCloseButtonAttribute),
                  CFEqual(button, officialButton),
                  let frame = try frame(button), frame.contains(point) else { return nil }

            var pid: pid_t = 0
            guard AXUIElementGetPid(window, &pid) == .success, pid == targetPID,
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular, app.isFinishedLaunching,
                  !app.isHidden, !app.isTerminated,
                  !AppProtection.isProtected(bundleIdentifier: app.bundleIdentifier,
                                             processID: pid, ownProcessID: ProcessInfo.processInfo.processIdentifier)
            else { return nil }
            let appElement = AXUIElementCreateApplication(pid)
            let windows = try windows(appElement)
            guard windows.contains(where: { CFEqual($0, window) }) else { return nil }
            return Hit(application: app, appElement: appElement, window: window,
                       initialWindows: windows, buttonFrame: frame)
        } catch { return nil }
    }

    func snapshot(for hit: Hit) -> CloseSnapshot {
        deadline = ProcessInfo.processInfo.systemUptime + 0.45
        do {
            let current = try windows(hit.appElement)
            var blocking = false
            // All windows count, including minimized windows, panels, and other Spaces.
            // Inspect sheets/modal state only while windows exist; empty is not guessed on AX errors.
            for window in current {
                if try hasBlockingUI(window) { blocking = true; break }
            }
            return CloseSnapshot(
                windowCount: current.count,
                targetWindowPresent: current.contains { CFEqual($0, hit.window) },
                hasBlockingUI: blocking,
                isReliable: true,
                hasReplacementWindow: current.contains { candidate in
                    !hit.initialWindows.contains { CFEqual($0, candidate) }
                }
            )
        } catch {
            return CloseSnapshot(windowCount: 0, targetWindowPresent: true,
                                 hasBlockingUI: false, isReliable: false)
        }
    }

    private func value(_ element: AXUIElement, _ attribute: String, optional: Bool = false) throws -> CFTypeRef? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw ReadError.exceededBudget }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if optional && (error == .attributeUnsupported || error == .noValue) { return nil }
        guard error == .success else { throw ReadError.unavailable }
        return value
    }

    private func string(_ object: AXUIElement, _ attribute: String) throws -> String? {
        try value(object, attribute) as? String
    }

    private func bool(_ object: AXUIElement, _ attribute: String, optional: Bool = false) throws -> Bool? {
        guard let raw = try value(object, attribute, optional: optional) else { return nil }
        guard CFGetTypeID(raw) == CFBooleanGetTypeID() else { throw ReadError.unexpectedValue }
        return (raw as! CFBoolean) == kCFBooleanTrue
    }

    private func element(_ object: AXUIElement, _ attribute: String) throws -> AXUIElement? {
        guard let raw = try value(object, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private func windows(_ app: AXUIElement) throws -> [AXUIElement] {
        guard let raw = try value(app, kAXWindowsAttribute),
              CFGetTypeID(raw) == CFArrayGetTypeID(), let windows = raw as? [AXUIElement],
              windows.count <= 64 else { throw ReadError.unexpectedValue }
        return windows
    }

    private func hasBlockingUI(_ window: AXUIElement) throws -> Bool {
        guard let modal = try bool(window, kAXModalAttribute) else { throw ReadError.unexpectedValue }
        if modal { return true }
        // Sheets are direct AX children of a window; there is no public AXSheets attribute.
        guard let raw = try value(window, kAXChildrenAttribute),
              let children = raw as? [AXUIElement], children.count <= 64 else { throw ReadError.unexpectedValue }
        for child in children {
            guard let role = try string(child, kAXRoleAttribute) else { throw ReadError.unexpectedValue }
            if role == kAXSheetRole { return true }
        }
        return false
    }

    private func frame(_ object: AXUIElement) throws -> CGRect? {
        guard let position = try value(object, kAXPositionAttribute),
              let size = try value(object, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
}
