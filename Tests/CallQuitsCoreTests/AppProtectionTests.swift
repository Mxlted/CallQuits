import XCTest
@testable import CallQuitsCore

final class AppProtectionTests: XCTestCase {
    func testProtectsFinderAndSystemInterfacesCaseInsensitively() {
        let identifiers = [
            "com.apple.finder", "com.apple.dock", "com.apple.SystemUIServer",
            "com.apple.loginwindow", "com.apple.WindowManager", "com.apple.WindowServer",
            "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight",
            "com.apple.SecurityAgent", "com.apple.authorizationhost", "com.apple.coreservices.uiagent",
            "com.apple.universalaccesscontrol", "com.apple.VoiceOver", "com.apple.TextInputMenuAgent",
            "com.apple.screencaptureui"
        ]
        for identifier in identifiers {
            XCTAssertTrue(AppProtection.isProtected(bundleIdentifier: identifier, processID: 42, ownProcessID: 99), identifier)
            XCTAssertTrue(AppProtection.isProtected(bundleIdentifier: identifier.uppercased(), processID: 42, ownProcessID: 99), identifier)
        }
    }

    func testProtectsSelfAndReservedProcessIDs() {
        for processID: Int32 in [-1, 0, 1, 99] {
            XCTAssertTrue(AppProtection.isProtected(bundleIdentifier: "example.app", processID: processID, ownProcessID: 99))
        }
    }

    func testUnknownOrMalformedIdentityFailsClosed() {
        for identifier: String? in [nil, "", " ", "\n", " com.apple.finder", "com.apple.finder ", "example. app"] {
            XCTAssertTrue(AppProtection.isProtected(bundleIdentifier: identifier, processID: 42, ownProcessID: 99))
        }
    }

    func testAllowsRegularUserAppIdentitiesWithoutExcludingAllAppleApps() {
        for identifier in ["com.apple.TextEdit", "com.apple.Safari", "com.example.fixture", "org.mozilla.firefox"] {
            XCTAssertFalse(AppProtection.isProtected(bundleIdentifier: identifier, processID: 42, ownProcessID: 99), identifier)
        }
    }
}
