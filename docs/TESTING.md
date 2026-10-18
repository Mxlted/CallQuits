# Testing CallQuits

`swift test` exercises the independent policy with simulated application and window states. `./scripts/build.sh` compiles and signs a real app bundle. Neither proves that Accessibility permission is granted or that a particular app exposes reliable window metadata.

The XCTest suite in `Tests/CallQuitsCoreTests/` covers exact event identity and conflicts, close-time window disappearance, gesture modifiers, pointer movement, protected apps, stable close confirmation, unreadable states, sheets, replacement windows, expiry, and repeated decisions. `Tests/CallQuitsTests/` exercises AppModel status mapping and event-tap recovery with simulated settings and monitoring state, plus Accessibility capture and snapshot recovery through injected hit testing and attribute readers. Neither suite drives the real Core Graphics event tap or Accessibility observer.

The [October 17 lifecycle and compatibility investigation](INVESTIGATION-2026-10-17.md) records the broader audit, native fixture observations, focused fixes, validation results, and unresolved limits. Its regression additions cover target-scoped visibility changes, pinned application identity, and secondary/auxiliary press cancellation.

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

The fixture deliberately remains running after its last window closes. Its native tab group has a Close button; hit testing exposes a sibling rendering group to reproduce Brave's native tab-strip structure. New Tab or ⌘T adds an in-memory tab, and ⌘W closes one tab before closing the window when the last tab is removed. Its documents are memory-only and it never reads or writes personal files. Relaunch it between quit cases. Its File menu can create a window even when all previous windows are closed. Use its checkboxes to simulate unsaved changes or a replacement window, and its button to show a blocking sheet.

The **Hide application instead of closing** checkbox reproduces retained-window behavior for native/AX inspection. Dirty-close and blocking-sheet handling run first. The fixture logs lifecycle timestamps to stdout without window titles or document content. Its bundle identity is not Discord, so production CallQuits must continue rejecting its hidden state; testing the Discord-specific snapshot policy in isolation requires an explicitly injected qualification, not a spoofed bundle identifier.

Enable CallQuits and grant its Accessibility permission before live checks. Confirm the fixture is not excluded. Use last-window mode and leave Shift-click force quit disabled unless the test explicitly requires them. Do not use the user's real applications as termination targets.

## Manual matrix

| Scenario | Expected outcome |
| --- | --- |
| Red click on one clean fixture window | Window closes; CallQuits requests a graceful quit after confirming the app has no remaining windows. |
| Quickly red-click an empty fixture window; repeat with a held click | Both can qualify only while AX can positively identify the close button. A close immediately after the final control read must not lose already captured window membership; confirmation delays remain unchanged. |
| Two fixture windows; close one | App and second window remain. |
| Two windows; minimize one, close the other | App remains. |
| Two windows on different Spaces; close the visible one | App remains. |
| Fullscreen window in another Space | It still counts; closing another window does not quit the app. |
| Close the last window with ⌘W, additional close methods enabled | Graceful quit after confirming the window closed; native recipient must match the captured application. |
| Close a tab with ⌘W while its window remains | App remains, including in any-window mode. |
| Click the native tab-close button on the last tab | Graceful quit only if the last window closes; sheets and replacements cancel. |
| Close with additional close methods disabled, a menu command, or a programmatic close | Only verified red clicks can request quit. |
| Shift-click a tab-close button, or press ⌘⇧W / ⌘⌥W / repeated ⌘W | Native behavior; no new automatic quit intent. |
| Type ⌘W on another keyboard layout, or with missing native PID | Match the resolved W character; never use a fixed physical key or guess the recipient. |
| Close several tabs with successive ⌘W presses | Remaining tabs keep the window/app open; the final close can quit without switching apps. |
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
| Press a key while a close is pending, including Cancel/Escape or Hide shortcuts | Cancel the attempt without reading or recording the key. A later app hide must not revive it. |
| Right-click or press an auxiliary mouse button during a pending close, including inside CallQuits | Cancel the old attempt; these presses must never qualify as close-button intent. |
| A separate disposable app hides itself while the target's close is pending | Ignore the unrelated hide; hiding/unhiding the target still invalidates intent except for the existing qualified hide-on-close path. |
| Target process exits or automatically relaunches during a pending decision | The old application's object, native PID, and bundle identity must still match at both termination paths; a new process cannot inherit the old attempt. |
| Enable any-window mode and close one of two clean windows | Graceful quit is requested after the clicked window closes. |
| Any-window mode with another unsaved document | The target app's ordinary quit/save behavior remains authoritative. |
| Close one native window tab while another tab remains | A newly exposed tab identity currently cancels as a replacement, including in any-window mode; do not relax replacement protection to force a quit. |
| Enable Shift-click force quit after warning; Shift-click a verified red button | Explicit force quit may discard all fixture state, even with other windows. |
| Exclude fixture; repeat ordinary and enabled Shift-click | Neither path terminates it. |
| Protected apps such as Finder or CallQuits | Verify policy protection with unit tests; do not terminate actual system apps. |
| Accessibility denied or revoked | Explain permission status; do not act on uncertain state. |
| Monitoring unavailable while enabled and Accessibility-trusted | Retry monitoring is available; failed creation/re-enable remains unavailable and exposes permission-recovery help. No endless automatic retries. |
| Event tap is disabled, then restored | Cancel any pending gesture before re-enabling; resume only after the tap is confirmed enabled and Accessibility trust remains available. A user-disabled tap stays paused until the user chooses Enable CallQuits. Retry monitoring appears only while enabled, trusted, and unavailable. |
| Intentional pause or CallQuits disabled | Permission refresh and monitoring retries must not resume capture implicitly. |
| Unreadable or unsupported AX tree | Skip; never infer zero windows from an error. |
| Clicked window disappears between AX enumeration and inspection | Only `invalidUIElement` from that window or its children permits one immediate fresh enumeration. Continue only if exactly the clicked window disappeared and all surviving windows can be inspected; the normal stable confirmation still applies. |
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

