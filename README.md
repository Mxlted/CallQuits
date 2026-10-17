<img src="Resources/AppIcon.png" width="128" height="128" alt="CallQuits: a red close button on a window with a power symbol">

# CallQuits

A small native macOS menu bar app that makes the red close button quit an app after its **last window** closes.

macOS 14+ · SwiftUI + AppKit · No runtime dependencies · MIT licensed

The close button still belongs to the application. CallQuits observes a verified click, lets the normal close happen, then asks the app to quit when it is safe to do so. The graceful quit corresponds to **⌘Q**; **⌘X** remains Cut.

## Everyday behavior

| Action | Result |
| --- | --- |
| Click the red button on the last window | Close normally, then request a graceful app quit once the window is confirmed gone. |
| Close one of several windows | Keep the app running by default. Minimized windows and windows on other Spaces still count. |
| Choose the optional any-window behavior | Request a graceful quit after the clicked window closes, even if other windows remain. The app can still show its own save prompts. |
| Hold Option, Command, or Control while clicking | Leave the app's native behavior alone for that click. |
| Press ⌘W, close from a menu, or close a window programmatically | Leave the app's native behavior alone. |
| Shift-click the red button | Force quit **only when explicitly enabled**. This can lose unsaved work. When disabled, Shift-click keeps native behavior. |
| Cancel a close, encounter a sheet, or open a replacement window | Keep the app running. A fresh click is needed for a later automatic quit. |
| Click an excluded app | Leave it alone, including Shift-click. |

Force quit is off by default. Enabling it requires acknowledging the unsaved-work warning. A normal quit is never silently escalated to force quit.

Finder, CallQuits, and protected system processes cannot be targeted. Music, Spotify, Mail, Messages, FaceTime, Terminal, and iTerm start in the editable exclusions list because closing their last window often should leave them running. Add your own apps or remove these optional defaults in settings.

## Download

[CallQuits 0.1.0](https://github.com/Mxlted/CallQuits/releases/tag/v0.1.0) is a private development release for **Apple silicon Macs running macOS 14 or newer**. Repository access is required to download it. The ZIP is **ad hoc signed and not notarized**; it does not carry a verified Developer ID, and Gatekeeper may block its first launch. Intel Macs require a local build.

Download the ZIP and `SHA256SUMS.txt` from the release, then verify them from the download directory:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Extract the ZIP, move `CallQuits.app` to `/Applications`, and follow the Accessibility setup below. See the [0.1.0 release notes](docs/releases/v0.1.0.md) for validation and limitations.

## Build and use

Install Xcode or the Command Line Tools with Swift 5.9 or newer, then run:

```sh
swift test
./scripts/build.sh
open build/CallQuits.app
```

The build script produces a locally signed app for your Mac's architecture. It does not install or launch the app. For a stable installation, move `build/CallQuits.app` to `/Applications` before enabling launch at login or granting permissions.

On first launch, use the menu bar controls to grant **Accessibility** access in System Settings → Privacy & Security → Accessibility. This is required to identify the actual close button and inspect an app's windows. Accessibility also covers listening to mouse events, so CallQuits does not request separate Input Monitoring access. It does not need Screen Recording or Full Disk Access. Reopen the app after granting access if the permission status has not updated. [Apple's permission guidance](https://developer.apple.com/forums/thread/828052).

Rebuilding an ad hoc-signed app can leave a stale Accessibility entry. If access still appears unavailable, quit CallQuits, remove its old entry from the Accessibility list, add the current app bundle again, enable it, and relaunch. Toggling the existing entry alone was insufficient during development.

Use the menu bar to pause CallQuits, open settings, or quit it. Settings include the quit behavior, Shift-click force quit, launch at login, and application exclusions. Launch at login may require approval in System Settings → General → Login Items.

### Xcode

Open `CallQuits.xcodeproj` and run the CallQuits scheme. `project.yml` is the source of truth for project structure; regenerate with [XcodeGen](https://github.com/yonaskolb/XcodeGen) after adding or removing source files:

```sh
xcodegen generate
```

The Xcode app target compiles the UI and policy in one module. SwiftPM keeps the policy in a separate `CallQuitsCore` module for fast, independent tests. No developer team is required for the default local build.

## How it decides

CallQuits uses a public Core Graphics event tap in listen-only mode and Accessibility hit testing to verify the red button. The tap observes only left-button presses, releases, and drags, using the original annotated event metadata. It does not swallow or rewrite mouse events, send keyboard shortcuts, guess button positions, or run a continuous scan of every app's windows.

The mouse-down and mouse-up must identify the same original recipient with matching modifiers. Identity comes from the event's target process or its exact stamped window ID and verified owner; the app under the pointer later is never used as a guess. After a verified normal click, a short, bounded sequence of Accessibility snapshots checks that the clicked window disappeared, looks for sheets and replacement windows, and evaluates the selected quit rule. A temporary Accessibility observer also watches for newly created windows between snapshots. Apps that do not support that notification are skipped for automatic graceful quit. Unknown or incomplete state prevents termination. Synchronous Accessibility calls and observer registration run away from the UI thread with time limits; a newer interaction or settings change invalidates stale work.

If a save sheet interrupts the close, CallQuits steps aside even if you later choose Save or Don't Save. It does not schedule a surprise quit when that sheet finishes.

Some apps expose incomplete or unusual Accessibility trees. A very fast click can close the window before the asynchronous mouse-down hit test identifies its close button. These cases intentionally do nothing. An unresponsive app may not expose enough information even for Shift-click force quit; use the macOS Force Quit window in that case. The Activity pane reports permission changes, quit requests, and some reasons for keeping an app open; unrecognized clicks may not produce an entry.

Permissions and real applications affect behavior. User-operated close-button checks produced successful quit requests and confirmed process exits for two Chrome launches and one Safari launch. The wider fixture and multiple-window matrix remains unverified. Unit tests validate the policy, but do not establish compatibility with every macOS app or measure visible Dock-indicator latency. See the [manual test matrix and observed results](docs/TESTING.md) and [implementation notes](docs/ARCHITECTURE.md).

## Privacy and distribution

All settings and decisions stay on your Mac. There is no telemetry, network client, private API, injected code, or auto-updater. Accessibility is used to read window/control metadata; CallQuits does not record keystrokes or document content.

Local and CI builds use ad hoc signing. They are **not notarized releases** and are not ready for frictionless distribution to other Macs. To use your Developer ID certificate:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build.sh
```

Notarization, stapling, universal binaries, and release publishing are separate steps described in [release notes for maintainers](docs/RELEASING.md). No signing credentials are included.

## Development

```sh
swift test
./scripts/build.sh
./scripts/build-fixture.sh
git diff --check
```

The fixture is a separate disposable app for testing termination, multiple windows, save cancellation, sheets, and replacement windows without risking personal applications. Building it does not launch it. See [CONTRIBUTING.md](CONTRIBUTING.md).

The icon pairs a coral red close button with a power mark on a dark window and a soft porcelain tile. It is original vector artwork generated by `scripts/generate-icon.swift`. Regenerate its checked-in `.icns` and PNG preview with `./scripts/generate-icon.sh`.
