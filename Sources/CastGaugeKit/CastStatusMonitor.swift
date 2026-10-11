import Foundation
import Network
import Security

/// Reads the running app and the media title from a Cast device on port 8009.
/// It only reads. It never sends a playback command.
public final class CastStatusMonitor: Sendable {
    private let address: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "CastStatusMonitor")
    private let state = Locked(State())
    private static let sender = "sender-castgauge"
    private static let receiver = "receiver-0"

    private struct State: @unchecked Sendable {
        var connection: NWConnection?
        var running = false
        var buffer = Data()
        var app: CastApp?
        var mediaTitle: String?
        var mediaTransport: String?
        var requestID = 0
        var backoff = Backoff()
    }

    /// `onChange` runs after the app or the title changes, so the app needs no timer to watch it.
    public init(address: String, onChange: @escaping @Sendable () -> Void = {}) {
        self.address = address
        self.onChange = onChange
    }

    public func start() {
        let start = state.withLock { s -> Bool in
            guard !s.running else { return false }
            s.running = true
            return true
        }
        if start { connect() }
    }

    public func stop() {
        let connection = state.withLock { s -> NWConnection? in
            s.running = false
            defer { s.connection = nil }
            return s.connection
        }
        connection?.cancel()
    }

    /// What the device plays now, or nil for no app, the idle screen, or a tab mirror.
    public var nowPlaying: NowPlaying? {
        state.withLock { NowPlaying.from(app: $0.app, mediaTitle: $0.mediaTitle) }
    }

    /// The app that the device reports, including a tab mirror or a native Google TV app.
    public var app: CastApp? {
        state.withLock { $0.app }
    }

    private func connect() {
        // The Cast device uses a self-signed certificate. CastGauge only reads public status,
        // so it accepts the certificate without the Cast device authentication.
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
        let connection = NWConnection(host: NWEndpoint.Host(address), port: 8009,
                                      using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                self.state.withLock { $0.backoff.reset() }
                self.send(namespace: CastNamespace.connection, to: Self.receiver, ["type": "CONNECT"])
                self.send(namespace: CastNamespace.receiver, to: Self.receiver, ["type": "GET_STATUS"])
                self.receive(on: connection)
                self.heartbeat(on: connection)
            case .failed, .waiting:
                connection.cancel()
                self.reconnectLater(after: connection)
            default:
                break
            }
        }
        state.withLock { s in
            s.connection = connection
            s.buffer.removeAll()
        }
        connection.start(queue: queue)
    }

    private func reconnectLater(after old: NWConnection) {
        let delay = state.withLock { s -> TimeInterval? in
            guard s.connection === old else { return nil }
            s.connection = nil
            s.app = nil
            s.mediaTitle = nil
            s.mediaTransport = nil
            // An unreachable TV gets a growing wait, not a new attempt every few seconds.
            return s.running ? s.backoff.next() : nil
        }
        guard let delay else { return }
        onChange()
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.state.withLock({ $0.running && $0.connection == nil }) else { return }
            self.connect()
        }
    }

    /// The device closes a channel with no traffic, so send a PING every 5 seconds.
    private func heartbeat(on connection: NWConnection) {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.state.withLock({ $0.connection === connection }) else { return }
            self.send(namespace: CastNamespace.heartbeat, to: Self.receiver, ["type": "PING"])
            self.heartbeat(on: connection)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.consume(data) }
            if isComplete || error != nil {
                connection.cancel()
                self.reconnectLater(after: connection)
            } else {
                self.receive(on: connection)
            }
        }
    }

    private func consume(_ data: Data) {
        let (messages, broken, connection) = state.withLock { s -> ([CastMessage], Bool, NWConnection?) in
            s.buffer.append(data)
            var messages: [CastMessage] = []
            var index = s.buffer.startIndex
            while s.buffer.endIndex - index >= 4 {
                let length = s.buffer[index..<index + 4].reduce(0) { $0 << 8 | Int($1) }
                // The Cast protocol limits a message to 64 KiB. A larger length is a broken stream.
                guard length <= 65_536 else { return ([], true, s.connection) }
                guard s.buffer.endIndex - index >= 4 + length else { break }
                if let message = try? CastMessage.decode(Data(s.buffer[index + 4..<index + 4 + length])) {
                    messages.append(message)
                }
                index += 4 + length
            }
            s.buffer.removeSubrange(s.buffer.startIndex..<index)
            return (messages, false, s.connection)
        }
        if broken, let connection {
            connection.cancel()
            reconnectLater(after: connection)
            return
        }
        messages.forEach(handle)
    }

    private func handle(_ message: CastMessage) {
        switch message.namespace {
        case CastNamespace.heartbeat where message.payload.contains(#""PING""#):
            send(namespace: CastNamespace.heartbeat, to: message.source, ["type": "PONG"])
        case CastNamespace.receiver:
            guard let status = ReceiverStatus.parse(message.payload) else { return }
            let transport = state.withLock { s -> String? in
                if s.app?.id != status.app?.id { s.mediaTitle = nil }
                s.app = status.app
                // Ask for the media status one time for each app session.
                guard let transport = status.app?.transportID, transport != s.mediaTransport,
                      NowPlaying.from(app: status.app, mediaTitle: nil) != nil else { return nil }
                s.mediaTransport = transport
                return transport
            }
            if let transport {
                send(namespace: CastNamespace.connection, to: transport, ["type": "CONNECT"])
                send(namespace: CastNamespace.media, to: transport, ["type": "GET_STATUS"])
            }
            onChange()
        case CastNamespace.media:
            if let title = MediaStatus.parseTitle(message.payload) {
                state.withLock { $0.mediaTitle = title }
                onChange()
            }
        default:
            break
        }
    }

    private func send(namespace: String, to destination: String, _ body: [String: Any]) {
        let (connection, payload) = state.withLock { s -> (NWConnection?, [String: Any]) in
            var body = body
            if namespace != CastNamespace.connection && namespace != CastNamespace.heartbeat {
                s.requestID += 1
                body["requestId"] = s.requestID
            }
            return (s.connection, body)
        }
        guard let connection,
              let json = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let message = CastMessage(source: Self.sender, destination: destination, namespace: namespace,
                                  payload: String(decoding: json, as: UTF8.self))
        connection.send(content: message.framed(), completion: .contentProcessed { _ in })
    }
}
