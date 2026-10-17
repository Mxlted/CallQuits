import XCTest
@testable import CallQuitsCore

final class CloseSessionTests: XCTestCase {
    private func snapshot(
        _ count: Int = 0,
        target: Bool = false,
        blocking: Bool = false,
        reliable: Bool = true,
        replacement: Bool = false
    ) -> CloseSnapshot {
        CloseSnapshot(
            windowCount: count,
            targetWindowPresent: target,
            hasBlockingUI: blocking,
            isReliable: reliable,
            hasReplacementWindow: replacement
        )
    }

    func testFinalWindowRequiresDisappearanceAndStableConfirmation() {
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(1, target: true), now: 0.05), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.1), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.2), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.26), .quit)
    }

    func testImmediateCloseStillNeedsMinimumElapsedTime() {
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.16), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.2), .quit)
    }

    func testOneLateSnapshotNeverQuitsByItself() {
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 2.8), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 2.96), .quit)
    }

    func testRepeatedSnapshotAtSameTimeDoesNotConfirm() {
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.5), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.5), .wait)
    }

    func testUnclosedOrCanceledWindowExpiresWithoutQuit() {
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        for time in [0.1, 0.5, 1, 2.99] {
            XCTAssertEqual(session.evaluate(snapshot: snapshot(1, target: true), now: time), .wait)
        }
        XCTAssertEqual(session.evaluate(snapshot: snapshot(1, target: true), now: 3), .cancel)
    }

    func testExpirationWinsEvenWhenConfirmationWouldOtherwiseSucceed() {
        var session = CloseSession(behavior: .lastWindow, startedAt: 10)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 12.8), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 13), .cancel)
    }

    func testOtherWindowsPreventLastWindowQuitRegardlessOfVisibility() {
        // The AX adapter supplies all windows, including minimized windows and other Spaces.
        for remainingCount in [1, 2, 10] {
            var session = CloseSession(behavior: .lastWindow, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount + 1, target: true), now: 0.1), .wait)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount), now: 0.2), .cancel)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.5), .cancel)
        }
    }

    func testEveryWindowAllowsStableExistingWindowsAfterTheTargetCloses() {
        for remainingCount in [0, 1, 5] {
            var session = CloseSession(behavior: .everyWindow, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount + 1, target: true), now: 0.1), .wait)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount), now: 0.2), .wait)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount), now: 0.36), .quit)
        }
    }

    func testEveryWindowStillRequiresTargetToClose() {
        var session = CloseSession(behavior: .everyWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(3, target: true), now: 0.5), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(3, target: true), now: 2), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(3, target: true), now: 3), .cancel)
    }

    func testUnreadableBlockingAndInconsistentSnapshotsFailClosed() {
        let invalidSnapshots = [
            snapshot(reliable: false),
            snapshot(blocking: true),
            snapshot(-1),
            snapshot(0, target: true),
            snapshot(replacement: true)
        ]
        for behavior in CloseBehavior.allCases {
            for invalid in invalidSnapshots {
                for afterDisappearance in [false, true] {
                    var session = CloseSession(behavior: behavior, startedAt: 0)
                    if afterDisappearance {
                        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.1), .wait)
                    }
                    XCTAssertEqual(session.evaluate(snapshot: invalid, now: 0.3), .cancel)
                    XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.5), .cancel)
                }
            }
        }
    }

    func testSaveSheetCancelsWhileTargetStillExists() {
        for behavior in CloseBehavior.allCases {
            var session = CloseSession(behavior: behavior, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(1, target: true, blocking: true), now: 0.1), .cancel)
            // Dismissing a sheet later must not revive a pending quit.
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 1), .cancel)
        }
    }

    func testReplacementWindowAndReappearingTargetCancel() {
        for behavior in CloseBehavior.allCases {
            for changed in [snapshot(1), snapshot(1, target: true), snapshot(replacement: true)] {
                var session = CloseSession(behavior: behavior, startedAt: 0)
                XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.1), .wait)
                XCTAssertEqual(session.evaluate(snapshot: changed, now: 0.3), .cancel)
            }
        }
    }

    func testEveryWindowDetectsIdentityReplacementEvenWithUnchangedCount() {
        var session = CloseSession(behavior: .everyWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(2), now: 0.1), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(2, replacement: true), now: 0.3), .cancel)
    }

    func testEveryWindowCancelsWhenRemainingWindowCountChanges() {
        for changedCount in [1, 3] {
            var session = CloseSession(behavior: .everyWindow, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(2), now: 0.1), .wait)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(changedCount), now: 0.3), .cancel)
        }
    }

    func testQuitIsEmittedAtMostOnce() {
        for behavior in CloseBehavior.allCases {
            var session = CloseSession(behavior: behavior, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.1), .wait)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.3), .quit)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.5), .cancel)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.7), .cancel)
        }
    }

    func testInvalidAndReversedClockValuesCancel() {
        for invalidStart in [Double.nan, Double.infinity, -Double.infinity] {
            var session = CloseSession(behavior: .lastWindow, startedAt: invalidStart)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 1), .cancel)
        }
        for invalidNow in [Double.nan, Double.infinity, -Double.infinity, -1] {
            var session = CloseSession(behavior: .lastWindow, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: invalidNow), .cancel)
        }
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.4), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.3), .cancel)
    }
}
