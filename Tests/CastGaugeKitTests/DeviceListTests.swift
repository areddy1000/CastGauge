import Foundation
import Testing
@testable import CastGaugeKit

/// The device list reads each Chromecast's state from its Bonjour record, with no connection.
@Suite("DeviceList")
struct DeviceListTests {
    @Test func idleDeviceHasNoActivity() {
        let device = CastDevice.from(txt: ["id": "a", "fn": "Bedroom TV", "rs": ""])
        #expect(device?.activity == .idle)
    }

    @Test func mirroringDeviceCastsATab() {
        let device = CastDevice.from(txt: ["id": "a", "fn": "Bedroom TV", "rs": "Chrome Mirroring"])
        #expect(device?.activity == .castingTab)
    }

    @Test func appDeviceShowsTheStatusText() {
        let device = CastDevice.from(txt: ["id": "a", "fn": "Bedroom TV", "rs": "YouTube"])
        #expect(device?.activity == .app("YouTube"))
    }

    @Test func parsesTheSessionID() throws {
        let json = #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"233637DE","displayName":"YouTube","sessionId":"s-1","transportId":"t-1"}]}}"#
        #expect(try #require(ReceiverStatus.parse(json)?.app).sessionID == "s-1")
    }

    @Test func stopNamesTheSession() throws {
        let payload = CastCommand.stop(sessionID: "s-1", requestID: 7)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        #expect(object["type"] as? String == "STOP")
        #expect(object["sessionId"] as? String == "s-1")
        #expect(object["requestId"] as? Int == 7)
    }
}
