# Release preparation

Public releases use a signed, notarized DMG containing `CallQuits.app` and an Applications shortcut, plus `SHA256SUMS.txt`. Keep previous releases and their ZIP assets unchanged. A ZIP is still used privately to submit the app for notarization before placing it in the DMG.

The default build is a development artifact. Ad hoc signing lets it run locally, but does not establish a trusted publisher identity and does not satisfy notarization for public distribution. The GitHub Actions workflow offers development ZIPs only on manual dispatch and never publishes a release.

## Prepare and validate the final signed bundle

Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, the version authority for both build routes. Update published download details and release notes when applicable. Regenerate the Xcode project only for relevant configuration or source/resource structure changes, and regenerate fixtures or icons only when needed.

Use an existing Developer ID Application identity and an existing local notarytool Keychain profile. No certificate, team, or credentials are configured in this repository. The commands below are for an authorized release operator; do not obtain credentials, submit to Apple, or publish as part of routine development validation.

From the repository root, set the identity in your shell:

```sh
export CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
```

Now run [routine validation](TESTING.md#routine-validation) once. Its `./scripts/build.sh` command uses this identity to build and sign the final release app with the hardened runtime and a secure timestamp, then verifies its signature. There is no prerequisite ad hoc app build. Inspect the resulting signature:

```sh
codesign --verify --deep --strict --verbose=2 build/CallQuits.app
codesign --display --verbose=4 build/CallQuits.app
```

Confirm the expected Developer ID authority, TeamIdentifier, runtime flag, and timestamp. Exercise [release validation and the full manual matrix](TESTING.md#release-validation) with this exact bundle in a permission-enabled desktop session. Do not rebuild or change its contents between these checks and packaging.

## Notarize and staple the app

Run these commands in the same repository-root shell after the signed bundle passes validation. Replace the Keychain profile name with one already configured locally. Submission and waiting are separate so the submission ID is saved before waiting. Apple's `Accepted` result is required before stapling:

```sh
set -euo pipefail
NOTARY_PROFILE='your-existing-notarytool-profile'
APP='build/CallQuits.app'
RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
RELEASE_ARCHS="$(lipo -archs "$APP/Contents/MacOS/CallQuits" | tr ' ' '-')"
SUBMISSION_ZIP='build/CallQuits-notary-submission.zip'
DELIVERY_DMG="build/CallQuits-${RELEASE_VERSION}-macos-${RELEASE_ARCHS}.dmg"

# This ZIP is a private notarization input, never a release asset.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION_ZIP"
xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" --output-format plist \
  > build/app-notary-submission.plist
APP_SUBMISSION_ID="$(plutil -extract id raw -o - build/app-notary-submission.plist)"
xcrun notarytool wait "$APP_SUBMISSION_ID" \
  --keychain-profile "$NOTARY_PROFILE" --output-format plist \
  > build/app-notary-result.plist
test "$(plutil -extract status raw -o - build/app-notary-result.plist)" = 'Accepted'
xcrun notarytool log "$APP_SUBMISSION_ID" \
  --keychain-profile "$NOTARY_PROFILE" build/app-notary-log.json

# The app must retain its ticket when copied out of the disk image.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=4 "$APP"
```

Inspect `build/app-notary-log.json`, including any warnings. If a submission is rejected or interrupted, stop and inspect that submission with `xcrun notarytool info` or `log` and the same Keychain profile. After a timeout, resume `notarytool wait` using the saved ID; do not upload a duplicate or treat upload success as acceptance. Never store credentials in repository files or CI logs.

## Create, notarize, and staple the DMG

The packaging script copies the already signed and stapled app, adds an Applications shortcut, creates a compressed read-only HFS+ disk image, and signs the DMG with `CODE_SIGN_IDENTITY`. It never rebuilds or modifies the source app and refuses to replace an existing output. An `APP_BUNDLE_PATH` override can select a bundle outside `build/`. The `DMG_OUTPUT_PATH` parent directory must already exist and must be outside the source app, including after resolving symlinks.

```sh
APP_BUNDLE_PATH="$APP" DMG_OUTPUT_PATH="$DELIVERY_DMG" ./scripts/package-dmg.sh
xcrun notarytool submit "$DELIVERY_DMG" \
  --keychain-profile "$NOTARY_PROFILE" --output-format plist \
  > build/dmg-notary-submission.plist
DMG_SUBMISSION_ID="$(plutil -extract id raw -o - build/dmg-notary-submission.plist)"
xcrun notarytool wait "$DMG_SUBMISSION_ID" \
  --keychain-profile "$NOTARY_PROFILE" --output-format plist \
  > build/dmg-notary-result.plist
test "$(plutil -extract status raw -o - build/dmg-notary-result.plist)" = 'Accepted'
xcrun notarytool log "$DMG_SUBMISSION_ID" \
  --keychain-profile "$NOTARY_PROFILE" build/dmg-notary-log.json

xcrun stapler staple "$DELIVERY_DMG"
xcrun stapler validate "$DELIVERY_DMG"
codesign --verify --strict "$DELIVERY_DMG"
hdiutil verify "$DELIVERY_DMG"

# Checksum only the final, stapled DMG.
(cd build && shasum -a 256 "$(basename "$DELIVERY_DMG")" > SHA256SUMS.txt)
(cd build && shasum -a 256 -c SHA256SUMS.txt)
```

Inspect `build/dmg-notary-log.json` as well. Preserve the final app and DMG after these steps. Rebuilding or changing either artifact requires repeating the affected signature, notarization, stapling, and checksum checks. In particular, do not rerun `scripts/build.sh` over the final bundle during documentation or publication work.

## Verify the delivered disk image

Mount the exact delivered DMG read-only and copy the app into a fresh verification directory. Check the Applications shortcut and verify the copied app without launching or replacing an installed copy:

```sh
(
  set -euo pipefail
  IMAGE_CHECK="$(mktemp -d "$PWD/build/dmg-check.XXXXXX")"
  MOUNT_POINT="$IMAGE_CHECK/mounted"
  mkdir "$MOUNT_POINT" "$IMAGE_CHECK/copied"
  trap 'hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true' EXIT
  hdiutil attach "$DELIVERY_DMG" -readonly -noautoopen -mountpoint "$MOUNT_POINT"
  test "$(readlink "$MOUNT_POINT/Applications")" = /Applications
  ditto "$MOUNT_POINT/CallQuits.app" "$IMAGE_CHECK/copied/CallQuits.app"
  hdiutil detach "$MOUNT_POINT"
  trap - EXIT
  test -x "$IMAGE_CHECK/copied/CallQuits.app/Contents/MacOS/CallQuits"
  codesign --verify --deep --strict "$IMAGE_CHECK/copied/CallQuits.app"
  xcrun stapler validate "$IMAGE_CHECK/copied/CallQuits.app"
  spctl --assess --type execute --verbose=4 "$IMAGE_CHECK/copied/CallQuits.app"
  if command -v syspolicy_check >/dev/null 2>&1; then
    syspolicy_check distribution "$IMAGE_CHECK/copied/CallQuits.app"
  fi
)
```

If `spctl` reports a security-disabled override, record it and do not claim that default Gatekeeper enforcement was tested. Do not change the Mac's security settings to make a check pass.

Test the exact final DMG and checksum on a separate Mac/account, including first launch with normal download quarantine, Accessibility permission, login-item approval, and upgrading an existing copy. Follow the [fresh-install and upgrade recovery instructions](HELP.md). Test with the final app in `/Applications`; permission grants may depend on application location and signing identity. Replacing an ad hoc app can require removing its stale Accessibility entry and adding the current bundle again. Do not promise that a development permission grant carries over to a signed release.

The build script emits a binary for the host architecture. A universal release needs both Apple silicon and Intel slices, or separate clearly labeled artifacts, with validation on each claimed architecture. Intel and macOS 14 runtime support must remain explicitly unverified until tested; a deployment target or cross-compilation alone is not runtime evidence.

## Publish an authorized release

Commit the version and release documentation, push the authorized changes, and confirm the required `macos` CI job passes for that exact commit. Tag that commit. Upload only the final stapled DMG and `SHA256SUMS.txt`; a draft release can hold the assets while CI completes. Verify the uploaded asset digests against the local files, then publish and check the public release URL and latest-release status. Do not replace previous published tags or assets. Release authorization applies to the requested release, not future releases.

Apple documents [Developer ID distribution](https://developer.apple.com/developer-id/), [notarization and stapling](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), and [disk image packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution). `xcrun notarytool submit --help` and `xcrun stapler` describe the installed tools' supported flags.
