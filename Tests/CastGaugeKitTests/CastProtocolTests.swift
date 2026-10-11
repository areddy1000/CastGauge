import Foundation
import Testing
@testable import CastGaugeKit

@Suite("CastProtocol")
struct CastProtocolTests {
    @Test func messageRoundTrips() throws {
        let message = CastMessage(source: "sender-0", destination: "receiver-0",
                                  namespace: CastNamespace.receiver, payload: #"{"type":"GET_STATUS","requestId":1}"#)
        let frame = message.framed()
        // A frame starts with a 4-byte big-endian length.
        let length = frame.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        #expect(length == frame.count - 4)
        #expect(try CastMessage.decode(frame.dropFirst(4)) == message)
    }

    @Test func decodesKnownBytes() throws {
        // protocol_version 0, source "a", destination "b", namespace "n", payload_type 0, payload "p".
        let bytes: [UInt8] = [0x08, 0x00, 0x12, 0x01, 0x61, 0x1A, 0x01, 0x62, 0x22, 0x01, 0x6E,
                              0x28, 0x00, 0x32, 0x01, 0x70]
        #expect(try CastMessage.decode(Data(bytes)) == CastMessage(source: "a", destination: "b", namespace: "n", payload: "p"))
    }

    @Test func parsesYouTubeStatus() throws {
        let json = #"""
        {"requestId":1,"status":{"applications":[{"appId":"233637DE","displayName":"YouTube",
        "iconUrl":"https://example.com/yt.png","isIdleScreen":false,"statusText":"YouTube",
        "transportId":"web-5"}],"volume":{"level":1.0}},"type":"RECEIVER_STATUS"}
        """#
        let app = try #require(ReceiverStatus.parse(json)?.app)
        #expect(app == CastApp(id: "233637DE", name: "YouTube", iconURL: URL(string: "https://example.com/yt.png"),
                               statusText: "YouTube", transportID: "web-5", isIdleScreen: false))
    }

    @Test func parsesIdleStatus() {
        let json = #"{"status":{"volume":{"level":1}},"type":"RECEIVER_STATUS"}"#
        #expect(ReceiverStatus.parse(json) != nil)
        #expect(ReceiverStatus.parse(json)?.app == nil)
    }

    @Test func parsesMediaTitle() {
        let json = #"""
        {"type":"MEDIA_STATUS","status":[{"mediaSessionId":1,"media":{"metadata":
        {"title":"Big Buck Bunny","images":[{"url":"https://example.com/a.jpg"}]}}}]}
        """#
        #expect(MediaStatus.parseTitle(json) == "Big Buck Bunny")
    }

    @Test func otherMessageIsNotMediaStatus() {
        #expect(MediaStatus.parseTitle(#"{"type":"PING"}"#) == nil)
    }

    @Test func showsRecognizedApp() {
        let app = CastApp(id: "233637DE", name: "YouTube", iconURL: nil, statusText: "YouTube", transportID: "t", isIdleScreen: false)
        #expect(NowPlaying.from(app: app, mediaTitle: "Big Buck Bunny") == NowPlaying(appName: "YouTube", iconURL: nil, title: "Big Buck Bunny"))
        #expect(NowPlaying.from(app: app, mediaTitle: nil)?.title == "YouTube")
    }

    @Test func hidesMirroringAndIdle() {
        let mirror = CastApp(id: "0F5096E8", name: "Chrome Mirroring", iconURL: nil, statusText: nil, transportID: "t", isIdleScreen: false)
        let idle = CastApp(id: "E8C28D3C", name: "Backdrop", iconURL: nil, statusText: nil, transportID: "t", isIdleScreen: true)
        #expect(NowPlaying.from(app: mirror, mediaTitle: nil) == nil)
        #expect(NowPlaying.from(app: idle, mediaTitle: nil) == nil)
        #expect(NowPlaying.from(app: nil, mediaTitle: nil) == nil)
    }
}
