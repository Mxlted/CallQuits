import Foundation

/// Whether a verified close-button click should quit after the final window or after any window.
public enum CloseBehavior: String, CaseIterable, Codable, Sendable {
    case lastWindow
    case everyWindow
}

/// A complete Accessibility snapshot of an application, including minimized windows and other Spaces.
///
/// The caller must mark partially read snapshots unreliable and compare window identities against
/// the click-time snapshot to detect replacement windows. Visible screen geometry is not a window count.
public struct CloseSnapshot: Sendable {
    public let windowCount: Int
    public let targetWindowPresent: Bool
    public let hasBlockingUI: Bool
    public let isReliable: Bool
    public let hasReplacementWindow: Bool

    public init(
        windowCount: Int,
        targetWindowPresent: Bool,
        hasBlockingUI: Bool,
        isReliable: Bool,
        hasReplacementWindow: Bool = false
    ) {
        self.windowCount = windowCount
        self.targetWindowPresent = targetWindowPresent
        self.hasBlockingUI = hasBlockingUI
        self.isReliable = isReliable
        self.hasReplacementWindow = hasReplacementWindow
    }
}

public enum CloseDecision: Equatable, Sendable {
    case wait
    case cancel
    case quit
}

/// A short-lived, fail-closed decision session for one positively identified close-button click.
///
/// Create a session only after Accessibility identifies the actual close button. Use a monotonic
/// clock for `startedAt` and `now`. The integration owns cancellation when a new click, preference
/// change, or process change supersedes this session. A `.quit` decision is emitted at most once.
public struct CloseSession: Sendable {
    public static let confirmationInterval: TimeInterval = 0.15
    public static let minimumElapsedTime: TimeInterval = 0.2
    public static let maximumDuration: TimeInterval = 3

    private let behavior: CloseBehavior
    private let startedAt: TimeInterval
    private var previousObservationAt: TimeInterval
    private var disappearanceObservedAt: TimeInterval?
    private var confirmationWindowCount: Int?
    private var isFinished = false

    public init(behavior: CloseBehavior, startedAt: TimeInterval) {
        self.behavior = behavior
        self.startedAt = startedAt
        self.previousObservationAt = startedAt
    }

    public mutating func evaluate(snapshot: CloseSnapshot, now: TimeInterval) -> CloseDecision {
        guard !isFinished else { return .cancel }

        guard startedAt.isFinite,
              now.isFinite,
              now >= previousObservationAt,
              now - startedAt < Self.maximumDuration,
              snapshot.isReliable,
              !snapshot.hasBlockingUI,
              !snapshot.hasReplacementWindow,
              snapshot.windowCount >= 0,
              !snapshot.targetWindowPresent || snapshot.windowCount > 0
        else {
            return finish(.cancel)
        }
        previousObservationAt = now

        if snapshot.targetWindowPresent {
            // A window that reappears may represent a canceled close or reused AX identity.
            guard disappearanceObservedAt == nil else { return finish(.cancel) }
            return .wait
        }

        if behavior == .lastWindow && snapshot.windowCount != 0 {
            return finish(.cancel)
        }

        guard let disappearedAt = disappearanceObservedAt else {
            disappearanceObservedAt = now
            confirmationWindowCount = snapshot.windowCount
            return .wait
        }

        guard snapshot.windowCount == confirmationWindowCount else {
            return finish(.cancel)
        }

        guard now - disappearedAt >= Self.confirmationInterval,
              now - startedAt >= Self.minimumElapsedTime
        else {
            return .wait
        }
        return finish(.quit)
    }

    private mutating func finish(_ decision: CloseDecision) -> CloseDecision {
        isFinished = true
        return decision
    }
}
