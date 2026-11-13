import XCTest
import GameKit
@testable import TrafficJamRush

/// Mid-level autosave: the engine state is captured with every animation settled, survives JSON in the "player"
/// store, is validated against the level, restores into a fresh engine, and the restored level plays on.
@MainActor
final class ExtrasAutosaveTests: XCTestCase {

    private func comparable(_ s: ExtrasSnapshot) -> ExtrasSnapshot {
        var c = s
        c.savedAt = 0
        return c
    }

    func testFreshLevelIsNotWorthSaving() {
        let e = ExtrasTest.engine(1)
        XCTAssertFalse(ExtrasAutosave.touched(e, moves: []))
        e.unlockSlot(4)
        XCTAssertTrue(ExtrasAutosave.touched(e, moves: []), "an unlocked spot is progress")
    }

    func testMidBoardingCaptureRestoresAndPlaysOn() throws {
        var events: [GameEvent] = []
        let a = ExtrasTest.engine(1)
        let xa = ExtrasSession(engine: a, levelNumber: 1, day: nil)
        ExtrasTest.run(a, xa, 1.5)
        let van = ExtrasTest.vehicle(a, 0)
        a.onTap(van.home)
        XCTAssertTrue(ExtrasTest.runUntil(a, xa) { van.state == .PARKED && van.filled >= 2 && van.reserved > 0 })
        let s = try XCTUnwrap(ExtrasAutosave.capture(a, day: nil, moves: xa.moves, now: 123))
        // Passengers mid-hop count as seated; nothing is left in flight.
        XCTAssertEqual(s.spots[0], van.slot)
        XCTAssertEqual(s.filled[0], van.filled + van.reserved)
        XCTAssertEqual(s.head, a.qHead)
        XCTAssertEqual(s.moves, [0])
        XCTAssertEqual(s.waiting, a.queue.count - a.qHead)
        XCTAssertTrue(ExtrasAutosave.isValid(s, for: LevelGenerator.generate(1)))

        // Through the store (JSON) like a relaunch.
        let (store, defaults) = ExtrasTest.store()
        ExtrasRepository(store: store).saveGame(s)
        XCTAssertNotNil(defaults.string(forKey: "player.autosave"))
        let loaded = try XCTUnwrap(ExtrasRepository(store: store).savedGame)
        XCTAssertEqual(loaded, s)

        let b = ExtrasTest.engine(1) { events.append($0) }
        let xb = ExtrasSession(engine: b, levelNumber: 1, day: nil)
        xb.resume = loaded
        XCTAssertTrue(ExtrasAutosave.restore(b, loaded))
        let vb = ExtrasTest.vehicle(b, 0)
        XCTAssertEqual(vb.state, .PARKED)
        XCTAssertTrue(b.slots[s.spots[0]].vehicle === vb)
        XCTAssertEqual(vb.pos, b.slotCenter(s.spots[0]))
        XCTAssertEqual(b.qHead, s.head)
        XCTAssertEqual(b.grid.at(vb.spec.x, vb.spec.y), -1, "left the lot")
        XCTAssertEqual(comparable(try XCTUnwrap(ExtrasAutosave.capture(b, day: nil, moves: [0]))), comparable(s))

        // Plays on to a 3-star win (no boosters were used).
        ExtrasTest.run(b, xb, 4)
        XCTAssertEqual(vb.state, .GONE, "the van fills up and leaves")
        for id in [1, 2] {
            b.onTap(ExtrasTest.vehicle(b, id).home)
            ExtrasTest.run(b, xb, 3)
        }
        ExtrasTest.run(b, xb, 3)
        XCTAssertEqual(b.phase, .WON)
        XCTAssertEqual(events.last, .Won(stars: 3))
    }

