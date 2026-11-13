import XCTest
@testable import TrafficJamRush

/// PathMeasure vs real Skia (Golden/pathmeasure.json: SkPathMeasure through Skiko on the JVM, for 300 rounded
/// polylines like the engine's exit roads). Lengths, positions and tangents must agree to float precision.
final class PathMeasureTests: XCTestCase {

    func testMatchesSkia() throws {
        let cases = try Golden.lines("pathmeasure", key: "paths")
        XCTAssertEqual(cases.count, 300)
        var maxPos: Float = 0
        var maxTan: Float = 0
        var maxLen: Float = 0
        var exact = 0
        var total = 0
        for (ci, c) in cases.enumerated() {
            let parts = c.split(separator: "|")
            XCTAssertEqual(parts.count, 3)
            var path = EnginePath()
            for cmd in parts[0].split(separator: ";") {
                let t = cmd.split(separator: "~", omittingEmptySubsequences: false)
                let v = t.dropFirst().map { Float(String($0))! }
                switch t[0] {
                case "M": path.moveTo(v[0], v[1])
                case "L": path.lineTo(v[0], v[1])
                case "Q": path.quadraticTo(v[0], v[1], v[2], v[3])
                default: XCTFail("verb \(t[0])")
                }
            }
            let m = PathMeasure()
            m.setPath(path, false)
            let len = Golden.parse(parts[1])!
            maxLen = max(maxLen, abs(m.length - len) / len)
            XCTAssertEqual(m.length, len, accuracy: len * 1e-5, "case \(ci) length")
            for s in parts[2].split(separator: ";") {
                let f = s.split(separator: ":").map { Golden.parse($0)! }
                let (pos, tan) = m.getPosTan(f[0])
                let dp = max(abs(pos.x - f[1]), abs(pos.y - f[2]))
                let dt = max(abs(tan.x - f[3]), abs(tan.y - f[4]))
                total += 1
                if dp == 0 && dt == 0 { exact += 1 }
                maxPos = max(maxPos, dp)
                maxTan = max(maxTan, dt)
                XCTAssertLessThanOrEqual(dp, 2e-3, "case \(ci) d=\(f[0]) pos \(pos) vs \(f[1]),\(f[2])")
                XCTAssertLessThanOrEqual(dt, 1e-4, "case \(ci) d=\(f[0]) tan \(tan) vs \(f[3]),\(f[4])")
            }
        }
        print("PathMeasure vs Skia: \(exact)/\(total) samples bit-identical, max |Δpos| \(maxPos) px, max |Δtan| \(maxTan), max rel Δlength \(maxLen)")
    }

    func testStraightLineAndPinning() {
        var p = EnginePath()
        p.moveTo(10, 10)
        p.lineTo(10, 110)
        let m = PathMeasure(p)
        XCTAssertEqual(m.length, 100)
        XCTAssertEqual(m.getPosition(25), Offset(10, 35))
        XCTAssertEqual(m.getTangent(25), Offset(0, 1))
        XCTAssertEqual(m.getPosition(-5), Offset(10, 10))
        XCTAssertEqual(m.getPosition(500), Offset(10, 110))
        let empty = PathMeasure()
        XCTAssertEqual(empty.length, 0)
        XCTAssertTrue(empty.getPosition(1).x.isNaN)
    }
}
