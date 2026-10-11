import Foundation

/// Measures the delay, the delay variation, and the loss to one address with `/sbin/ping`.
public final class LinkMonitor: Sendable {
    private let process: LineProcess
    private let window: Locked<LinkWindow>

    public init(targetAddress: String) {
        let window = Locked(LinkWindow())
        self.window = window
        self.process = LineProcess(
            executable: "/sbin/ping",
            arguments: ["-n", "-i", "1", targetAddress],
            onLine: { line in
                guard let event = PingEvent.parse(line) else { return }
                window.withLock { $0.add(event, at: Date()) }
            }
        )
    }

    public func start() { process.start() }
    public func stop() { process.stop() }

    /// The link values over the last 10 pings, or nil before the first result.
    public var latest: LinkStats? {
        window.withLock { $0.stats }
    }
}
