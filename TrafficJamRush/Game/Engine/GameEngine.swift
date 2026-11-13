import SwiftUI
import CoreGraphics
import Observation
import GameKit

// Port of game/engine/GameEngine.kt. Compose snapshot state → @Observable (only the Kotlin `mutableStateOf`
// properties are observed; everything per-frame is @ObservationIgnored). Compose Path/PathMeasure/Offset →
// EnginePath / PathMeasure (Skia-exact port) / Offset (Float). Every RNG use, Float operation order and
// timing constant is kept; verified against the real Android engine in TrafficJamRushTests/EngineTraceTests.

@MainActor
protocol GameFx {
    func sfx(_ s: Sfx, _ rate: Float)
    func haptic(_ h: Haptic)
}

extension GameFx {
    func sfx(_ s: Sfx) { sfx(s, 1) }
}

/// Closure-backed GameFx (Kotlin used an anonymous `object : GameFx`).
struct AnyGameFx: GameFx {
    let onSfx: @MainActor (Sfx, Float) -> Void
    let onHaptic: @MainActor (Haptic) -> Void

    init(sfx: @escaping @MainActor (Sfx, Float) -> Void, haptic: @escaping @MainActor (Haptic) -> Void) {
        onSfx = sfx
        onHaptic = haptic
    }

    func sfx(_ s: Sfx, _ rate: Float) { onSfx(s, rate) }
    func haptic(_ h: Haptic) { onHaptic(h) }
}

enum GameEvent: Equatable {
    case Won(stars: Int)
    case Stuck
    case LockedSlot(index: Int)
    case NoSpace
    case VipBusy
}

enum Phase { case INTRO, PLAYING, STUCK, WON }

enum VState { case LOT, EXITING, PARKED, DEPARTING, CRANE, GONE }

final class Vehicle {
    let spec: VehicleSpec
    var id: Int { spec.id }
    var type: VehicleType { spec.type }
    var seats: Int { spec.type.seats }
    var color: Int
    var mystery: Bool
    var state = VState.LOT
    var slot = -1
    var filled = 0
    var reserved = 0
    var parkedOrder = 0

    // Transform
    var pos = Offset.Zero
    var home = Offset.Zero
    var heading: Float = 0
    var scale: Float = 1
    var lift: Float = 0

    // Animation clocks (seconds; < 0 means idle)
    var t: Float = 0
    var duration: Float = 0
    var measure: PathMeasure?
    var pathLen: Float = 0
    var startScale: Float = 1
    var endScale: Float = 1
    var bumpT: Float = -1
    var bumpPx: Float = 0
    var bumped = false
    var shakeT: Float = -1
    var popT: Float = 0
    var popDelay: Float = 0
    var bounceT: Float = -1
    var flipT: Float = -1
    var departDelay: Float = -1
    var departPhase = 0
    var departFromX: Float = 0
    var smokeClock: Float = 0
    var craneFrom = Offset.Zero
    var craneCtrl = Offset.Zero
    var craneTo = Offset.Zero
    var startHeading: Float = 0

    init(_ spec: VehicleSpec) {
        self.spec = spec
        color = spec.color
        mystery = spec.mystery
    }

    var inSlot: Bool { state == .PARKED || (state == .DEPARTING && departPhase == 0) }
}

final class Walker {
    let color: Int
    let from: Offset
    let vehicle: Vehicle
    var t: Float = 0

    init(_ color: Int, _ from: Offset, _ vehicle: Vehicle) {
        self.color = color
        self.from = from
        self.vehicle = vehicle
    }
}

final class Slot {
    var open: Bool
    var vehicle: Vehicle?

    init(_ open: Bool) { self.open = open }

    var free: Bool { open && vehicle == nil }
}

