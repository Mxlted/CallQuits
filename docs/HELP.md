# CallQuits help

[← Back to CallQuits](../README.md)

## macOS blocks the app

The current release is Developer ID signed and notarized by Apple, with notarization tickets attached to the app and disk image. Open the DMG, drag CallQuits into its Applications shortcut, eject the disk image, and open CallQuits from Applications. macOS may ask you to confirm that you want to open an app downloaded from the internet.

If macOS instead reports an unverified developer, a damaged app, or another security problem, check that you downloaded the current DMG from [Mxlted/CallQuits Releases](https://github.com/Mxlted/CallQuits/releases) and [verify the download](#verify-your-download). Download a fresh copy if needed. If the warning persists, report the exact message rather than bypassing it.

Older v0.1.0 downloads and default local development builds are ad hoc signed and not notarized. Use the current public release for normal installation. See [Apple's first-launch guidance](https://support.apple.com/en-us/102445) for an explanation of macOS security prompts.

First-launch approval is separate from Accessibility permission. A managed Mac may have additional installation restrictions.

## Enable Accessibility

1. Move `CallQuits.app` to **Applications** before granting access.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Enable CallQuits. If it is missing, use **+** to select it from Applications.
4. Reopen CallQuits if its status has not updated.

CallQuits uses Accessibility to identify the actual red close button and read window/control metadata. Pressing a key cancels a pending close attempt; the key itself is never read or recorded. It does not record document content. Its event-listening design does not request a separate Input Monitoring grant, Screen Recording, or Full Disk Access. See [Apple's Accessibility and event-listening explanation](https://developer.apple.com/forums/thread/828052).

### Permission is enabled, but CallQuits still reports no access

Replacing or rebuilding an ad hoc-signed app can leave a stale Accessibility entry. This can also affect an upgrade from v0.1.0 to the Developer ID-signed release. Quit CallQuits, remove its old entry from the Accessibility list, add the current copy from Applications, enable it, and relaunch. During development, toggling the existing entry alone did not always restore access.

### Monitoring is unavailable

When CallQuits is enabled and Accessibility access is granted but monitoring is unavailable, choose **Retry monitoring** from the menu bar menu or Settings. If it still fails, use the permission-recovery help shown in Settings to refresh the Accessibility entry using the steps above. An intentionally paused or disabled app stays paused or disabled; resume or enable it when you are ready.

## An app stays open

Check these in order:

1. **CallQuits is enabled.** Open its menu bar menu and check the status.
2. **The app is not excluded.** Open **Settings → Exceptions**. Music, Spotify, Mail, Messages, FaceTime, Terminal, and iTerm are excluded by default. These optional defaults can be removed; Finder, system processes, and CallQuits stay protected.
3. **No other windows remain.** In the default last-window mode, minimized windows and windows on other Spaces still count.
4. **You clicked the red close button.** ⌘W, menu commands, programmatic closes, and Option/Command/Control-clicks do not trigger automatic quit. Shift-click also leaves native behavior alone unless force quit is enabled.
5. **No save dialog or replacement window interrupted the close.** Either cancels the attempt, even if you later resolve the dialog.
6. **No further interaction interrupted confirmation.** A new click or key press cancels the pending attempt.

Version 0.1.2 includes normal-close handling for Discord hiding its main window. This requires exactly one Discord window, which must not be minimized, and reliable Accessibility confirmation; extra windows, sheets, replacements, or uncertain state still prevent quitting. It sends a normal quit request and does not require enabling Shift-click force quit. This support is scoped to the standard Discord app; other release channels have not been validated. See the [validation record](TESTING.md#discord-hide-on-close-development-checks--october-17-2026) for tested behavior and remaining checks.

Some apps expose incomplete Accessibility information or do not support the window notifications CallQuits needs. A very fast click can close the window before its button can be identified. These cases are skipped rather than guessed. Check **Settings → Activity** for permission changes and quit decisions; unrecognized clicks may not produce an entry.

An unresponsive app may be impossible to identify even for opt-in Shift-click force quit. Use macOS's own Force Quit window when necessary; force quitting can lose unsaved work.

If the problem persists, [report it](https://github.com/Mxlted/CallQuits/issues/new/choose) with your macOS version, app name/version, window arrangement, and the observed result. Avoid sharing document contents or personal information. The [testing record](TESTING.md) lists confirmed behavior and remaining live checks; the automated policy suite does not establish compatibility with every app.

## Launch at login

Enable launch at login in CallQuits settings after moving it to Applications. macOS may require approval under **System Settings → General → Login Items**. Keep the app in that location so the login item and permissions refer to the same copy.

## Update CallQuits

CallQuits has no automatic updater.

1. Download the new DMG from [Releases](https://github.com/Mxlted/CallQuits/releases).
2. Quit CallQuits from its menu bar menu.
3. Open the DMG and drag CallQuits into its Applications shortcut, replacing the old app when Finder asks.
4. Eject the disk image, open CallQuits from Applications, and check its permission status. If needed, [refresh the Accessibility entry](#permission-is-enabled-but-callquits-still-reports-no-access).

When upgrading from v0.1.0, the signing identity changes. Do not assume its old Accessibility grant will carry over; check that CallQuits reports monitoring is active before using it.

## Verify your download

Download the release DMG and its `SHA256SUMS.txt` from the **same release** into one folder. In Terminal, switch to that folder and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

The DMG should be reported as `OK`. A matching checksum confirms that its contents match the published disk image. The app and disk image also carry Developer ID signatures and stapled Apple notarization tickets; the checksum is a separate integrity check. Earlier releases distributed as ZIPs keep their original assets and checksums.

## Remove CallQuits

Disable launch at login in settings, quit CallQuits from the menu bar, and move it from Applications to the Trash. You can also remove its entry from **System Settings → Privacy & Security → Accessibility**.
