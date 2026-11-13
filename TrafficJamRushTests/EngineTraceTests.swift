import XCTest
@testable import TrafficJamRush

/// The real Android GameEngine was driven on the JVM by a deterministic bot (Golden/source/GoldenDumpTest.kt,
/// android.graphics.Path/PathMeasure backed by real Skia through Skiko). This replays the same bot against the
/// Swift engine and requires the same trace: every tap, sound (with its random pitch), haptic, event, booster,
/// phase, queue, slot, walker and vehicle state, and positions / headings / scales to float precision.
@MainActor
final class EngineTraceTests: XCTestCase {

    private final class Recorder: GameFx {
        var out: [String] = []
        var frame = 0
        func sfx(_ s: Sfx, _ rate: Float) { out.append("S|\(frame)|\(s.name)|\(Golden.f(rate))") }
        func haptic(_ h: Haptic) { out.append("H|\(frame)|\(h.rawValue)") }
    }

    private func f(_ x: Float) -> String { Golden.f(x) }

    private func trace(_ n: Int, _ w: Float, _ h: Float, _ top: Float, _ bottom: Float) -> [String] {
        let level = LevelGenerator.generate(n)
        let rec = Recorder()
        let e = GameEngine(level, Themes.forLevel(n), Skin.CLASSIC, fx: rec, headless: true)
        e.onEvent = { ev in
            let s: String
            switch ev {
            case .Won(let stars): s = "Won:\(stars)"
            case .Stuck: s = "Stuck"
            case .LockedSlot(let index): s = "LockedSlot:\(index)"
            case .NoSpace: s = "NoSpace"
            case .VipBusy: s = "VipBusy"
            }
            rec.out.append("E|\(rec.frame)|" + s)
        }
        e.setSize(w, h, top, bottom)
        let lay = e.layout!
        var l = "L|\(f(lay.u))|\(f(lay.unit))|\(f(lay.slotUnit))|\(f(lay.cosR))|\(f(lay.sinR))|\(f(lay.boardCenter.x))|\(f(lay.boardCenter.y))|"
        l += "\(f(lay.track.left))|\(f(lay.track.top))|\(f(lay.track.right))|\(f(lay.track.bottom))|"
        l += "\(f(lay.roadY))|\(f(lay.queueVisibleLength))|\(f(lay.queueSign.x))|\(f(lay.queueSign.y))"
        for i in 0...SLOT_COUNT {
            let s = lay.slotRect(i)
            l += "|\(f(s.left)):\(f(s.top)):\(f(s.right)):\(f(s.bottom))"
        }
        for v in e.vehicles { l += "|\(f(v.home.x)):\(f(v.home.y)):\(f(v.heading)):\(f(v.popDelay))" }
        rec.out.append(l)

        let dts: [Float] = [1 / 60, 1 / 60, 1 / 120, 1 / 60, 0.05, 1 / 60, 1 / 90]
        var actions = 0
        var stuckCount = 0

        func tapAt(_ p: Offset) {
            rec.out.append("T|\(rec.frame)|\(f(p.x))|\(f(p.y))")
            e.onTap(p)
        }

        func act() {
            actions += 1
            switch actions {
            case 3:
                tapAt(e.slotCenter(5))
                if !e.slots[5].open { e.unlockSlot(5) }
                return
            case 7:
                if level.number % 3 == 0 {
                    rec.out.append("B|\(rec.frame)|shuffle")
                    e.shuffle()
                    return
                }
            case 9:
                if level.number % 2 == 0 {
                    let ok = e.armCrane()
                    rec.out.append("B|\(rec.frame)|crane:\(ok)")
                    if ok {
                        let lotNow = e.vehicles.filter { $0.state == .LOT }
                        if let target = lotNow.first(where: { !e.grid.isFree($0.spec) }) ?? lotNow.first { tapAt(target.home) }
                    }
                    return
                }
            case 12:
                if level.number % 4 == 1 {
                    rec.out.append("B|\(rec.frame)|sort")
                    e.useSort()
                    return
                }
            default:
                break
            }
            let lot = e.vehicles.filter { $0.state == .LOT }
            if lot.isEmpty || actions % 13 == 6 {
                tapAt(Offset(lay.width * 0.5, lay.height - 2))
                return
            }
            let front = e.qHead < e.queue.count ? e.queue[e.qHead] : -1
            let free = lot.filter { e.grid.isFree($0.spec) }
            let blocked = lot.filter { !e.grid.isFree($0.spec) && $0.bumpT < 0 }
            if actions % 5 == 2 && !blocked.isEmpty {
                tapAt(blocked[actions % blocked.count].home)
                return
            }
            var pick = free.first { $0.color == front }
            if pick == nil {
                var bestKey = Int.max
                for v in free {
                    var i = e.qHead
                    while i < e.queue.count && e.queue[i] != v.color { i += 1 }
                    if pick == nil || i < bestKey {
                        pick = v
                        bestKey = i
                    }
                }
            }
            if let pick { tapAt(pick.home) }
        }

        loop: while rec.frame < 20000 {
            e.update(dts[rec.frame % dts.count])
            rec.frame += 1
            if rec.frame % 8 == 0 { rec.out.append(snapshot(e, rec.frame)) }
            if e.phase == .WON { break }
            if e.phase == .STUCK {
                stuckCount += 1
                rec.out.append("B|\(rec.frame)|stuck:\(stuckCount)")
                switch stuckCount {
                case 1, 3, 4: e.revive()
                case 2: e.useSort()
                default: break loop
                }
                continue
            }
            if e.phase != .PLAYING || rec.frame % 10 != 5 { continue }
            act()
        }
        rec.out.append(snapshot(e, rec.frame))
        rec.out.append("END|\(rec.frame)|\(e.phase)|\(e.boostersUsed)|\(e.revivesUsed)|\(e.remaining)|\(e.qHead)")
        return rec.out
    }