/// Owns all live game state and advances it each frame. Rendering reads it directly; SwiftUI
/// observes only the small set of Kotlin snapshot states (frame, phase, remaining, craneArmed,
/// tutorialPoint, tutorialText, scene).
@Observable
@MainActor
final class GameEngine {
    let level: Level
    let theme: SceneTheme
    private let skin: Skin
    let fx: GameFx
    @ObservationIgnored var onEvent: (GameEvent) -> Void
    /// Tests only: skip VehicleArt / PassengerArt / SceneArt (no bitmaps), everything else runs as normal.
    private let headless: Bool
    /// Extras: colour-blind symbols baked into the vehicle / passenger sprite caches.
    private let patterns: Bool
    /// Extras hook: called after a vehicle leaves the lot (drive or crane), for the Undo booster's move log.
    @ObservationIgnored var onVehicleMove: ((Vehicle) -> Void)?

    private(set) var frame: Int64 = 0
    var phase: Phase = .INTRO
    private(set) var remaining: Int
    var craneArmed = false
    private(set) var tutorialPoint: Offset?
    private(set) var tutorialText: String?

    @ObservationIgnored var boostersUsed = 0
    @ObservationIgnored var revivesUsed = 0

    let vehicles: [Vehicle]
    private let byId: [Int: Vehicle]
    let grid: LotGrid
    let slots: [Slot]

    @ObservationIgnored var queue: [Int]
    @ObservationIgnored var qHead = 0
    @ObservationIgnored var qS: [Float] = []
    @ObservationIgnored var walkers: [Walker] = []

    @ObservationIgnored private(set) var layout: GameLayout!
    @ObservationIgnored private(set) var art: VehicleArt!
    @ObservationIgnored private(set) var passengerArt: PassengerArt!
    private(set) var scene: ImageBitmap?
    @ObservationIgnored private(set) var particles: Particles!

    @ObservationIgnored private var time: Float = 0
    @ObservationIgnored var parkCounter = 0
    @ObservationIgnored private var boardCooldown: Float = 0
    @ObservationIgnored var stuckTimer: Float = 0
    @ObservationIgnored private var winTimer: Float = -1
    @ObservationIgnored private var popIndex = 0
    @ObservationIgnored private var shakeScreen: Float = 0
    private let rnd: KotlinRandom

    private static let PI = Float(Double.pi)

    init(_ level: Level, _ theme: SceneTheme, _ skin: Skin, fx: GameFx, onEvent: @escaping (GameEvent) -> Void = { _ in },
         headless: Bool = false, patterns: Bool = false) {
        self.level = level
        self.theme = theme
        self.skin = skin
        self.fx = fx
        self.onEvent = onEvent
        self.headless = headless
        self.patterns = patterns
        remaining = level.queue.count
        let vs = level.vehicles.map { Vehicle($0) }
        vehicles = vs
        var map: [Int: Vehicle] = [:]
        for v in vs { map[v.id] = v }
        byId = map
        let g = LotGrid(level.cols, level.rows)
        for v in level.vehicles { g.put(v) }
        grid = g
        slots = (0...SLOT_COUNT).map { i in Slot(i < level.openSlots || i == VIP_SLOT) }
        queue = level.queue
        rnd = KotlinRandom(intSeed: level.number)
    }

    var screenShake: Offset {
        if shakeScreen <= 0 { return .Zero }
        return Offset(Kt.sin(time * 90) * 3 * layout.u * shakeScreen, Kt.cos(time * 77) * 2 * layout.u * shakeScreen)
    }

    var ready: Bool { scene != nil }

    // --- Setup ------------------------------------------------------------------------------

