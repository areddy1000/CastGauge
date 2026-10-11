import Darwin
import Foundation

/// Reads the command line of a running process.
public enum ProcessArguments {
    /// Reads the arguments of a process with `sysctl` and `KERN_PROCARGS2`.
    /// It returns nil when the process is gone or macOS refuses the request.
    public static func read(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parse(procargs2: Data(buffer.prefix(size)))
    }

    /// Parses `KERN_PROCARGS2` data: a 4-byte argc, the executable path, NUL padding,
    /// then argc NUL-terminated arguments. The environment follows and is ignored.
    public static func parse(procargs2 data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let argc = Int(bytes[0..<4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self).littleEndian })
        var index = 4
        // Skip the executable path and its padding.
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        var arguments: [String] = []
        while arguments.count < argc, index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            arguments.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments.count == argc ? arguments : nil
    }
}
