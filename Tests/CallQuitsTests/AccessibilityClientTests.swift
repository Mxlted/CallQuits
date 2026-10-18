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

final class CloseControlCaptureTests: XCTestCase {
    private final class Fixture {
        // Only AXUIElementGetPid sees these opaque handles; all remote reads are injected.
        let targetPID: pid_t = 710_001
        let target = AXUIElementCreateApplication(710_001)
        let button = AXUIElementCreateApplication(710_002)
        let child = AXUIElementCreateApplication(710_003)
        let other = AXUIElementCreateApplication(710_004)
        let point = CGPoint(x: 105, y: 105)
        let expectedFrame = CGRect(x: 100, y: 100, width: 14, height: 14)
        let windowAttributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXModalAttribute,
                                kAXChildrenAttribute, kAXCloseButtonAttribute]
        let buttonAttributes = [kAXSubroleAttribute, kAXRoleAttribute, kAXEnabledAttribute,
                                kAXPositionAttribute, kAXSizeAttribute]
        var windowValues: [CFTypeRef]?
        var buttonValues: [CFTypeRef]?
        var windowError: AXError = .success
        var buttonError: AXError = .success
        var findError: AXError = .success
        var findChild = false
        var returnNoElement = false
        var childRole: CFTypeRef = kAXGroupRole as CFString
        var childRoleError: AXError = .success
        var scalarError: AXError = .success
        var initialWindows: [AXUIElement]
        var windowListValue: CFTypeRef?
        var onFinalButtonRead: (() -> Void)?
        private(set) var operations: [String] = []
        private(set) var fallbackReads = 0

        init() {
            initialWindows = [target]
            windowValues = [kAXWindowRole as CFString, kAXStandardWindowSubrole as CFString,
                            kCFBooleanFalse, [] as NSArray, button]
            buttonValues = [kAXCloseButtonSubrole as CFString, kAXButtonRole as CFString,
                            kCFBooleanTrue, Self.position(100, 100), Self.size(14, 14)]
        }

        static func position(_ x: CGFloat, _ y: CGFloat) -> AXValue {
            var point = CGPoint(x: x, y: y)
            return AXValueCreate(.cgPoint, &point)!
        }

        static func size(_ width: CGFloat, _ height: CGFloat) -> AXValue {
            var size = CGSize(width: width, height: height)
            return AXValueCreate(.cgSize, &size)!
        }

        func client() -> AccessibilityClient {
            AccessibilityClient(readAttribute: { [self] element, attribute in
                let name = attribute as String
                operations.append("scalar:\(name)")
                if CFEqual(element, button), name == kAXWindowAttribute { return (.success, target) }
                if CFEqual(element, target), name == kAXWindowsAttribute {
                    return (.success, windowListValue ?? initialWindows as NSArray)
                }
                if CFEqual(element, child) {
                    if name == kAXSubroleAttribute { return (.attributeUnsupported, nil) }
                    if name == kAXParentAttribute { return (.success, button) }
                    if name == kAXRoleAttribute { return (childRoleError, childRole) }
                }
                if CFEqual(element, button), name == kAXSubroleAttribute,
                   !operations.contains("batch:button") {
                    return (.success, kAXCloseButtonSubrole as CFString)
                }
                if CFEqual(element, target), windowError == .notImplemented,
                   let index = windowAttributes.firstIndex(of: name) {
                    fallbackReads += 1
                    return (scalarError, windowValues?[index])
                }
                if CFEqual(element, button), buttonError == .notImplemented,
                   let index = buttonAttributes.firstIndex(of: name) {
                    fallbackReads += 1
                    return (scalarError, buttonValues?[index])
                }
                XCTFail("Unexpected scalar Accessibility read: \(name)")
                return (.failure, nil)
            }, readAttributes: { [self] element, attributes in
                if CFEqual(element, target) {
                    operations.append("batch:window")
                    XCTAssertEqual(attributes, windowAttributes)
                    return (windowError, windowValues)
                }
                if CFEqual(element, button) {
                    operations.append("batch:button")
                    XCTAssertEqual(attributes, buttonAttributes)
                    onFinalButtonRead?()
                    return (buttonError, buttonValues)
                }
                XCTFail("Unexpected grouped Accessibility element")
                return (.failure, nil)
            }, findElement: { [self] _, location in
                operations.append("find")
                XCTAssertEqual(location, point)
                return (findError, returnNoElement ? nil : (findChild ? child : button))
            })
        }

