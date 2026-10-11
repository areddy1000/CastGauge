import Foundation
import Network

public enum CastStopError: Error, Equatable {
    case noSession
    case timeout
}

/// Ends the running app session on one Cast device, the same as Stop in the Google Home app.
/// It opens a short connection only for this request, and closes it after.
public enum CastStopper {
    public static func stop(address: String, timeout: Duration = .seconds(5)) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            StopSession(address: address, timeout: timeout, continuation: continuation).start()
        }
    }
}

/// One Stop request. All its state stays on its serial queue.
private final class StopSession: @unchecked Sendable {
    private static let sender = "sender-castgauge-stop"
    private static let receiver = "receiver-0"
    private let queue = DispatchQueue(label: "CastStopper")
    private let connection: NWConnection
    private let timeout: Duration
    private var continuation: CheckedContinuation<Void, Error>?
    private var buffer = Data()

    init(address: String, timeout: Duration, continuation: CheckedContinuation<Void, Error>) {
        let tls = NWProtocolTLS.Options()
        // The same rule as CastStatusMonitor: the device has a self-signed certificate.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
        connection = NWConnection(host: NWEndpoint.Host(address), port: 8009,
                                  using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
        self.timeout = timeout
        self.continuation = continuation
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                send(CastNamespace.connection, #"{"type":"CONNECT"}"#)
                send(CastNamespace.receiver, #"{"type":"GET_STATUS","requestId":1}"#)
                receive()
            case .failed(let error), .waiting(let error):
                complete(.failure(error))
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout.timeInterval) { [self] in complete(.failure(CastStopError.timeout)) }
    }

    /// Runs on the queue. The first result wins, and the connection closes, which ends the cycle.
    private func complete(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(with: result)
    }

    private func send(_ namespace: String, _ payload: String) {
        let message = CastMessage(source: Self.sender, destination: Self.receiver, namespace: namespace, payload: payload)
        connection.send(content: message.framed(), completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            guard continuation != nil else { return }
            if let data { buffer.append(data) }
            while buffer.count >= 4 {
                let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
                guard length <= 65_536 else { return complete(.failure(CastProtocolError.malformed)) }
                guard buffer.count >= 4 + length else { break }
                let body = Data(buffer.dropFirst(4).prefix(length))
                buffer = Data(buffer.dropFirst(4 + length))
                guard let message = try? CastMessage.decode(body),
                      message.namespace == CastNamespace.receiver,
                      let status = ReceiverStatus.parse(message.payload) else { continue }
                guard let app = status.app, !app.isIdleScreen, let session = app.sessionID else {
                    return complete(.failure(CastStopError.noSession))
                }
                send(CastNamespace.receiver, CastCommand.stop(sessionID: session, requestID: 2))
                // Give the request a moment to leave before the connection closes.
                queue.asyncAfter(deadline: .now() + 0.3) { [self] in complete(.success(())) }
                return
            }
            if isComplete || error != nil {
                complete(.failure(error ?? CastStopError.noSession))
            } else {
                receive()
            }
        }
    }
}