## Discord hide-on-close development checks — October 17, 2026

On this Mac, programmatic closes in a disposable native fixture retained the identical AX window after hiding. The app-hidden state updated asynchronously. A second window, including a minimized one, remained in the AX window list. Dirty-close and existing blocking sheets prevented hiding and remained visible in AX. Five native/self-AX scenarios completed; these were not physical pointer captures or measurements of Discord.

A separate disposable probe compiled the production `AccessibilityClient`, `CloseSession`, and `AppProtection` unchanged. With verified-click qualification explicitly injected into the probe only, clean hidden-window snapshots waited for stable confirmation, then produced a graceful quit decision and the fixture exited. Dirty-close and existing sheets canceled with `blockingUI`; two retained windows canceled with `remainingWindows`. The blocked fixtures were quit separately during cleanup. This validates the snapshot/policy path, not event identity, positive close-button hit testing, external AX permission, or observer delivery.

XCTest covers the scoped identity/transition allowance, release expiry, hidden-before-click protection, retained/minimized/multiple windows, sheets, replacement windows, unreliable snapshots, unhide, and final eligibility boundaries. Keyboard-interruption delivery and both hide-notification orderings through the complete monitor still need live validation. No user applications were used as automated termination targets. No click-to-quit or Dock-disappearance timing is claimed.

Routine validation passed: 63 debug XCTest cases, the release-configuration bundle build with the existing Developer ID identity, strict signature verification, and whitespace checks. The release build needed desktop execution access for `dsymutil`; no source workaround was required. The separately built development app was installed locally, and computer-use inspection showed **Watching close buttons** with Accessibility access retained. The previous notarized app was preserved for rollback; the development build was not submitted for notarization or published.

After installation, the user physically clicked Discord's red close button without Shift and reported that Discord quit normally. Activity recorded **Asked Discord to quit**, and a subsequent read-only process check found no running Discord main application. This is one observed successful normal-close case for the installed Discord 0.0.416 (with Equicord), not a guarantee across Discord versions, release channels, or window arrangements.


## v0.1.2 release validation — October 17, 2026

Version 0.1.2, build 3, was built separately from the preserved v0.1.1 artifacts with Developer ID Application signing, hardened runtime, and a secure timestamp. Its binary contains only `arm64`, with a macOS 14 deployment target. All 63 debug XCTest cases passed during final preparation.

