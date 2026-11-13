import XCTest
@testable import TrafficJamRush

/// Every level 1…5000 must equal the Android generator's output exactly (Golden/levels.json: all Level fields,
/// every vehicle, the full queue, and Solver.solvesIntended / solvesGreedy, dumped from the JVM).
final class GoldenLevelsTests: XCTestCase {

    func testAllLevelDefinitionsMatchAndroid() throws {
        let lines = try Golden.lines("levels", key: "levels")
        XCTAssertEqual(lines.count, TOTAL_LEVELS)
        var matched = 0
        var diffs: [String] = []
        for n in 1...min(TOTAL_LEVELS, lines.count) {
            let mine = LevelFormat.line(LevelGenerator.generate(n))
            if mine == lines[n - 1] {
                matched += 1
            } else if diffs.count < 5 {
                diffs.append("level \(n)\n android: \(lines[n - 1])\n ios:     \(mine)")
            }
        }
        print("Golden levels: \(matched)/\(lines.count) match Android")
        XCTAssertEqual(matched, lines.count, diffs.joined(separator: "\n"))
    }

    func testCachedLevelsMatchAndroid() throws {
        let lines = try Golden.lines("levels", key: "levels")
        for n in [1, 2, 25, 26, 100, 101, 4999, 5000] {
            XCTAssertEqual(LevelFormat.line(LevelGenerator.get(n)), lines[n - 1], "level \(n)")
        }
    }
}
