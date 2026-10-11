import Foundation
import Testing
@testable import CastGaugeKit

@Suite("ProcessArguments")
struct ProcessArgumentsTests {
    @Test func parsesProcargs2() {
        var d = withUnsafeBytes(of: Int32(2).littleEndian) { Data($0) }
        d.append(contentsOf: Array("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome".utf8) + [0, 0, 0])
        d.append(contentsOf: Array("Google Chrome".utf8) + [0] + Array("--castgauge-playout-delay=400".utf8) + [0])
        d.append(contentsOf: Array("HOME=/Users/x".utf8) + [0])
        #expect(ProcessArguments.parse(procargs2: d) == ["Google Chrome", "--castgauge-playout-delay=400"])
    }

    @Test func rejectsShortData() {
        #expect(ProcessArguments.parse(procargs2: Data([1, 0])) == nil)
    }

    @Test func readsOwnProcess() {
        let args = ProcessArguments.read(pid: getpid())
        #expect(args?.isEmpty == false)
    }
}
