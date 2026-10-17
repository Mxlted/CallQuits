import AppKit
import ApplicationServices
#if canImport(CallQuitsCore)
import CallQuitsCore
#endif

/// Observes clicks; never swallows, rewrites, or synthesizes a user's input.
@MainActor
final class CloseMonitor {
    private let model: AppModel
    private let worker = CloseWorker()
    private var eventMonitor: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var permissionTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var generation: UInt64 = 0
    private var gesture: CloseGesture?
    private var pressIdentity: EventIdentity?
    private var windowObservation: CloseWindowObservation?

    init(model: AppModel) { self.model = model }

    func start() {
        guard permissionTimer == nil else { return }
        model.onConfigurationChange = { [weak self] in self?.reconfigure() }
        let center = NSWorkspace.shared.notificationCenter
        for notification in [NSWorkspace.willSleepNotification,
                             NSWorkspace.screensDidSleepNotification,
                             NSWorkspace.sessionDidResignActiveNotification,
                             NSWorkspace.activeSpaceDidChangeNotification,
                             NSWorkspace.didHideApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.invalidate() }
            })
        }
        // Only checks our permission bit, never enumerates other apps or windows when idle.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let granted = AXIsProcessTrusted()
                if self.model.accessibilityGranted != granted {
                    self.model.accessibilityGranted = granted
                    self.reconfigure()
                }
            }
        }
        model.refreshPermission()
        reconfigure()
    }

    func stop() {
        invalidate()
        removeMonitors()
        permissionTimer?.invalidate()
        permissionTimer = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        model.onConfigurationChange = nil
        model.monitorRunning = false
    }

    private func reconfigure() {
        invalidate()
        removeMonitors()
        guard model.enabled, model.accessibilityGranted else {
            model.monitorRunning = false
            model.statusMessage = model.enabled ? "Accessibility access needed" : "Paused"
            return
        }
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        // AppKit's reconstructed CGEvent can identify the observing app as its recipient.
        // Read the original annotated mouse event instead. A listen-only tap cannot modify input.
        eventMonitor = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
                                        options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<CloseMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if type == .tapDisabledByUserInput {
                    monitor.model.enabled = false
                    monitor.model.record("macOS paused click monitoring. Enable CallQuits to resume.")
                } else if type == .tapDisabledByTimeout {
                    monitor.invalidate()
                    if let tap = monitor.eventMonitor, monitor.model.enabled, AXIsProcessTrusted() {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                } else { monitor.handle(type, event: event) }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let eventMonitor {
            eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventMonitor, 0)
            if let eventSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
                CGEvent.tapEnable(tap: eventMonitor, enable: true)
            }
        }
        // Local keyboard interaction also cancels pending work without observing other apps' typing.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.invalidate() }
            return event
        }
        model.monitorRunning = eventMonitor != nil && eventSource != nil
        model.statusMessage = model.monitorRunning ? "Ready for your next close" : "Couldn’t start click monitoring"
    }

    private func removeMonitors() {
        if let eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        if let eventMonitor { CFMachPortInvalidate(eventMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        eventMonitor = nil
        eventSource = nil
        localMonitor = nil
    }

    private func invalidate() {
        generation &+= 1
        gesture = nil
        pressIdentity = nil
        windowObservation?.stop()
        windowObservation = nil
        worker.cancel(generation: generation)
    }

    private func handle(_ type: CGEventType, event: CGEvent) {
        // CGEvent already uses the same top-left global display coordinates as Accessibility.
        let point = event.location
        let timestamp = TimeInterval(event.timestamp) / 1_000_000_000
        let targetValue = event.getIntegerValueField(.eventTargetUnixProcessID)
        let handlerWindow = event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        let eventWindow = handlerWindow > 0 ? handlerWindow : event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
        let modifiers = event.flags.intersection([.maskShift, .maskAlternate, .maskCommand, .maskControl])
        let intent: CloseGestureModifiers = modifiers.isEmpty ? .normal :
            (modifiers == .maskShift && model.forceQuitEnabled ? .force : .bypass)
        switch type {
        case .leftMouseDown:
            invalidate()
            guard let identity = EventIdentity(nativeProcessID: targetValue, eventWindowID: eventWindow,
                                               windowOwnerProcessID: windowOwner(eventWindow)),
                  let app = NSRunningApplication(processIdentifier: identity.processID),
                  isEligible(app) else { return }
            pressIdentity = identity
            gesture = CloseGesture(x: point.x, y: point.y, timestamp: timestamp,
                                   targetProcessID: identity.processID, modifiers: intent)
            guard gesture != nil else { return }
            worker.mouseDown(point: point, eventTime: timestamp, targetPID: identity.processID, generation: generation)
        case .leftMouseDragged:
            if let gesture, !gesture.allowsDrag(toX: point.x, y: point.y) { invalidate() }
        case .leftMouseUp:
            guard let identity = pressIdentity,
                  identity.matchesRelease(nativeProcessID: targetValue, eventWindowID: eventWindow,
                                          windowOwnerProcessID: windowOwner(eventWindow)),
                  let action = gesture?.actionOnRelease(x: point.x, y: point.y, timestamp: timestamp,
                                                       targetProcessID: identity.processID, modifiers: intent)
            else { invalidate(); return }
            gesture = nil
            pressIdentity = nil
            let force = action == .force
            let token = generation
            let validUntil = timestamp + (force ? 0.8 : CloseSession.maximumDuration)
            worker.mouseUp(point: point, eventTime: timestamp, generation: token) { [weak self] hit in
                guard let self, token == self.generation, self.isEligible(hit.application) else { return }
                if force {
                    self.requestQuit(hit.application, force: true, generation: token, validUntil: validUntil)
                } else {
                    self.worker.prepareObservation(hit: hit, generation: token, onChange: { [weak self] in
                        guard let self, self.generation == token else { return }
                        self.invalidate()
                    }) { [weak self] observation in
                        guard let self, self.generation == token,
                              ProcessInfo.processInfo.systemUptime < validUntil else { return }
                        guard let observation else {
                            self.model.record("Kept \(hit.application.localizedName ?? "the app") open: window observation is unavailable.")
                            self.invalidate()
                            return
                        }
                        self.windowObservation = observation
                        observation.start()
                        self.worker.confirm(hit: hit, behavior: self.model.behavior, generation: token) { [weak self] shouldQuit, checkedAt in
                            guard let self, self.generation == token else { return }
                            if shouldQuit {
                                // Even a fresh click must not use an old snapshot after the UI queue stalls.
                                self.requestQuit(hit.application, force: false, generation: token,
                                                 validUntil: min(validUntil, checkedAt + 0.25))
                            } else {
                                self.model.record("Kept \(hit.application.localizedName ?? "the app") open: another window, dialog, or uncertain close.")
                                self.invalidate()
                            }
                        }
                    }
                }
            }
        default: break
        }
    }

    private func windowOwner(_ eventWindow: Int64) -> Int64? {
        // Only an event-stamped WindowServer ID is accepted. NSEvent.windowNumber is not a CGWindowID.
        // Exact-ID lookup reads owner metadata, never a screen image, title, or guessed frontmost app.
        guard eventWindow > 0, eventWindow <= Int64(UInt32.max),
              let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(eventWindow)) as? [[String: Any]],
              let window = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.int64Value == eventWindow })
        else { return nil }
        return (window[kCGWindowOwnerPID as String] as? NSNumber)?.int64Value
    }

    private func isEligible(_ app: NSRunningApplication) -> Bool {
        model.enabled && model.accessibilityGranted && AXIsProcessTrusted() && model.monitorRunning &&
        AppProtection.isEligible(bundleIdentifier: app.bundleIdentifier,
                                 processID: app.processIdentifier,
                                 ownProcessID: ProcessInfo.processInfo.processIdentifier,
                                 isTerminated: app.isTerminated, isHidden: app.isHidden,
                                 isRegular: app.activationPolicy == .regular,
                                 isFinishedLaunching: app.isFinishedLaunching,
                                 isExcluded: app.bundleIdentifier.map { model.isExcluded($0) } ?? true)
    }

    private func requestQuit(_ app: NSRunningApplication, force: Bool, generation token: UInt64, validUntil: TimeInterval) {
        guard token == generation else { return }
        guard ProcessInfo.processInfo.systemUptime < validUntil,
              isEligible(app), !force || model.forceQuitEnabled else { invalidate(); return }
        invalidate() // One request per click. A rejected/canceled graceful quit is never retried.
        let name = app.localizedName ?? "Application"
        let sent = force ? app.forceTerminate() : app.terminate()
        model.record(sent ? (force ? "Requested force quit for \(name)." : "Asked \(name) to quit.")
                          : "\(name) did not accept the quit request.")
    }
}

