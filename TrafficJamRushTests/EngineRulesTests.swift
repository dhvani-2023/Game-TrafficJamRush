import XCTest
@testable import TrafficJamRush

/// Rules of GameEngine.kt that the golden traces do not reach on their own: a perfect run earns 3 stars,
/// the star rule (3 / 2 with up to two helps / else 1), the VIP spot being taken, and the full lot.
@MainActor
final class EngineRulesTests: XCTestCase {

    private struct NoFx: GameFx {
        func sfx(_ s: Sfx, _ rate: Float) {}
        func haptic(_ h: Haptic) {}
    }

    private func makeEngine(_ n: Int, _ events: @escaping (GameEvent) -> Void) -> GameEngine {
        let e = GameEngine(LevelGenerator.generate(n), Themes.forLevel(n), Skin.CLASSIC, fx: NoFx(), onEvent: events, headless: true)
        e.setSize(393, 852, 59, 34)
        return e
    }

    private func run(_ e: GameEngine, _ seconds: Float) {
        var t: Float = 0
        while t < seconds {
            e.update(1 / 60)
            t += 1 / 60
        }
    }

    private func vehicle(_ e: GameEngine, _ id: Int) -> Vehicle { e.vehicles.first { $0.id == id }! }

    func testPerfectTutorialEarnsThreeStars() {
        var events: [GameEvent] = []
        let e = makeEngine(1) { events.append($0) }
        XCTAssertTrue(e.ready)
        XCTAssertEqual(e.phase, .INTRO)
        run(e, 1.5)
        XCTAssertEqual(e.phase, .PLAYING)
        XCTAssertEqual(e.tutorialText, "Tap the van! A van carries 6 passengers of its color.")
        // Blocked bus: lurches and springs back, stays in the lot.
        e.onTap(vehicle(e, 2).home)
        XCTAssertEqual(vehicle(e, 2).bumpT, 0)
        run(e, 0.6)
        XCTAssertEqual(vehicle(e, 2).state, .LOT)
        XCTAssertEqual(vehicle(e, 2).pos, vehicle(e, 2).home)
        for id in [0, 1, 2] {
            e.onTap(vehicle(e, id).home)
            XCTAssertNotEqual(vehicle(e, id).state, .LOT, "vehicle \(id) drives off")
            run(e, 3)
        }
        run(e, 3)
        XCTAssertEqual(e.phase, .WON)
        XCTAssertEqual(e.remaining, 0)
        XCTAssertEqual(events.last, .Won(stars: 3))
        XCTAssertNil(e.tutorialText)
        XCTAssertNil(e.tutorialPoint)
    }

    func testStarRule() {
        for (helps, stars) in [(1, 2), (2, 2), (3, 1)] {
            var events: [GameEvent] = []
            let e = makeEngine(1) { events.append($0) }
            run(e, 1.5)
            for _ in 0..<helps { e.useSort() }
            for id in [0, 1, 2] {
                e.onTap(vehicle(e, id).home)
                run(e, 3)
            }
            run(e, 3)
            XCTAssertEqual(events.last, .Won(stars: stars), "\(helps) boosters")
        }
    }

    func testCraneUsesTheVipSpotOnce() {
        var events: [GameEvent] = []
        let e = makeEngine(1) { events.append($0) }
        run(e, 1.5)
        XCTAssertTrue(e.armCrane())
        XCTAssertTrue(e.craneArmed)
        e.onTap(vehicle(e, 2).home) // the blocked bus
        XCTAssertFalse(e.craneArmed)
        XCTAssertEqual(vehicle(e, 2).state, .CRANE)
        XCTAssertTrue(e.slots[VIP_SLOT].vehicle === vehicle(e, 2))
        XCTAssertEqual(e.boostersUsed, 1)
        XCTAssertFalse(e.armCrane())
        XCTAssertEqual(events.last, .VipBusy)
        run(e, 1.2)
        XCTAssertEqual(vehicle(e, 2).state, .PARKED)
        XCTAssertEqual(vehicle(e, 2).pos, e.slotCenter(VIP_SLOT))
    }

    func testLockedSlotsAndFullLot() throws {
        var events: [GameEvent] = []
        let e = makeEngine(40) { events.append($0) }
        run(e, 2.5)
        XCTAssertEqual(e.phase, .PLAYING)
        XCTAssertEqual(e.slots.map(\.open), [true, true, true, true, false, false, false, true])
        e.onTap(e.slotCenter(6))
        XCTAssertEqual(events.last, .LockedSlot(index: 6))
        // Park free vehicles that nobody waits for until the four open spots are full.
        var parked = 0
        while parked < 4 {
            let front = e.queue[e.qHead]
            let v = try XCTUnwrap(e.vehicles.first { $0.state == .LOT && e.grid.isFree($0.spec) && $0.color != front })
            e.onTap(v.home)
            parked += 1
            run(e, 0.2)
        }
        let extra = try XCTUnwrap(e.vehicles.first { $0.state == .LOT && e.grid.isFree($0.spec) })
        e.onTap(extra.home)
        XCTAssertEqual(events.last, .NoSpace)
        XCTAssertEqual(extra.state, .LOT)
        XCTAssertEqual(extra.shakeT, 0)
        e.unlockSlot(4)
        XCTAssertTrue(e.slots[4].open)
    }
}
