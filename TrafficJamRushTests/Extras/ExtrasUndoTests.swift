import XCTest
@testable import TrafficJamRush

/// Undo booster: the newest move whose vehicle hasn't departed goes back (lot position and grid, slot, the
/// passengers it took back to the front of the line), it counts as a booster for stars, and the level plays on.
@MainActor
final class ExtrasUndoTests: XCTestCase {

    private func make(_ n: Int, _ events: @escaping (GameEvent) -> Void = { _ in }) -> (GameEngine, ExtrasSession) {
        let e = ExtrasTest.engine(n, events)
        return (e, ExtrasSession(engine: e, levelNumber: n, day: nil))
    }

    func testUndoParkedVehicleRestoresLotSlotAndQueue() {
        var events: [GameEvent] = []
        let (e, x) = make(1) { events.append($0) }
        ExtrasTest.run(e, x, 1.5)
        XCTAssertNil(x.undoTarget())
        XCTAssertFalse(x.undo(), "nothing to undo yet")
        XCTAssertEqual(e.boostersUsed, 0)

        let van = ExtrasTest.vehicle(e, 0)
        let queueBefore = e.queue
        e.onTap(van.home)
        XCTAssertEqual(van.state, .EXITING)
        XCTAssertTrue(x.undoTarget() === van)
        XCTAssertTrue(ExtrasTest.runUntil(e, x) { van.state == .PARKED && van.filled >= 2 && van.reserved > 0 })
        let slot = van.slot
        let taken = van.filled + van.reserved
        let head = e.qHead
        XCTAssertEqual(head, taken)

        XCTAssertTrue(x.undo())
        XCTAssertEqual(van.state, .LOT)
        XCTAssertEqual(van.slot, -1)
        XCTAssertEqual(van.filled + van.reserved, 0)
        XCTAssertNil(e.slots[slot].vehicle, "slot freed")
        XCTAssertEqual(e.grid.at(van.spec.x, van.spec.y), van.id, "back in the lot grid")
        XCTAssertFalse(e.walkers.contains { $0.vehicle === van }, "passengers mid-hop come back too")
        XCTAssertEqual(e.qHead, head - taken)
        XCTAssertEqual(e.queue, queueBefore, "the line is the same as before the move")
        XCTAssertEqual(e.boostersUsed, 1)
        XCTAssertNil(x.undoTarget())
        XCTAssertTrue(x.animating)

        // The rewind and the hops finish; everything is back in place.
        ExtrasTest.run(e, x, 1.5)
        XCTAssertFalse(x.animating)
        XCTAssertEqual(van.pos, van.home)
        XCTAssertEqual(van.heading, e.layout.rotationDeg + van.spec.dir.degrees)
        XCTAssertEqual(van.scale, 1)
        XCTAssertEqual(van.shakeT, -1)
        XCTAssertEqual(e.qS[e.qHead], 0, "first passenger back at the front")
        XCTAssertEqual(e.remaining, queueBefore.count)
        XCTAssertEqual(e.phase, .PLAYING)

        // The level still plays out; one booster → 2 stars.
        for id in [0, 1, 2] {
            e.onTap(ExtrasTest.vehicle(e, id).home)
            ExtrasTest.run(e, x, 3)
        }
        ExtrasTest.run(e, x, 3)
        XCTAssertEqual(e.phase, .WON)
        XCTAssertEqual(events.last, .Won(stars: 2))
    }

    func testUndoWhileDrivingAndNewestFirst() {
        let (e, x) = make(1)
        ExtrasTest.run(e, x, 1.5)
        let van = ExtrasTest.vehicle(e, 0)
        let car = ExtrasTest.vehicle(e, 1)
        e.onTap(van.home)
        ExtrasTest.run(e, x, 0.1)
        e.onTap(car.home)
        ExtrasTest.run(e, x, 0.1)
        XCTAssertEqual(car.state, .EXITING)
        XCTAssertEqual(x.moves, [0, 1])

        XCTAssertTrue(x.undo())
        XCTAssertEqual(car.state, .LOT, "newest move first")
        XCTAssertNotEqual(van.state, .LOT)
        XCTAssertEqual(e.qHead, 0)
        XCTAssertTrue(x.undo())
        XCTAssertEqual(van.state, .LOT)
        XCTAssertFalse(x.undo())
        XCTAssertEqual(e.boostersUsed, 2)
        XCTAssertTrue(e.slots[0..<SLOT_COUNT].allSatisfy { $0.vehicle == nil })
        // The car blocks the bus again.
        XCTAssertFalse(e.grid.isFree(ExtrasTest.vehicle(e, 2).spec))
        ExtrasTest.run(e, x, 1.5)
        XCTAssertEqual(car.pos, car.home)
        XCTAssertEqual(van.pos, van.home)
    }

