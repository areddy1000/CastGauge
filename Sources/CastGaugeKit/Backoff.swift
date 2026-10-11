import Foundation

/// The wait before the next retry. It doubles after each failure, up to a limit.
public struct Backoff: Sendable {
    private let initial: TimeInterval
    private let limit: TimeInterval
    private var current: TimeInterval?

    public init(initial: TimeInterval = 5, limit: TimeInterval = 300) {
        self.initial = initial
        self.limit = limit
    }

    /// Returns the wait for this retry, and doubles it for the next one.
    public mutating func next() -> TimeInterval {
        let delay = current.map { min($0 * 2, limit) } ?? initial
        current = delay
        return delay
    }

    /// Starts again from the first wait, for example after a success.
    public mutating func reset() {
        current = nil
    }
}