        func capture(eventTime: TimeInterval? = nil, targetPID: pid_t? = nil) -> AccessibilityClient.CloseControl? {
            client().captureCloseControl(at: point,
                                         eventTime: eventTime ?? ProcessInfo.processInfo.systemUptime,
                                         targetPID: targetPID ?? self.targetPID)
        }
    }

    func testVerifiedCloseControlPreservesWindowIdentityFrameAndAllInitialWindows() throws {
        let fixture = Fixture()
        fixture.initialWindows = [fixture.target, fixture.other]
        let control = try XCTUnwrap(fixture.capture())
        XCTAssertTrue(CFEqual(control.window, fixture.target))
        XCTAssertTrue(CFEqual(control.appElement, AXUIElementCreateApplication(fixture.targetPID)))
        XCTAssertEqual(control.buttonFrame, fixture.expectedFrame)
        XCTAssertEqual(control.initialWindows.count, 2)
        XCTAssertTrue(CFEqual(control.initialWindows[1], fixture.other))
        XCTAssertEqual(fixture.fallbackReads, 0)
    }

    func testInitialMembershipIsCapturedBeforeImmediateCloseDuringFinalButtonRead() throws {
        let fixture = Fixture()
        fixture.onFinalButtonRead = { fixture.initialWindows = [] }
        let control = try XCTUnwrap(fixture.capture())
        XCTAssertTrue(fixture.initialWindows.isEmpty)
        XCTAssertEqual(control.initialWindows.count, 1)
        XCTAssertTrue(CFEqual(control.initialWindows[0], fixture.target))
        XCTAssertEqual(fixture.operations.filter { $0 == "scalar:\(kAXWindowsAttribute)" }.count, 1)
        let membership = try XCTUnwrap(fixture.operations.firstIndex(of: "scalar:\(kAXWindowsAttribute)"))
        let finalButton = try XCTUnwrap(fixture.operations.firstIndex(of: "batch:button"))
        XCTAssertLessThan(membership, finalButton)
        XCTAssertEqual(fixture.operations.last, "batch:button")
    }

    func testMissingTargetOrMalformedInitialWindowListStopsBeforeGroupedReads() {
        let lists: [CFTypeRef] = [([] as NSArray), [AXUIElementCreateApplication(710_004)] as NSArray,
                                 "not windows" as CFString, ["not a window"] as NSArray]
        for list in lists {
            let fixture = Fixture()
            fixture.windowListValue = list
            XCTAssertNil(fixture.capture())
            XCTAssertFalse(fixture.operations.contains(where: { $0.hasPrefix("batch:") }))
        }
        let tooMany = Fixture()
        tooMany.initialWindows = Array(repeating: tooMany.target, count: 65)
        XCTAssertNil(tooMany.capture())
    }

    func testWindowOwnerMustMatchVerifiedNativeTargetBeforeWindowEnumeration() {
        let fixture = Fixture()
        XCTAssertNil(fixture.capture(targetPID: fixture.targetPID + 1))
        XCTAssertFalse(fixture.operations.contains("scalar:\(kAXWindowsAttribute)"))
        XCTAssertFalse(fixture.operations.contains(where: { $0.hasPrefix("batch:") }))
    }

    func testChildHitResolvesOnlyThroughItsActualCloseButtonParent() throws {
        let fixture = Fixture()
        fixture.findChild = true
        XCTAssertNotNil(fixture.capture())
        XCTAssertTrue(fixture.operations.contains("scalar:\(kAXParentAttribute)"))
    }

    func testRequiredWindowRoleSubroleModalAndOfficialButtonCannotBeSubstituted() {
        let replacements: [(Int, CFTypeRef)] = [
            (0, kAXSheetRole as CFString), (1, kAXDialogSubrole as CFString),
            (2, kCFBooleanTrue), (2, NSNumber(value: 0)),
            (3, "not children" as CFString), (3, ["not an element"] as NSArray),
            (4, AXUIElementCreateApplication(710_004)), (4, "not a button" as CFString)
        ]
        for (index, value) in replacements {
            let fixture = Fixture()
            fixture.windowValues![index] = value
            XCTAssertNil(fixture.capture(), "window attribute index=\(index)")
            XCTAssertFalse(fixture.operations.contains("batch:button"))
        }
    }

    func testFinalButtonMetadataMustStillIdentifyEnabledCloseButton() {
        let replacements: [(Int, CFTypeRef)] = [
            (0, kAXMinimizeButtonSubrole as CFString), (1, kAXGroupRole as CFString),
            (2, kCFBooleanFalse), (2, NSNumber(value: 1)),
            (3, "not a position" as CFString), (4, "not a size" as CFString),
            (3, Fixture.size(14, 14)), (4, Fixture.position(100, 100)),
            (3, Fixture.position(.infinity, 100)), (3, Fixture.position(.nan, 100)),
            (4, Fixture.size(.infinity, 14)), (4, Fixture.size(14, .nan)),
            (4, Fixture.size(0, 14)), (4, Fixture.size(14, -1)),
            (3, Fixture.position(200, 200))
        ]
        for (index, value) in replacements {
            let fixture = Fixture()
            fixture.buttonValues![index] = value
            XCTAssertNil(fixture.capture(), "button attribute index=\(index)")
        }
    }

    func testSheetOrUnreadableChildBlocksCaptureButOrdinaryChildDoesNot() {
        for role in [kAXSheetRole as CFString, NSNumber(value: 1)] as [CFTypeRef] {
            let fixture = Fixture()
            fixture.windowValues![3] = [fixture.child] as NSArray
            fixture.childRole = role
            XCTAssertNil(fixture.capture())
        }
        let unreadable = Fixture()
        unreadable.windowValues![3] = [unreadable.child] as NSArray
        unreadable.childRoleError = .cannotComplete
        XCTAssertNil(unreadable.capture())
        let clear = Fixture()
        clear.windowValues![3] = [clear.child] as NSArray
        XCTAssertNotNil(clear.capture())
        let tooMany = Fixture()
        tooMany.windowValues![3] = Array(repeating: tooMany.child, count: 65) as NSArray
        XCTAssertNil(tooMany.capture())
    }

    func testFailedGroupedReadsNeverFallBackOrAuthorizeControl() {
        for error: AXError in [.invalidUIElement, .cannotComplete, .attributeUnsupported, .noValue,
                              .apiDisabled, .failure] {
            for failsAtWindow in [true, false] {
                let fixture = Fixture()
                if failsAtWindow { fixture.windowError = error } else { fixture.buttonError = error }
                XCTAssertNil(fixture.capture(), "error=\(error.rawValue), window=\(failsAtWindow)")
                XCTAssertEqual(fixture.fallbackReads, 0)
            }
        }
    }

    func testMalformedGroupedResponseIsNeverAcceptedOrRetried() {
        var attributeError = AXError.attributeUnsupported
        let encodedError = AXValueCreate(.axError, &attributeError)!
        for failsAtWindow in [true, false] {
            for malformed in 0..<5 {
                let fixture = Fixture()
                var values = failsAtWindow ? fixture.windowValues : fixture.buttonValues
                switch malformed {
                case 0: values = nil
                case 1: values?.removeLast()
                case 2: values?.append(kCFBooleanTrue)
                case 3: values?[0] = kCFNull
                default: values?[0] = encodedError
                }
                if failsAtWindow { fixture.windowValues = values } else { fixture.buttonValues = values }
                XCTAssertNil(fixture.capture(), "case=\(malformed), window=\(failsAtWindow)")
                XCTAssertEqual(fixture.fallbackReads, 0)
            }
        }
    }

    func testOnlyNotImplementedUsesFullyValidatedScalarCompatibilityReads() {
        let fixture = Fixture()
        fixture.windowError = .notImplemented
        fixture.buttonError = .notImplemented
        XCTAssertNotNil(fixture.capture())
        XCTAssertEqual(fixture.fallbackReads, fixture.windowAttributes.count + fixture.buttonAttributes.count)

        let invalid = Fixture()
        invalid.buttonError = .notImplemented
        invalid.buttonValues![2] = kCFBooleanFalse
        XCTAssertNil(invalid.capture())

        let failed = Fixture()
        failed.windowError = .notImplemented
        failed.scalarError = .cannotComplete
        XCTAssertNil(failed.capture())
        XCTAssertEqual(failed.fallbackReads, 1)
    }

    func testStaleEventAndFailedHitTestNeverStartAttributeReads() {
        let stale = Fixture()
        XCTAssertNil(stale.capture(eventTime: ProcessInfo.processInfo.systemUptime - 1))
        XCTAssertTrue(stale.operations.isEmpty)
        for missing in [true, false] {
            let fixture = Fixture()
            fixture.returnNoElement = missing
            fixture.findError = missing ? .success : .cannotComplete
            XCTAssertNil(fixture.capture())
            XCTAssertEqual(fixture.operations, ["find"])
        }
    }

    func testSlowGroupedReadCannotReturnProofOrRenewBudgetThroughFallback() {
        for error: AXError in [.success, .notImplemented] {
            let fixture = Fixture()
            fixture.buttonError = error
            fixture.onFinalButtonRead = { Thread.sleep(forTimeInterval: 0.57) }
            XCTAssertNil(fixture.capture())
            XCTAssertEqual(fixture.fallbackReads, 0)
        }
    }

    func testOwnApplicationIsRejectedBeforeHitTesting() {
        let fixture = Fixture()
        XCTAssertNil(fixture.client().closeButton(at: fixture.point, eventTime: ProcessInfo.processInfo.systemUptime,
                                                  targetPID: ProcessInfo.processInfo.processIdentifier))
        XCTAssertTrue(fixture.operations.isEmpty)
    }
}

