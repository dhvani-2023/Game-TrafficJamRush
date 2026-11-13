import SwiftUI
import GameKit

/// Undo booster rules (engine-level helpers; the per-level move log and animations live in ExtrasSession).
enum ExtrasUndo {

    /// A vehicle's move can be undone until it starts to depart: driving to its spot, being craned, or parked
    /// (even full and about to leave).
    static func canUndo(_ v: Vehicle) -> Bool {
        v.state == .EXITING || v.state == .CRANE || v.state == .PARKED
    }

    /// The path `drive()` would have built from the vehicle's lot spot to [slot] (used after a resume, when the
    /// vehicle was parked without driving in this session).
    @MainActor
    static func buildExitPath(_ e: GameEngine, _ v: Vehicle, lotHeading: Float, slot: Int) {
        guard let lay = e.layout else { return }
        let pts = e.exitPoints(v.home, e.headingVec(lotHeading), e.slotCenter(slot))
        let m = PathMeasure()
        m.setPath(e.roundedPath(pts, 16 * lay.u), false)
        v.measure = m
        v.pathLen = m.length
    }

    static func shortestAngle(_ from: Float, _ to: Float) -> Float {
        var d = Kt.rem(to - from, 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

/// Per-level companion of GameEngine for the extras: the Undo move log, the undo "rewind" (the vehicle reverses
/// along its own path, its passengers hop back to the front of the line while the line steps back), and the
/// autosave / resume of this level. `tick` runs right after `engine.update` each frame; `draw` after the renderer.
@MainActor
final class ExtrasSession {
    let engine: GameEngine
    /// Normal level number (0 for a daily puzzle).
    let levelNumber: Int
    let day: ExtrasDay?

    /// Ids of vehicles in the order they left the lot (Undo takes the newest that hasn't departed).
    private(set) var moves: [Int] = []
    /// Snapshot to apply once the level is laid out (Home ▸ Continue).
    var resume: ExtrasSnapshot?
    private(set) var resumed = false

    nonisolated static let REWIND_TIME: Float = 0.5
    nonisolated static let CRANE_REWIND_TIME: Float = 0.75
    nonisolated static let HOP_TIME: Float = 0.3
    nonisolated static let HOP_STAGGER: Float = 0.05
    nonisolated static let SLIDE_TIME: Float = 0.3

    private final class Rewind {
        let v: Vehicle
        let crane: Bool
        /// Drive: distance along the exit path to rewind from. Crane: flight progress (0…1) to rewind from.
        let from: Float
        let startScale: Float
        let lotHeading: Float
        let duration: Float
        var t: Float = 0

        init(_ v: Vehicle, crane: Bool, from: Float, startScale: Float, lotHeading: Float, duration: Float) {
            self.v = v
            self.crane = crane
            self.from = from
            self.startScale = startScale
            self.lotHeading = lotHeading
            self.duration = duration
        }
    }

    private struct Hop {
        /// Queue index the passenger returns to (hidden until it lands).
        let index: Int
        let color: Int
        let from: Offset
        /// Seconds since the hop started (negative while waiting for its turn).
        var t: Float
    }

    private struct Slide {
        /// First queue index of the passengers already waiting (they step back to make room).
        let from: Int
        let amount: Float
        var t: Float = 0

        var remaining: Float {
            let p = Swift.min(1, t / ExtrasSession.SLIDE_TIME)
            return amount * (1 - p) * (1 - p)
        }
    }

    private var rewinds: [Rewind] = []
    private var hops: [Hop] = []
    private var slide: Slide?

    init(engine: GameEngine, levelNumber: Int, day: ExtrasDay?) {
        self.engine = engine
        self.levelNumber = levelNumber
        self.day = day
        engine.onVehicleMove = { [weak self] v in self?.moves.append(v.id) }
    }

    /// True while an undo animation is still playing.
    var animating: Bool { !rewinds.isEmpty || !hops.isEmpty || slide != nil }

    // --- Undo --------------------------------------------------------------------------------

    /// The vehicle Undo would send back: the newest move whose vehicle hasn't started to depart.
    func undoTarget() -> Vehicle? {
        for id in moves.reversed() {
            if let v = engine.vehicles.first(where: { $0.id == id }), ExtrasUndo.canUndo(v) { return v }
        }
        return nil
    }

    /// Undoes the newest move that hasn't departed. Returns false (nothing changes, no booster spent) when there is
    /// none or the level isn't being played.
    @discardableResult
    func undo() -> Bool {
        let e = engine
        guard e.ready, let lay = e.layout, e.phase == .PLAYING || e.phase == .STUCK, let v = undoTarget() else { return false }
        let k = v.filled + v.reserved
        guard e.qHead >= k else { return false }

        // Passengers: the seated ones (boarded first) then the ones mid-hop return to the front of the line, in order.
        var sources: [Offset] = []
        let roof = v.pos - Offset(0, 8 * lay.u)
        for j in 0..<v.filled {
            sources.append(roof + Offset((j % 2 == 0 ? -4 : 4) * lay.u, Float(j / 2) * 3 * lay.u))
        }
        for w in e.walkers where w.vehicle === v { sources.append(e.walkerPos(w)) }
        e.walkers.removeAll { $0.vehicle === v }
        let oldHead = e.qHead
        let newHead = oldHead - k
        if k > 0 {
            let hidden = lay.queueVisibleLength + 10_000 * lay.u
            for (j, i) in (newHead..<oldHead).enumerated() {
                e.queue[i] = v.color
                e.qS[i] = hidden
                hops.append(Hop(index: i, color: v.color, from: j < sources.count ? sources[j] : roof, t: -Float(j) * Self.HOP_STAGGER))
            }
            e.qHead = newHead
            let carry = slide?.remaining ?? 0
            slide = Slide(from: oldHead, amount: Float(k) * lay.passengerSpacing + carry)
        }

        // The vehicle reverses out of its spot along the way it came.
        let slot = v.slot
        if slot >= 0 && slot <= VIP_SLOT && e.slots[slot].vehicle === v { e.slots[slot].vehicle = nil }
        let crane = slot == VIP_SLOT
        let lotHeading = lay.rotationDeg + v.spec.dir.degrees
        var from: Float
        switch v.state {
        case .EXITING:
            let p = (v.t / v.duration).coerceIn(0, 1)
            from = v.pathLen * (1 - Kt.pow(1 - p, 2.3))
        case .CRANE:
            from = (v.t / v.duration).coerceIn(0, 1)
        default:
            from = crane ? 1 : v.pathLen
        }
        if !crane && v.measure == nil {
            ExtrasUndo.buildExitPath(e, v, lotHeading: lotHeading, slot: Swift.max(0, slot))
            from = v.pathLen
        }
        let fraction = crane ? from : (v.pathLen > 0 ? from / v.pathLen : 0)
        let duration = (crane ? Self.CRANE_REWIND_TIME : Self.REWIND_TIME) * (0.45 + 0.55 * fraction)
        rewinds.append(Rewind(v, crane: crane, from: from, startScale: v.scale, lotHeading: lotHeading, duration: duration))
        e.particles.stars(v.pos, 8)

        v.state = .LOT
        v.slot = -1
        v.filled = 0
        v.reserved = 0
        v.departDelay = -1
        v.departPhase = 0
        v.bounceT = -1
        v.bumpT = -1
        v.flipT = -1
        v.t = 0
        e.grid.put(v.spec)
        if let i = moves.lastIndex(of: v.id) { moves.remove(at: i) }

        // Counts as a booster for stars.
        e.boostersUsed += 1
        if e.phase == .STUCK { e.phase = .PLAYING }
        e.stuckTimer = 0
        e.fx.sfx(.Whoosh)
        e.fx.sfx(.Booster)
        e.fx.haptic(.Tap)
        // Draw the rewinding vehicle slice by slice (like any moving vehicle) right away.
        v.shakeT = 1
        return true
    }

    /// Runs after `engine.update`: drives the rewinds, the returning passengers and the line stepping back.
    func tick(_ dtRaw: Float) {
        guard animating, engine.ready, let lay = engine.layout else { return }
        let e = engine
        let dt = Kt.min(dtRaw, 1 / 30)

        // Rewinding vehicles (a tap during the rewind may have sent one off again: it then stops rewinding).
        var r = 0
        while r < rewinds.count {
            let w = rewinds[r]
            let v = w.v
            if v.state != .LOT {
                v.lift = 0
                rewinds.remove(at: r)
                continue
            }
            w.t += dt
            let q = Kt.min(1, w.t / w.duration)
            let ease = q * q * (3 - 2 * q)
            if w.crane {
                let p = w.from * (1 - ease)
                let ee = p * p * (3 - 2 * p)
                let o = 1 - ee
                v.pos = v.craneFrom * (o * o) + v.craneCtrl * (2 * o * ee) + v.craneTo * (ee * ee)
                v.lift = Kt.sin(p * Float.pi)
                v.scale = v.startScale + (v.endScale - v.startScale) * ee + v.lift * 0.25
                v.heading = v.startHeading + ExtrasUndo.shortestAngle(v.startHeading, 0) * ee
            } else if let m = v.measure {
                let (pos, tan) = m.getPosTan(w.from * (1 - ease))
                v.pos = pos
                if tan.getDistance() > 0.01 { v.heading = Kt.atan2(tan.x, -tan.y) * 180 / Float.pi }
                v.scale = w.startScale + (1 - w.startScale) * ease
            }
            v.shakeT = 1 // slice drawing while moving; no visible shake at shakeT 1
            if q >= 1 {
                v.pos = v.home
                v.heading = w.lotHeading
                v.scale = 1
                v.lift = 0
                v.shakeT = -1
                v.bounceT = 0
                e.particles.smoke(v.pos, count: 4)
                e.fx.sfx(.Park)
                rewinds.remove(at: r)
                continue
            }
            r += 1
        }

        let sp = lay.passengerSpacing
        // The line steps back to make room.
        if var s = slide {
            s.t += dt
            let rem = s.remaining
            let visible = Kt.toInt(lay.queueVisibleLength / sp) + 3
            let start = Swift.max(s.from, e.qHead)
            let end = Swift.min(e.queue.count, e.qHead + visible)
            if start < end {
                for i in start..<end {
                    let target = Float(i - e.qHead) * sp
                    if e.qS[i] <= target + 0.5 { e.qS[i] = target - rem }
                }
            }
            slide = s.t >= Self.SLIDE_TIME ? nil : s
        }

        // Passengers hop back; each one reappears in the line when it lands.
        if !hops.isEmpty {
            let hidden = lay.queueVisibleLength + 10_000 * lay.u
            var landed = false
            var j = 0
            while j < hops.count {
                hops[j].t += dt
                let h = hops[j]
                if h.t >= Self.HOP_TIME || h.index < e.qHead {
                    if h.index >= e.qHead && h.index < e.qS.count { e.qS[h.index] = Float(h.index - e.qHead) * sp }
                    landed = true
                    hops.remove(at: j)
                    continue
                }
                if h.index < e.qS.count { e.qS[h.index] = hidden }
                j += 1
            }
            if landed && hops.isEmpty { e.fx.sfx(.Pop2, 1.1) }
        }
    }

    /// Draws the returning passengers (and the crane cable of a craned vehicle flying back), over the board.
    func draw(_ ctx: inout GraphicsContext) {
        guard !hops.isEmpty || rewinds.contains(where: { $0.crane }), let lay = engine.layout, let pa = engine.passengerArt else { return }
        let e = engine
        var s = FrameScope(ctx, Size(lay.width, lay.height))
        let shake = e.screenShake
        let u = lay.u
        let sp = lay.passengerSpacing
        let hops = self.hops
        let rewinds = self.rewinds
        s.translate(shake.x, shake.y) { s in
            for w in rewinds where w.crane && w.v.lift > 0.02 {
                let v = w.v
                s.drawLine(ArtColor(0xFF45_5A64), Offset(v.pos.x, -10 * Art.px), v.pos - Offset(0, 6 * u), 2.5 * u, .round)
                s.drawCircle(ArtColor(0xFFFF_C107), 5 * u, v.pos - Offset(0, 6 * u))
            }
            let pw = pa.w
            let ph = pa.h
            for h in hops where h.t >= 0 {
                let p = Kt.min(1, h.t / Self.HOP_TIME)
                let ease = 1 - (1 - p) * (1 - p)
                let to = lay.queuePoint(Float(h.index - e.qHead) * sp)
                let pos = h.from + (to - h.from) * ease - Offset(0, Kt.sin(p * Float.pi) * 30 * u)
                let sc = 0.65 + 0.35 * p
                s.withTransform({ t in t.scale(sc, sc, pos) }) { s in
                    s.drawImage(pa.get(h.color, Kt.toInt(p * 8) % 4), Offset(pos.x - pw / 2, pos.y - ph))
                }
            }
        }
    }

    // --- Autosave ----------------------------------------------------------------------------

    private func belongs(_ s: ExtrasSnapshot) -> Bool {
        if let day { return s.day == day.epochDay }
        return s.day == nil && s.level == levelNumber
    }

    /// Saves this level (app going to the background). An untouched level just drops its old save.
    func autosave() {
        guard ExtrasFeatures.autosave else { return }
        let repo = App.container.extras
        guard ExtrasAutosave.touched(engine, moves: moves) else {
            clearSave()
            return
        }
        if let s = ExtrasAutosave.capture(engine, day: day?.epochDay, moves: moves) { repo.saveGame(s) }
    }

    /// Win, fail or quit: this level's save is no longer needed.
    func clearSave() {
        let repo = App.container.extras
        if let s = repo.savedGame, belongs(s) { repo.clearSavedGame() }
    }

    /// Applies the Home ▸ Continue snapshot once the level is laid out (call right after `setSize`).
    func applyResume() {
        guard !resumed, let s = resume else { return }
        resumed = true
        resume = nil
        if ExtrasAutosave.restore(engine, s) {
            moves = s.moves
        } else {
            clearSave()
        }
    }
}
