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
        let allowsApplicationHide: Bool
    }

    /// AX-only proof, kept separate from application eligibility and native event identity.
    struct CloseControl {
        let appElement: AXUIElement
        let window: AXUIElement
        let initialWindows: [AXUIElement]
        let buttonFrame: CGRect
    }

    private enum ReadError: Error { case unavailable(AXError), unexpectedValue, exceededBudget }
    typealias AttributeReader = (AXUIElement, CFString) -> (AXError, CFTypeRef?)
    typealias AttributesReader = (AXUIElement, [String]) -> (AXError, [CFTypeRef]?)
    typealias ElementFinder = (AXUIElement, CGPoint) -> (AXError, AXUIElement?)
    private let readAttribute: AttributeReader
    private let readAttributes: AttributesReader
    private let findElement: ElementFinder
    private let system = AXUIElementCreateSystemWide()
    private var deadline: TimeInterval = 0

    init(readAttribute: @escaping AttributeReader = { element, attribute in
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        return (error, value)
    }, readAttributes: @escaping AttributesReader = { element, attributes in
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, .stopOnError, &values)
        return (error, values as? [CFTypeRef])
    }, findElement: @escaping ElementFinder = { system, point in
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element)
        return (error, element)
    }) {
        self.readAttribute = readAttribute
        self.readAttributes = readAttributes
        self.findElement = findElement
        // The system-wide element sets the default for every AX object in this process.
        AXUIElementSetMessagingTimeout(system, 0.12)
    }

    func closeButton(at point: CGPoint, eventTime: TimeInterval, targetPID: pid_t) -> Hit? {
        guard let app = NSRunningApplication(processIdentifier: targetPID), isEligible(app),
              let control = captureCloseControl(at: point, eventTime: eventTime, targetPID: targetPID)
        else { return nil }
        // The monitor rechecks eligibility after release and immediately before termination.
        // Let it adjudicate a same-process Discord hide that arrives while capture finishes.
        // Only Discord's single, nonminimized window can use hide-on-close confirmation.
        // Every reported window counts here, including windows on other Spaces.
        let allowsHide = HiddenCloseIntent.supports(bundleIdentifier: app.bundleIdentifier) &&
            control.initialWindows.count == 1 && (try? bool(control.window, kAXMinimizedAttribute)) == false
        return Hit(application: app, appElement: control.appElement, window: control.window,
                   initialWindows: control.initialWindows, buttonFrame: control.buttonFrame,
                   allowsApplicationHide: allowsHide)
    }

    private func isEligible(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.isFinishedLaunching && !app.isHidden && !app.isTerminated &&
        !AppProtection.isProtected(bundleIdentifier: app.bundleIdentifier, processID: app.processIdentifier,
                                   ownProcessID: ProcessInfo.processInfo.processIdentifier)
    }

    func captureCloseControl(at point: CGPoint, eventTime: TimeInterval, targetPID: pid_t) -> CloseControl? {
        deadline = ProcessInfo.processInfo.systemUptime + 0.55
        guard ProcessInfo.processInfo.systemUptime - eventTime < 0.5 else { return nil }
        do {
            let (error, result) = findElement(system, point)
            guard error == .success, var button = result else { return nil }
            // Some apps expose a child of the actual button to hit testing.
            for depth in 0...4 {
                if try value(button, kAXSubroleAttribute, optional: true) as? String == kAXCloseButtonSubrole { break }
                guard depth < 4, let parent = try element(button, kAXParentAttribute) else { return nil }
                button = parent
            }
            guard let window = try element(button, kAXWindowAttribute) else { return nil }
            var pid: pid_t = 0
            guard AXUIElementGetPid(window, &pid) == .success, pid == targetPID else { return nil }
            let appElement = AXUIElementCreateApplication(pid)
            // Capture membership before the remaining control checks. Empty documents can
            // close immediately after the final button read; a later enumeration would discard
            // an otherwise fully verified click. Disappearance still needs normal confirmation.
            let windows = try windows(appElement)
            guard windows.contains(where: { CFEqual($0, window) }) else { return nil }
            // Group required values to reduce IPC while the button is still alive. These calls
            // are not atomic snapshots; all identity, sheet and later stability checks remain.
            let windowValues = try values(window, [kAXRoleAttribute, kAXSubroleAttribute,
                                                   kAXModalAttribute, kAXChildrenAttribute, kAXCloseButtonAttribute])
            guard windowValues[0] as? String == kAXWindowRole,
                  windowValues[1] as? String == kAXStandardWindowSubrole,
                  try boolean(windowValues[2]) == false,
                  try !hasSheet(windowValues[3]),
                  let officialButton = axElement(windowValues[4]), CFEqual(button, officialButton)
            else { return nil }
            let buttonValues = try values(button, [kAXSubroleAttribute, kAXRoleAttribute, kAXEnabledAttribute,
                                                   kAXPositionAttribute, kAXSizeAttribute])
            guard buttonValues[0] as? String == kAXCloseButtonSubrole,
                  buttonValues[1] as? String == kAXButtonRole,
                  try boolean(buttonValues[2]) == true,
                  let frame = frame(position: buttonValues[3], size: buttonValues[4]), frame.contains(point)
            else { return nil }
            return CloseControl(appElement: appElement, window: window, initialWindows: windows, buttonFrame: frame)
        } catch { return nil }
    }

    func snapshot(for hit: Hit) -> CloseSnapshot {
        deadline = ProcessInfo.processInfo.systemUptime + 0.45
        do {
            var current = try windows(hit.appElement)
            var blocking = false
            // All windows count, including minimized windows, panels, and other Spaces.
            // Inspect sheets/modal state only while windows exist; empty is not guessed on AX errors.
            for window in current {
                do {
                    if try hasBlockingUI(window) { blocking = true; break }
                } catch ReadError.unavailable(.invalidUIElement) where CFEqual(window, hit.window) {
                    // Native close can destroy the clicked window (or a child) after AXWindows
                    // enumerates it. Confirm that exact disappearance, rather than treating a
                    // dead reference as an unreadable live window. No timeout/unsupported-value
                    // fallback, extra delay, or renewed budget is allowed here.
                    let remaining = current.filter { !CFEqual($0, hit.window) }
                    let refreshed = try windows(hit.appElement)
                    guard refreshed.count == remaining.count,
                          !refreshed.contains(where: { CFEqual($0, hit.window) }),
                          remaining.allSatisfy({ original in refreshed.contains { CFEqual($0, original) } }),
                          refreshed.allSatisfy({ survivor in remaining.contains { CFEqual($0, survivor) } })
                    else { throw ReadError.unexpectedValue }
                    // Start a complete inspection of the surviving set. A second failure is
                    // terminal; never keep retrying an app with unreliable Accessibility.
                    current = refreshed
                    for survivor in current {
                        if try hasBlockingUI(survivor) { blocking = true; break }
                    }
                    break
                }
            }
            let targetPresent = current.contains { CFEqual($0, hit.window) }
            let hidden = hit.application.isHidden
            // A hidden Discord window is retained, not destroyed. Read its minimized state
            // explicitly; unsupported metadata must never authorize the compatibility path.
            var minimized = false
            if hidden && hit.allowsApplicationHide && targetPresent {
                guard let value = try bool(hit.window, kAXMinimizedAttribute) else { throw ReadError.unexpectedValue }
                minimized = value
            }
            guard hidden == hit.application.isHidden else { throw ReadError.unexpectedValue }
            return CloseSnapshot(
                windowCount: current.count,
                targetWindowPresent: targetPresent,
                hasBlockingUI: blocking,
                isReliable: true,
                hasReplacementWindow: current.contains { candidate in
                    !hit.initialWindows.contains { CFEqual($0, candidate) }
                },
                applicationHidden: hidden,
                targetWindowMinimized: minimized
            )
        } catch {
            return CloseSnapshot(windowCount: 0, targetWindowPresent: true,
                                 hasBlockingUI: false, isReliable: false)
        }
    }

    private func value(_ element: AXUIElement, _ attribute: String, optional: Bool = false) throws -> CFTypeRef? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw ReadError.exceededBudget }
        let (error, value) = readAttribute(element, attribute as CFString)
        if optional && (error == .attributeUnsupported || error == .noValue) { return nil }
        guard error == .success else { throw ReadError.unavailable(error) }
        return value
    }

    private func string(_ object: AXUIElement, _ attribute: String) throws -> String? {
        try value(object, attribute) as? String
    }

    private func values(_ element: AXUIElement, _ attributes: [String]) throws -> [CFTypeRef] {
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw ReadError.exceededBudget }
        let (error, result) = readAttributes(element, attributes)
        // Some providers implement individual attributes only. Preserve that compatibility
        // within the same budget; never retry a timeout, invalid element or partial result.
        if error == .notImplemented {
            let result = try attributes.map {
                guard let result = try value(element, $0) else { throw ReadError.unexpectedValue }
                return result
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ReadError.exceededBudget }
            return result
        }
        guard error == .success else { throw ReadError.unavailable(error) }
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw ReadError.exceededBudget }
        guard let result, result.count == attributes.count,
              result.allSatisfy({ raw in
                  CFGetTypeID(raw) != CFNullGetTypeID() &&
                  !(CFGetTypeID(raw) == AXValueGetTypeID() && AXValueGetType(raw as! AXValue) == .axError)
              }) else { throw ReadError.unexpectedValue }
        return result
    }

    private func bool(_ object: AXUIElement, _ attribute: String, optional: Bool = false) throws -> Bool? {
        guard let raw = try value(object, attribute, optional: optional) else { return nil }
        return try boolean(raw)
    }

    private func boolean(_ raw: CFTypeRef) throws -> Bool {
        guard CFGetTypeID(raw) == CFBooleanGetTypeID() else { throw ReadError.unexpectedValue }
        return (raw as! CFBoolean) == kCFBooleanTrue
    }

    private func element(_ object: AXUIElement, _ attribute: String) throws -> AXUIElement? {
        axElement(try value(object, attribute))
    }

    private func axElement(_ raw: CFTypeRef?) -> AXUIElement? {
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private func windows(_ app: AXUIElement) throws -> [AXUIElement] {
        guard let raw = try value(app, kAXWindowsAttribute) else { throw ReadError.unexpectedValue }
        return try elements(raw)
    }

    private func elements(_ raw: CFTypeRef) throws -> [AXUIElement] {
        // Swift's bridging cast alone does not validate the CF type of each array member.
        guard CFGetTypeID(raw) == CFArrayGetTypeID(), let members = raw as? [CFTypeRef],
              members.count <= 64, members.allSatisfy({ CFGetTypeID($0) == AXUIElementGetTypeID() })
        else { throw ReadError.unexpectedValue }
        return members.map { $0 as! AXUIElement }
    }

    private func hasBlockingUI(_ window: AXUIElement) throws -> Bool {
        guard let modal = try bool(window, kAXModalAttribute) else { throw ReadError.unexpectedValue }
        if modal { return true }
        // Sheets are direct AX children of a window; there is no public AXSheets attribute.
        guard let raw = try value(window, kAXChildrenAttribute) else { throw ReadError.unexpectedValue }
        return try hasSheet(raw)
    }

    private func hasSheet(_ raw: CFTypeRef) throws -> Bool {
        let children = try elements(raw)
        for child in children {
            guard let role = try string(child, kAXRoleAttribute) else { throw ReadError.unexpectedValue }
            if role == kAXSheetRole { return true }
        }
        return false
    }

    private func frame(position: CFTypeRef, size: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              origin.x.isFinite, origin.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
}