final class AdditionalCloseCaptureTests: XCTestCase {
    private final class Fixture {
        let pid: pid_t = 720_001
        let window = AXUIElementCreateApplication(720_001)
        let button = AXUIElementCreateApplication(720_002)
        let tab = AXUIElementCreateApplication(720_003)
        let group = AXUIElementCreateApplication(720_004)
        let redButton = AXUIElementCreateApplication(720_005)
        let webArea = AXUIElementCreateApplication(720_006)
        let sheet = AXUIElementCreateApplication(720_007)
        var label = "Close"
        var tabRole = kAXRadioButtonRole
        var groupRole = kAXTabGroupRole
        var officialTabButton = false
        var tabCloseValue: CFTypeRef?
        var webContent = false
        var enabled = true
        var blocking = false
        var minimized = false
        var empty = false
        var focusedWindow: AXUIElement?
        var attributeError: AXError?
        var buttonReads = 0
        var beforeFinalButtonRead: (() -> Void)?
        var attributeNames: [(AXUIElement, String)] = []
        let point = CGPoint(x: 105, y: 105)

        func client() -> AccessibilityClient {
            AccessibilityClient(readAttribute: { [self] element, attribute in
                let name = attribute as String
                attributeNames.append((element, name))
                if let attributeError { return (attributeError, nil) }
                if CFEqual(element, window) {
                    switch name {
                    case kAXWindowsAttribute: return (.success, (empty ? [] : [window]) as NSArray)
                    case kAXFocusedWindowAttribute: return (.success, focusedWindow ?? window)
                    default: break
                    }
                }
                if CFEqual(element, button) {
                    switch name {
                    case kAXRoleAttribute: return (.success, kAXButtonRole as CFString)
                    case kAXParentAttribute: return (.success, tab)
                    case kAXWindowAttribute: return (.success, window)
                    case kAXTitleAttribute: return (.success, label as CFString)
                    default: break
                    }
                }
                if CFEqual(element, tab) {
                    switch name {
                    case kAXRoleAttribute: return (.success, tabRole as CFString)
                    case kAXParentAttribute: return (.success, group)
                    case kAXCloseButtonAttribute where tabCloseValue != nil: return (.success, tabCloseValue)
                    case kAXCloseButtonAttribute where officialTabButton: return (.success, button)
                    default: break
                    }
                }
                if CFEqual(element, group) {
                    if name == kAXRoleAttribute { return (.success, groupRole as CFString) }
                    if name == kAXParentAttribute { return (.success, webContent ? webArea : window) }
                }
                if CFEqual(element, webArea), name == kAXRoleAttribute { return (.success, "AXWebArea" as CFString) }
                if CFEqual(element, sheet), name == kAXRoleAttribute { return (.success, kAXSheetRole as CFString) }
                return (.attributeUnsupported, nil)
            }, readAttributes: { [self] element, attributes in
                if let attributeError { return (attributeError, nil) }
                if CFEqual(element, window) {
                    let last: CFTypeRef = attributes.last == kAXMinimizedAttribute
                        ? (minimized ? kCFBooleanTrue! : kCFBooleanFalse!) : redButton
                    return (.success, [kAXWindowRole as CFString, kAXStandardWindowSubrole as CFString,
                                       kCFBooleanFalse, (blocking ? [sheet] : []) as NSArray, last])
                }
                if CFEqual(element, button) {
                    buttonReads += 1
                    beforeFinalButtonRead?()
                    var origin = CGPoint(x: 100, y: 100)
                    var size = CGSize(width: 14, height: 14)
                    return (.success, [kAXButtonRole as CFString, enabled ? kCFBooleanTrue! : kCFBooleanFalse!,
                                       AXValueCreate(.cgPoint, &origin)!, AXValueCreate(.cgSize, &size)!])
                }
                return (.failure, nil)
            }, findElement: { [self] _, _ in (.success, button) })
        }

