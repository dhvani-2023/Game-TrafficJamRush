import Foundation
import GameKit

/// Everything needed to resume a level: the logical engine state with every in-flight animation settled
/// (moving vehicles parked, passengers mid-hop seated, full vehicles departed). Stored as JSON in the "player" Prefs.
struct ExtrasSnapshot: Codable, Equatable {
    static let VERSION = 1
    static let LOT = -1
    static let GONE = -2

    var version = ExtrasSnapshot.VERSION
    /// The level number (for a daily puzzle: the difficulty-curve number it was generated as).
    var level: Int
    /// Daily puzzle: its local epoch day; nil for a normal level.
    var day: Int?
    /// `ExtrasAutosave.fingerprint` of the level it was taken from.
    var fingerprint: Int
    /// Per vehicle (level order): current colour (Shuffle repaints), mystery flag, LOT / GONE / slot index,
    /// seated passengers and boarding order (`parkedOrder`).
    var colors: [Int]
    var mystery: [Bool]
    var spots: [Int]
    var filled: [Int]
    var order: [Int]
    /// Per slot (0…7, VIP last): open (unlocked by revive or the "Extra Spot" reward).
    var open: [Bool]
    /// The passenger line (Sort reorders it) and its head.
    var queue: [Int]
    var head: Int
    var boostersUsed: Int
    var revivesUsed: Int
    var parkCounter: Int
    /// Crane booster armed (already paid for) but not used yet.
    var craneArmed: Bool
    /// Undo log: ids of parked vehicles, oldest move first.
    var moves: [Int]
    var savedAt: Int64

    var isDaily: Bool { day != nil }
    /// Passengers still waiting.
    var waiting: Int { queue.count - head }
}

enum ExtrasAutosave {

    /// FNV-1a over the level's layout (not Swift's per-process `Hasher`), so a save is never applied to a
    /// different level (e.g. after a generator change).
    static func fingerprint(_ level: Level) -> Int {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        func eat(_ v: Int) {
            h ^= UInt64(bitPattern: Int64(v))
            h = h &* 0x0000_0100_0000_01B3
        }
        eat(level.number); eat(level.cols); eat(level.rows); eat(level.queue.count)
        for v in level.vehicles { eat(v.id); eat(v.type.ordinal); eat(v.dir.ordinal); eat(v.x); eat(v.y); eat(v.color); eat(v.mystery ? 1 : 0) }
        for c in level.queue { eat(c) }
        return Int(truncatingIfNeeded: h)
    }

    /// True once the player has done anything worth resuming.
    @MainActor
    static func touched(_ e: GameEngine, moves: [Int]) -> Bool {
        if !moves.isEmpty || e.boostersUsed > 0 || e.revivesUsed > 0 || e.qHead > 0 || e.craneArmed { return true }
        for i in 0...SLOT_COUNT where e.slots[i].open != (i < e.level.openSlots || i == VIP_SLOT) { return true }
        return false
    }

    /// The engine's state with every animation run to its end. nil before the level is laid out or once it is won.
    @MainActor
    static func capture(_ e: GameEngine, day: Int?, moves: [Int], now: Int64 = Days.nowMillis()) -> ExtrasSnapshot? {
        guard e.ready, e.phase != .WON else { return nil }
        let n = e.vehicles.count
        var spots = [Int](repeating: ExtrasSnapshot.LOT, count: n)
        var filled = [Int](repeating: 0, count: n)
        var order = [Int](repeating: 0, count: n)
        var arriving: [(index: Int, left: Float)] = []
        for (i, v) in e.vehicles.enumerated() {
            switch v.state {
            case .LOT:
                spots[i] = ExtrasSnapshot.LOT
            case .GONE, .DEPARTING:
                spots[i] = ExtrasSnapshot.GONE
            case .EXITING, .CRANE:
                spots[i] = v.slot
                arriving.append((i, v.duration - v.t))
            case .PARKED:
                // Passengers mid-hop (reserved) land; a full vehicle drives off.
                let seated = v.filled + v.reserved
                if v.departDelay >= 0 || seated >= v.seats {
                    spots[i] = ExtrasSnapshot.GONE
                } else {
                    spots[i] = v.slot
                    filled[i] = seated
                    order[i] = v.parkedOrder
                }
            }
        }
        // Vehicles still on their way park in arrival order.
        var counter = e.parkCounter
        for a in arriving.enumerated().sorted(by: { $0.element.left != $1.element.left ? $0.element.left < $1.element.left : $0.offset < $1.offset }) {
            order[a.element.index] = counter
            counter += 1
        }
        let parkedIds = Set(e.vehicles.indices.filter { spots[$0] >= 0 }.map { e.vehicles[$0].id })
        return ExtrasSnapshot(
            level: e.level.number,
            day: day,
            fingerprint: fingerprint(e.level),
            colors: e.vehicles.map(\.color),
            mystery: e.vehicles.map(\.mystery),
            spots: spots,
            filled: filled,
            order: order,
            open: e.slots.map(\.open),
            queue: e.queue,
            head: e.qHead,
            boostersUsed: e.boostersUsed,
            revivesUsed: e.revivesUsed,
            parkCounter: counter,
            craneArmed: e.craneArmed && e.slots[VIP_SLOT].vehicle == nil,
            moves: moves.filter { parkedIds.contains($0) },
            savedAt: now
        )
    }

