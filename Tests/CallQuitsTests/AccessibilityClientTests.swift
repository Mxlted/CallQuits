import AppKit
import ApplicationServices
import CallQuitsCore
import XCTest
@testable import CallQuits

final class AccessibilityClientTests: XCTestCase {
    // These are opaque test identities. The injected reader never sends IPC to these PIDs.
    private let application = AXUIElementCreateApplication(700_001)
    private let target = AXUIElementCreateApplication(700_002)
    private let other = AXUIElementCreateApplication(700_003)
    private let replacement = AXUIElementCreateApplication(700_004)
    private let child = AXUIElementCreateApplication(700_005)

    private struct Read {
        let element: AXUIElement
        let attribute: String
        let error: AXError
        let value: CFTypeRef?

        init(_ element: AXUIElement, _ attribute: String,
             error: AXError = .success, value: CFTypeRef? = nil) {
            self.element = element
            self.attribute = attribute
            self.error = error
            self.value = value
        }
    }

    private final class Script {
        let reads: [Read]
        private(set) var count = 0

        init(_ reads: [Read]) { self.reads = reads }

        func read(_ element: AXUIElement, _ attribute: CFString) -> (AXError, CFTypeRef?) {
            guard count < reads.count else {
                XCTFail("Unexpected extra Accessibility read: \(attribute)")
                return (.failure, nil)
            }
            let expected = reads[count]
            count += 1
            XCTAssertTrue(CFEqual(element, expected.element), "Read \(count) used the wrong element")
            XCTAssertEqual(attribute as String, expected.attribute, "Read \(count) used the wrong attribute")
            return (expected.error, expected.value)
        }

        func assertConsumed(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(count, reads.count, "The expected Accessibility sequence was incomplete", file: file, line: line)
        }
    }

    private func hit(initialWindows: [AXUIElement]? = nil) -> AccessibilityClient.Hit {
        AccessibilityClient.Hit(application: .current, appElement: application, window: target,
                                initialWindows: initialWindows ?? [target], buttonFrame: .zero,
                                allowsApplicationHide: false)
    }

    private func windowList(_ windows: [AXUIElement]) -> Read {
        Read(application, kAXWindowsAttribute, value: windows as NSArray)
    }

    private func clearWindow(_ window: AXUIElement) -> [Read] {
        [Read(window, kAXModalAttribute, value: kCFBooleanFalse),
         Read(window, kAXChildrenAttribute, value: [] as NSArray)]
    }

    private func snapshot(_ reads: [Read], initialWindows: [AXUIElement]? = nil,
                          file: StaticString = #filePath, line: UInt = #line) -> CloseSnapshot {
        let script = Script(reads)
        let result = AccessibilityClient(readAttribute: script.read).snapshot(for: hit(initialWindows: initialWindows))
        script.assertConsumed(file: file, line: line)
        return result
    }

    func testDisappearedTargetRecoversFromInvalidWindowOrChildWithinOneRefresh() {
        let failures: [[Read]] = [
            [Read(target, kAXModalAttribute, error: .invalidUIElement)],
            [Read(target, kAXModalAttribute, value: kCFBooleanFalse),
             Read(target, kAXChildrenAttribute, error: .invalidUIElement)],
            [Read(target, kAXModalAttribute, value: kCFBooleanFalse),
             Read(target, kAXChildrenAttribute, value: [child] as NSArray),
             Read(child, kAXRoleAttribute, error: .invalidUIElement)]
        ]
        for failure in failures {
            let result = snapshot([windowList([target])] + failure + [windowList([])])
            XCTAssertTrue(result.isReliable)
            XCTAssertEqual(result.windowCount, 0)
            XCTAssertFalse(result.targetWindowPresent)
            XCTAssertFalse(result.hasBlockingUI)
            XCTAssertFalse(result.hasReplacementWindow)
        }
    }

