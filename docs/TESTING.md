# Testing CallQuits

`swift test` exercises the independent policy with simulated application and window states. `./scripts/build.sh` compiles and signs a real app bundle. Neither proves that Accessibility permission is granted or that a particular app exposes reliable window metadata.

The initial suite contains 40 unit tests covering exact event identity and conflicts, close-time window disappearance, gesture modifiers, pointer movement, protected apps, stable close confirmation, unreadable states, sheets, replacement windows, expiry, and repeated decisions. It does not drive the real Core Graphics event tap or Accessibility observer.

## Disposable fixture

```sh
./scripts/build-fixture.sh
open "build/CallQuits Fixture.app"
```

The fixture deliberately remains running after its last window closes. Its documents are memory-only and it never reads or writes personal files. Relaunch it between quit cases. Its File menu can create a window even when all previous windows are closed. Use its checkboxes to simulate unsaved changes or a replacement window, and its button to show a blocking sheet.

Enable CallQuits and grant its Accessibility permission before live checks. Confirm the fixture is not excluded. Use last-window mode and leave Shift-click force quit disabled unless the test explicitly requires them. Do not use the user's real applications as termination targets.

## Manual matrix

| Scenario | Expected outcome |
| --- | --- |
| Red click on one clean fixture window | Window closes; CallQuits requests a graceful quit after confirming the app has no remaining windows. |
| Two fixture windows; close one | App and second window remain. |
| Two windows; minimize one, close the other | App remains. |
| Two windows on different Spaces; close the visible one | App remains. |
| Fullscreen window in another Space | It still counts; closing another window does not quit the app. |
| Close the last window with ⌘W or File → Close Window | App remains; no verified red-button intent. |
| Click yellow or green button, title bar, or toolbar control | No quit request. |
| Press red button, drag away, release | No quit request. Test drag away and back as well. |
| Option-, Command-, or Control-click red button | App's native modifier behavior; no CallQuits quit request. |
| Press without Shift, release with Shift, or vice versa | No CallQuits quit request; supported modifier intent must match at mouse-down and mouse-up. |
| Native mouse-down and mouse-up report different target process IDs | No quit request, even when screen coordinates match. |
| Native target PID is absent but the event carries a valid global window ID | Resolve only that exact window's owner and require the AX close control to belong to it. |
| Native close removes the original window entry before mouse-up | A matching original stamped window ID can preserve the verified owner; conflicting process/window metadata still cancels. |
| Release reports the newly exposed underlying window or a different positive owner | Cancel; the quit request cannot transfer to the underlying application. |
| Shift-click with force quit disabled | Native close behavior; no CallQuits quit request. |
| Enable unsaved changes, click red, select Cancel | App and document remain; pending quit is canceled. |
| Enable unsaved changes, click red, then Save or Don't Save | Native sheet handles close; CallQuits does not reuse the interrupted intent to quit later. |
| Show a blocking sheet, try to close | No termination while a sheet or unknown state is present. |
| Enable replacement checkbox and close | New window appears; app remains. |
| Close, then create another window during the confirmation interval | App remains. |
| A new window appears briefly between snapshots | A supported window-created notification cancels the pending normal quit. |
| Switch mode, pause, revoke permission, or exclude fixture while a decision is pending | Old intent cannot terminate the fixture. |
| Enable any-window mode and close one of two clean windows | Graceful quit is requested after the clicked window closes. |
| Any-window mode with another unsaved document | The target app's ordinary quit/save behavior remains authoritative. |
| Enable Shift-click force quit after warning; Shift-click a verified red button | Explicit force quit may discard all fixture state, even with other windows. |
| Exclude fixture; repeat ordinary and enabled Shift-click | Neither path terminates it. |
| Protected apps such as Finder or CallQuits | Verify policy protection with unit tests; do not terminate actual system apps. |
| Accessibility denied or revoked | Explain permission status; do not act on uncertain state. |
| Event tap is disabled, then restored | Cancel any pending gesture before re-enabling; only resume when enabled and Accessibility trust remains available. |
| Unreadable or unsupported AX tree | Skip; never infer zero windows from an error. |
| App does not support registration for AX window-created notifications | Skip automatic graceful quit. Sheet notifications are optional because snapshots also inspect sheets. |
| Very fast click closes the original window before its AX close button can be read | Native close proceeds; skip automatic quit because the gesture could not be verified. |
| Hung target process | Bound waiting, keep CallQuits responsive, and skip if identity/control cannot be verified. Shift-click is not guaranteed; macOS Force Quit remains available. |
| Rapid successive clicks or restart of target process | Stale intents cannot affect a newer process or gesture. |
| Mixed-DPI displays, negative-coordinate display, dock on either screen | Only a positively identified red button may trigger. No geometric fallback. |
| Relaunch CallQuits; toggle launch at login | Settings persist; actual ServiceManagement status is reported. |

Fullscreen, Spaces, multiple displays, native event target IDs, notification delivery, macOS version differences, and hung targets need a real desktop session. A synthetic policy result does not establish that the corresponding real-world gesture was captured. Verify that each temporary observer's main-run-loop source is removed when its decision completes, is canceled, or times out.

## Recording results

Record the macOS version, build/commit, permissions, target app, window layout, action, and observed result. Separate the time of the quit request from the visible disappearance of the Dock indicator. A successful `terminate()` request does not prove the app exited; the application may still be saving or may decline.

## Observed development results — October 16, 2026

With Accessibility granted and the listen-only annotated session event tap active, the user performed physical red close-button clicks. CallQuits recorded graceful quit requests for two Google Chrome launches and one Safari launch. Subsequent process checks confirmed that all three target processes exited. These observations validate that physical clicks can reach the tap, resolve the target, and trigger a real graceful quit.

Computer-use automation clicks did not produce a usable event through this path. Direct process delivery or Accessibility actions are possible explanations, but the delivery mechanism was not verified. Those attempts are not evidence for or against physical-pointer behavior.

The full disposable-fixture matrix, multiple-window behavior, save cancellation, minimized windows, other Spaces, and Shift-click force quit still need live verification. No exhaustive compatibility result or measured Dock-indicator latency is claimed. Use the fixture for further integration tests, and update this record only with observed results.
