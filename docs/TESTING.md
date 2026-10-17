# Testing CallQuits

`swift test` exercises the independent policy with simulated application and window states. `./scripts/build.sh` compiles and signs a real app bundle. Neither proves that Accessibility permission is granted or that a particular app exposes reliable window metadata.

The XCTest suite covers exact event identity and conflicts, close-time window disappearance, gesture modifiers, pointer movement, protected apps, stable close confirmation, unreadable states, sheets, replacement windows, expiry, and repeated decisions. It does not drive the real Core Graphics event tap or Accessibility observer.

## Routine validation

Run from the repository root before delivery:

```sh
swift test
./scripts/build.sh
git diff --check
```

Before committing, also run `git diff --cached --check` to check the staged changes. These local whitespace checks inspect actual edits; CI's clean checkout would have no working-tree changes to inspect.

Keep debug XCTest execution and the release app-bundle build/signature check. They exercise different configurations and require separate compilation; sharing a scratch path would not eliminate that work. The build script's `swift build --show-bin-path` only locates the output and does not compile it again.

If the default SwiftPM cache locations are not writable, use repository-local directories:

```sh
mkdir -p .build/cache .build/config .build/security .build/ModuleCache
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --scratch-path .build/swiftpm --cache-path .build/cache \
  --config-path .build/config --security-path .build/security --disable-sandbox
```

The build script already uses writable repository-local caches. Run the focused fixture cases relevant to a behavior change; routine validation does not require regenerating fixtures, icons, or the Xcode project.

CI retains the `macos` job in one workflow, on the explicit `macos-15` image with the app's macOS 14 deployment target unchanged. It validates every pull request without path filters, pushes to the default `main` branch, and manual dispatches. Superseded runs cancel only within the same event type and PR or ref. Only manual dispatch creates a downloadable ad hoc development ZIP, using `ditto` to preserve executable permissions. It does not publish releases. The selected [runner image](https://github.com/actions/runner-images) and [checkout v6](https://github.com/actions/checkout/tree/v6)/[upload-artifact v6](https://github.com/actions/upload-artifact/tree/v6) support current Node 24 action runtimes.

## Xcode configuration changes

After relevant `project.yml` or source/resource structure changes, regenerate the project as described in [Development](DEVELOPMENT.md#xcode-and-project-structure), then build its route:

```sh
xcodebuild -project CallQuits.xcodeproj -scheme CallQuits \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath .build/xcode build
codesign --verify --deep --strict .build/xcode/Build/Products/Release/CallQuits.app
```

Check that the generated bundle's version and build number match `Resources/Info.plist` and its minimum OS remains macOS 14. SwiftPM remains the canonical test route.

## Release validation

Follow [release preparation](RELEASING.md) to select the Developer ID identity **before** routine validation, so the build step validates the final signed bundle without requiring an ad hoc build first. Run the full manual matrix below on that bundle, including macOS 14 and the current macOS release, then test the exact delivered archive on a separate Mac/account for first install and upgrade. Record untested OS versions, architectures, and scenarios explicitly.

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
| Monitoring unavailable while enabled and Accessibility-trusted | Retry monitoring is available; failed creation/re-enable remains unavailable and exposes permission-recovery help. No endless automatic retries. |
| Event tap is disabled, then restored | Cancel any pending gesture before re-enabling; resume only after the tap is confirmed enabled and Accessibility trust remains available. A user-disabled tap stays stopped until explicitly retried. |
| Intentional pause or CallQuits disabled | Permission refresh and monitoring retries must not resume capture implicitly. |
| Unreadable or unsupported AX tree | Skip; never infer zero windows from an error. |
| App does not support registration for AX window-created notifications | Skip automatic graceful quit. Sheet notifications are optional because snapshots also inspect sheets. |
| Very fast click closes the original window before its AX close button can be read | Native close proceeds; skip automatic quit because the gesture could not be verified. |
| Hung target process | Bound waiting, keep CallQuits responsive, and skip if identity/control cannot be verified. Shift-click is not guaranteed; macOS Force Quit remains available. |
| Rapid successive clicks or restart of target process | Stale intents cannot affect a newer process or gesture. |
| Mixed-DPI displays, negative-coordinate display, dock on either screen | Only a positively identified red button may trigger. No geometric fallback. |
| Grant/revoke Accessibility while settings are open | Timer and manual refresh produce the same status and one Activity entry per meaningful transition. |
| Relaunch CallQuits; toggle launch at login or change approval in System Settings | Settings reflect enabled, pending approval, unregistered, missing, or unknown status without stale approval/error text. |

Fullscreen, Spaces, multiple displays, native event target IDs, notification delivery, macOS version differences, and hung targets need a real desktop session. A synthetic policy result does not establish that the corresponding real-world gesture was captured. Verify that each temporary observer's main-run-loop source is removed when its decision completes, is canceled, or times out.

## Recording results

Record the macOS version, build/commit, permissions, disposable target app, window layout, action, and observed result. Measure click-to-quit-request, actual process exit, and visible Dock disappearance separately. A successful `terminate()` request does not prove the app exited; the application may still be saving or may decline. Keep physical clicks, computer-use actions, and simulated inputs clearly labeled, without recording document names or window titles.

## Observed development results — October 16, 2026

With Accessibility granted and the listen-only annotated session event tap active, the user performed physical red close-button clicks. CallQuits recorded graceful quit requests for two Google Chrome launches and one Safari launch. Subsequent process checks confirmed that all three target processes exited. These observations validate that physical clicks can reach the tap, resolve the target, and trigger a real graceful quit.

Computer-use automation clicks did not produce a usable event through this path. Direct process delivery or Accessibility actions are possible explanations, but the delivery mechanism was not verified. Those attempts are not evidence for or against physical-pointer behavior.

The full disposable-fixture matrix, multiple-window behavior, save cancellation, minimized windows, other Spaces, and Shift-click force quit still need live verification. No exhaustive compatibility result or measured Dock-indicator latency is claimed. Use the fixture for further integration tests, and update this record only with observed results.

## Review implementation feasibility checks — October 17, 2026

The disposable fixture built on macOS 27.0.1 (26A434), but was not launched for termination tests. A temporary diagnostic process reported no Accessibility trust or listen-event access, and creating the passive annotated-session event tap returned nil. This describes that diagnostic process, not the permission state of an installed CallQuits copy. No physical-pointer participant was available.

No live click-to-quit-request, process-exit, or Dock-disappearance timings were collected. Save cancellation, replacement windows, minimized windows, Spaces, exclusions on both termination paths, monitoring recovery, and macOS 14 still need the live checks above. No personal applications were used as termination targets.

Source inspection found that cancellation work on the serial AX worker waits behind work already running. Per-read soft budgets are checked before attribute calls and can overrun by one bounded synchronous call; polling schedules its next attempt after completion. These observations do not quantify a user-visible cost. Absolute operation expiry, additional between-call cancellation, observer-setup changes, and fast-click optimizations are deliberately deferred until disposable-fixture measurements justify them. Confirmation and safety delays remain unchanged.
