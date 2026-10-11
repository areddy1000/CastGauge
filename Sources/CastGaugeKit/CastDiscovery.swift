import Foundation
import Network

/// A Cast device that announces `_googlecast._tcp` on the local network.
public struct CastDevice: Equatable, Sendable {
    public let id: String
    public let name: String
    /// True when the device shows a Chrome tab mirror now.
    public let isMirroring: Bool
    /// The IPv4 address, after the resolve step.
    public var address: String?
    /// The status text of the running app, from the `rs` record. Empty or nil when idle.
    public var statusText: String?

    public init(id: String, name: String, isMirroring: Bool, address: String?, statusText: String? = nil) {
        self.id = id
        self.name = name
        self.isMirroring = isMirroring
        self.address = address
        self.statusText = statusText
    }

    /// What the device does now, from its Bonjour record. The list needs no connection for it.
    public enum Activity: Equatable, Sendable {
        case idle
        case castingTab
        case app(String)
    }

    public var activity: Activity {
        if isMirroring { return .castingTab }
        guard let text = statusText, !text.isEmpty else { return .idle }
        return .app(text)
    }

    /// Makes a device from the Bonjour TXT record. It needs `id` and `fn`.
    public static func from(txt: [String: String]) -> CastDevice? {
        guard let id = txt["id"], let name = txt["fn"] else { return nil }
        return CastDevice(id: id, name: name, isMirroring: txt["rs"] == "Chrome Mirroring", address: nil,
                          statusText: txt["rs"])
    }

    /// Returns the first device that mirrors a Chrome tab, or nil.
    public static func pick(_ devices: [CastDevice]) -> CastDevice? {
        devices.first { $0.isMirroring }
    }
}

/// Finds Cast devices with Bonjour and resolves their IPv4 addresses.
public final class CastDiscovery: Sendable {
    private let queue = DispatchQueue(label: "CastDiscovery")
    private let state = Locked(State())

    private struct State: @unchecked Sendable {
        var browser: NWBrowser?
        var devices: [String: CastDevice] = [:]
        var addresses: [String: String] = [:]
        var resolving: [String: UUID] = [:]
        var endpoints: [String: NWEndpoint] = [:]
        var permissionDenied = false
    }

    public init() {}

    public func start() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            // macOS refuses the browse when the user turned off Local Network access.
            let denied: Bool
            if case .waiting(let error) = newState, case .dns(let code) = error, code == kDNSServiceErr_PolicyDenied {
                denied = true
            } else {
                denied = false
            }
            self.state.withLock { $0.permissionDenied = denied }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.update(results)
        }
        state.withLock { $0.browser = browser }
        browser.start(queue: queue)
    }

    public func stop() {
        let browser = state.withLock { s -> NWBrowser? in
            defer { s.browser = nil }
            return s.browser
        }
        browser?.cancel()
    }

    /// The devices that the browser sees now, with the addresses that are resolved.
    public var devices: [CastDevice] {
        state.withLock { s in
            s.devices.values
                .map { device in
                    var device = device
                    device.address = s.addresses[device.id]
                    return device
                }
                .sorted { $0.name < $1.name }
        }
    }

    /// True when macOS refuses Local Network access.
    public var permissionDenied: Bool {
        state.withLock { $0.permissionDenied }
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [String: (CastDevice, NWEndpoint)] = [:]
        for result in results {
            guard case .bonjour(let txt) = result.metadata,
                  let device = CastDevice.from(txt: txt.dictionary) else { continue }
            found[device.id] = (device, result.endpoint)
        }
        let toResolve = state.withLock { s -> [(String, NWEndpoint)] in
            s.devices = found.mapValues(\.0)
            s.endpoints = found.mapValues(\.1)
            s.addresses = s.addresses.filter { found[$0.key] != nil }
            let missing = found.filter { s.addresses[$0.key] == nil && s.resolving[$0.key] == nil }
            return missing.map { ($0.key, $0.value.1) }
        }
        for (id, endpoint) in toResolve {
            resolve(id: id, endpoint: endpoint)
        }
    }

    /// Tries the resolve again after 3 seconds, while the device is still in the browse results.
    private func retry(id: String) {
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            let endpoint = self.state.withLock { s -> NWEndpoint? in
                guard s.browser != nil, s.addresses[id] == nil, s.resolving[id] == nil,
                      let endpoint = s.endpoints[id] else { return nil }
                return endpoint
            }
            if let endpoint { self.resolve(id: id, endpoint: endpoint) }
        }
    }

    /// Opens a short TCP connection to the service to learn its IPv4 address.
    /// Each attempt has a token, so a late event from an old attempt changes nothing.
    private func resolve(id: String, endpoint: NWEndpoint) {
        let token = UUID()
        state.withLock { $0.resolving[id] = token }
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                var address: String?
                if case .hostPort(let host, _)? = connection.currentPath?.remoteEndpoint {
                    address = "\(host)".split(separator: "%").first.map(String.init)
                }
                connection.cancel()
                self?.finish(id: id, token: token, address: address, error: nil)
            case .failed(let error), .waiting(let error):
                connection.cancel()
                self?.finish(id: id, token: token, address: nil, error: error)
            default:
                break
            }
        }
        connection.start(queue: queue)
        // A connection can wait with no event, for example while macOS asks for Local Network access.
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard connection.state != .ready else { return }
            connection.cancel()
            self?.finish(id: id, token: token, address: nil, error: nil)
        }
    }

    private func finish(id: String, token: UUID, address: String?, error: NWError?) {
        let current = state.withLock { s -> Bool in
            guard s.resolving[id] == token else { return false }
            s.resolving[id] = nil
            if let address {
                s.addresses[id] = address
                s.permissionDenied = false
            } else if case .dns(let code)? = error, code == kDNSServiceErr_PolicyDenied {
                // macOS refuses local connections when Local Network access is off.
                s.permissionDenied = true
            }
            return true
        }
        if current && address == nil { retry(id: id) }
    }
}
