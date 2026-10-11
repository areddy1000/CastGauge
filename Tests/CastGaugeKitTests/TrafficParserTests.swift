import Testing
@testable import CastGaugeKit

@Suite("TrafficParser")
struct TrafficParserTests {
    let sample = """
    ,bytes_out,
    Google Chrome H.34072,640000,
    udp4 192.168.1.188:50123<->192.168.1.155:38429,612000,
    tcp4 192.168.1.188:52112<->18.97.36.16:443,28000,
    Safari.501,9000,
    udp4 192.168.1.188:50999<->192.168.1.155:38429,5000,
    ,bytes_out,
    """

    @Test func countsOnlyChromeFlowsToTheTV() {
        var p = TrafficParser(targetAddress: "192.168.1.155")
        let results = sample.split(separator: "\n").compactMap { p.feed(String($0)) }
        #expect(results == [612000])
    }

    @Test func emptySampleIsZero() {
        var p = TrafficParser(targetAddress: "192.168.1.155")
        _ = p.feed(",bytes_out,")
        #expect(p.feed(",bytes_out,") == 0)
    }

    @Test func ignoresGarbage() {
        var p = TrafficParser(targetAddress: "192.168.1.155")
        #expect(p.feed("nettop: something odd") == nil)
    }

    // Chrome sends the cast stream from an unconnected UDP socket, so nettop shows no remote address.
    @Test func countsUnconnectedChromeUDP() {
        var p = TrafficParser(targetAddress: "192.168.1.155")
        let lines = [
            ",bytes_out,",
            "Google Chrome H.34072,645380,",
            "tcp4 192.168.1.188:51614<->93.123.109.203:443,106,",
            "udp4 *:52876<->*:*,645274,",
            "udp4 *:5353<->*:*,300,",
            ",bytes_out,",
        ]
        #expect(lines.compactMap { p.feed($0) } == [645274])
    }
}
