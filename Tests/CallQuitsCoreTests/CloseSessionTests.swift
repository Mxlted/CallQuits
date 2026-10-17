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
            XCTAssertEqual(session.evaluate(snapshot: snapshot(1, target: true), now: time), .wait,
                           "target still present, elapsed=\(time)")
        }
        XCTAssertEqual(session.evaluate(snapshot: snapshot(1, target: true), now: 3), .cancel(.expired))
    }

    func testExpirationWinsEvenWhenConfirmationWouldOtherwiseSucceed() {
        var session = CloseSession(behavior: .lastWindow, startedAt: 10)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 12.8), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 13), .cancel(.expired))
    }

    func testOtherWindowsPreventLastWindowQuitRegardlessOfVisibility() {
        // The AX adapter supplies all windows, including minimized windows and other Spaces.
        for remainingCount in [1, 2, 10] {
            let context = "last-window mode, remaining windows=\(remainingCount)"
            var session = CloseSession(behavior: .lastWindow, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount + 1, target: true), now: 0.1), .wait, context)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount), now: 0.2), .cancel(.remainingWindows), context)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.5), .cancel(.remainingWindows), context)
        }
    }

    func testEveryWindowAllowsStableExistingWindowsAfterTheTargetCloses() {
        for remainingCount in [0, 1, 5] {
            let context = "every-window mode, remaining windows=\(remainingCount)"
            var session = CloseSession(behavior: .everyWindow, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount + 1, target: true), now: 0.1), .wait, context)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount), now: 0.2), .wait, context)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(remainingCount), now: 0.36), .quit, context)
        }
    }

    func testEveryWindowStillRequiresTargetToClose() {
        var session = CloseSession(behavior: .everyWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(3, target: true), now: 0.5), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(3, target: true), now: 2), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(3, target: true), now: 3), .cancel(.expired))
    }

    func testUnreadableBlockingAndInconsistentSnapshotsFailClosed() {
        let cases: [(name: String, snapshot: CloseSnapshot, reason: CloseCancellationReason)] = [
            ("unreadable snapshot", snapshot(reliable: false), .unreliableSnapshot),
            ("observed blocking UI", snapshot(blocking: true), .blockingUI),
            ("negative window count", snapshot(-1), .unreliableSnapshot),
            ("present target with zero windows", snapshot(0, target: true), .unreliableSnapshot),
            ("observed replacement", snapshot(replacement: true), .replacementWindow)
        ]
        for behavior in CloseBehavior.allCases {
            for testCase in cases {
                for afterDisappearance in [false, true] {
                    let context = "\(testCase.name), behavior=\(behavior), after disappearance=\(afterDisappearance)"
                    var session = CloseSession(behavior: behavior, startedAt: 0)
                    if afterDisappearance {
                        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.1), .wait, context)
                    }
                    XCTAssertEqual(session.evaluate(snapshot: testCase.snapshot, now: 0.3), .cancel(testCase.reason), context)
                    XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.5), .cancel(testCase.reason),
                                   "\(context), cancellation must remain final")
                }
            }
        }
    }

    func testSaveSheetCancelsWhileTargetStillExists() {
        for behavior in CloseBehavior.allCases {
            let context = "save sheet with target present, behavior=\(behavior)"
            var session = CloseSession(behavior: behavior, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(1, target: true, blocking: true), now: 0.1),
                           .cancel(.blockingUI), context)
            // Dismissing a sheet later must not revive a pending quit.
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 1), .cancel(.blockingUI), context)
        }
    }

    func testReplacementWindowAndReappearingTargetCancel() {
        let cases: [(name: String, snapshot: CloseSnapshot, lastWindowReason: CloseCancellationReason)] = [
            ("window count increases", snapshot(1), .remainingWindows),
            ("target reappears", snapshot(1, target: true), .windowSetChanged)
        ]
        for behavior in CloseBehavior.allCases {
            for testCase in cases {
                let context = "\(testCase.name), behavior=\(behavior)"
                let reason: CloseCancellationReason = behavior == .lastWindow ? testCase.lastWindowReason : .windowSetChanged
                var session = CloseSession(behavior: behavior, startedAt: 0)
                XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.1), .wait, context)
                XCTAssertEqual(session.evaluate(snapshot: testCase.snapshot, now: 0.3), .cancel(reason), context)
            }
        }
    }

    func testEveryWindowDetectsIdentityReplacementEvenWithUnchangedCount() {
        var session = CloseSession(behavior: .everyWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(2), now: 0.1), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(2, replacement: true), now: 0.3), .cancel(.replacementWindow))
    }

    func testEveryWindowCancelsWhenRemainingWindowCountChanges() {
        for changedCount in [1, 3] {
            let context = "every-window mode, remaining count changes from 2 to \(changedCount)"
            var session = CloseSession(behavior: .everyWindow, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(2), now: 0.1), .wait, context)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(changedCount), now: 0.3), .cancel(.windowSetChanged), context)
        }
    }

    func testQuitIsEmittedAtMostOnce() {
        for behavior in CloseBehavior.allCases {
            let context = "behavior=\(behavior)"
            var session = CloseSession(behavior: behavior, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.1), .wait, context)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.3), .quit, context)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.5), .cancel(.alreadyFinished), context)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.7), .cancel(.alreadyFinished), context)
        }
    }

    func testInvalidAndReversedClockValuesCancel() {
        for invalidStart in [Double.nan, Double.infinity, -Double.infinity] {
            var session = CloseSession(behavior: .lastWindow, startedAt: invalidStart)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 1), .cancel(.invalidTiming), "start=\(invalidStart)")
        }
        for invalidNow in [Double.nan, Double.infinity, -Double.infinity, -1] {
            var session = CloseSession(behavior: .lastWindow, startedAt: 0)
            XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: invalidNow), .cancel(.invalidTiming), "now=\(invalidNow)")
        }
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.4), .wait)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 0.3), .cancel(.invalidTiming))
    }

    func testUnreliableSnapshotDoesNotClaimAnObservedDialogOrReplacement() {
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(blocking: true, reliable: false, replacement: true), now: 0.1),
                       .cancel(.unreliableSnapshot))
    }

    func testCancellationKeepsItsOriginalReasonAfterExpiry() {
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: snapshot(blocking: true), now: 0.1), .cancel(.blockingUI))
        XCTAssertEqual(session.evaluate(snapshot: snapshot(), now: 4), .cancel(.blockingUI))
    }
}
