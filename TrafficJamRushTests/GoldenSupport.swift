import XCTest
@testable import TrafficJamRush

/// Golden files dumped from the JVM (Golden/source/GoldenDumpTest.kt run on a scratch copy of the Android project).
enum Golden {
    static func url(_ name: String) -> URL? {
        final class Anchor {}
        let bundle = Bundle(for: Anchor.self)
        if let u = bundle.url(forResource: name, withExtension: "json") { return u }
        if let u = bundle.url(forResource: name, withExtension: "json", subdirectory: "Golden") { return u }
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/\(name).json")
        return FileManager.default.fileExists(atPath: here.path) ? here : nil
    }

    static func json(_ name: String) throws -> [String: Any] {
        let u = try XCTUnwrap(url(name), "missing Golden/\(name).json")
        let data = try Data(contentsOf: u)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func lines(_ name: String, key: String) throws -> [String] {
        try XCTUnwrap(try json(name)[key] as? [String])
    }

    /// Kotlin `Float.toString()` style token used in the dumps ("~" + value). Parsed back for tolerant comparison.
    static func f(_ x: Float) -> String { "~\(x)" }

    /// Parses a "~" float token (Kotlin or Swift spelling).
    static func parse(_ token: Substring) -> Float? {
        guard token.first == "~" else { return nil }
        let s = token.dropFirst()
        if s == "NaN" || s == "nan" { return .nan }
        if s == "Infinity" || s == "inf" { return .infinity }
        if s == "-Infinity" || s == "-inf" { return -.infinity }
        return Float(String(s))
    }

    struct Tolerance {
        var abs: Float
        var rel: Float
    }

    /// Compares two dump lines token by token ('|' and ':' separated). Tokens starting with "~" are floats and may
    /// differ by `tol`; everything else must be identical. Returns nil when equal, else a description.
    static func compare(_ android: String, _ ios: String, _ tol: Tolerance, maxDiff: inout Float) -> String? {
        if android == ios { return nil }
        let a = android.split(separator: "|", omittingEmptySubsequences: false).flatMap { $0.split(separator: ":", omittingEmptySubsequences: false) }
        let b = ios.split(separator: "|", omittingEmptySubsequences: false).flatMap { $0.split(separator: ":", omittingEmptySubsequences: false) }
        if a.count != b.count { return "token count \(a.count) vs \(b.count)" }
        for i in a.indices where a[i] != b[i] {
            guard let x = parse(a[i]), let y = parse(b[i]) else { return "token \(i): \(a[i]) vs \(b[i])" }
            if x.isNaN && y.isNaN { continue }
            if x == y { continue }
            let d = Swift.abs(x - y)
            maxDiff = Swift.max(maxDiff, d / Swift.max(1, Swift.abs(x)))
            if !(d <= tol.abs + tol.rel * Swift.abs(x)) { return "token \(i): \(a[i]) vs \(b[i]) (diff \(d))" }
        }
        return nil
    }
}

/// The level fingerprint format of GoldenDumpTest.levelLine: every Level field, the full vehicle list,
/// the queue run-length encoded, and both Solver results.
enum LevelFormat {
    static func line(_ l: Level) -> String {
        var s = "\(l.number)|\(l.cols)|\(l.rows)|\(Int32(bitPattern: l.rotation.bitPattern))|\(l.difficulty.name)|"
        s += "\(l.colorCount)|\(l.openSlots)|\(l.lockedSlots)|"
        let hex = Array("0123456789abcdef")
        let n = l.cols * l.rows
        var i = 0
        while i < n {
            var nib = 0
            for k in 0..<4 where i + k < n && l.mask[i + k] { nib |= 1 << k }
            s.append(hex[nib])
            i += 4
        }
        s += "|"
        s += l.vehicles.map { v in
            "\(v.id),\(v.type.name.first!)\(v.color)\(v.dir.name)\(v.x),\(v.y)" + (v.mystery ? "m" : "")
        }.joined(separator: ";")
        s += "|"
        var runs: [String] = []
        var j = 0
        let q = l.queue
        while j < q.count {
            var k = j
            while k < q.count && q[k] == q[j] { k += 1 }
            runs.append("\(q[j])x\(k - j)")
            j = k
        }
        s += runs.joined(separator: ",")
        s += "|\(Solver.solvesIntended(l) ? 1 : 0)\(Solver.solvesGreedy(l) ? 1 : 0)"
        return s
    }
}
