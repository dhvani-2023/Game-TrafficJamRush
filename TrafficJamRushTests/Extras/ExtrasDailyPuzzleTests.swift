import XCTest
import GameKit
@testable import TrafficJamRush

/// Daily Puzzle: local-day maths, date-seeded generation with the game's own generator rules, the streak and the
/// 50 + 10 × streak (max 150) reward.
@MainActor
final class ExtrasDailyPuzzleTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testLocalDayMaths() {
        let today = ExtrasDay.today(date(2026, 11, 8))
        XCTAssertEqual(today.yyyymmdd, 20261108)
        XCTAssertEqual(today.weekday, 1, "8 Nov 2026 is a Sunday")
        XCTAssertTrue(today.isWeekend)
        XCTAssertEqual(today.monthBadge, "NOV")
        XCTAssertEqual(today.label, "Sun, Nov 8")
        XCTAssertEqual(today.weekdayLetter, "S")
        XCTAssertEqual(ExtrasDay(today.epochDay + 1).label, "Mon, Nov 9")
        XCTAssertFalse(ExtrasDay(today.epochDay + 1).isWeekend)
        // Late evening and early morning stay on the local date.
        XCTAssertEqual(ExtrasDay.today(date(2026, 11, 8, hour: 0)).epochDay, today.epochDay)
        XCTAssertEqual(ExtrasDay.today(date(2026, 11, 8, hour: 23)).epochDay, today.epochDay)
        for (y, m, d) in [(2024, 2, 29), (2026, 1, 1), (2026, 12, 31), (2030, 6, 15)] {
            let dt = date(y, m, d)
            XCTAssertEqual(ExtrasDay.today(dt).yyyymmdd, Days.yyyymmdd(dt))
        }
    }

    func testDifficultyFollowsTheWeek() {
        let start = ExtrasDay.today(date(2026, 11, 2)).epochDay
        var numbers = Set<Int>()
        for d in start..<(start + 70) {
            let day = ExtrasDay(d)
            let n = ExtrasDailyPuzzle.number(day)
            numbers.insert(n)
            XCTAssertTrue((15...80).contains(n), "day \(day.yyyymmdd) → \(n)")
            XCTAssertEqual(DifficultyCurve.difficulty(n), day.isWeekend ? .HARD : .NORMAL, "day \(day.label)")
            XCTAssertEqual(ExtrasDailyPuzzle.number(day), n, "deterministic")
            XCTAssertEqual(ExtrasDailyPuzzle.seed(day), ExtrasDailyPuzzle.seed(ExtrasDay(d)))
        }
        XCTAssertGreaterThan(numbers.count, 20, "the puzzle size varies from day to day")
    }

    func testDailyLevelsAreValidSolvableAndDeterministic() {
        let start = ExtrasDay.today(date(2026, 11, 1)).epochDay
        var previous: Level?
        for d in start..<(start + 21) {
            let day = ExtrasDay(d)
            let level = ExtrasDailyPuzzle.generate(day)
            XCTAssertEqual(level.number, ExtrasDailyPuzzle.number(day))
            for c in 0..<8 {
                let seats = level.vehicles.filter { $0.color == c }.reduce(0) { $0 + $1.type.seats }
                XCTAssertEqual(seats, level.queue.filter { $0 == c }.count, "\(day.label) colour \(c)")
            }
            let grid = LotGrid(level.cols, level.rows)
            for v in level.vehicles {
                v.forEachCell { x, y in
                    XCTAssertTrue(level.inMask(x, y))
                    XCTAssertEqual(grid.at(x, y), -1)
                }
                grid.put(v)
            }
            XCTAssertTrue(Solver.solves(level), "\(day.label) unsolvable")
            let again = ExtrasDailyPuzzle.generate(day)
            XCTAssertEqual(again.vehicles, level.vehicles)
            XCTAssertEqual(again.queue, level.queue)
            if let previous { XCTAssertNotEqual(previous.vehicles, level.vehicles, "a new puzzle every day") }
            previous = level
        }
    }

    func testDailyPuzzleLeavesNormalLevelsAlone() throws {
        let before = LevelGenerator.cachedLevelNumbers
        let day = ExtrasDay.today(date(2026, 11, 8))
        let daily = ExtrasDailyPuzzle.level(day)
        XCTAssertTrue(daily === ExtrasDailyPuzzle.level(day), "cached for the day")
        XCTAssertEqual(LevelGenerator.cachedLevelNumbers, before, "the 12-level cache is untouched")
        // Same generator number, different seed: the daily level is not the normal level.
        let normal = LevelGenerator.generate(daily.number)
        XCTAssertNotEqual(normal.vehicles, daily.vehicles)
        let lines = try Golden.lines("levels", key: "levels")
        XCTAssertEqual(LevelFormat.line(normal), lines[daily.number - 1], "normal level still matches Android")
    }

    func testRewardFormula() {
        XCTAssertEqual(ExtrasDailyPuzzle.reward(streak: 1), 60)
        XCTAssertEqual(ExtrasDailyPuzzle.reward(streak: 2), 70)
        XCTAssertEqual(ExtrasDailyPuzzle.reward(streak: 9), 140)
        XCTAssertEqual(ExtrasDailyPuzzle.reward(streak: 10), 150)
        XCTAssertEqual(ExtrasDailyPuzzle.reward(streak: 25), 150, "capped")
        XCTAssertEqual(ExtrasDailyPuzzle.reward(streak: 0), 50)
    }

    func testStreakAndCalendar() {
        let (store, defaults) = ExtrasTest.store()
        let repo = ExtrasRepository(store: store)
        let d0 = ExtrasDay.today(date(2026, 11, 8)).epochDay
        XCTAssertFalse(repo.puzzleSolved(d0))
        XCTAssertEqual(repo.puzzleStreakAlive(d0), 0)
        XCTAssertEqual(repo.puzzleStreakAfterSolving(d0), 1)

        XCTAssertEqual(repo.completePuzzle(d0), ExtrasDailyResult(day: d0, streak: 1, reward: 60))
        XCTAssertNil(repo.completePuzzle(d0), "one reward per day")
        XCTAssertTrue(repo.puzzleSolved(d0))
        XCTAssertEqual(repo.puzzleStreakAfterSolving(d0), 1)
        XCTAssertEqual(repo.puzzleStreakAlive(d0 + 1), 1, "still alive the next day")
        XCTAssertEqual(repo.completePuzzle(d0 + 1)?.reward, 70)
        XCTAssertEqual(repo.completePuzzle(d0 + 2)?.streak, 3)
        XCTAssertEqual(repo.puzzleStreakAlive(d0 + 4), 0, "a missed day breaks it")
        XCTAssertEqual(repo.completePuzzle(d0 + 4), ExtrasDailyResult(day: d0 + 4, streak: 1, reward: 60))

        let week = repo.puzzleWeek(d0 + 4)
        XCTAssertEqual(week.map(\.day.epochDay), Array((d0 - 2)...(d0 + 4)))
        XCTAssertEqual(week.map(\.solved), [false, false, true, true, true, false, true])
        XCTAssertEqual(week.map(\.isToday), [false, false, false, false, false, false, true])

        // Saved in the "player" store and read back.
        XCTAssertEqual(defaults.integer(forKey: "player.puzzle_streak"), 1)
        XCTAssertEqual(defaults.integer(forKey: "player.puzzle_last"), d0 + 4)
        XCTAssertEqual(defaults.string(forKey: "player.puzzle_days"), "\(d0),\(d0 + 1),\(d0 + 2),\(d0 + 4)")
        let again = ExtrasRepository(store: store)
        XCTAssertEqual(again.puzzleWeek(d0 + 4), week)
        XCTAssertEqual(again.puzzleStreakAlive(d0 + 5), 1)
    }

    func testTenDayStreakPaysTheCap() {
        let (store, _) = ExtrasTest.store()
        let repo = ExtrasRepository(store: store)
        let rewards = (0..<12).map { repo.completePuzzle(1000 + $0)!.reward }
        XCTAssertEqual(rewards, [60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 150, 150])
        XCTAssertLessThanOrEqual(repo.puzzleDays.count, ExtrasRepository.DAYS_KEPT)
    }

    func testDailyPuzzlePlaysInTheEngine() {
        let day = ExtrasDay.today(date(2026, 11, 9))
        var events: [GameEvent] = []
        let e = ExtrasTest.engine(ExtrasDailyPuzzle.level(day)) { events.append($0) }
        // Solver.solvesIntended in the live engine: drive vehicles in reverse placement order, parking the next one
        // only when nobody in the line can board.
        let order = Array(e.level.vehicles.reversed().map(\.id))
        var next = 0
        ExtrasTest.run(e, nil, 2.5)
        var t: Float = 0
        while e.phase != .WON && t < 300 {
            if e.phase == .STUCK { e.revive() }
            let moving = e.vehicles.contains { $0.state == .EXITING || $0.departDelay >= 0 || ($0.state == .DEPARTING && $0.departPhase == 0) }
            let front = e.qHead < e.queue.count ? e.queue[e.qHead] : -1
            let canBoard = e.slots.contains { s in
                guard let v = s.vehicle else { return false }
                return v.state == .PARKED && v.color == front && v.filled + v.reserved < v.seats
            }
            if !moving && e.walkers.isEmpty && !canBoard && front >= 0 {
                while next < order.count && ExtrasTest.vehicle(e, order[next]).state != .LOT { next += 1 }
                if next < order.count { e.onTap(ExtrasTest.vehicle(e, order[next]).home) }
            }
            ExtrasTest.run(e, nil, 0.1)
            t += 0.1
        }
        XCTAssertEqual(e.phase, .WON, "\(day.label) daily puzzle can be finished")
        if case .Won = events.last {} else { XCTFail("no win event") }
    }
}
