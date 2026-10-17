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

/// What was observed when a verified close attempt could no longer safely request a quit.
/// None of these reasons implies that the user canceled a save dialog.
public enum CloseCancellationReason: Equatable, Sendable {
    case remainingWindows
    case blockingUI
    case replacementWindow
    case unreliableSnapshot
    case windowSetChanged
    case expired
    case invalidTiming
    case alreadyFinished
}

public enum CloseDecision: Equatable, Sendable {
    case wait
    case cancel(CloseCancellationReason)
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
    private var finishedReason: CloseCancellationReason?

    public init(behavior: CloseBehavior, startedAt: TimeInterval) {
        self.behavior = behavior
        self.startedAt = startedAt
        self.previousObservationAt = startedAt
    }

    public mutating func evaluate(snapshot: CloseSnapshot, now: TimeInterval) -> CloseDecision {
        if let finishedReason { return .cancel(finishedReason) }

        guard startedAt.isFinite,
              now.isFinite,
              now >= previousObservationAt
        else { return cancel(.invalidTiming) }
        guard now - startedAt < Self.maximumDuration else { return cancel(.expired) }
        guard snapshot.isReliable,
              snapshot.windowCount >= 0,
              !snapshot.targetWindowPresent || snapshot.windowCount > 0
        else { return cancel(.unreliableSnapshot) }
        guard !snapshot.hasBlockingUI else { return cancel(.blockingUI) }
        guard !snapshot.hasReplacementWindow else { return cancel(.replacementWindow) }
        previousObservationAt = now

        if snapshot.targetWindowPresent {
            // A window that reappears may represent a canceled close or reused AX identity.
            guard disappearanceObservedAt == nil else { return cancel(.windowSetChanged) }
            return .wait
        }

        if behavior == .lastWindow && snapshot.windowCount != 0 {
            return cancel(.remainingWindows)
        }

        guard let disappearedAt = disappearanceObservedAt else {
            disappearanceObservedAt = now
            confirmationWindowCount = snapshot.windowCount
            return .wait
        }

        guard snapshot.windowCount == confirmationWindowCount else {
            return cancel(.windowSetChanged)
        }

        guard now - disappearedAt >= Self.confirmationInterval,
              now - startedAt >= Self.minimumElapsedTime
        else {
            return .wait
        }
        finishedReason = .alreadyFinished
        return .quit
    }

    private mutating func cancel(_ reason: CloseCancellationReason) -> CloseDecision {
        finishedReason = reason
        return .cancel(reason)
    }
}
