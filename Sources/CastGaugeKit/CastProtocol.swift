import Foundation

/// The Cast message namespaces that CastGauge uses.
public enum CastNamespace {
    public static let connection = "urn:x-cast:com.google.cast.tp.connection"
    public static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    public static let receiver = "urn:x-cast:com.google.cast.receiver"
    public static let media = "urn:x-cast:com.google.cast.media"
}

public enum CastProtocolError: Error {
    case malformed
}

/// One Cast V2 message with a string payload. On the wire it is a protobuf `CastMessage`
/// after a 4-byte big-endian length.
public struct CastMessage: Equatable, Sendable {
    public let source: String
    public let destination: String
    public let namespace: String
    public let payload: String

    public init(source: String, destination: String, namespace: String, payload: String) {
        self.source = source
        self.destination = destination
        self.namespace = namespace
        self.payload = payload
    }

    /// The message with its length prefix, ready to send.
    public func framed() -> Data {
        var body = Data()
        body.appendVarintField(1, 0)  // protocol_version: CASTV2_1_0
        body.appendStringField(2, source)
        body.appendStringField(3, destination)
        body.appendStringField(4, namespace)
        body.appendVarintField(5, 0)  // payload_type: STRING
        body.appendStringField(6, payload)
        var frame = withUnsafeBytes(of: UInt32(body.count).bigEndian) { Data($0) }
        frame.append(body)
        return frame
    }

    /// Decodes a message body without the length prefix. It skips fields that it does not use.
    public static func decode(_ data: Data) throws -> CastMessage {
        var reader = ProtobufReader(bytes: [UInt8](data))
        var strings: [Int: String] = [:]
        while !reader.atEnd {
            let key = try reader.varint()
            let field = Int(key >> 3)
            switch key & 7 {
            case 0: _ = try reader.varint()
            case 2: strings[field] = String(decoding: try reader.bytes(count: Int(try reader.varint())), as: UTF8.self)
            default: throw CastProtocolError.malformed
            }
        }
        return CastMessage(source: strings[2] ?? "", destination: strings[3] ?? "",
                           namespace: strings[4] ?? "", payload: strings[6] ?? "")
    }
}

struct ProtobufReader {
    let bytes: [UInt8]
    var index = 0

    var atEnd: Bool { index >= bytes.count }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < bytes.count, shift < 64 else { throw CastProtocolError.malformed }
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
    }

    mutating func bytes(count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, index + count <= bytes.count else { throw CastProtocolError.malformed }
        defer { index += count }
        return bytes[index..<index + count]
    }
}

private extension Data {
    mutating func appendVarint(_ value: UInt64) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            append(byte)
        } while value != 0
    }

    mutating func appendVarintField(_ field: Int, _ value: UInt64) {
        appendVarint(UInt64(field << 3))
        appendVarint(value)
    }

    mutating func appendStringField(_ field: Int, _ value: String) {
        let utf8 = Data(value.utf8)
        appendVarint(UInt64(field << 3 | 2))
        appendVarint(UInt64(utf8.count))
        append(utf8)
    }
}

/// The app that runs on the Cast device.
public struct CastApp: Equatable, Sendable {
    public let id: String
    public let name: String
    public let iconURL: URL?
    public let statusText: String?
    public let transportID: String?
    public let isIdleScreen: Bool
    /// The session to name in a STOP request.
    public var sessionID: String? = nil

    /// The app ID that Google TV reports for its own foreground app, for example the Apple TV app.
    public static let nativeAppID = "AndroidNativeApp"

    /// True for an app that runs on Google TV by itself. It is not a cast.
    public var isNativeApp: Bool { id == Self.nativeAppID }
}

/// Cast requests that change the device state. CastGauge sends them only when the user asks.
public enum CastCommand {
    /// Ends the app session on the receiver, the same as Stop in the Google Home app.
    public static func stop(sessionID: String, requestID: Int) -> String {
        let object: [String: Any] = ["type": "STOP", "sessionId": sessionID, "requestId": requestID]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// A `RECEIVER_STATUS` message.
public struct ReceiverStatus: Equatable, Sendable {
    /// The running app, or nil when no app runs.
    public let app: CastApp?

    public static func parse(_ json: String) -> ReceiverStatus? {
        guard let object = jsonObject(json), object["type"] as? String == "RECEIVER_STATUS",
              let status = object["status"] as? [String: Any] else { return nil }
        guard let first = (status["applications"] as? [[String: Any]])?.first,
              let id = first["appId"] as? String else {
            return ReceiverStatus(app: nil)
        }
        return ReceiverStatus(app: CastApp(
            id: id,
            name: first["displayName"] as? String ?? id,
            iconURL: (first["iconUrl"] as? String).flatMap(URL.init(string:)),
            statusText: first["statusText"] as? String,
            transportID: first["transportId"] as? String,
            isIdleScreen: first["isIdleScreen"] as? Bool ?? false,
            sessionID: first["sessionId"] as? String
        ))
    }
}

/// A `MEDIA_STATUS` message.
public enum MediaStatus {
    /// Returns the media title, or nil when the message has none.
    public static func parseTitle(_ json: String) -> String? {
        guard let object = jsonObject(json), object["type"] as? String == "MEDIA_STATUS",
              let first = (object["status"] as? [[String: Any]])?.first,
              let media = first["media"] as? [String: Any],
              let metadata = media["metadata"] as? [String: Any],
              let title = metadata["title"] as? String, !title.isEmpty else { return nil }
        return title
    }
}

/// What the menu bar shows for an app that the Cast device reports.
public struct NowPlaying: Equatable, Sendable {
    public let appName: String
    public let iconURL: URL?
    public let title: String

    public init(appName: String, iconURL: URL?, title: String) {
        self.appName = appName
        self.iconURL = iconURL
        self.title = title
    }

    /// The Chrome tab mirror apps. The menu bar shows the TV name for them, not an app.
    static let mirroringAppIDs: Set<String> = ["0F5096E8", "85CDB22F", "674A0243"]

    /// Returns what to show for an app, or nil for no app, the idle screen, a tab mirror,
    /// or a native Google TV app.
    /// Without a media title, the app name is the title.
    public static func from(app: CastApp?, mediaTitle: String?) -> NowPlaying? {
        guard let app, !app.isIdleScreen, !app.isNativeApp, !mirroringAppIDs.contains(app.id) else { return nil }
        return NowPlaying(appName: app.name, iconURL: app.iconURL, title: mediaTitle ?? app.name)
    }
}

private func jsonObject(_ json: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
}