    private func snapshot(_ e: GameEngine, _ frame: Int) -> String {
        var s = "F|\(frame)|\(e.phase)|\(e.remaining)|\(e.qHead)|\(e.walkers.count)|\(e.particles.list.count)|\(e.craneArmed)"
        s += "|\(f(e.screenShake.x))|\(f(e.screenShake.y))"
        s += "|\(f(e.qHead < e.queue.count ? e.qS[e.qHead] : -1))"
        s += "|\(e.queue.count):\(e.queue.reduce(0, +)):" + e.queue.dropFirst(e.qHead).prefix(12).map(String.init).joined()
        s += "|" + e.slots.map { sl in !sl.open ? "x" : (sl.vehicle.map { String($0.id) } ?? ".") }.joined(separator: ",")
        for w in e.walkers {
            let p = e.walkerPos(w)
            s += "|w:\(w.color):\(w.vehicle.id):\(f(w.t)):\(f(p.x)):\(f(p.y))"
        }
        for v in e.vehicles {
            let moving = v.state != .LOT && v.state != .GONE
            let interesting = moving || v.bumpT >= 0 || v.shakeT >= 0 || v.flipT >= 0 || (v.popT < 1 && frame == 32)
            if !interesting { continue }
            if v.state == .PARKED && v.bounceT < 0 && v.shakeT < 0 && v.flipT < 0 {
                s += "|p\(v.id):\(v.slot):\(v.filled):\(v.reserved):\(v.color):\(v.parkedOrder):\(f(v.departDelay))"
                continue
            }
            s += "|v\(v.id):\(v.state):\(v.slot):\(v.filled):\(v.reserved):\(v.color):\(v.mystery):\(v.parkedOrder):\(v.departPhase)"
            s += ":\(f(v.pos.x)):\(f(v.pos.y)):\(f(v.heading)):\(f(v.scale)):\(f(v.lift))"
            s += ":\(f(v.bumpT)):\(f(v.shakeT)):\(f(v.flipT)):\(f(v.popT)):\(f(v.bounceT))"
            s += ":\(f(v.departDelay)):\(f(v.t))"
            if v.state == .EXITING { s += ":\(f(v.pathLen)):\(f(v.duration))" }
        }
        if e.level.number == 1 {
            s += "|tut:\(e.tutorialText ?? "-"):\(f(e.tutorialPoint?.x ?? -1)):\(f(e.tutorialPoint?.y ?? -1))"
        }
        if let vip = e.slots[VIP_SLOT].vehicle { s += "|vip:\(vip.id)" }
        return s
    }

    func testComparatorCatchesDifferences() {
        let tol = Golden.Tolerance(abs: 2e-3, rel: 2e-5)
        var m: Float = 0
        let a = "F|8|PLAYING|20|~541.8333|v0:EXITING:~369.0"
        XCTAssertNil(Golden.compare(a, a, tol, maxDiff: &m))
        XCTAssertNil(Golden.compare("x|~1.0E-5", "x|~1e-05", tol, maxDiff: &m), "same float, other spelling")
        XCTAssertNotNil(Golden.compare(a, "F|8|PLAYING|21|~541.8333|v0:EXITING:~369.0", tol, maxDiff: &m))
        XCTAssertNotNil(Golden.compare(a, "F|8|PLAYING|20|~541.9|v0:EXITING:~369.0", tol, maxDiff: &m))
        XCTAssertNotNil(Golden.compare(a, "F|8|PLAYING|20|~541.8333|v0:PARKED:~369.0", tol, maxDiff: &m))
        XCTAssertNotNil(Golden.compare(a, a + "|x", tol, maxDiff: &m))
    }

    func testEngineTracesMatchAndroid() throws {
        let traces = try XCTUnwrap(try Golden.json("traces")["traces"] as? [[String: Any]])
        XCTAssertEqual(traces.count, 18)
        let tol = Golden.Tolerance(abs: 2e-3, rel: 2e-5)
        var maxDiff: Float = 0
        var matched = 0
        var lines = 0
        for t in traces {
            let n = try XCTUnwrap(t["n"] as? Int)
            let w = try XCTUnwrap((t["w"] as? NSNumber)?.floatValue)
            let h = try XCTUnwrap((t["h"] as? NSNumber)?.floatValue)
            let top = try XCTUnwrap((t["top"] as? NSNumber)?.floatValue)
            let bottom = try XCTUnwrap((t["bottom"] as? NSNumber)?.floatValue)
            let golden = try XCTUnwrap(t["lines"] as? [String])
            let mine = trace(n, w, h, top, bottom)
            lines += golden.count
            var failure: String?
            for i in 0..<max(golden.count, mine.count) {
                guard i < golden.count, i < mine.count else {
                    failure = "line \(i): android \(i < golden.count ? golden[i] : "<end>")\n ios \(i < mine.count ? mine[i] : "<end>")"
                    break
                }
                if let d = Golden.compare(golden[i], mine[i], tol, maxDiff: &maxDiff) {
                    failure = "line \(i) (\(d))\n android: \(golden[i])\n ios:     \(mine[i])"
                    break
                }
            }
            if let failure {
                XCTFail("level \(n) \(w)x\(h): trace diverges at \(failure)")
            } else {
                matched += 1
            }
        }
        print("Golden traces: \(matched)/\(traces.count) runs match Android (\(lines) lines, max relative float diff \(maxDiff))")
    }
}
