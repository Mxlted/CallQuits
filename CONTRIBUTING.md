# Contributing

CallQuits should make the red close button predictable without risking a user's work. Changes to quit behavior need a concrete scenario, an explanation of the expected outcome, and tests around the relevant state transition.

Use macOS 14 or newer and Swift 5.9 or newer. Keep third-party runtime dependencies out of the app unless there is a compelling, reviewed reason to add one. Prefer public AppKit, Accessibility, SwiftUI, and ServiceManagement APIs.

## Working locally

```sh
swift test
./scripts/build.sh
git diff --check
```

Run policy tests before and after changes. Use the [disposable fixture and manual matrix](docs/TESTING.md) for integration checks; never automate termination of a contributor's real apps. State which live checks were actually performed and which still require Accessibility permission or a particular application.

Regenerate `CallQuits.xcodeproj` with `xcodegen generate` when the file structure changes. Keep `project.yml` and the generated project in sync. SwiftPM is the canonical route for policy tests.

## Safety constraints

- Only a verified red close-button gesture supplies quit intent. A window disappearing by itself does not.
- Graceful quit must preserve the app's opportunity to cancel or save. Never upgrade it automatically to force quit.
- A failed Accessibility read is unknown, never proof that there are zero windows.
- Account for minimized windows, other Spaces, sheets, replacement windows, process reuse, and stale callbacks.
- Keep Accessibility IPC off the UI thread and bound both individual calls and the overall work.
- Apply protected-app and user exclusions to every termination path.
- Keep Shift-click force quit opt-in and clearly describe possible loss of unsaved work.

Keep changes focused and describe user-visible results in commit messages. Reports and screenshots should avoid document names or other personal content. A local `AGENTS.md` may carry contributor-specific guidance; this repository intentionally keeps that file out of tracking through `.git/info/exclude`.