/// Queue-confined state keeps slow or unresponsive AX servers away from the main run loop.
private final class CloseWorker {
    private let queue = DispatchQueue(label: "app.callquits.accessibility", qos: .userInitiated)
    private lazy var client = AccessibilityClient()
    private var generation: UInt64 = 0
    private var down: AccessibilityClient.Hit?
    private var downTime: TimeInterval = 0

    func cancel(generation: UInt64) {
        queue.async { self.generation = generation; self.down = nil }
    }

    func mouseDown(point: CGPoint, eventTime: TimeInterval, targetPID: pid_t, generation: UInt64) {
        queue.async {
            guard self.generation == generation else { return }
            self.downTime = eventTime
            self.down = self.client.closeButton(at: point, eventTime: eventTime, targetPID: targetPID)
        }
    }

    func mouseUp(point: CGPoint, eventTime: TimeInterval, generation: UInt64,
                 completion: @escaping @MainActor (AccessibilityClient.Hit) -> Void) {
        queue.async {
            defer { self.down = nil }
            guard self.generation == generation, let hit = self.down,
                  eventTime >= self.downTime, eventTime - self.downTime <= 3,
                  ProcessInfo.processInfo.systemUptime - eventTime <= 0.8,
                  hit.buttonFrame.contains(point) else { return }
            DispatchQueue.main.async { completion(hit) }
        }
    }