    func setSize(_ width: Float, _ height: Float, _ topInset: Float, _ bottomInset: Float) {
        if let l = layout, l.width == width, l.height == height, l.topInset == topInset, l.bottomInset == bottomInset { return }
        let layout = GameLayout(width, height, topInset, bottomInset, level)
        self.layout = layout
        if !headless {
            art = VehicleArt(layout.unit, skin, patterns: patterns)
            passengerArt = PassengerArt(layout.passengerW, layout.passengerH, patterns: patterns)
        }
        particles = Particles(layout.u)
        scene = headless ? Self.placeholderScene : SceneArt.render(layout, level, theme)
        qS = (0..<queue.count).map { i in Float(i) * layout.passengerSpacing + layout.width * 0.6 }
        let count = Float(vehicles.count)
        for (i, v) in vehicles.enumerated() {
            v.home = layout.boardToScreen(v.spec.centerX, v.spec.centerY)
            if v.state == .LOT {
                v.pos = v.home
                v.heading = layout.rotationDeg + v.spec.dir.degrees
            }
            v.popDelay = 0.15 + Float(i) * Kt.min(0.018, 0.7 / count) + rnd.nextFloat() * 0.05
        }
        // Pre-build the 3D sprites the level opens with, plus the parked pose of each kind.
        if !headless {
            for v in vehicles {
                _ = art.composite(v.type, v.color, v.mystery, v.heading)
                _ = art.composite(v.type, v.color, false, 0)
                _ = art.shadow(v.type)
            }
        }
    }

    private static let placeholderScene: ImageBitmap? = {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return ctx?.makeImage().map { ImageBitmap($0, scale: 1) }
    }()

    func headingVec(_ deg: Float) -> Offset {
        let r = deg * Self.PI / 180
        return Offset(Kt.sin(r), -Kt.cos(r))
    }

    /// VehicleArt.bodyL (unit · length − 0.32 · unit); kept here so the engine runs without the sprite cache.
    private func bodyL(_ type: VehicleType) -> Float { layout.unit * Float(type.length) - layout.unit * 0.32 }

    var slotScale: Float { layout.slotUnit / layout.unit }

    func slotCenter(_ i: Int) -> Offset { layout.slotRect(i).center }

    // --- Input ------------------------------------------------------------------------------

    func onTap(_ p: Offset) {
        if !ready || phase != .PLAYING { return }
        particles.ring(p)

        for i in 0..<SLOT_COUNT where !slots[i].open && layout.slotRect(i).inflate(2 * layout.u).contains(p) {
            fx.sfx(.Click)
            onEvent(.LockedSlot(index: i))
            return
        }

        guard let v = hitVehicle(p) else { return }
        fx.haptic(.Tap)
        if craneArmed {
            crane(v)
            return
        }
        if v.bumpT >= 0 { return }
        let d = grid.blockDistance(v.spec)
        if d >= 0 {
            v.bumpT = 0
            v.bumped = false
            v.bumpPx = Kt.max(0.2, Float(d) + 0.1) * layout.unit
            fx.sfx(.Tap)
            return
        }
        guard let slot = (0..<SLOT_COUNT).first(where: { slots[$0].free }) else {
            v.shakeT = 0
            fx.sfx(.Warning)
            fx.haptic(.Bump)
            onEvent(.NoSpace)
            return
        }
        drive(v, slot)
    }

    private func hitVehicle(_ p: Offset) -> Vehicle? {
        let b = layout.screenToBoard(p)
        let gx = Kt.toInt(b.x)
        let gy = Kt.toInt(b.y)
        if b.x >= 0 && b.y >= 0 {
            let id = grid.at(gx, gy)
            if id >= 0 { return byId[id] }
        }
        // Forgiving fallback: nearest footprint within ~0.8 units.
        var best: Vehicle?
        var bestD: Float = 0.8
        for v in vehicles where v.state == .LOT {
            let s = v.spec
            let dx = Kt.max(0, Kt.max(Float(s.x) - b.x, b.x - Float(s.x + s.w)))
            let dy = Kt.max(0, Kt.max(Float(s.y) - b.y, b.y - Float(s.y + s.h)))
            let d = Kt.hypot(dx, dy)
            if d < bestD {
                bestD = d
                best = v
            }
        }
        return best
    }

    // --- Movement ---------------------------------------------------------------------------