    func testBoostersRevivesSlotsAndColoursSurvive() throws {
        let a = ExtrasTest.engine(30)
        let xa = ExtrasSession(engine: a, levelNumber: 30, day: nil)
        ExtrasTest.run(a, xa, 2.5)
        a.shuffle()
        a.revive() // unlocks the first locked spot
        a.unlockSlot(6)
        var moved = 0
        for v in a.vehicles where v.state == .LOT && a.grid.isFree(v.spec) && moved < 3 {
            a.onTap(v.home)
            moved += 1
            ExtrasTest.run(a, xa, 0.3)
        }
        XCTAssertTrue(a.armCrane())
        ExtrasTest.run(a, xa, 0.2) // some still driving
        let s = try XCTUnwrap(ExtrasAutosave.capture(a, day: nil, moves: xa.moves))
        for (i, spot) in s.spots.enumerated() where spot >= 0 {
            XCTAssertTrue([VState.EXITING, .PARKED].contains(a.vehicles[i].state), "vehicle \(i) settles into spot \(spot)")
        }
        XCTAssertGreaterThan(s.spots.filter { $0 >= 0 }.count, 0)
        XCTAssertEqual(s.boostersUsed, 1)
        XCTAssertEqual(s.revivesUsed, 1)
        XCTAssertEqual(s.open, [true, true, true, true, true, false, true, true])
        XCTAssertTrue(s.craneArmed)
        XCTAssertEqual(s.colors, a.vehicles.map(\.color))
        XCTAssertTrue(ExtrasAutosave.isValid(s, for: a.level))

        let b = ExtrasTest.engine(30)
        XCTAssertTrue(ExtrasAutosave.restore(b, s))
        XCTAssertEqual(b.boostersUsed, 1)
        XCTAssertEqual(b.revivesUsed, 1)
        XCTAssertEqual(b.slots.map(\.open), s.open)
        XCTAssertTrue(b.craneArmed)
        XCTAssertEqual(b.vehicles.map(\.color), s.colors)
        XCTAssertEqual(b.queue, s.queue)
        XCTAssertEqual(comparable(try XCTUnwrap(ExtrasAutosave.capture(b, day: nil, moves: s.moves))), comparable(s))
        // Parked vehicles can still be undone after the resume: their way back to the lot is rebuilt.
        for v in b.vehicles where v.state == .PARKED && v.slot != VIP_SLOT {
            XCTAssertNotNil(v.measure)
            XCTAssertEqual(v.measure!.getPosTan(v.pathLen).pos.x, b.slotCenter(v.slot).x, accuracy: 0.5)
        }
    }

    func testInvalidSnapshotsAreRejected() throws {
        let a = ExtrasTest.engine(1)
        ExtrasTest.run(a, nil, 1.5)
        let van = ExtrasTest.vehicle(a, 0)
        a.onTap(van.home)
        XCTAssertTrue(ExtrasTest.runUntil(a) { van.state == .PARKED })
        let s = try XCTUnwrap(ExtrasAutosave.capture(a, day: nil, moves: [0]))
        XCTAssertEqual(s.spots[0], 0)
        let level = LevelGenerator.generate(1)
        XCTAssertTrue(ExtrasAutosave.isValid(s, for: level))
        XCTAssertFalse(ExtrasAutosave.isValid(s, for: LevelGenerator.generate(2)), "another level")

        var t = s
        t.fingerprint ^= 1
        XCTAssertFalse(ExtrasAutosave.isValid(t, for: level))
        t = s
        t.head = s.head + 1
        XCTAssertFalse(ExtrasAutosave.isValid(t, for: level), "a passenger would be lost")
        t = s
        t.spots[1] = t.spots[0]
        XCTAssertFalse(ExtrasAutosave.isValid(t, for: level), "two vehicles in one spot")
        t = s
        t.spots[1] = 5
        XCTAssertFalse(ExtrasAutosave.isValid(t, for: level), "a locked spot")
        t = s
        t.version = 99
        XCTAssertFalse(ExtrasAutosave.isValid(t, for: level))

        let b = ExtrasTest.engine(1)
        t = s
        t.head += 1
        XCTAssertFalse(ExtrasAutosave.restore(b, t))
        XCTAssertEqual(b.qHead, 0, "untouched")
        XCTAssertTrue(b.vehicles.allSatisfy { $0.state == .LOT })
    }

