import XCTest
@testable import TrafficJamRush

/// 1:1 port of app/src/test/.../LevelGeneratorTest.kt, plus the level cache.
final class LevelGeneratorTest: XCTestCase {

    func testAllLevelsAreValidAndSolvable() {
        let start = Date()
        var maxMs = 0.0
        var totalVehicles = 0
        for n in 1...5000 {
            let t = Date()
            let level = LevelGenerator.generate(n)
            maxMs = max(maxMs, Date().timeIntervalSince(t) * 1000)
            totalVehicles += level.vehicles.count

            // Seats always equal passengers, per colour.
            for c in 0..<8 {
                let seats = level.vehicles.filter { $0.color == c }.reduce(0) { $0 + $1.type.seats }
                XCTAssertEqual(seats, level.queue.filter { $0 == c }.count, "level \(n) colour \(c)")
            }
            // No overlaps, everything inside the mask.
            let grid = LotGrid(level.cols, level.rows)
            for v in level.vehicles {
                v.forEachCell { x, y in
                    XCTAssertTrue(level.inMask(x, y), "level \(n) off-mask")
                    XCTAssertEqual(-1, grid.at(x, y), "level \(n) overlap")
                }
                grid.put(v)
            }
            XCTAssertTrue(level.vehicles.contains { grid.isFree($0) }, "level \(n) has no free vehicle")
            XCTAssertTrue(Solver.solves(level), "level \(n) unsolvable")
        }
        let totalS = Date().timeIntervalSince(start)
        print(String(format: "5000 levels in %.1fs, slowest %.1f ms, avg vehicles %.1f", totalS, maxMs, Double(totalVehicles) / 5000.0))
        XCTAssertTrue(maxMs < 250, "slowest level took \(maxMs) ms")
    }

    func testGenerationIsDeterministic() {
        for n in [2, 17, 250, 4999] {
            let a = LevelGenerator.generate(n)
            let b = LevelGenerator.generate(n)
            XCTAssertEqual(a.vehicles, b.vehicles)
            XCTAssertEqual(a.queue, b.queue)
        }
    }

    func testPrintCurve() {
        for n in [1, 2, 3, 5, 10, 20, 50, 100, 500, 1000, 5000] {
            let l = LevelGenerator.generate(n)
            print("L\(n) \(l.cols)x\(l.rows) vehicles=\(l.vehicles.count) colors=\(l.colorCount) passengers=\(l.queue.count) rot=\(l.rotation) \(l.difficulty)")
        }
    }

    /// Kotlin: access-ordered LinkedHashMap with removeEldestEntry(size > 12).
    func testCacheKeepsTheTwelveMostRecentlyUsedLevels() {
        let first = LevelGenerator.get(4001)
        XCTAssertTrue(first === LevelGenerator.get(4001), "cached instance is reused")
        for n in 4002...4012 { _ = LevelGenerator.get(n) } // 12 entries: 4001...4012
        _ = LevelGenerator.get(4001) // touch 4001: 4002 is now the eldest
        _ = LevelGenerator.get(4013) // evicts 4002
        let cached = LevelGenerator.cachedLevelNumbers
        XCTAssertEqual(cached.count, 12)
        XCTAssertFalse(cached.contains(4002))
        XCTAssertEqual(cached.first, 4003)
        XCTAssertEqual(cached.last, 4013)
        XCTAssertTrue(first === LevelGenerator.get(4001), "touched entry survived")
    }

    func testDifficultyAndTutorial() {
        XCTAssertEqual(DifficultyCurve.difficulty(5), .HARD)
        XCTAssertEqual(DifficultyCurve.difficulty(10), .SUPER_HARD)
        XCTAssertEqual(DifficultyCurve.difficulty(15), .HARD)
        XCTAssertEqual(DifficultyCurve.difficulty(20), .SUPER_HARD)
        XCTAssertEqual(DifficultyCurve.difficulty(7), .NORMAL)
        let l1 = LevelGenerator.generate(1)
        XCTAssertEqual(l1.vehicles.count, 3)
        XCTAssertEqual(l1.queue.count, 20)
        XCTAssertEqual(l1.colorCount, 3)
        XCTAssertEqual(l1.openSlots, 4)
        XCTAssertEqual(l1.lockedSlots, 3)
    }
}
