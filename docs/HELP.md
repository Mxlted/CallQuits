# CallQuits help

[← Back to CallQuits](../README.md)

## macOS blocks the app

The current release is ad hoc signed and not notarized. That means it does not have a verified Developer ID, and Apple has not checked it through the notarization service.

If macOS blocks it because the developer cannot be verified, first check that you downloaded it from [Mxlted/CallQuits Releases](https://github.com/Mxlted/CallQuits/releases). You can also [verify the archive](#verify-your-download).

If you trust the download and choose to open it, try launching CallQuits once, then open **System Settings → Privacy & Security**. Look for the message about CallQuits and choose **Open Anyway**, if available. Confirm the macOS prompt. See [Apple's first-launch guidance](https://support.apple.com/en-us/102445) for the current steps and explanation of the different warnings.

This approval is separate from Accessibility permission. A managed Mac may prevent it. If macOS reports malware or that the app will damage your computer, do not treat that as the ordinary unidentified-developer warning.

## Enable Accessibility

1. Move `CallQuits.app` to **Applications** before granting access.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Enable CallQuits. If it is missing, use **+** to select it from Applications.
4. Reopen CallQuits if its status has not updated.

CallQuits uses Accessibility to identify the actual red close button and read window/control metadata. It does not record keystrokes or document content. Its event-listening design does not request a separate Input Monitoring grant, Screen Recording, or Full Disk Access. See [Apple's Accessibility and event-listening explanation](https://developer.apple.com/forums/thread/828052).

### Permission is enabled, but CallQuits still reports no access

Replacing or rebuilding an ad hoc-signed app can leave a stale Accessibility entry. Quit CallQuits, remove its old entry from the Accessibility list, add the current copy from Applications, enable it, and relaunch. During development, toggling the existing entry alone did not always restore access.

## An app stays open

Check these in order:

1. **CallQuits is enabled.** Open its menu bar menu and check the status.
2. **The app is not excluded.** Open **Settings → Exceptions**. Music, Spotify, Mail, Messages, FaceTime, Terminal, and iTerm are excluded by default. These optional defaults can be removed; Finder, system processes, and CallQuits stay protected.
3. **No other windows remain.** In the default last-window mode, minimized windows and windows on other Spaces still count.
4. **You clicked the red close button.** ⌘W, menu commands, programmatic closes, and Option/Command/Control-clicks do not trigger automatic quit. Shift-click also leaves native behavior alone unless force quit is enabled.
5. **No save dialog or replacement window interrupted the close.** Either cancels the attempt, even if you later resolve the dialog.

Some apps expose incomplete Accessibility information or do not support the window notifications CallQuits needs. A very fast click can close the window before its button can be identified. These cases are skipped rather than guessed. Check **Settings → Activity** for permission changes and quit decisions; unrecognized clicks may not produce an entry.

An unresponsive app may be impossible to identify even for opt-in Shift-click force quit. Use macOS's own Force Quit window when necessary; force quitting can lose unsaved work.

If the problem persists, [report it](https://github.com/Mxlted/CallQuits/issues/new/choose) with your macOS version, app name/version, window arrangement, and the observed result. Avoid sharing document contents or personal information. The [testing record](TESTING.md) lists confirmed behavior and remaining live checks; the automated policy suite does not establish compatibility with every app.

## Launch at login

Enable launch at login in CallQuits settings after moving it to Applications. macOS may require approval under **System Settings → General → Login Items**. Keep the app in that location so the login item and permissions refer to the same copy.

## Update CallQuits

CallQuits has no automatic updater.

1. Download the new ZIP from [Releases](https://github.com/Mxlted/CallQuits/releases).
2. Quit CallQuits from its menu bar menu.
3. Extract the ZIP and replace the old app in Applications.
4. Open it and check its permission status. If needed, [refresh the Accessibility entry](#permission-is-enabled-but-callquits-still-reports-no-access).

## Verify your download

Download the release ZIP and its `SHA256SUMS.txt` from the **same release** into one folder. In Terminal, switch to that folder and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

The ZIP should be reported as `OK`. A matching checksum confirms that its contents match the published archive; it does not provide Developer ID signing or Apple notarization.

## Remove CallQuits

Disable launch at login in settings, quit CallQuits from the menu bar, and move it from Applications to the Trash. You can also remove its entry from **System Settings → Privacy & Security → Accessibility**.