    private func drive(_ v: Vehicle, _ slot: Int) {
        grid.remove(v.spec)
        slots[slot].vehicle = v
        v.slot = slot
        v.state = .EXITING
        v.t = 0
        v.startScale = 1
        v.endScale = slotScale
        let pts = exitPoints(v.pos, headingVec(v.heading), slotCenter(slot))
        let path = roundedPath(pts, 16 * layout.u)
        let m = PathMeasure()
        m.setPath(path, false)
        v.measure = m
        v.pathLen = m.length
        v.duration = (0.3 + v.pathLen / (1250 * layout.u)).coerceIn(0.5, 1.35)
        let hv = headingVec(v.heading)
        particles.smoke(v.pos - hv * (bodyL(v.type) / 2), -hv.x, -hv.y, count: 5)
        fx.sfx(.EngineGo, 0.95 + rnd.nextFloat() * 0.15)
        afterLotChange()
        onVehicleMove?(v)
    }

    func exitPoints(_ start: Offset, _ d: Offset, _ slot: Offset) -> [Offset] {
        let t = layout.track
        let eps: Float = 1e-4
        let tx: Float = d.x > eps ? (t.right - start.x) / d.x : (d.x < -eps ? (t.left - start.x) / d.x : Float.greatestFiniteMagnitude)
        let ty: Float = d.y > eps ? (t.bottom - start.y) / d.y : (d.y < -eps ? (t.top - start.y) / d.y : Float.greatestFiniteMagnitude)
        let k = Kt.min(tx, ty)
        let hit = Offset(
            (start.x + d.x * k).coerceIn(t.left, t.right),
            (start.y + d.y * k).coerceIn(t.top, t.bottom)
        )
        var pts = [start, hit]
        let onTop = ty <= tx && d.y < 0
        let onBottom = ty <= tx && d.y > 0
        let onRight = tx < ty && d.x > 0
        if onTop {
            // straight up onto the road
        } else if onBottom {
            let goLeft = (hit.x - t.left) < (t.right - hit.x)
            let sx = goLeft ? t.left : t.right
            pts.append(Offset(sx, t.bottom))
            pts.append(Offset(sx, t.top))
        } else if onRight {
            pts.append(Offset(t.right, t.top))
        } else {
            pts.append(Offset(t.left, t.top))
        }
        pts.append(Offset(slot.x, t.top))
        pts.append(slot)
        // drop near-duplicates
        var out: [Offset] = []
        for p in pts where out.isEmpty || (out[out.count - 1] - p).getDistance() > 2 { out.append(p) }
        return out
    }

    func roundedPath(_ pts: [Offset], _ radius: Float) -> EnginePath {
        var path = EnginePath()
        path.moveTo(pts[0].x, pts[0].y)
        if pts.count > 2 {
            for i in 1..<(pts.count - 1) {
                let a = pts[i - 1]
                let b = pts[i]
                let c = pts[i + 1]
                let inLen = (b - a).getDistance()
                let outLen = (c - b).getDistance()
                let r = Kt.min(radius, Kt.min(inLen, outLen) / 2)
                let p1 = b - (b - a) / inLen * r
                let p2 = b + (c - b) / outLen * r
                path.lineTo(p1.x, p1.y)
                path.quadraticTo(b.x, b.y, p2.x, p2.y)
            }
        }
        path.lineTo(pts[pts.count - 1].x, pts[pts.count - 1].y)
        return path
    }

    private func crane(_ v: Vehicle) {
        let vip = slots[VIP_SLOT]
        if vip.vehicle != nil {
            onEvent(.VipBusy)
            craneArmed = false
            return
        }
        craneArmed = false
        boostersUsed += 1
        grid.remove(v.spec)
        vip.vehicle = v
        v.slot = VIP_SLOT
        v.state = .CRANE
        v.t = 0
        v.duration = 1.0
        v.craneFrom = v.pos
        v.craneTo = slotCenter(VIP_SLOT)
        v.craneCtrl = Offset((v.pos.x + v.craneTo.x) / 2, Kt.min(v.pos.y, v.craneTo.y) - 140 * layout.u)
        v.startHeading = v.heading
        v.startScale = v.scale
        v.endScale = Kt.min(slotScale, layout.slotRect(VIP_SLOT).width / (Float(VehicleType.WIDTH) * 1.25) / layout.unit)
        fx.sfx(.Crane)
        particles.stars(v.pos, 10)
        afterLotChange()
        onVehicleMove?(v)
    }

