import CoreWLAN
import Testing
@testable import CastGaugeKit

@Suite("CastDiscovery")
struct CastDiscoveryTests {
    @Test func parsesTXT() {
        let d = CastDevice.from(txt: ["id": "d6f4", "fn": "Bedroom TV", "md": "Chromecast", "rs": "Chrome Mirroring"])
        #expect(d == CastDevice(id: "d6f4", name: "Bedroom TV", isMirroring: true, address: nil, statusText: "Chrome Mirroring"))
    }

    @Test func idleDeviceIsNotMirroring() {
        #expect(CastDevice.from(txt: ["id": "a", "fn": "Kitchen"])?.isMirroring == false)
    }

    @Test func missingNameIsNoDevice() {
        #expect(CastDevice.from(txt: ["id": "a"]) == nil)
    }

    @Test func picksTheMirroringDevice() {
        let idle = CastDevice(id: "a", name: "Kitchen", isMirroring: false, address: "192.168.1.20")
        let busy = CastDevice(id: "b", name: "Bedroom TV", isMirroring: true, address: "192.168.1.155")
        #expect(CastDevice.pick([idle, busy]) == busy)
        #expect(CastDevice.pick([idle]) == nil)
    }

    @Test func namesBands() {
        #expect(WiFiReader.bandName(.band5GHz) == "5 GHz")
        #expect(WiFiReader.bandName(.band2GHz) == "2.4 GHz")
        #expect(WiFiReader.bandName(.band6GHz) == "6 GHz")
    }
}
