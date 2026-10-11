import Foundation

/// Runs a command-line tool and sends each output line to a handler.
/// When the tool exits, it starts the tool again after a pause, until `stop()`.
/// When the tool writes nothing for the silence limit, it stops the tool, so the restart applies.
public final class LineProcess: Sendable {
    private let executable: String
    private let arguments: [String]
    private let silenceLimit: Duration
    private let restartDelay: Duration
    private let onLaunch: @Sendable () -> Void
    private let onLine: @Sendable (String) -> Void
    private let state = Locked(State())
    private let queue = DispatchQueue(label: "LineProcess")

    private struct State: @unchecked Sendable {
        var process: Process?
        var running = false
        var buffer = Data()
        var lastOutput = Date()
    }

    public init(
        executable: String,
        arguments: [String],
        silenceLimit: Duration = .seconds(5),
        restartDelay: Duration = .seconds(2),
        onLaunch: @Sendable @escaping () -> Void = {},
        onLine: @Sendable @escaping (String) -> Void
    ) {
        self.executable = executable
        self.arguments = arguments
        self.silenceLimit = silenceLimit
        self.restartDelay = restartDelay
        self.onLaunch = onLaunch
        self.onLine = onLine
    }

    public func start() {
        let shouldLaunch = state.withLock { s -> Bool in
            guard !s.running else { return false }
            s.running = true
            return true
        }
        if shouldLaunch { launch() }
    }

    public func stop() {
        let process = state.withLock { s -> Process? in
            s.running = false
            defer { s.process = nil }
            return s.process
        }
        if let process, process.isRunning { process.terminate() }
    }

    private func launch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // A GUI app has /dev/null as stdin. A tool that reads stdin gets EOF at once and can
        // spin on it, so give it an open pipe. The process keeps the pipe until it ends.
        process.standardInput = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            // Empty data means EOF. Without this, the handler runs again and again until exit.
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.receive(chunk)
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
            let again = self.state.withLock { s -> Bool in
                s.buffer.removeAll()
                return s.running
            }
            if again { self.relaunchLater() }
        }
        // The monitor resets its own state here, because a new process starts its counts again.
        onLaunch()
        do {
            try process.run()
        } catch {
            relaunchLater()
            return
        }
        let keep = state.withLock { s -> Bool in
            // stop() can come while the tool starts. Then the new process must not stay.
            guard s.running else { return false }
            s.process = process
            s.lastOutput = Date()
            return true
        }
        if keep {
            watch(process)
        } else {
            process.terminate()
        }
    }

    private func relaunchLater() {
        queue.asyncAfter(deadline: .now() + restartDelay.timeInterval) { [weak self] in
            guard let self, self.state.withLock({ $0.running }) else { return }
            self.launch()
        }
    }

    /// Stops a tool that writes nothing for the silence limit. The exit then starts it again.
    private func watch(_ process: Process) {
        let interval = silenceLimit.timeInterval / 2
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            let silent = self.state.withLock { s -> Bool? in
                guard s.running, s.process === process, process.isRunning else { return nil }
                return Date().timeIntervalSince(s.lastOutput) > self.silenceLimit.timeInterval
            }
            switch silent {
            case true?: process.terminate()
            case false?: self.watch(process)
            case nil: break
            }
        }
    }

    private func receive(_ chunk: Data) {
        let lines = state.withLock { s -> [String] in
            s.lastOutput = Date()
            s.buffer.append(chunk)
            var lines: [String] = []
            while let newline = s.buffer.firstIndex(of: 0x0A) {
                let line = s.buffer[s.buffer.startIndex..<newline]
                lines.append(String(decoding: line, as: UTF8.self))
                s.buffer.removeSubrange(s.buffer.startIndex...newline)
            }
            return lines
        }
        lines.forEach(onLine)
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