        func captureTab(includingTabs: Bool = true, targetPID: pid_t? = nil) -> AccessibilityClient.CloseControl? {
            client().captureCloseControl(at: point, eventTime: ProcessInfo.processInfo.systemUptime,
                                         targetPID: targetPID ?? pid, includingTabs: includingTabs)
        }

        func captureShortcut() -> AccessibilityClient.CloseControl? {
            client().captureShortcutWindow(eventTime: ProcessInfo.processInfo.systemUptime, targetPID: pid)
        }
    }

    func testTabProofKeepsWindowMembershipThroughImmediateNativeClose() throws {
        let fixture = Fixture()
        fixture.beforeFinalButtonRead = { fixture.empty = true }
        let control = try XCTUnwrap(fixture.captureTab())
        XCTAssertEqual(control.trigger, .tabButton)
        XCTAssertTrue(CFEqual(control.window, fixture.window))
        XCTAssertEqual(control.initialWindows.count, 1)
        XCTAssertEqual(fixture.buttonReads, 1)
        XCTAssertTrue(fixture.empty)
        XCTAssertFalse(fixture.attributeNames.contains { CFEqual($0.0, fixture.tab) && $0.1 == kAXTitleAttribute },
                       "never read a tab's title")
    }

    func testOfficialTabCloseAttributeWorksWithoutAnEnglishLabel() throws {
        let fixture = Fixture()
        fixture.officialTabButton = true
        fixture.label = "Fermer"
        XCTAssertEqual(try XCTUnwrap(fixture.captureTab()).trigger, .tabButton)
    }

