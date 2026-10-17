# Developing CallQuits

Use macOS 14 or newer with Xcode or the Command Line Tools and Swift 5.9 or newer. The app has no third-party runtime dependencies. A developer team or signing certificate is not required for local builds.

## Build and run

Download the source with Git:

```sh
git clone https://github.com/Mxlted/CallQuits.git
cd CallQuits
```

Then, from that repository folder:

```sh
swift test
./scripts/build.sh
git diff --check
open build/CallQuits.app
```

The build script creates `build/CallQuits.app` for the host Mac's architecture, enables the hardened runtime, and verifies its signature. It defaults to a release configuration and ad hoc signing. Intel builds have not yet been validated. Building does not install or launch the app; the final command above launches it explicitly. Build output and caches stay in `build/` and `.build/`.

For a debug build:

```sh
CONFIGURATION=debug ./scripts/build.sh
```

For a stable local installation, quit the running copy and move the built app to `/Applications` before granting permissions or enabling launch at login. Launch it from that location, then grant access in **System Settings → Privacy & Security → Accessibility**. Launch at login may also need approval under **General → Login Items**.

Rebuilding or replacing an ad hoc-signed app can leave a stale Accessibility entry. If permission remains unavailable, quit CallQuits, remove the old entry, add the current app bundle, enable it, and relaunch. Toggling the existing entry alone was insufficient during development.

## Xcode and project structure

Open `CallQuits.xcodeproj` and run the **CallQuits** scheme. `project.yml` is the source of truth for the Xcode project. After adding or removing source files, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.38.0 or newer:

```sh
xcodegen generate
```

Keep the generated project and `project.yml` in sync.

| Location | Purpose |
| --- | --- |
| `Sources/CallQuitsCore/` | Deterministic gesture, event identity, protection, and close-decision policy. |
| `Sources/CallQuits/` | Menu bar UI, settings, Accessibility integration, and event monitoring. |
| `Tests/CallQuitsCoreTests/` | Policy tests using simulated inputs and window states. |
| `scripts/fixtures/` | Disposable app for live integration checks. |
| `Resources/` | App metadata and checked-in icon assets. |

SwiftPM builds the policy as a separate `CallQuitsCore` module for independent tests. The Xcode app target compiles the UI and policy together in one module. Read the [architecture notes](ARCHITECTURE.md) before changing event capture or termination behavior.

## Test safely

`swift test` checks the policy without Accessibility permission or process termination. A successful build confirms compilation and signing; it does not establish that real mouse events, Accessibility notifications, or a particular app behave as expected.

Use the disposable fixture for integration checks:

```sh
./scripts/build-fixture.sh
open "build/CallQuits Fixture.app"
```

Building the fixture does not launch it. It keeps documents in memory and supports multiple windows, unsaved changes, save cancellation, sheets, and replacement windows. Never use personal applications as automated termination targets.

Follow the [manual test matrix](TESTING.md) and record what was actually observed. Physical pointer input and computer-use automation can take different delivery paths; an automated click does not prove the global event tap captured a real close-button gesture. Keep simulated results separate from permission-dependent live checks and measured app-exit timing.

## Regenerate the icon

The icon is original vector artwork drawn by `scripts/generate-icon.swift`: a coral close button and power mark on a dark window, set inside a porcelain tile. To regenerate it:

```sh
./scripts/generate-icon.sh
```

This writes the checked-in `Resources/AppIcon.icns` and `Resources/AppIcon.png`, with intermediate sizes in `build/AppIcon.iconset/`. Review the small and large sizes before committing the source and generated assets together.

## Prepare a release

Local builds are ad hoc signed and are not notarized. To select an existing Developer ID certificate:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build.sh
```

Signing alone does not perform notarization or produce a universal binary. Follow [release preparation](RELEASING.md) for packaging, architecture coverage, notarization, and validation of the delivered app. See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution and safety requirements.
