import Foundation

/// Turns nettop lines into the latest bytes per second.
/// The first full sample after each launch holds the totals since the flow opened, so it is skipped.
struct TrafficAccumulator: Sendable {
    private let targetAddress: String
    private var parser: TrafficParser
    private var samples = 0
    private(set) var latest: (bytesPerSecond: Int, at: Date)?

    init(targetAddress: String) {
        self.targetAddress = targetAddress
        parser = TrafficParser(targetAddress: targetAddress)
    }

    /// Starts again for a new nettop process. The last value stays until a real sample replaces it.
    mutating func launched() {
        parser = TrafficParser(targetAddress: targetAddress)
        samples = 0
    }

    mutating func feed(_ line: String, at date: Date) {
        guard let bytes = parser.feed(line) else { return }
        samples += 1
        if samples > 1 { latest = (bytes, date) }
    }
}

/// Measures the bytes per second that Chrome sends to one address.
public final class TrafficMonitor: Sendable {
    private let process: LineProcess
    private let state: Locked<TrafficAccumulator>

    public init(targetAddress: String) {
        let state = Locked(TrafficAccumulator(targetAddress: targetAddress))
        self.state = state
        self.process = LineProcess(
            executable: "/usr/bin/nettop",
            arguments: ["-d", "-L", "0", "-s", "1", "-n", "-x", "-J", "bytes_out"],
            onLaunch: { state.withLock { $0.launched() } },
            onLine: { line in state.withLock { $0.feed(line, at: Date()) } }
        )
    }

    public func start() { process.start() }
    public func stop() { process.stop() }

    /// The last measured rate and its time, or nil before the first full sample.
    public var latest: (bytesPerSecond: Int, at: Date)? {
        state.withLock { $0.latest }
    }
}