    func confirm(hit: AccessibilityClient.Hit, behavior: CloseBehavior, generation: UInt64,
                 completion: @escaping @MainActor (Bool, TimeInterval) -> Void) {
        queue.async {
            guard self.generation == generation else { return }
            let session = CloseSession(behavior: behavior, startedAt: ProcessInfo.processInfo.systemUptime)
            self.poll(hit: hit, session: session, generation: generation, completion: completion)
        }
    }

    func prepareObservation(hit: AccessibilityClient.Hit, generation: UInt64,
                            onChange: @escaping @MainActor () -> Void,
                            completion: @escaping @MainActor (CloseWindowObservation?) -> Void) {
        queue.async {
            guard self.generation == generation else { return }
            let observation = CloseWindowObservation(hit: hit, onChange: onChange)
            DispatchQueue.main.async { completion(observation) }
        }
    }

    private func poll(hit: AccessibilityClient.Hit, session: CloseSession, generation: UInt64,
                      completion: @escaping @MainActor (Bool, TimeInterval) -> Void) {
        guard self.generation == generation else { return }
        var session = session
        let snapshot = client.snapshot(for: hit)
        let checkedAt = ProcessInfo.processInfo.systemUptime
        switch session.evaluate(snapshot: snapshot, now: checkedAt) {
        case .quit:
            DispatchQueue.main.async { completion(true, checkedAt) }
        case .cancel:
            DispatchQueue.main.async { completion(false, checkedAt) }
        case .wait:
            // Schedule from completion, so slow AX reads never build up a backlog of overdue polls.
            queue.asyncAfter(deadline: .now() + 0.1) {
                self.poll(hit: hit, session: session, generation: generation, completion: completion)
            }
        }
    }
}

/// Once registered, creation notifications also catch replacements between snapshots.
/// Registration is worker-only; source activation and removal are main-thread-only.
private final class CloseWindowObservation {
    private final class Relay {
        let onChange: @MainActor () -> Void
        init(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    }
    private let observer: AXObserver
    private let relay: Relay

    init?(hit: AccessibilityClient.Hit, onChange: @escaping @MainActor () -> Void) {
        relay = Relay(onChange)
        var result: AXObserver?
        let error = AXObserverCreate(hit.application.processIdentifier, { _, _, _, context in
            guard let context else { return }
            let relay = Unmanaged<Relay>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { relay.onChange() }
        }, &result)
        guard error == .success, let result else { return nil }
        observer = result
        let context = Unmanaged.passUnretained(relay).toOpaque()
        guard AXObserverAddNotification(observer, hit.appElement, kAXWindowCreatedNotification as CFString, context) == .success
        else { return nil }
        // Window creation support is mandatory. Sheet support varies; snapshots also detect sheets.
        AXObserverAddNotification(observer, hit.appElement, kAXSheetCreatedNotification as CFString, context)
    }

    @MainActor func start() {
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    @MainActor func stop() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}
