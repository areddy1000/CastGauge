import Darwin
import Foundation

/// Turns a 32-bit byte counter into bytes per second.
public struct RateMeter: Sendable {
    private var last: (bytes: UInt32, at: Date)?

    public init() {}

    /// Returns the rate since the last sample, or nil for the first sample or a gap under 0.2 s.
    public mutating func sample(bytes: UInt32, at date: Date) -> Int? {
        defer { last = (bytes, date) }
        guard let last else { return nil }
        let seconds = date.timeIntervalSince(last.at)
        guard seconds >= 0.2 else { return nil }
        // Wrapping subtraction gives the right count after the counter passes UInt32.max.
        return Int((Double(bytes &- last.bytes) / seconds).rounded())
    }
}

/// Measures the upload rate of the network interface that reaches one address.
///
/// It reads the interface byte counter, so it costs almost no CPU and starts no process.
/// It counts all the Mac uploads on that interface. During a tab cast, the cast stream is
/// almost all of them.
public final class InterfaceTraffic: Sendable {
    private let targetAddress: String
    private let state = Locked(State())

    private struct State: Sendable {
        var meter = RateMeter()
        var latest: (bytesPerSecond: Int, at: Date)?
    }

    public init(targetAddress: String) {
        self.targetAddress = targetAddress
    }

    /// Reads the counter one time. The caller calls it once per sample, for example each second.
    public func sample(at date: Date = Date()) {
        guard let bytes = Self.outputBytes(toward: targetAddress) else { return }
        state.withLock { s in
            if let rate = s.meter.sample(bytes: bytes, at: date) { s.latest = (rate, date) }
        }
    }

    /// The last measured rate and its time, or nil before the second sample.
    public var latest: (bytesPerSecond: Int, at: Date)? {
        state.withLock { $0.latest }
    }

    /// The output byte counter of the interface whose IPv4 subnet holds the address.
    static func outputBytes(toward address: String) -> UInt32? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }

        var name: String?
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let item = entry.pointee
            guard let addr = item.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let mask = item.ifa_netmask,
                  let local = ipv4(addr), let netmask = ipv4(mask),
                  sameSubnet(local, address, mask: netmask) else { continue }
            name = String(cString: item.ifa_name)
            break
        }
        guard let name else { return nil }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let item = entry.pointee
            guard let addr = item.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: item.ifa_name) == name,
                  let data = item.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            return data.pointee.ifi_obytes
        }
        return nil
    }

    static func sameSubnet(_ a: String, _ b: String, mask: String) -> Bool {
        guard let a = parse(a), let b = parse(b), let mask = parse(mask) else { return false }
        return a & mask == b & mask
    }

    private static func parse(_ text: String) -> UInt32? {
        var value = in_addr()
        guard inet_pton(AF_INET, text, &value) == 1 else { return nil }
        return UInt32(bigEndian: value.s_addr)
    }

    private static func ipv4(_ pointer: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let result = pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin -> UnsafePointer<CChar>? in
            var address = sin.pointee.sin_addr
            return inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN))
        }
        guard result != nil else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