Apple accepted notarization submission `d673cd5e-6c4d-4fbe-9e2e-3821d21409cd`; its log reported no issues. Stapling and ticket validation passed. The final `ditto` ZIP was extracted into a fresh directory; executable permissions, strict signature verification, the stapled ticket, and the archive checksum all passed. `syspolicy_check distribution` passed on both the original and extracted app. `spctl` reported Notarized Developer ID with `override=security disabled`; default Gatekeeper enforcement was not established and system security settings were not changed.

The delivered ZIP SHA-256 is `d743f422be4da4481cc9fc239db81112363db5f693014b0554dec1da3b00e602`. The earlier physical Discord test used the preceding development build with the same application source, not this exact versioned archive. The remaining live-matrix, keyboard/notification-delivery, macOS 14/Intel runtime, separate-Mac/account installation/upgrade, and latency limitations above still apply.

The final stapled v0.1.2 app was installed on this Mac. Its installed signature and ticket verified, and computer-use inspection showed version 0.1.2 and **Watching close buttons**, with the existing Accessibility grant retained. This same-Mac check does not establish fresh-install or upgrade behavior on another Mac/account.

## Closing-window snapshot race — October 17, 2026

The user reported intermittent Chrome failures with Activity saying **Accessibility could not reliably confirm the window state**. A disposable native fixture reproduced a matching failure: after `AXWindows` enumerated the clicked target, the fixture closed that window immediately before the adapter read `AXModal`. The real AX read returned `invalidUIElement` (`-25202`). The old adapter canceled with `unreliableSnapshot` in all eight repetitions; the updated adapter obtained a complete empty snapshot and reached a quit decision in all eight repetitions. This establishes a window-lifecycle race, not the exact underlying error in the user's Chrome process.

The updated fixture snapshot took 2.36–7.60 ms; the policy reached its quit decision 211–220 ms after snapshot processing began, with the existing 150 ms stable confirmation and 200 ms minimum unchanged. Recovery adds no scheduled delay. These measurements used self-AX with verified-click qualification injected and a controlled close between reads. They are not physical click-to-request, actual process-exit, or Dock-disappearance timings; the fixture was quit separately during cleanup. External AX permission, native event capture, observer delivery, and Chrome itself were not exercised.

Additional fixture cases retained cancellation for messaging failures, a still-present invalid target, failed fresh enumeration, unreadable surviving windows, replacement windows, other remaining windows, and sheets, including a sheet appearing on a survivor during recovery. XCTest separately covers invalid child elements, malformed values, survivor identity changes, repeated failure, the shared read budget, and unchanged close confirmation. Tests with an injected reader simulate AX results and do not establish app compatibility. The earlier live-matrix gaps still apply.

Routine validation passed: 77 debug XCTest cases, a separate release-configuration development bundle with ad hoc signing and strict signature verification, and whitespace checks. The release build required desktop execution access for `dsymutil`. Finalized release artifacts and the installed application were preserved.

## v0.1.3 release validation — October 17, 2026

Version 0.1.3, build 4, was built in a separate release directory with Developer ID Application signing, hardened runtime, and a secure timestamp. The binary contains only `arm64`, with a macOS 14 deployment target. All 77 debug XCTest cases passed during final preparation. Prior release artifacts and the installed application were preserved.

Apple accepted notarization submission `f809cc56-0649-498b-a020-cd00f7c4d008`; its log reported no issues. Stapling and ticket validation passed. The delivery ZIP was recreated from the stapled app and extracted into a fresh directory. Executable permissions, strict signature verification, the stapled ticket, and the archive checksum all passed. `syspolicy_check distribution` passed for the original and extracted app. `spctl` reported Notarized Developer ID with `override=security disabled`; default Gatekeeper enforcement was not established and no system security settings were changed.

The final ZIP SHA-256 is `9eaefad02bea9bf2289451d27d02bbef4b39aea1237cb5ad99d2f2f3cce5a2d3`. The snapshot-race fixture measurements above used the preceding development source, not physical clicks on the final signed archive. Physical Chrome verification, the full live fixture matrix, keyboard/notification delivery, macOS 14/Intel runtime, separate-Mac/account installation and upgrade, and physical latency measurements remain incomplete. Notarization and unit tests do not establish those results.

## Empty-editor close capture — October 17, 2026

