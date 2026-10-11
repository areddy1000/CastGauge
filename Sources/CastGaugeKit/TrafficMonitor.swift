import Foundation
import Synchronization

/// Measures the bytes per second that Chrome sends to one address.
public final class TrafficMonitor: Sendable {
    private let process: LineProcess
    private let state: Locked<State>

    private struct State {
        var parser: TrafficParser
        var samples = 0
        var latest: (bytesPerSecond: Int, at: Date)?
    }

    public init(targetAddress: String) {
        let state = Locked(State(parser: TrafficParser(targetAddress: targetAddress)))
        self.state = state
        self.process = LineProcess(
            executable: "/usr/bin/nettop",
            arguments: ["-d", "-L", "0", "-s", "1", "-n", "-x", "-J", "bytes_out"],
            onLine: { line in
                state.withLock { s in
                    guard let bytes = s.parser.feed(line) else { return }
                    s.samples += 1
                    // The first sample holds the totals since the flow opened, not a one-second change.
                    if s.samples > 1 { s.latest = (bytes, Date()) }
                }
            }
        )
    }

    public func start() { process.start() }
    public func stop() { process.stop() }

    /// The last measured rate and its time, or nil before the first full sample.
    public var latest: (bytesPerSecond: Int, at: Date)? {
        state.withLock { $0.latest }
    }
}
