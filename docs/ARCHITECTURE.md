# Implementation notes

CallQuits separates a deterministic decision policy (`Sources/CallQuitsCore`) from macOS integration and presentation (`Sources/CallQuits`). SwiftPM tests the policy without needing Accessibility permission or terminating a process.

## One explicit gesture, one bounded decision

1. A public AppKit global mouse monitor observes another application's left-button gesture without changing the event.
2. Accessibility hit testing must identify the actual close control and its owning window and process. The Accessibility owner must match the native event's target process ID. Missing metadata means no action.
3. Mouse-down and mouse-up must have the same native target process ID and supported modifier intent. Dragging away, a long hold, bypass modifiers, exclusion changes, and new interactions invalidate the gesture.
4. For a normal quit, a short-lived Accessibility observer subscribes to the target app's window-created notifications. Registration must succeed; unsupported apps are skipped. Sheet-created notifications are also requested where supported, and snapshots check for sheets independently.
5. Normal mode lets the target handle its close. Bounded snapshots verify the original window disappeared, check for sheets and replacement windows, and count all reported windows, including minimized windows and other Spaces. A creation notification invalidates the pending request, including when a new window appears between snapshots.
6. After a stable eligible result, the adapter requests graceful termination. The target app retains its native save/quit behavior. Explicitly enabled Shift-click uses the separate force-termination path after gesture and target verification; it does not wait for the normal close confirmation.

The adapter runs synchronous Accessibility queries and observer registration on one serial background queue, uses short IPC timeouts, and discards stale work. The observer's run-loop source is installed on the main run loop and removed when the decision ends or is invalidated. This observer exists only for a pending normal close decision; the app does not periodically sweep every application.

The finite sampling after a close gesture is intentionally conservative: cancellation, an unreadable snapshot, or evidence of a replacement window ends the request. If a save sheet interrupts the close, resolving the sheet does not revive that earlier intent. The user must make a fresh close-button gesture for another automatic quit attempt.

## Platform boundaries

- AppKit's [global event monitor](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)) observes events sent to other apps; it cannot change or suppress those events.
- [Accessibility hit testing](https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition) uses top-left-relative screen coordinates and respects window layering. CallQuits reads the underlying `CGEvent` location, which already uses the matching global coordinate system.
- [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) bounds synchronous Accessibility messaging. A timeout on the system-wide object sets the process default; an element-specific timeout applies to that object.
- [`NSRunningApplication.terminate()`](https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate()) requests normal termination. [`forceTerminate()`](https://developer.apple.com/documentation/appkit/nsrunningapplication/forceterminate()) is a distinct action reserved for the user's enabled Shift-click gesture.
- [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) manages the optional login item. System approval can still be required.

Accessibility is not an atomic window-server transaction. The mouse-down hit test runs asynchronously; a very fast click can close the original window before its close control can be read. In that case CallQuits skips the gesture. A target app can also create a window before observer registration or after the final snapshot, omit notifications, or expose incomplete metadata. Unknown results are handled by declining to act, and termination requests still rely on the target application's normal lifecycle. The code never promises universal compatibility or guaranteed quit latency.

## Scope

CallQuits uses public APIs and stores settings locally. It has no network dependency, input injection, continuous window polling, or document-content collection. It runs outside App Sandbox because it needs cross-application Accessibility access, while local builds enable the hardened runtime. Developer ID signing and notarization remain release concerns.