The user reported that CotEditor's empty Untitled editor remained running after a red-button close, while a file-backed editor quit. Computer-use inspection showed a standard editor window with a close control; the installed CotEditor version was 7.1.2. Its [versioned source](https://github.com/coteditor/CotEditor/blob/7.1.2/CotEditor/Sources/Document/Document.swift#L604-L670) bypasses the ordinary document close path for empty drafts. This supports investigating a fast-close race; it does not establish which AX operation failed in the user's physical click.

On macOS 27.0.1 (26A434), a disposable native fixture closed its own window immediately after returning the final button geometry. The old adapter discarded all eight attempts because its subsequent initial-window enumeration no longer included the target. The updated production AX capture accepted all eight using the earlier initial window set. Reliable empty snapshots then reached the unchanged policy's quit decision after 207–216 ms from confirmation start. Targets absent before initial enumeration and windows with sheets remained rejected; remaining and replacement windows still canceled the policy decision.

The fixture's attribute calls fell from 18 to 10 (eight individual calls and two grouped calls). Across nine retained-window samples, summed time inside actual AX attribute calls had medians of 15.06 ms before and 12.57 ms after, with overlapping ranges. These are self-AX measurements with the genuine close element injected in place of global hit testing. The production capture method was compiled directly; the baseline probe alone bypassed own-process protection to inspect itself. No physical event capture, external Accessibility permission, observer delivery, automatic process termination, or Dock latency was measured. Fixture processes exited through separate cleanup. The source, runner and raw measurements remain in the ignored local `build/fixture-fast-close/` directory.

Regression tests exercise complete close-control proof, initial membership, mismatched ownership, sheets, malformed bulk responses, strict CF element types, expired read budgets and the bounded individual-read fallback for an unimplemented bulk API. All 91 debug XCTest cases passed. The release-configuration development bundle at `build/development/coteditor-close-fix/CallQuits.app` passed ad hoc signing and strict signature verification; `dsymutil` required desktop execution access. Working and staged whitespace checks passed. This build has not been installed, notarized or published. Physical verification with CotEditor and other editors, plus the earlier live-matrix gaps, remains outstanding.

## Untitled document release checks — October 17, 2026

The reported editor case was clarified as a blank Untitled document, rather than a startup file chooser. On macOS 27.0.1 (26A434), arm64, a new disposable fixture used real `NSDocument` instances, `NSWindowController`, and empty `NSTextView` editors without reading or writing files. It compiled the current production Accessibility capture and close policy directly and closed each clean document immediately after the final button metadata read.

The earlier enumerate-last adapter rejected all eight controlled closes. The current adapter captured all eight and reached the unchanged quit policy after 206.5–211.2 ms from confirmation start. A retained document kept waiting; a target absent before initial membership and a pre-existing sheet prevented capture. Marking an Untitled document dirty opened its actual native save sheet and canceled confirmation with `blockingUI`. A second document canceled with `remainingWindows`, and a newly created document canceled with `replacementWindow`.

These are native document-lifecycle and self-Accessibility checks with the genuine close element injected instead of global hit testing. The baseline alone bypassed own-process protection; current production code was unchanged. The timings measure policy confirmation, not physical click-to-request, process exit, or visible Dock disappearance. Each fixture exited through separate cleanup. Physical CotEditor/TextEdit compatibility, external Accessibility access, event capture, and observer delivery remain unverified, along with the earlier live-matrix gaps. Source, runner, hashes, raw results, and a summary remain in the ignored local `build/fixture-editor-release-20261017/` directory.

## v0.1.4 release validation — October 17, 2026

Version 0.1.4, build 5, was built in `build/releases/0.1.4/` with Developer ID Application signing, hardened runtime, and a secure timestamp. The binary contains only `arm64` and declares macOS 14 as its minimum. All 95 debug XCTest cases passed. The release includes the previously unpublished empty-editor capture and lifecycle fixes. The installed application and previous finalized releases were preserved.

