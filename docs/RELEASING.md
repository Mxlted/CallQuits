# Release preparation

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

## Submit, staple, and package

Run these commands in the same repository-root shell after the signed bundle passes validation. Replace the Keychain profile name with one already configured locally. This sequence makes Apple's `Accepted` result a prerequisite for stapling and recreates the delivered ZIP after stapling:

```sh
set -euo pipefail
NOTARY_PROFILE='your-existing-notarytool-profile'
APP='build/CallQuits.app'
RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
RELEASE_ARCHS="$(lipo -archs "$APP/Contents/MacOS/CallQuits" | tr ' ' '-')"
SUBMISSION_ZIP='build/CallQuits-notary-submission.zip'
DELIVERY_ZIP="build/CallQuits-${RELEASE_VERSION}-macos-${RELEASE_ARCHS}.zip"

# Submit a ZIP of the already signed app.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION_ZIP"
xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist \
  > build/notary-result.plist
test "$(plutil -extract status raw -o - build/notary-result.plist)" = 'Accepted'

# Staple the app itself; ZIP files cannot carry a stapled ticket.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=4 "$APP"

# Recreate the ZIP from the stapled app, then checksum that final ZIP.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DELIVERY_ZIP"
(cd build && shasum -a 256 "$(basename "$DELIVERY_ZIP")" > SHA256SUMS.txt)

# Validate the delivered bytes after extraction into a fresh directory.
ARCHIVE_CHECK="$(mktemp -d "$PWD/build/archive-check.XXXXXX")"
ditto -x -k "$DELIVERY_ZIP" "$ARCHIVE_CHECK"
(cd build && shasum -a 256 -c SHA256SUMS.txt)
test -x "$ARCHIVE_CHECK/CallQuits.app/Contents/MacOS/CallQuits"
codesign --verify --deep --strict "$ARCHIVE_CHECK/CallQuits.app"
xcrun stapler validate "$ARCHIVE_CHECK/CallQuits.app"
spctl --assess --type execute --verbose=4 "$ARCHIVE_CHECK/CallQuits.app"
```

If submission is rejected or interrupted, stop. Use the submission ID in `build/notary-result.plist` with `xcrun notarytool info` or `log` and the same Keychain profile to inspect it; do not treat a successful upload as acceptance. Never store credentials in repository files or CI logs. Keep the submission ZIP separate from the final deliverable.

## Delivered-archive checks

Test the exact final ZIP and checksum on a separate Mac/account, including first launch with normal download quarantine, Accessibility permission, login-item approval, and upgrading an existing copy. Follow the [fresh-install and upgrade recovery instructions](HELP.md). Test with the final app in `/Applications`; permission grants may depend on application location and signing identity. Replacing an ad hoc app can require removing its stale Accessibility entry and adding the current bundle again. Do not promise that a development permission grant carries over to a signed release.

The build script emits a binary for the host architecture. A universal release needs both Apple silicon and Intel slices, or separate clearly labeled artifacts, with validation on each claimed architecture. Intel and macOS 14 runtime support must remain explicitly unverified until tested; a deployment target or cross-compilation alone is not runtime evidence. Publish only the final stapled-app ZIP and its checksum after separately authorizing publication.

Apple documents [Developer ID distribution](https://developer.apple.com/developer-id/), [notarization and stapling](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), and [ZIP packaging with ditto](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution). `xcrun notarytool submit --help` and `xcrun stapler` describe the installed tools' supported flags.
