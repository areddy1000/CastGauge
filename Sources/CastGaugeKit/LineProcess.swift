import Foundation
import Synchronization

/// Runs a command-line tool and sends each output line to a handler.
/// When the tool exits, it starts the tool again after 2 seconds, until `stop()`.
public final class LineProcess: Sendable {
    private let executable: String
    private let arguments: [String]
    private let onLine: @Sendable (String) -> Void
    private let state = Mutex(State())

    private struct State {
        var process: Process?
        var running = false
        var buffer = Data()
    }

    public init(executable: String, arguments: [String], onLine: @Sendable @escaping (String) -> Void) {
        self.executable = executable
        self.arguments = arguments
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
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            self.receive(chunk)
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
            let again = self.state.withLock { s -> Bool in
                s.buffer.removeAll()
                return s.running
            }
            guard again else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.state.withLock({ $0.running }) else { return }
                self.launch()
            }
        }
        let started: Bool
        do {
            try process.run()
            started = true
        } catch {
            started = false
        }
        state.withLock { $0.process = started ? process : nil }
        if !started {
            // The tool did not start. Try again after the same pause as after an exit.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.state.withLock({ $0.running }) else { return }
                self.launch()
            }
        }
    }

    private func receive(_ chunk: Data) {
        let lines = state.withLock { s -> [String] in
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
