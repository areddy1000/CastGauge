import AppKit
import Foundation

/// The Chrome operations that the controller needs. Tests use a stand-in.
public protocol ChromeApp: Sendable {
    /// The pid of the main Chrome process, or nil when Chrome is not running.
    var pid: pid_t? { get }
    /// Asks Chrome to quit, the same as Cmd-Q.
    func terminate() -> Bool
    func isRunning() -> Bool
    func launch(arguments: [String]) throws
}

/// What the running Chrome uses.
public enum ChromeState: Equatable, Sendable {
    case notRunning
    /// Chrome runs, but CastGauge did not start it.
    case inactive
    /// Chrome runs with these CastGauge settings.
    case active(MirrorSettings)
}

public enum RestartError: Error, Equatable, Sendable {
    case chromeStayedOpen
    case launchFailed(String)
}

/// The real Google Chrome on this Mac.
public struct SystemChrome: ChromeApp {
    static let bundleID = "com.google.Chrome"

    public init() {}

    private var apps: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
    }

    public var pid: pid_t? {
        apps.first { !$0.isTerminated }?.processIdentifier
    }

    public func terminate() -> Bool {
        apps.reduce(false) { $0 || $1.terminate() }
    }

    public func isRunning() -> Bool {
        // The app list can lag, so check each process directly.
        apps.contains { kill($0.processIdentifier, 0) == 0 }
    }

    public func launch(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw RestartError.launchFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw RestartError.launchFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// Reads the Chrome settings and restarts Chrome with new ones.
public struct ChromeController: Sendable {
    private let app: ChromeApp
    private let quitTimeout: Duration

    public init(app: ChromeApp = SystemChrome(), quitTimeout: Duration = .seconds(20)) {
        self.app = app
        self.quitTimeout = quitTimeout
    }

    /// Reads the state from the command line of the running Chrome.
    public func state() -> ChromeState {
        Self.state(fromArguments: app.pid.flatMap(ProcessArguments.read(pid:)))
    }

    public static func state(fromArguments arguments: [String]?) -> ChromeState {
        guard let arguments else { return .notRunning }
        guard let settings = MirrorSettings.parse(chromeArguments: arguments) else { return .inactive }
        return .active(settings)
    }

    /// Quits Chrome in the normal way and starts it with the settings.
    /// It never force quits. When Chrome stays open, it throws `chromeStayedOpen`.
    public func restart(with settings: MirrorSettings) async throws {
        if app.isRunning() {
            _ = app.terminate()
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: quitTimeout)
            while app.isRunning() {
                guard clock.now < deadline else { throw RestartError.chromeStayedOpen }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        try app.launch(arguments: settings.clamped().openArguments())
    }
}