    /// Structural checks plus the game's invariant: per colour, waiting passengers == free seats of the vehicles
    /// still in play. A snapshot that fails is never applied.
    static func isValid(_ s: ExtrasSnapshot, for level: Level) -> Bool {
        let n = level.vehicles.count
        guard s.version == ExtrasSnapshot.VERSION, s.fingerprint == fingerprint(level), s.level == level.number,
              s.colors.count == n, s.mystery.count == n, s.spots.count == n, s.filled.count == n, s.order.count == n,
              s.open.count == SLOT_COUNT + 1, s.queue.count == level.queue.count, s.head >= 0, s.head <= s.queue.count,
              s.boostersUsed >= 0, s.revivesUsed >= 0
        else { return false }
        if s.queue.sorted() != level.queue.sorted() { return false }
        if s.colors.contains(where: { $0 < 0 || $0 >= 8 }) { return false }
        var used = Set<Int>()
        var seatsLeft = [Int](repeating: 0, count: 8)
        for (i, spec) in level.vehicles.enumerated() {
            let spot = s.spots[i]
            if spot >= 0 {
                if spot > VIP_SLOT || used.contains(spot) || !s.open[spot] { return false }
                used.insert(spot)
                if s.filled[i] < 0 || s.filled[i] >= spec.type.seats { return false }
            } else if spot != ExtrasSnapshot.LOT && spot != ExtrasSnapshot.GONE {
                return false
            }
            if spot != ExtrasSnapshot.GONE { seatsLeft[s.colors[i]] += spec.type.seats - (spot >= 0 ? s.filled[i] : 0) }
        }
        var waiting = [Int](repeating: 0, count: 8)
        for i in s.head..<s.queue.count { waiting[s.queue[i]] += 1 }
        return waiting == seatsLeft
    }

    /// Applies [s] to a freshly laid-out engine (after `setSize`, before the first `update`). Vehicles in slots are
    /// parked straight away; the level then plays its intro (pop-in, passengers walking up) as on a fresh start.
    @MainActor
    @discardableResult
    static func restore(_ e: GameEngine, _ s: ExtrasSnapshot) -> Bool {
        guard e.ready, let lay = e.layout, e.phase == .INTRO, e.qHead == 0, isValid(s, for: e.level) else { return false }
        for i in 0...SLOT_COUNT { e.slots[i].open = s.open[i] }
        for (i, v) in e.vehicles.enumerated() {
            v.color = s.colors[i]
            v.mystery = s.mystery[i]
            let spot = s.spots[i]
            if spot == ExtrasSnapshot.LOT { continue }
            e.grid.remove(v.spec)
            if spot == ExtrasSnapshot.GONE {
                v.state = .GONE
                continue
            }
            e.slots[spot].vehicle = v
            v.slot = spot
            v.state = .PARKED
            v.filled = s.filled[i]
            v.parkedOrder = s.order[i]
            v.pos = e.slotCenter(spot)
            v.heading = 0
            // The pose drive() / crane() would have left (Undo rewinds along it).
            let lotHeading = lay.rotationDeg + v.spec.dir.degrees
            if spot == VIP_SLOT {
                v.endScale = Kt.min(e.slotScale, lay.slotRect(VIP_SLOT).width / (Float(VehicleType.WIDTH) * 1.25) / lay.unit)
                v.craneFrom = v.home
                v.craneTo = v.pos
                v.craneCtrl = Offset((v.home.x + v.pos.x) / 2, Kt.min(v.home.y, v.pos.y) - 140 * lay.u)
                v.startHeading = lotHeading
                v.startScale = 1
            } else {
                v.endScale = e.slotScale
                v.startScale = 1
                ExtrasUndo.buildExitPath(e, v, lotHeading: lotHeading, slot: spot)
            }
            v.scale = v.endScale
        }
        e.queue = s.queue
        e.qHead = s.head
        // Waiting passengers walk back up from the right, like at the start of a level.
        for i in s.head..<s.queue.count { e.qS[i] = Float(i - s.head) * lay.passengerSpacing + lay.width * 0.6 }
        e.boostersUsed = s.boostersUsed
        e.revivesUsed = s.revivesUsed
        e.parkCounter = s.parkCounter
        e.craneArmed = s.craneArmed && e.slots[VIP_SLOT].vehicle == nil
        // Warm the sprites the restored level shows (Shuffle may have changed colours).
        if let art = e.art {
            for v in e.vehicles where v.state != .GONE {
                art.composite(v.type, v.color, v.mystery, v.state == .LOT ? v.heading : 0)
                art.composite(v.type, v.color, false, 0)
            }
        }
        return true
    }
}