    private func afterLotChange() {
        for o in vehicles where o.state == .LOT && o.mystery && grid.isFree(o.spec) {
            o.mystery = false
            o.flipT = 0
            particles.stars(o.pos, 6, jamColor(o.color))
            fx.sfx(.Pop2, 1.2)
        }
    }

    // --- Boosters & rewards -----------------------------------------------------------------

    func unlockSlot(_ i: Int) {
        if slots[i].open { return }
        slots[i].open = true
        fx.sfx(.Unlock)
        let c = slotCenter(i)
        particles.stars(c, 14)
        particles.ring(c, Color(argb: 0xFFFFE066), 40)
        if phase == .STUCK { phase = .PLAYING }
        stuckTimer = 0
    }

    func revive() {
        revivesUsed += 1
        if let locked = (0..<SLOT_COUNT).first(where: { !slots[$0].open }) {
            unlockSlot(locked)
        } else {
            sortQueue()
        }
        if phase != .PLAYING { phase = .PLAYING }
        stuckTimer = 0
    }

    @discardableResult
    func armCrane() -> Bool {
        if slots[VIP_SLOT].vehicle != nil {
            onEvent(.VipBusy)
            return false
        }
        craneArmed = true
        fx.sfx(.Booster)
        return true
    }

    /// Recolours lot vehicles so the free ones match what the queue needs next.
    func shuffle() {
        boostersUsed += 1
        let lot = vehicles.filter { $0.state == .LOT }
        if lot.isEmpty { return }
        // Demand left after parked vehicles take what they still have room for.
        var room = [Int](repeating: 0, count: 8)
        for s in slots {
            if let v = s.vehicle, v.state != .DEPARTING { room[v.color] += v.seats - v.filled - v.reserved }
        }
        var demand: [Int] = []
        for i in qHead..<queue.count {
            let c = queue[i]
            if room[c] > 0 { room[c] -= 1 } else { demand.append(c) }
        }
        var pool: [VehicleType: [Int]] = [:]
        for v in lot { pool[v.type, default: []].append(v.color) }
        let ordered = lot.map { ($0, grid.isFree($0.spec) ? 0 : 1) }
            .sorted { a, b in a.1 != b.1 ? a.1 < b.1 : a.0.id > b.0.id }
            .map(\.0)
        for v in ordered {
            let avail = pool[v.type]!
            var chosen = -1
            var i = 0
            while i < demand.count && chosen < 0 {
                if avail.contains(demand[i]) { chosen = demand[i] }
                i += 1
            }
            if chosen < 0 { chosen = avail[0] }
            if let k = avail.firstIndex(of: chosen) { pool[v.type]!.remove(at: k) }
            // consume that colour's demand
            var need = v.seats
            var j = 0
            while j < demand.count && need > 0 {
                if demand[j] == chosen {
                    demand.remove(at: j)
                    need -= 1
                } else {
                    j += 1
                }
            }
            v.color = chosen
            v.flipT = 0
            v.popT = 0.6
        }
        fx.sfx(.Booster)
        for v in lot { particles.stars(v.pos, 2) }
    }

    /// Moves passengers that parked vehicles are waiting for to the front of the line.
    func sortQueue() {
        var needs: [(v: Vehicle, order: Int)] = []
        for s in slots {
            if let v = s.vehicle, v.state == .PARKED || v.state == .EXITING || v.state == .CRANE { needs.append((v, needs.count)) }
        }
        // Kotlin sortedBy is stable.
        needs.sort { $0.v.parkedOrder != $1.v.parkedOrder ? $0.v.parkedOrder < $1.v.parkedOrder : $0.order < $1.order }
        var rest: [Int] = Array(qHead..<queue.count)
        var front: [Int] = []
        for (v, _) in needs {
            var need = v.seats - v.filled - v.reserved
            var j = 0
            while j < rest.count && need > 0 {
                let idx = rest[j]
                if queue[idx] == v.color {
                    front.append(idx)
                    rest.remove(at: j)
                    need -= 1
                } else {
                    j += 1
                }
            }
        }
        let order = front + rest
        let newColors = order.map { queue[$0] }
        let newPos = order.map { qS[$0] }
        for k in order.indices {
            queue[qHead + k] = newColors[k]
            qS[qHead + k] = newPos[k]
        }
        fx.sfx(.Whoosh)
    }