    func testTabCaptureRejectsOrdinaryButtonsWebTabsUnknownLabelsAndDisabledControls() {
        let mutations: [(Fixture) -> Void] = [
            { $0.tabRole = kAXGroupRole }, { $0.groupRole = kAXGroupRole },
            { $0.webContent = true }, { $0.label = "Mute" }, { $0.label = "x" },
            { $0.label = "Fermer" }, { $0.enabled = false }, { $0.blocking = true },
            { $0.empty = true }, { $0.attributeError = .cannotComplete }
        ]
        for mutate in mutations {
            let fixture = Fixture()
            mutate(fixture)
            XCTAssertNil(fixture.captureTab())
        }
        XCTAssertNil(Fixture().captureTab(includingTabs: false))
        XCTAssertNil(Fixture().captureTab(targetPID: 720_010))
    }

    func testTabLabelCannotOverrideAConflictingOrMalformedOfficialCloseButton() {
        let fixture = Fixture()
        fixture.tabCloseValue = fixture.redButton
        XCTAssertNil(fixture.captureTab())
        fixture.tabCloseValue = "not a control" as CFString
        XCTAssertNil(fixture.captureTab())
    }

    func testShortcutRequiresFocusedOwnedLiveUnblockedWindow() throws {
        let fixture = Fixture()
        let control = try XCTUnwrap(fixture.captureShortcut())
        XCTAssertEqual(control.trigger, .keyboardShortcut)
        XCTAssertTrue(CFEqual(control.window, fixture.window))
        let mutations: [(Fixture) -> Void] = [
            { $0.empty = true }, { $0.focusedWindow = $0.webArea }, { $0.blocking = true },
            { $0.minimized = true }, { $0.attributeError = .cannotComplete }
        ]
        for mutate in mutations {
            let invalid = Fixture()
            mutate(invalid)
            XCTAssertNil(invalid.captureShortcut())
        }
    }
}
