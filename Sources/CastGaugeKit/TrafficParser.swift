import Foundation

/// Reads `nettop -d -x -n -J bytes_out` output.
/// It adds the bytes that a Chrome process sends to one address in each sample.
/// It also adds unconnected UDP flows, because the cast stream uses one.
public struct TrafficParser: Sendable {
    private let targetAddress: String
    private let processPrefix: String
    private var inSample = false
    private var processMatches = false
    private var total = 0

    public init(targetAddress: String, processPrefix: String = "Google Chrome") {
        self.targetAddress = targetAddress
        self.processPrefix = processPrefix
    }

    /// Reads one line. It returns the total of the sample that this line closes, or nil.
    public mutating func feed(_ line: String) -> Int? {
        let line = line.trimmingCharacters(in: .whitespaces)
        // A header line starts each sample, so it also closes the previous one.
        if line.hasPrefix(",") {
            defer {
                inSample = true
                processMatches = false
                total = 0
            }
            return inSample ? total : nil
        }
        guard inSample else { return nil }
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 2, let bytes = Int(fields[1]) else { return nil }
        let name = String(fields[0])

        if let arrow = name.range(of: "<->") {
            guard processMatches else { return nil }
            let local = name[..<arrow.lowerBound]
            let remote = name[arrow.upperBound...]
            if host(of: remote) == targetAddress || isCastStream(local: local, remote: remote) {
                total += bytes
            }
        } else {
            processMatches = name.hasPrefix(processPrefix)
        }
        return nil
    }

    /// Chrome sends the cast stream from an unconnected UDP socket, so nettop shows `*:*` as the remote.
    /// The mDNS socket (port 5353) is also unconnected, so it is left out.
    private func isCastStream(local: Substring, remote: Substring) -> Bool {
        local.hasPrefix("udp") && remote == "*:*" && !local.hasSuffix(":5353")
    }

    /// Removes the port from an endpoint such as `192.168.1.155:38429`.
    private func host(of endpoint: Substring) -> String {
        guard let colon = endpoint.lastIndex(of: ":") else { return String(endpoint) }
        return String(endpoint[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }
}