Apple accepted app submission `7e1d2757-b9a7-438d-abf3-6a05945222d2` and DMG submission `ede5f73f-3845-4266-99cb-90ef5bf09d05`; both logs reported no issues. The app was stapled before packaging. The signed DMG contains that app and an Applications shortcut, and its own ticket was stapled after acceptance. Strict signatures, both tickets, `hdiutil verify`, and the final checksum passed. A read-only mount and fresh app copy preserved the executable, signature, and ticket; the copied executable matched the original SHA-256. `syspolicy_check distribution` passed for both the original and copied app. `spctl` reported `override=security disabled`, so default Gatekeeper enforcement was not established and no system security settings were changed.

The final DMG SHA-256 is `a96c6de6ef4ac9b5bca831d401b8a8104db75c1d285003e69d49a87b28bb7f62`. Public releases now deliver the DMG and checksum; the private app-submission ZIP is not a public asset. Physical editor verification, the full live matrix, macOS 14/Intel runtime, and installation/upgrade on a separate Mac/account remain incomplete. The document fixture above tests the production source and native document lifecycle, not a physical click through the final signed app.

## Tabs and shortcuts development checks — October 18, 2026

Source builds add **Close tabs and use ⌘W**, enabled by default. It is independent of the red button's any-window mode and force-quit opt-in. The v0.1.4 download does not include this change.

Debug XCTest and the release app-bundle/signature build passed. New cases cover native tab ancestry versus web controls, conflicting official close-button identity, disabled/unknown/localized controls, close-time window disappearance, focused-window ownership, sheets, minimized targets, layout-resolved shortcut matching, repeats and modifiers, identity/freshness boundaries, preference persistence, and last-window/graceful-only routing.

A fixture-only monitor was compiled from the current integration and policy sources on arm64 macOS 27.0.1 (26A434). Its only behavior restriction was an additional eligibility allowlist for `app.callquits.Fixture`; temporary instrumentation recorded verified input timestamps and decisions. The fixture contained disposable in-memory tabs and documents. External Accessibility permission and the native event tap were available. Computer-use input reached the tap for the measured cases; this does not establish physical input behavior.

| Scenario | Observation |
| --- | --- |
| ⌘W with two tabs | One tab closed; the window and app remained. |
| Subsequent ⌘W on the last tab | Normal quit requested without switching apps; process exited. |
| Native tab Close button, last tab | Normal quit requested; process exited. |
| Unsaved document, ⌘W, Cancel | Save sheet appeared; the pending quit ended and the document stayed open. |
| Replacement window after ⌘W | New window remained; no quit request. |
| Two windows, including a minimized-window case | App remained. These trials conservatively rejected an unreliable AX snapshot rather than demonstrating complete enumeration of the surviving window. |
| Automated red-button close | One trial canceled on a creation notification; later title-bar interactions were not reproducible. Physical red-button checks remain required; its policy/capture regression tests passed. |

Representative verified-input measurements used the native event timestamp, the monitor's return from `terminate()`, and a parent process's observation of fixture exit, all aligned to `mach_absolute_time`. Native application close/save behavior was retained.

| Input | Quit request | Process exit |
| --- | ---: | ---: |
| ⌘W | 322 ms | 330 ms |
| Tab-close click | 236 ms | 239 ms |

These are individual fixture trials, not latency guarantees or a statistical benchmark. Visible Dock-indicator disappearance was not measured. The reference implementation's roughly 1.55-second minimum is derived from its code (350 ms first check plus 1.2 s confirmation), not a side-by-side runtime measurement. CallQuits keeps its existing 150 ms stable confirmation and 200 ms minimum session duration.

The live trials justified preparing the active window before ⌘W: immediate post-key capture could lose the window entirely. They also exposed a snapshot racing native close, so shortcut checks use a destroy-notification wakeup with a 100 ms fallback on providers that retain closed window objects. Idle observations cannot request quit. Ordinary red-button clicks retain their existing capture and observation path.

Chrome's native AX tree was inspected read-only and exposed a Close button inside a tab inside a tab group. No real browser was used as a termination target. Cross-browser behavior, unsupported localized labels, alternate keyboard layouts with physical input, other Spaces/fullscreen, macOS 14/Intel runtime, and the rest of the live matrix remain unverified. Raw fixture harnesses and logs are local under the ignored `build/close-methods-probe/` directory. The reference `vorssaint-utils/` directory was read only.

## Browser tab hit testing and settings — October 18, 2026