    func testDepartedVehicleCannotBeUndone() {
        let (e, x) = make(1)
        ExtrasTest.run(e, x, 1.5)
        let van = ExtrasTest.vehicle(e, 0)
        e.onTap(van.home)
        XCTAssertTrue(ExtrasTest.runUntil(e, x) { van.state == .GONE })
        XCTAssertNil(x.undoTarget())
        XCTAssertFalse(x.undo())
        XCTAssertEqual(e.boostersUsed, 0)
        // An older move that is still parked is the one undone.
        let car = ExtrasTest.vehicle(e, 1)
        e.onTap(car.home)
        XCTAssertTrue(ExtrasTest.runUntil(e, x) { car.state == .PARKED })
        XCTAssertEqual(x.moves, [0, 1])
        XCTAssertTrue(x.undoTarget() === car, "the newest move that is still parked")
    }

    func testUndoCraneMove() {
        var events: [GameEvent] = []
        let (e, x) = make(1) { events.append($0) }
        ExtrasTest.run(e, x, 1.5)
        let bus = ExtrasTest.vehicle(e, 2)
        XCTAssertTrue(e.armCrane())
        e.onTap(bus.home)
        XCTAssertEqual(bus.state, .CRANE)
        ExtrasTest.run(e, x, 1.2)
        XCTAssertEqual(bus.state, .PARKED)
        XCTAssertTrue(e.slots[VIP_SLOT].vehicle === bus)

        XCTAssertTrue(x.undo())
        XCTAssertEqual(bus.state, .LOT)
        XCTAssertNil(e.slots[VIP_SLOT].vehicle)
        XCTAssertFalse(e.grid.isFree(bus.spec), "blocked by the car again")
        XCTAssertEqual(e.boostersUsed, 2)
        ExtrasTest.run(e, x, 0.4)
        XCTAssertGreaterThan(bus.lift, 0, "flies back on the crane")
        ExtrasTest.run(e, x, 1)
        XCTAssertEqual(bus.pos, bus.home)
        XCTAssertEqual(bus.lift, 0)
        XCTAssertTrue(e.armCrane(), "the VIP spot is free again")
        e.craneArmed = false

        for id in [0, 1, 2] {
            e.onTap(ExtrasTest.vehicle(e, id).home)
            ExtrasTest.run(e, x, 3)
        }
        ExtrasTest.run(e, x, 3)
        XCTAssertEqual(events.last, .Won(stars: 2), "crane + undo = two boosters")
    }

    func testUndoGetsAStuckLevelGoing() throws {
        var events: [GameEvent] = []
        let (e, x) = make(40) { events.append($0) }
        ExtrasTest.run(e, x, 2.5)
        var parked = 0
        while parked < 4 {
            let front = e.queue[e.qHead]
            let v = try XCTUnwrap(e.vehicles.first { $0.state == .LOT && e.grid.isFree($0.spec) && $0.color != front })
            e.onTap(v.home)
            parked += 1
            ExtrasTest.run(e, x, 0.2)
        }
        XCTAssertTrue(ExtrasTest.runUntil(e, x) { e.phase == .STUCK })
        XCTAssertEqual(events.last, .Stuck)
        let last = ExtrasTest.vehicle(e, x.moves.last!)
        XCTAssertTrue(x.undo())
        XCTAssertEqual(last.state, .LOT)
        XCTAssertEqual(e.phase, .PLAYING)
        XCTAssertTrue(e.slots[0..<SLOT_COUNT].contains { $0.free })
        ExtrasTest.run(e, x, 1)
        XCTAssertEqual(e.phase, .PLAYING, "a free spot: not stuck any more")
    }

    func testRewindFollowsTheExitPathBackwards() throws {
        let (e, x) = make(40)
        ExtrasTest.run(e, x, 2.5)
        let front = e.queue[e.qHead]
        let v = try XCTUnwrap(e.vehicles.first { $0.state == .LOT && e.grid.isFree($0.spec) && $0.color != front })
        e.onTap(v.home)
        ExtrasTest.run(e, x, 1.5)
        XCTAssertEqual(v.state, .PARKED)
        let m = try XCTUnwrap(v.measure)
        XCTAssertTrue(x.undo())
        // Half way through the rewind the vehicle is on its own path.
        ExtrasTest.run(e, x, ExtrasSession.REWIND_TIME * 0.5)
        var best = Float.greatestFiniteMagnitude
        var d: Float = 0
        while d <= m.length {
            best = min(best, (m.getPosTan(d).pos - v.pos).getDistance())
            d += 1
        }
        XCTAssertLessThan(best, 1.5)
        ExtrasTest.run(e, x, 1)
        XCTAssertEqual(v.pos, v.home)
    }
}
