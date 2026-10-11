import Foundation

/// The health of the cast, for the menu bar dot and the status chip.
public enum Health: Equatable, Sendable {
    case notCasting, good, unstable, losingData

    /// Classifies a snapshot. A rate below the maximum alone is never a warning,
    /// because the encoder sends less data for still content.
    public static func classify(_ s: Snapshot, _ t: HealthThresholds = .standard) -> Health {
        guard s.casting else { return .notCasting }
        // Without fresh link values, the app cannot say that the link is good.
        guard let link = s.link else { return .unstable }
        if link.lossPercent >= t.lossPercent { return .losingData }
        if link.avgMs >= t.delayMs || link.jitterMs >= t.jitterMs { return .unstable }
        if let rate = s.rateBps, let previous = s.previousRateBps, previous > 0,
           Double(rate) < Double(previous) * t.suddenDropRatio,
           link.avgMs > t.delayMs / 2 {
            return .unstable
        }
        return .good
    }
}

/// The limits for each health state. Tune them here.
public struct HealthThresholds: Sendable {
    public var lossPercent = 2.0
    public var delayMs = 50.0
    public var jitterMs = 20.0
    public var suddenDropRatio = 0.5

    public static let standard = HealthThresholds()
}

/// The measured values at one moment. A value older than 3 seconds is nil.
public struct Snapshot: Equatable, Sendable {
    public let casting: Bool
    public let rateBps: Int?
    public let previousRateBps: Int?
    public let link: LinkStats?

    public init(casting: Bool, rateBps: Int?, previousRateBps: Int?, link: LinkStats?) {
        self.casting = casting
        self.rateBps = rateBps
        self.previousRateBps = previousRateBps
        self.link = link
    }

    static let maxAge: TimeInterval = 3

    /// Makes a snapshot and removes each value older than 3 seconds, so a stale value never shows.
    public static func make(
        casting: Bool,
        rate: (bytesPerSecond: Int, at: Date)?,
        previous: (bytesPerSecond: Int, at: Date)?,
        link: LinkStats?,
        now: Date
    ) -> Snapshot {
        func fresh(_ date: Date) -> Bool { now.timeIntervalSince(date) <= maxAge }
        return Snapshot(
            casting: casting,
            rateBps: rate.flatMap { fresh($0.at) ? $0.bytesPerSecond : nil },
            previousRateBps: previous.flatMap { fresh($0.at) ? $0.bytesPerSecond : nil },
            link: link.flatMap { fresh($0.at) ? $0 : nil }
        )
    }
}