    func useSort() {
        boostersUsed += 1
        sortQueue()
        fx.sfx(.Booster)
        if phase == .STUCK { phase = .PLAYING }
        stuckTimer = 0
    }

    // --- Frame update -----------------------------------------------------------------------

    func update(_ dtRaw: Float) {
        if !ready { return }
        let dt = Kt.min(dtRaw, 1 / 30)
        time += dt
        shakeScreen = Kt.max(0, shakeScreen - dt * 4)
        particles.update(dt)

        if phase == .INTRO {
            if vehicles.allSatisfy({ $0.popT >= 1 }) && time > 0.5 { phase = .PLAYING }
        }

        updateVehicles(dt)
        updateQueue(dt)
        updateWalkers(dt)
        checkEnd(dt)
        updateTutorial()
        let r = queue.count - qHead
        if remaining != r { remaining = r }
        frame += 1
    }

    private func updateVehicles(_ dt: Float) {
        let u = layout.u
        for v in vehicles {
            if v.popT < 1 {
                if time > v.popDelay { v.popT = Kt.min(1, v.popT + dt / 0.35) }
            }
            if v.flipT >= 0 {
                v.flipT += dt / 0.35
                if v.flipT >= 1 { v.flipT = -1 }
            }
            if v.bounceT >= 0 {
                v.bounceT += dt / 0.25
                if v.bounceT >= 1 { v.bounceT = -1 }
            }
            if v.shakeT >= 0 {
                v.shakeT += dt / 0.35
                if v.shakeT >= 1 { v.shakeT = -1 }
            }

            switch v.state {
            case .LOT:
                var off: Float = 0
                if v.bumpT >= 0 {
                    v.bumpT += dt
                    let hit: Float = 0.1
                    if v.bumpT < hit {
                        let p = v.bumpT / hit
                        off = v.bumpPx * p * p
                    } else {
                        if !v.bumped {
                            v.bumped = true
                            fx.sfx(.Bump, 0.9 + rnd.nextFloat() * 0.2)
                            fx.haptic(.Bump)
                            let hv = headingVec(v.heading)
                            let nose = v.home + hv * (v.bumpPx + bodyL(v.type) / 2)
                            particles.sparks(nose, 8)
                            shakeScreen = 0.5
                            let blocker = grid.blocker(v.spec)
                            if blocker >= 0 { byId[blocker]?.shakeT = 0 }
                        }
                        let tt = v.bumpT - hit
                        off = v.bumpPx * Kt.exp(-9 * tt) * Kt.cos(20 * tt)
                        if tt > 0.38 {
                            v.bumpT = -1
                            off = 0
                        }
                    }
                }
                v.pos = v.home + headingVec(v.heading) * off
            case .EXITING:
                v.t += dt
                let p = (v.t / v.duration).coerceIn(0, 1)
                let e = 1 - Kt.pow(1 - p, 2.3)
                let m = v.measure!
                let d = v.pathLen * e
                let (pos, tan) = m.getPosTan(d)
                v.pos = pos
                if tan.getDistance() > 0.01 { v.heading = Kt.atan2(tan.x, -tan.y) * 180 / Self.PI }
                v.scale = v.startScale + (v.endScale - v.startScale) * Kt.min(1, p * 1.3)
                v.smokeClock += dt
                if v.smokeClock > 0.07 && p < 0.85 {
                    v.smokeClock = 0
                    let back = v.pos - headingVec(v.heading) * (bodyL(v.type) * v.scale / 2)
                    particles.smoke(back, count: 1)
                }
                if p >= 1 { park(v) }
            case .CRANE:
                v.t += dt
                let p = (v.t / v.duration).coerceIn(0, 1)
                let e = p * p * (3 - 2 * p)
                let a = v.craneFrom
                let c = v.craneCtrl
                let b = v.craneTo
                let q = 1 - e
                v.pos = a * (q * q) + c * (2 * q * e) + b * (e * e)
                v.lift = Kt.sin(p * Self.PI)
                v.scale = v.startScale + (v.endScale - v.startScale) * e + v.lift * 0.25
                v.heading = v.startHeading + shortestAngle(v.startHeading, 0) * e
                if p >= 1 {
                    v.lift = 0
                    park(v)
                }
            case .PARKED:
                if v.departDelay >= 0 {
                    v.departDelay -= dt
                    if v.departDelay < 0 {
                        v.state = .DEPARTING
                        v.departPhase = 0
                        v.t = 0
                    }
                }
            case .DEPARTING:
                v.t += dt
                let sc = slotCenter(v.slot)
                if v.departPhase == 0 {
                    let p = (v.t / 0.22).coerceIn(0, 1)
                    let e = p * p * (3 - 2 * p)
                    v.pos = Offset(sc.x, sc.y + (layout.roadY - sc.y) * e)
                    if p >= 1 {
                        slots[v.slot].vehicle = nil
                        v.departPhase = 1
                        v.t = 0
                        v.departFromX = v.pos.x
                        fx.sfx(.Horn, 0.95 + rnd.nextFloat() * 0.1)
                    }
                } else {
                    let turn = (v.t / 0.2).coerceIn(0, 1)
                    v.heading = 90 * (turn * turn * (3 - 2 * turn))
                    let dist = 260 * u * v.t + 1400 * u * v.t * v.t
                    v.pos = Offset(v.departFromX + dist, layout.roadY)
                    v.smokeClock += dt
                    if v.smokeClock > 0.06 {
                        v.smokeClock = 0
                        particles.smoke(v.pos - Offset(bodyL(v.type) * v.scale / 2, 0), -1, 0, count: 1)
                    }
                    if v.pos.x > layout.width + 120 * u { v.state = .GONE }
                }
            case .GONE:
                break
            }
        }
    }