    func testFullVehicleIsSettledAsDeparted() throws {
        let a = ExtrasTest.engine(1)
        ExtrasTest.run(a, nil, 1.5)
        let van = ExtrasTest.vehicle(a, 0)
        a.onTap(van.home)
        XCTAssertTrue(ExtrasTest.runUntil(a) { van.departDelay >= 0 || van.state == .DEPARTING })
        let s = try XCTUnwrap(ExtrasAutosave.capture(a, day: nil, moves: [0]))
        XCTAssertEqual(s.spots[0], ExtrasSnapshot.GONE)
        XCTAssertEqual(s.moves, [], "a departed vehicle can't be undone")
        XCTAssertEqual(s.head, 6)
        XCTAssertTrue(ExtrasAutosave.isValid(s, for: a.level))
    }

    func testWonLevelIsNotCaptured() {
        let a = ExtrasTest.engine(1)
        ExtrasTest.run(a, nil, 1.5)
        for id in [0, 1, 2] {
            a.onTap(ExtrasTest.vehicle(a, id).home)
            ExtrasTest.run(a, nil, 3)
        }
        ExtrasTest.run(a, nil, 3)
        XCTAssertEqual(a.phase, .WON)
        XCTAssertNil(ExtrasAutosave.capture(a, day: nil, moves: []))
    }

    func testDailySnapshotRoundTrip() throws {
        let day = ExtrasDay(20_400)
        let level = ExtrasDailyPuzzle.level(day)
        let a = ExtrasTest.engine(level)
        let xa = ExtrasSession(engine: a, levelNumber: 0, day: day)
        ExtrasTest.run(a, xa, 2.5)
        let v = try XCTUnwrap(a.vehicles.first { $0.state == .LOT && a.grid.isFree($0.spec) })
        a.onTap(v.home)
        ExtrasTest.run(a, xa, 1.5)
        let s = try XCTUnwrap(ExtrasAutosave.capture(a, day: day.epochDay, moves: xa.moves))
        XCTAssertTrue(s.isDaily)
        XCTAssertEqual(s.level, level.number)
        let b = ExtrasTest.engine(ExtrasDailyPuzzle.generate(day))
        XCTAssertTrue(ExtrasAutosave.restore(b, s), "the day's puzzle regenerates identically")
    }

    func testRepositoryHandsTheSaveToTheMatchingSession() {
        let (store, _) = ExtrasTest.store()
        let repo = ExtrasRepository(store: store)
        let level = ExtrasSnapshot(level: 12, day: nil, fingerprint: 1, colors: [], mystery: [], spots: [], filled: [], order: [],
                                   open: [], queue: [], head: 0, boostersUsed: 0, revivesUsed: 0, parkCounter: 0,
                                   craneArmed: false, moves: [], savedAt: 0)
        repo.pendingResume = level
        XCTAssertNil(repo.takeResume(levelNumber: 13, day: nil))
        XCTAssertNil(repo.pendingResume, "taken once")
        repo.pendingResume = level
        XCTAssertEqual(repo.takeResume(levelNumber: 12, day: nil), level)
        var daily = level
        daily.day = 20_400
        repo.pendingResume = daily
        XCTAssertNil(repo.takeResume(levelNumber: 12, day: nil))
        repo.pendingResume = daily
        XCTAssertEqual(repo.takeResume(levelNumber: 0, day: 20_400), daily)

        repo.saveGame(level)
        XCTAssertEqual(ExtrasRepository(store: store).savedGame, level)
        repo.clearSavedGame()
        XCTAssertNil(ExtrasRepository(store: store).savedGame)
    }
}
