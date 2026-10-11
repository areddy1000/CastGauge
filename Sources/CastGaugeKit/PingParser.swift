import Foundation

/// One result line from `/sbin/ping`.
public enum PingEvent: Equatable, Sendable {
    case reply(seq: Int, ms: Double)
    case timeout(seq: Int)

    /// Reads a ping output line. It returns nil for other lines.
    public static func parse(_ line: String) -> PingEvent? {
        if line.hasPrefix("Request timeout for icmp_seq "),
           let seq = Int(line.dropFirst("Request timeout for icmp_seq ".count).trimmingCharacters(in: .whitespaces)) {
            return .timeout(seq: seq)
        }
        guard let seq = value(after: "icmp_seq=", in: line).flatMap(Int.init),
              let ms = value(after: "time=", in: line).flatMap(Double.init) else {
            return nil
        }
        return .reply(seq: seq, ms: ms)
    }

    private static func value(after key: String, in line: String) -> String? {
        guard let range = line.range(of: key) else { return nil }
        return String(line[range.upperBound...].prefix { !$0.isWhitespace })
    }
}

/// The link values over the last ping results.
public struct LinkStats: Equatable, Sendable {
    /// The average reply time in milliseconds.
    public let avgMs: Double
    /// The population standard deviation of the reply times in milliseconds.
    public let jitterMs: Double
    /// The percent of pings with no reply.
    public let lossPercent: Double
    /// The time of the newest ping result.
    public let at: Date

    public init(avgMs: Double, jitterMs: Double, lossPercent: Double, at: Date) {
        self.avgMs = avgMs
        self.jitterMs = jitterMs
        self.lossPercent = lossPercent
        self.at = at
    }
}

/// Keeps the last ping results and calculates the link values.
public struct LinkWindow: Sendable {
    private let capacity: Int
    private var events: [PingEvent] = []
    private var lastAt: Date?

    public init(capacity: Int = 30) {
        self.capacity = capacity
    }

    public mutating func add(_ event: PingEvent, at date: Date) {
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
        lastAt = date
    }

    /// The link values, or nil before the first result.
    public var stats: LinkStats? {
        guard let lastAt, !events.isEmpty else { return nil }
        let times = events.compactMap { event -> Double? in
            if case .reply(_, let ms) = event { return ms }
            return nil
        }
        let loss = Double(events.count - times.count) / Double(events.count) * 100
        guard !times.isEmpty else {
            return LinkStats(avgMs: 0, jitterMs: 0, lossPercent: loss, at: lastAt)
        }
        let avg = times.reduce(0, +) / Double(times.count)
        let variance = times.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(times.count)
        return LinkStats(avgMs: avg, jitterMs: variance.squareRoot(), lossPercent: loss, at: lastAt)
    }
}
