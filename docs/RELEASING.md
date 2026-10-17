# Release preparation

The default build is a development artifact. Ad hoc signing lets it run locally, but does not establish a trusted publisher identity and does not satisfy notarization for public distribution.

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` and matching values in `project.yml`.
2. Regenerate the Xcode project with `xcodegen generate`.
3. Run `swift test`, `./scripts/build.sh`, and `git diff --check`.
4. Exercise the [manual test matrix](TESTING.md) in a permission-enabled desktop session, including macOS 14 and the current supported macOS version. Record limitations.
5. Build with your Developer ID Application identity through `CODE_SIGN_IDENTITY`. No certificate or team is configured in this repository.
6. Use Apple's notarization workflow for the final archive, validate the result, and staple the ticket before sharing it. Do not store Apple credentials in the repository or CI logs.
7. Test the exact delivered archive on a separate Mac/account, including first launch, Accessibility permission, login-item approval, and upgrading an existing copy.

The build script emits a binary for the host architecture. A public universal release needs both Apple silicon and Intel slices, or separate clearly labeled artifacts, and validation on each supported architecture. The checked-in workflow currently produces an ad hoc development build, not an automatically published release.

Accessibility permissions can depend on application location and signing identity. Test with the final app in `/Applications`; rebuilding or replacing an ad hoc-signed binary may require removing its stale Accessibility entry and adding the current bundle again. Toggling the existing entry alone was insufficient during development. Do not promise that a local development permission grant will carry over to a signed release.

Apple's documentation covers [Developer ID distribution](https://developer.apple.com/developer-id/) and [notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