    func testRecoveredEmptySnapshotStillRequiresOriginalStableConfirmation() {
        let recovered = snapshot([
            windowList([target]),
            Read(target, kAXModalAttribute, error: .invalidUIElement),
            windowList([])
        ])
        let confirmedEmpty = snapshot([windowList([])])
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: recovered, now: 0), .wait)
        XCTAssertEqual(session.evaluate(snapshot: confirmedEmpty, now: 0.16), .wait)
        XCTAssertEqual(session.evaluate(snapshot: confirmedEmpty, now: 0.2), .quit)
    }

    func testInvalidTargetThatRemainsInRefreshedListIsUnreliable() {
        let failures: [[Read]] = [
            [Read(target, kAXModalAttribute, error: .invalidUIElement)],
            [Read(target, kAXModalAttribute, value: kCFBooleanFalse),
             Read(target, kAXChildrenAttribute, value: [child] as NSArray),
             Read(child, kAXRoleAttribute, error: .invalidUIElement)]
        ]
        for failure in failures {
            let result = snapshot([windowList([target])] + failure + [windowList([target])])
            XCTAssertFalse(result.isReliable)
        }
    }

    func testOtherAccessibilityErrorsDoNotRefreshOrGuessDisappearance() {
        for error: AXError in [.cannotComplete, .noValue, .attributeUnsupported, .apiDisabled, .failure] {
            let result = snapshot([
                windowList([target]),
                Read(target, kAXModalAttribute, error: error)
            ])
            XCTAssertFalse(result.isReliable, "error=\(error.rawValue)")
        }
        let malformed = snapshot([
            windowList([target]),
            Read(target, kAXModalAttribute, value: "not a Boolean" as CFString)
        ])
        XCTAssertFalse(malformed.isReliable)
    }

    func testInvalidUnrelatedWindowNeverUsesTargetRecovery() {
        for windows in [[other, target], [other]] {
            let result = snapshot([
                windowList(windows),
                Read(other, kAXModalAttribute, error: .invalidUIElement)
            ], initialWindows: [target, other])
            XCTAssertFalse(result.isReliable)
        }
        let unreadableList = snapshot([Read(application, kAXWindowsAttribute, error: .invalidUIElement)])
        XCTAssertFalse(unreadableList.isReliable)
    }

    func testRefreshFailureOrMalformedListRemainsUnreliable() {
        let refreshFailures = [
            Read(application, kAXWindowsAttribute, error: .invalidUIElement),
            Read(application, kAXWindowsAttribute, error: .cannotComplete),
            Read(application, kAXWindowsAttribute, value: "not a window list" as CFString),
            Read(application, kAXWindowsAttribute, value: ["not a window"] as NSArray)
        ]
        for failure in refreshFailures {
            let result = snapshot([
                windowList([target]),
                Read(target, kAXModalAttribute, error: .invalidUIElement),
                failure
            ])
            XCTAssertFalse(result.isReliable)
        }
    }

    func testRemainingWindowIsReinspectedAndCountedAfterTargetDisappears() {
        // The sibling was already inspected before the race. Its entire blocking-UI
        // state must be read again, and it still counts even if it is minimized/off-Space.
        let result = snapshot(
            [windowList([other, target])] + clearWindow(other) + [
                Read(target, kAXModalAttribute, error: .invalidUIElement),
                windowList([other])
            ] + clearWindow(other), initialWindows: [target, other])
        XCTAssertTrue(result.isReliable)
        XCTAssertEqual(result.windowCount, 1)
        XCTAssertFalse(result.targetWindowPresent)
        var session = CloseSession(behavior: .lastWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: result, now: 0.1), .cancel(.remainingWindows))
    }

    func testSheetOnRefreshedSiblingBlocksQuit() {
        let result = snapshot(
            [windowList([other, target])] + clearWindow(other) + [
                Read(target, kAXModalAttribute, error: .invalidUIElement),
                windowList([other]),
                Read(other, kAXModalAttribute, value: kCFBooleanFalse),
                Read(other, kAXChildrenAttribute, value: [child] as NSArray),
                Read(child, kAXRoleAttribute, value: kAXSheetRole as CFString)
            ], initialWindows: [target, other])
        XCTAssertTrue(result.isReliable)
        XCTAssertTrue(result.hasBlockingUI)
        var session = CloseSession(behavior: .everyWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: result, now: 0.1), .cancel(.blockingUI))
    }

    func testSecondReadFailureNeverStartsAnotherRecovery() {
        let result = snapshot([
            windowList([target, other]),
            Read(target, kAXModalAttribute, error: .invalidUIElement),
            windowList([other]),
            Read(other, kAXModalAttribute, error: .invalidUIElement)
        ], initialWindows: [target, other])
        XCTAssertFalse(result.isReliable)
    }

    func testRecoveryCannotRenewTheOriginalSnapshotReadBudget() {
        let script = Script([
            windowList([target]),
            Read(target, kAXModalAttribute, error: .invalidUIElement)
        ])
        let client = AccessibilityClient { element, attribute in
            if CFEqual(element, self.target), attribute as String == kAXModalAttribute {
                // Model a bounded AX call returning after the snapshot's original
                // soft deadline. Recovery must not grant a fresh 450 ms budget.
                Thread.sleep(forTimeInterval: 0.46)
            }
            return script.read(element, attribute)
        }
        XCTAssertFalse(client.snapshot(for: hit()).isReliable)
        script.assertConsumed()
    }

    func testRecoveryRejectsSiblingRemovalAdditionOrReplacement() {
        let changedSets: [[AXUIElement]] = [[], [other, replacement], [replacement], [other, other]]
        for refreshed in changedSets {
            let result = snapshot([
                windowList([target, other]),
                Read(target, kAXModalAttribute, error: .invalidUIElement),
                windowList(refreshed)
            ], initialWindows: [target, other])
            XCTAssertFalse(result.isReliable)
        }
    }

    func testDuplicateOriginalSiblingCannotMaskADifferentRefreshedWindow() {
        // Equal counts and one-way membership are insufficient for malformed lists.
        // Both siblings existed at click time, so replacement detection alone would
        // not reject a newly reported sibling concealed by a duplicate old identity.
        let result = snapshot([
            windowList([target, other, other]),
            Read(target, kAXModalAttribute, error: .invalidUIElement),
            windowList([other, replacement])
        ], initialWindows: [target, other, replacement])
        XCTAssertFalse(result.isReliable)
    }

    func testReplacementSeenBeforeRecoveryRemainsAReplacement() {
        let result = snapshot([
            windowList([target, replacement]),
            Read(target, kAXModalAttribute, error: .invalidUIElement),
            windowList([replacement])
        ] + clearWindow(replacement))
        XCTAssertTrue(result.isReliable)
        XCTAssertTrue(result.hasReplacementWindow)
        var session = CloseSession(behavior: .everyWindow, startedAt: 0)
        XCTAssertEqual(session.evaluate(snapshot: result, now: 0.1), .cancel(.replacementWindow))
    }

    func testObservedSheetStopsBeforeAnyStaleTargetRecovery() {
        let result = snapshot([
            windowList([other, target]),
            Read(other, kAXModalAttribute, value: kCFBooleanFalse),
            Read(other, kAXChildrenAttribute, value: [child] as NSArray),
            Read(child, kAXRoleAttribute, value: kAXSheetRole as CFString)
        ], initialWindows: [target, other])
        XCTAssertTrue(result.isReliable)
        XCTAssertTrue(result.hasBlockingUI)
    }
}