On arm64 macOS 27.0.1 (26A434), Brave 155.1.97.59 exposed its tab's Close button in the semantic AX tree, but an application-scoped native hit test at that button returned a leaf `AXGroup`. The leaf's immediate parent contained both that rendering group and the semantic `AXTabGroup`. The earlier capture code only searched upward from the hit, so seeing a Close button in a tree inspection had not established that clicks could reach it.

A read-only probe compared the previous capture source with the corrected sibling resolver. The previous source accepted 0/8 Close locations; the corrected source accepted 8/8. Both rejected all eight locations on the tab body outside the actual Close button. The probe called the real application-scoped AX hit test instead of injecting a button identity; it did not close any browser tab or request browser termination. Production continues to use its system-wide hit test and original native event identity. These checks do not establish physical event capture or browser process exit.

The disposable fixture now reproduces that native sibling hit while retaining its real button action. With real application-scoped AX hit testing, the previous capture accepted 0/8; the corrected capture accepted 8/8. After native fixture closes, the unchanged policy reached `.quit` in all eight clean cases. A remaining tab retained its window and kept waiting; a second visible or minimized window canceled with `remainingWindows`; a replacement canceled with `replacementWindow`; and a real dirty-close save sheet canceled with `blockingUI`. A pre-existing sheet, a tab-body point and disabled additional close methods prevented capture. The harness observed decisions without executing automatic termination; fixtures exited separately during cleanup. Sources, hashes and raw logs remain in ignored `build/sibling-tab-fixture-probe/`.

All 116 debug XCTest cases passed. New capture cases cover the observed sibling relationship, nested native groups, description-only Close labels, child hits, ambiguous or malformed competing controls, wrong window/parent identities, web ancestry, depth limits, unsupported labels, and all existing setting/control protections. The release-configuration app at `build/development/CallQuits.app` was signed with the installed Developer ID Application identity and passed strict signature verification. It is an arm64 development build, not a new notarized or published release; previous release artifacts were preserved.

The settings view was rendered with an isolated, paused model and no monitor at 830×680 and the effective minimum 780×632. Standard settings fit without scrolling; force-quit guidance remained readable. Permission recovery can still scroll when its extra notice is present, while the sidebar's Accessibility Settings shortcut remains visible. The existing privacy-pane link was checked in System Settings without changing any permissions. On this Mac it opened the page named Device Control and Data Access.

A computer-use fixture click did not yield an observable input event in the instrumented native tap during this run. No physical click-to-quit, process-exit or Dock-disappearance measurement is claimed. Read-only browser logs, layout renders and probe sources remain in ignored `build/tab-close-audit/` and `build/settings-layout-probe/`. The wider live matrix, macOS 14/Intel runtime, and physical browser compatibility checks remain outstanding.

## v0.1.5 release validation — October 18, 2026

Version 0.1.5, build 6, was built in `build/releases/0.1.5/` with Developer ID Application signing, hardened runtime and a secure timestamp. The binary contains only `arm64` and declares macOS 14 as its minimum. All 116 debug XCTest cases passed. The release includes native tab-close and ⌘W support, the browser sibling-hit correction, the permanent Accessibility Settings shortcut, and the more compact settings layout. Existing development and finalized release bundles were preserved.

Apple accepted app submission `131c09f5-c55a-4b54-8333-78252435cca3` and DMG submission `40b8cbe2-7b15-48d3-b00f-76b3ea976fac`; both logs reported no issues. The app was stapled before DMG packaging. Strict app and DMG signatures, both stapled tickets, `hdiutil verify`, and the final checksum passed. A read-only mount contained the app and the correct Applications shortcut. Its fresh app copy retained executable permissions, signature and ticket, and the copied executable matched the original SHA-256. `syspolicy_check distribution` passed for both the original and copied app. `spctl` reported `override=security disabled`, so default Gatekeeper enforcement was not established and no system security settings were changed.

The final DMG SHA-256 is `4f33c8543c68db97d28d2a76aea005e3ad3e423620deed8d9cdfb26e7a40539c`. Public assets are the DMG and `SHA256SUMS.txt`; the app-submission ZIP remains private. The physical-input, full live-matrix, macOS 14/Intel runtime, and separate-Mac/account installation and upgrade gaps above remain. Notarization and the earlier fixture results do not establish physical browser behavior through the final signed bundle.
