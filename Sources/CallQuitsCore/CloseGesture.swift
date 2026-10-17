import Foundation

/// The integration maps input modifiers to these values. `.force` requires explicit opt-in.
public enum CloseGestureModifiers: Equatable, Sendable {
    case normal
    case force
    case bypass
}

public enum CloseGestureAction: Equatable, Sendable {
    case graceful
    case force
}

/// Validates the pointer sequence independently of Accessibility and AppKit.
///
/// The integration must positively identify the actual close button and compare its application's
/// PID with the verified event identity. When the native PID is missing, verified ownership of
/// the exact event-stamped window is supported; never substitute the frontmost application.
/// Store this value only for the current press; discard it on release, an invalid drag, or cancellation.
public struct CloseGesture: Sendable {
    public static let maximumMovement: Double = 4
    public static let maximumDuration: TimeInterval = 3

    private let x: Double
    private let y: Double
    private let timestamp: TimeInterval
    private let targetProcessID: Int32
    private let modifiers: CloseGestureModifiers

    public init?(
        x: Double,
        y: Double,
        timestamp: TimeInterval,
        targetProcessID: Int32,
        modifiers: CloseGestureModifiers
    ) {
        guard x.isFinite, y.isFinite, timestamp.isFinite, timestamp >= 0,
              targetProcessID > 1, modifiers != .bypass else { return nil }
        self.x = x
        self.y = y
        self.timestamp = timestamp
        self.targetProcessID = targetProcessID
        self.modifiers = modifiers
    }

    public func allowsDrag(toX x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite else { return false }
        return hypot(x - self.x, y - self.y) <= Self.maximumMovement
    }

    public func actionOnRelease(
        x: Double,
        y: Double,
        timestamp: TimeInterval,
        targetProcessID: Int32,
        modifiers: CloseGestureModifiers
    ) -> CloseGestureAction? {
        guard timestamp.isFinite, timestamp >= self.timestamp,
              timestamp - self.timestamp <= Self.maximumDuration,
              targetProcessID == self.targetProcessID,
              modifiers == self.modifiers,
              allowsDrag(toX: x, y: y) else { return nil }
        return modifiers == .force ? .force : .graceful
    }
}