    private func shortestAngle(_ from: Float, _ to: Float) -> Float {
        var d = Kt.rem(to - from, 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    private func park(_ v: Vehicle) {
        v.state = .PARKED
        v.pos = slotCenter(v.slot)
        v.heading = 0
        v.scale = v.endScale
        v.parkedOrder = parkCounter
        parkCounter += 1
        v.bounceT = 0
        fx.sfx(.Park)
        particles.smoke(v.pos + Offset(0, bodyL(v.type) * v.scale / 2), 0, 1, count: 3)
    }

    private func updateQueue(_ dt: Float) {
        let sp = layout.passengerSpacing
        let speed = 260 * layout.u
        let visible = Kt.toInt(layout.queueVisibleLength / sp) + 2
        if qHead < queue.count {
            for i in qHead..<queue.count {
                let target = Float(i - qHead) * sp
                if i - qHead > visible {
                    qS[i] = target
                    continue
                }
                let cur = qS[i]
                qS[i] = cur > target ? Kt.max(target, cur - speed * dt) : target
            }
        }

        boardCooldown -= dt
        if boardCooldown > 0 || qHead >= queue.count { return }
        if qS[qHead] > sp * 0.9 { return }
        let c = queue[qHead]
        var best: Vehicle?
        for s in slots {
            guard let v = s.vehicle else { continue }
            if v.state != .PARKED || v.color != c || v.departDelay >= 0 { continue }
            if v.filled + v.reserved >= v.seats { continue }
            if best == nil || v.parkedOrder < best!.parkedOrder { best = v }
        }
        guard let v = best else { return }
        v.reserved += 1
        walkers.append(Walker(c, layout.queuePoint(qS[qHead]), v))
        qHead += 1
        boardCooldown = 0.065
    }

    private static let pops: [Sfx] = [.Pop1, .Pop2, .Pop3]

    private func updateWalkers(_ dt: Float) {
        var keep = 0
        for i in walkers.indices {
            let w = walkers[i]
            w.t += dt / 0.24
            if w.t >= 1 {
                let v = w.vehicle
                v.reserved -= 1
                v.filled += 1
                v.bounceT = 0
                fx.sfx(Self.pops[popIndex % 3], 0.95 + (Float(v.filled) / Float(v.seats)) * 0.25)
                popIndex += 1
                if v.filled >= v.seats {
                    v.departDelay = 0.28
                    fx.sfx(.Full)
                    particles.stars(v.pos, 8)
                }
            } else {
                walkers[keep] = w
                keep += 1
            }
        }
        if keep < walkers.count { walkers.removeLast(walkers.count - keep) }
    }

    func walkerPos(_ w: Walker) -> Offset {
        let p = w.t.coerceIn(0, 1)
        let to = w.vehicle.pos
        let base = w.from + (to - w.from) * p
        return base - Offset(0, Kt.sin(p * Self.PI) * 18 * layout.u)
    }

    private func checkEnd(_ dt: Float) {
        if phase != .PLAYING { return }
        if vehicles.allSatisfy({ $0.state == .GONE }) && walkers.isEmpty {
            if winTimer < 0 { winTimer = 0 }
            winTimer += dt
            if winTimer > 0.35 {
                phase = .WON
                particles.confetti(layout.width, layout.topInset, 140)
                let used = boostersUsed + revivesUsed
                let stars = used == 0 ? 3 : (used <= 2 ? 2 : 1)
                onEvent(.Won(stars: stars))
            }
            return
        }
        let busy = !walkers.isEmpty || vehicles.contains {
            $0.state == .EXITING || $0.state == .CRANE || $0.state == .DEPARTING || $0.departDelay >= 0 || $0.bumpT >= 0
        }
        if busy || qHead >= queue.count {
            stuckTimer = 0
            return
        }
        let front = queue[qHead]
        let canBoard = slots.contains { s in
            guard let v = s.vehicle else { return false }
            return v.state == .PARKED && v.color == front && v.filled + v.reserved < v.seats
        }
        let freeSlot = (0..<SLOT_COUNT).contains { slots[$0].free }
        if !canBoard && !freeSlot {
            stuckTimer += dt
            if stuckTimer > 0.6 {
                phase = .STUCK
                stuckTimer = 0
                fx.sfx(.Warning)
                onEvent(.Stuck)
            }
        } else {
            stuckTimer = 0
        }
    }

    private func updateTutorial() {
        if level.number != 1 || phase != .PLAYING || qHead >= queue.count {
            if tutorialPoint != nil { tutorialPoint = nil }
            if phase == .WON && tutorialText != nil { tutorialText = nil }
            return
        }
        let moving = vehicles.contains { $0.state == .EXITING || $0.bumpT >= 0 } || !walkers.isEmpty
        let front = queue[qHead]
        let parkedMatch = slots.contains { $0.vehicle?.color == front }
        let lotFree = vehicles.filter { $0.state == .LOT && grid.isFree($0.spec) }
        let target: Vehicle? = (moving || parkedMatch) ? nil : (lotFree.first { $0.color == front } ?? lotFree.first)
        let point = target?.home
        if tutorialPoint != point { tutorialPoint = point }
        let text: String?
        if let target {
            if target.color != front {
                text = "This one is blocking the bus. Move it out of the way!"
            } else if target.type == .VAN {
                text = "Tap the van! A van carries 6 passengers of its color."
            } else if target.type == .CAR {
                text = "Cars carry 4 passengers of the same color."
            } else {
                text = "Buses carry 10 passengers. Tap the bus!"
            }
        } else {
            text = tutorialText
        }
        if text != tutorialText { tutorialText = text }
    }
}
