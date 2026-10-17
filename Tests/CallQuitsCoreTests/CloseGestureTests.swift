import XCTest
@testable import CallQuitsCore

final class CloseGestureTests: XCTestCase {
    private func gesture(_ modifiers: CloseGestureModifiers = .normal) -> CloseGesture {
        CloseGesture(x: 100, y: 200, timestamp: 10, targetProcessID: 42, modifiers: modifiers)!
    }

    private func release(
        _ gesture: CloseGesture,
        x: Double = 100,
        y: Double = 200,
        timestamp: TimeInterval = 10.1,
        targetProcessID: Int32 = 42,
        modifiers: CloseGestureModifiers = .normal
    ) -> CloseGestureAction? {
        gesture.actionOnRelease(x: x, y: y, timestamp: timestamp,
                                targetProcessID: targetProcessID, modifiers: modifiers)
    }

    func testOrdinaryClickRequestsOnlyGracefulQuit() {
        XCTAssertEqual(release(gesture()), .graceful)
    }

    func testForceRequiresMatchingForceIntentAcrossTheClick() {
        XCTAssertEqual(release(gesture(.force), modifiers: .force), .force)
        // Pressing Shift only after an ordinary press must never upgrade it to force quit.
        XCTAssertNil(release(gesture(.normal), modifiers: .force))
        // Releasing Shift before mouse-up cancels rather than changing the meaning of the gesture.
        XCTAssertNil(release(gesture(.force), modifiers: .normal))
        XCTAssertNil(release(gesture(.force), modifiers: .bypass))
        XCTAssertNil(release(gesture(.normal), modifiers: .bypass))
    }

    func testUnsupportedModifiersCannotStartAGesture() {
        XCTAssertNil(CloseGesture(x: 100, y: 200, timestamp: 10, targetProcessID: 42, modifiers: .bypass))
    }

    func testDifferentEventRecipientCannotReceiveTheQuit() {
        for modifiers in [CloseGestureModifiers.normal, .force] {
            for otherPID: Int32 in [-1, 0, 1, 43, Int32.max] {
                XCTAssertNil(release(gesture(modifiers), targetProcessID: otherPID, modifiers: modifiers))
            }
        }
    }

    func testUnknownEventRecipientCannotStartAGesture() {
        for unknownPID: Int32 in [-1, 0, 1] {
            XCTAssertNil(CloseGesture(x: 100, y: 200, timestamp: 10, targetProcessID: unknownPID, modifiers: .normal))
        }
    }

    func testSlightPointerMovementIsAllowedButDraggingAwayCancels() {
        let gesture = gesture()
        XCTAssertTrue(gesture.allowsDrag(toX: 102, y: 202))
        XCTAssertTrue(gesture.allowsDrag(toX: 104, y: 200))
        XCTAssertFalse(gesture.allowsDrag(toX: 104.01, y: 200))
        XCTAssertFalse(gesture.allowsDrag(toX: 103, y: 203))
        XCTAssertEqual(release(gesture, x: 104), .graceful)
        // Validate the release too, even if the event system omitted intermediate drag events.
        XCTAssertNil(release(gesture, x: 105))
    }

    func testLongHoldsAndReversedTimestampsCancel() {
        let gesture = gesture()
        XCTAssertEqual(release(gesture, timestamp: 13), .graceful)
        XCTAssertNil(release(gesture, timestamp: 13.001))
        XCTAssertNil(release(gesture, timestamp: 9.9))
        XCTAssertEqual(release(gesture, timestamp: 10), .graceful)
    }

    func testInvalidNumbersFailClosed() {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(CloseGesture(x: invalid, y: 200, timestamp: 10, targetProcessID: 42, modifiers: .normal))
            XCTAssertNil(CloseGesture(x: 100, y: invalid, timestamp: 10, targetProcessID: 42, modifiers: .normal))
            XCTAssertNil(CloseGesture(x: 100, y: 200, timestamp: invalid, targetProcessID: 42, modifiers: .normal))
            XCTAssertFalse(gesture().allowsDrag(toX: invalid, y: 200))
            XCTAssertFalse(gesture().allowsDrag(toX: 100, y: invalid))
            XCTAssertNil(release(gesture(), x: invalid))
            XCTAssertNil(release(gesture(), y: invalid))
            XCTAssertNil(release(gesture(), timestamp: invalid))
        }
        XCTAssertNil(CloseGesture(x: 100, y: 200, timestamp: -1, targetProcessID: 42, modifiers: .normal))
    }

    func testNegativeCoordinatesSupportDisplaysLeftOfOrAboveTheMainDisplay() {
        let gesture = CloseGesture(x: -800, y: -200, timestamp: 10, targetProcessID: 42, modifiers: .normal)!
        XCTAssertEqual(release(gesture, x: -800, y: -200), .graceful)
    }
}
