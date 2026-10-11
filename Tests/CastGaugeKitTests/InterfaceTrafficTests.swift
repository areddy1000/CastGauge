import Foundation
import Testing
@testable import CastGaugeKit

/// The rate comes from the byte counter of the interface that reaches the TV.
@Suite("InterfaceTraffic")
struct InterfaceTrafficTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test func firstSampleHasNoRate() {
        var meter = RateMeter()
        #expect(meter.sample(bytes: 1_000, at: start) == nil)
    }

    @Test func rateIsBytesPerSecond() {
        var meter = RateMeter()
        _ = meter.sample(bytes: 1_000, at: start)
        #expect(meter.sample(bytes: 1_301_000, at: start.addingTimeInterval(2)) == 650_000)
    }

    // if_data keeps a 32-bit counter. At 20 Mbit/s it wraps about every 30 minutes.
    @Test func survivesACounterWrap() {
        var meter = RateMeter()
        _ = meter.sample(bytes: UInt32.max - 99, at: start)
        #expect(meter.sample(bytes: 600_000 - 100, at: start.addingTimeInterval(1)) == 600_000)
    }

    @Test func tooShortAGapHasNoRate() {
        var meter = RateMeter()
        _ = meter.sample(bytes: 0, at: start)
        #expect(meter.sample(bytes: 10, at: start.addingTimeInterval(0.01)) == nil)
    }

    @Test func matchesTheSubnet() {
        #expect(InterfaceTraffic.sameSubnet("192.168.1.188", "192.168.1.155", mask: "255.255.255.0"))
        #expect(!InterfaceTraffic.sameSubnet("10.0.0.5", "192.168.1.155", mask: "255.255.255.0"))
    }
}
