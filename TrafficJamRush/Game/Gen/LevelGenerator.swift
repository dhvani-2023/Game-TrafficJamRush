import Foundation
import GameKit

// Port of game/gen/LevelGenerator.kt (Shape, LevelParams, DifficultyCurve, Grid, LevelGenerator).
// Bit-exact with Android: kotlin.random.Random via GameKit KotlinRandom, Float maths through Kt, stable sorts.
// Two Kotlin names are changed so they do not shadow SwiftUI types in this module:
//   Kotlin `Shape` -> `LotShape`, Kotlin `Grid` -> `LotGrid`.

enum LotShape: Int, CaseIterable {
    case RECT, CIRCLE, DIAMOND, HEART, FLOWER, RING, CROSS, HEX

    var fill: Float {
        switch self {
        case .RECT: 1
        case .CIRCLE: 0.78
        case .DIAMOND: 0.55
        case .HEART: 0.62
        case .FLOWER: 0.62
        case .RING: 0.64
        case .CROSS: 0.6
        case .HEX: 0.76
        }
    }

    /// Whether the cell centre (u, v) in [-1, 1]² lies inside the shape.
    func contains(_ u: Float, _ v: Float) -> Bool {
        let r = Kt.sqrt(u * u + v * v)
        switch self {
        case .RECT:
            return true
        case .CIRCLE:
            return r <= 1.04
        case .DIAMOND:
            return abs(u) + abs(v) <= 1.12
        case .HEART:
            let x = u * 1.22
            let y = -v * 1.22 + 0.25
            return Kt.pow(x * x + y * y - 1, 3) - x * x * y * y * y <= 0
        case .FLOWER:
            return r <= 0.72 + 0.32 * Kt.cos(5 * Kt.atan2(v, u))
        case .RING:
            return r <= 1.04 && r >= 0.36
        case .CROSS:
            return abs(u) <= 0.46 || abs(v) <= 0.46
        case .HEX:
            return abs(v) <= 0.92 && abs(u) * 0.866 + abs(v) * 0.5 <= 0.95
        }
    }

    var name: String { String(describing: self) }
}

struct LevelParams {
    let vehicles: Int
    let colors: Int
    let cols: Int
    let rows: Int
    let shape: LotShape
    let rotation: Float
    let typeWeights: [Float]
    let mysteryRatio: Float
    let scramble: Float
    let difficulty: Difficulty
}

enum DifficultyCurve {

    static func difficulty(_ n: Int) -> Difficulty {
        if n >= 10 && n % 10 == 0 { return .SUPER_HARD }
        if n >= 5 && n % 5 == 0 { return .HARD }
        return .NORMAL
    }

    static func params(_ n: Int, _ rng: KotlinRandom) -> LevelParams {
        let diff = difficulty(n)
        let base: Float
        if n <= 10 {
            base = 3 * Float(n) + 2
        } else if n <= 50 {
            base = 32 + Float(n - 10) * 0.45
        } else if n <= 300 {
            base = 50 + Float(n - 50) * 0.05
        } else {
            base = 62.5 + Kt.min(9.5, Float(n - 300) * 0.004)
        }
        let breather = n > 5 && (n % 10 == 1 || n % 10 == 6)
        let mult: Float
        if diff == .SUPER_HARD {
            mult = 1.25
        } else if diff == .HARD {
            mult = 1.12
        } else if breather {
            mult = 0.8
        } else {
            mult = 1
        }
        let jitter: Float = 0.94 + rng.nextFloat() * 0.12
        let vehicles = Kt.roundToInt(base * mult * jitter).coerceIn(4, 62)

        var colors: Int
        if n <= 3 {
            colors = 2
        } else if n <= 6 {
            colors = 3
        } else if n <= 14 {
            colors = 4
        } else if n <= 32 {
            colors = 5
        } else if n <= 90 {
            colors = 6
        } else if n <= 220 {
            colors = 7
        } else {
            colors = 8
        }
        if diff != .NORMAL { colors += 1 }
        colors = colors.coerceIn(2, Swift.min(8, vehicles / 2))

        let shape: LotShape = n < 6 ? .RECT : pickShape(rng)
        let rotation: Float
        if n < 8 {
            rotation = 0
        } else {
            switch rng.nextInt(5) {
            case 0, 1: rotation = 0
            case 2: rotation = 14
            case 3: rotation = -14
            default: rotation = rng.nextBoolean() ? 22 : -22
            }
        }

        let weights: [Float] = n <= 5 ? [0.45, 0.4, 0.15] : [0.38, 0.34, 0.28]
        let avgArea: Float = 2 * (3 * weights[0] + 4 * weights[1] + 5 * weights[2])
        let cells: Float = Float(vehicles) * avgArea / 0.86 / shape.fill
        let aspect: Float = rotation == 0 ? 1.1 : 1.0
        let maxCols = rotation == 0 ? 23 : 20
        let cols = Kt.roundToInt(Kt.sqrt(cells / aspect)).coerceIn(9, maxCols)
        let rows = Kt.roundToInt(Float(cols) * aspect).coerceIn(9, maxCols + 2)
        // When the grid is capped, ask only for what fits.
        let fits = Kt.toInt(Float(cols * rows) * shape.fill * 0.86 / avgArea)
        let target = vehicles.coerceAtMost(fits.coerceAtLeast(4))

        let mystery: Float = n < 25 ? 0 : Kt.min(0.22, 0.06 + Float(n - 25) * 0.0008)
        let scrambleBase: Float
        if n <= 3 {
            scrambleBase = 0
        } else if n <= 20 {
            scrambleBase = 1.2
        } else {
            scrambleBase = 2.0
        }
        let scramble: Float = scrambleBase + (diff == .NORMAL ? 0 : 0.6)

        return LevelParams(
            vehicles: target,
            colors: colors.coerceAtMost(Swift.max(2, target / 2)),
            cols: cols,
            rows: rows,
            shape: shape,
            rotation: rotation,
            typeWeights: weights,
            mysteryRatio: mystery,
            scramble: Kt.min(scramble, 2.8),
            difficulty: diff
        )
    }

    private static func pickShape(_ rng: KotlinRandom) -> LotShape {
        let r = rng.nextFloat()
        if r < 0.30 { return .RECT }
        if r < 0.42 { return .CIRCLE }
        if r < 0.52 { return .HEART }
        if r < 0.62 { return .HEX }
        if r < 0.71 { return .DIAMOND }
        if r < 0.80 { return .FLOWER }
        if r < 0.90 { return .RING }
        return .CROSS
    }
}

/// Occupancy grid shared by the generator, the solver and the live game (Kotlin `Grid`).
final class LotGrid {
    let cols: Int
    let rows: Int
    var occ: [Int]

    init(_ cols: Int, _ rows: Int) {
        self.cols = cols
        self.rows = rows
        occ = [Int](repeating: -1, count: cols * rows)
    }

    func at(_ x: Int, _ y: Int) -> Int {
        (x >= 0 && x < cols && y >= 0 && y < rows) ? occ[y * cols + x] : -1
    }

    func put(_ v: VehicleSpec) {
        for yy in v.y..<(v.y + v.h) { for xx in v.x..<(v.x + v.w) { occ[yy * cols + xx] = v.id } }
    }

    func remove(_ v: VehicleSpec) {
        for yy in v.y..<(v.y + v.h) {
            for xx in v.x..<(v.x + v.w) where occ[yy * cols + xx] == v.id { occ[yy * cols + xx] = -1 }
        }
    }

    /// Free rows of units in front of [v] before it would touch another vehicle, or -1 if the
    /// whole strip to the board edge is clear.
    func blockDistance(_ v: VehicleSpec) -> Int {
        var d = 0
        var step = 1
        let vw = v.w
        let vh = v.h
        while true {
            var hit = false
            var outside = true
            switch v.dir {
            case .N, .S:
                let yy = v.dir == .N ? v.y - step : v.y + vh - 1 + step
                if yy >= 0 && yy < rows {
                    outside = false
                    for xx in v.x..<(v.x + vw) where occ[yy * cols + xx] >= 0 { hit = true }
                }
            case .E, .W:
                let xx = v.dir == .W ? v.x - step : v.x + vw - 1 + step
                if xx >= 0 && xx < cols {
                    outside = false
                    for yy in v.y..<(v.y + vh) where occ[yy * cols + xx] >= 0 { hit = true }
                }
            }
            if outside { return -1 }
            if hit { return d }
            d += 1
            step += 1
        }
    }

    /// The vehicle id standing in [v]'s way, or -1.
    func blocker(_ v: VehicleSpec) -> Int {
        let d = blockDistance(v)
        if d < 0 { return -1 }
        let step = d + 1
        switch v.dir {
        case .N, .S:
            let yy = v.dir == .N ? v.y - step : v.y + v.h - 1 + step
            for xx in v.x..<(v.x + v.w) {
                let it = occ[yy * cols + xx]
                if it >= 0 { return it }
            }
        case .E, .W:
            let xx = v.dir == .W ? v.x - step : v.x + v.w - 1 + step
            for yy in v.y..<(v.y + v.h) {
                let it = occ[yy * cols + xx]
                if it >= 0 { return it }
            }
        }
        return -1
    }

    func isFree(_ v: VehicleSpec) -> Bool { blockDistance(v) < 0 }
}

enum LevelGenerator {

    /// Kotlin: access-ordered LinkedHashMap that drops the eldest entry above 12 (an LRU cache).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cacheKeys: [Int] = []
    nonisolated(unsafe) private static var cacheValues: [Int: Level] = [:]
    static let CACHE_SIZE = 12

    static func get(_ n: Int) -> Level {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cacheValues[n] {
            if let i = cacheKeys.firstIndex(of: n) { cacheKeys.remove(at: i) }
            cacheKeys.append(n)
            return hit
        }
        let level = generate(n)
        cacheValues[n] = level
        cacheKeys.append(n)
        if cacheKeys.count > CACHE_SIZE {
            let eldest = cacheKeys.removeFirst()
            cacheValues[eldest] = nil
        }
        return level
    }

    /// Levels currently cached, eldest first (for tests).
    static var cachedLevelNumbers: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return cacheKeys
    }

    static func generate(_ n: Int) -> Level {
        if n == 1 { return tutorialLevel() }
        for attempt in 0..<12 {
            let rng = KotlinRandom(Int64(n) * 7919 + 104729 * Int64(attempt) + 17)
            let level = build(n, rng, scrambleOverride: attempt >= 8 ? 0 : nil, minFill: 0.7)
            if let level, Solver.solvesIntended(level) { return level }
        }
        // Scramble 0 always solves in removal order, so this cannot fail.
        for k in 0..<20 {
            if let level = build(n, KotlinRandom(Int64(n) * 31 + Int64(k)), scrambleOverride: 0, minFill: 0.4) { return level }
        }
        fatalError("level \(n) could not be generated")
    }

    /// Level 1: three vehicles that teach tap, match and blocking.
    private static func tutorialLevel() -> Level {
        let cols = 10
        let rows = 10
        let vehicles = [
            VehicleSpec(0, .VAN, JamColor.GREEN.ordinal, .N, 1, 4),
            VehicleSpec(1, .CAR, JamColor.CYAN.ordinal, .E, 5, 2),
            VehicleSpec(2, .BUS, JamColor.BLUE.ordinal, .N, 5, 4),
        ]
        let queue = [Int](repeating: JamColor.GREEN.ordinal, count: 6) +
            [Int](repeating: JamColor.CYAN.ordinal, count: 4) +
            [Int](repeating: JamColor.BLUE.ordinal, count: 10)
        return Level(number: 1, cols: cols, rows: rows, mask: [Bool](repeating: true, count: cols * rows), vehicles: vehicles,
                     queue: queue, rotation: 0, difficulty: .NORMAL, colorCount: 3)
    }

    /// Internal (not private) so Extras/DailyPuzzle can build a date-seeded level with the same rules.
    static func build(_ n: Int, _ rng: KotlinRandom, scrambleOverride: Float?, minFill: Float) -> Level? {
        let p = DifficultyCurve.params(n, rng)
        let cols = p.cols
        let rows = p.rows
        var mask = [Bool](repeating: false, count: cols * rows)
        for i in 0..<(cols * rows) {
            let x = i % cols
            let y = i / cols
            let u = (Float(x) + 0.5) / Float(cols) * 2 - 1
            let v = (Float(y) + 0.5) / Float(rows) * 2 - 1
            mask[i] = p.shape.contains(u, v)
        }
        if !mask.contains(true) { return nil }
        let grid = LotGrid(cols, rows)
        let cx = Float(cols - 1) / 2
        let cy = Float(rows - 1) / 2

        func fits(_ v: VehicleSpec) -> Bool {
            if v.x < 0 || v.y < 0 || v.x + v.w > cols || v.y + v.h > rows { return false }
            for yy in v.y..<(v.y + v.h) {
                for xx in v.x..<(v.x + v.w) where !mask[yy * cols + xx] || grid.occ[yy * cols + xx] >= 0 { return false }
            }
            return true
        }

        func pickType() -> VehicleType {
            let r = rng.nextFloat()
            if r < p.typeWeights[0] { return .CAR }
            if r < p.typeWeights[0] + p.typeWeights[1] { return .VAN }
            return .BUS
        }

        // 1) Dense packing, centre first, orientation decided now (direction later).
        var packed: [VehicleSpec] = []
        var keyed: [(cell: Int, key: Float, order: Int)] = []
        keyed.reserveCapacity(cols * rows)
        for c in 0..<(cols * rows) where mask[c] {
            let dx = Float(c % cols) - cx
            let dy = Float(c / cols) - cy
            let key = dx * dx + dy * dy + rng.nextFloat() * Float(cols) * 2
            keyed.append((c, key, keyed.count))
        }
        // Kotlin sortedBy is stable: ties keep their original order.
        keyed.sort { $0.key != $1.key ? $0.key < $1.key : $0.order < $1.order }
        let cells = keyed.map(\.cell)

        for pass in 0..<3 {
            for c in cells {
                if packed.count >= p.vehicles { break }
                if grid.occ[c] >= 0 { continue }
                let horizontalFirst = rng.nextBoolean()
                let type: VehicleType
                switch pass {
                case 0: type = pickType()
                case 1: type = rng.nextBoolean() ? .VAN : .CAR
                default: type = .CAR
                }
                for h in [horizontalFirst, !horizontalFirst] {
                    let v = VehicleSpec(packed.count, type, 0, h ? .E : .S, c % cols, c / cols)
                    if fits(v) {
                        grid.put(v)
                        packed.append(v)
                        break
                    }
                }
            }
        }

        // 2) Peel from the outside in. Each vehicle gets a direction that is clear of the
        //    vehicles still on the board; the peel order is a guaranteed solution.
        var remaining = packed
        var peeled: [VehicleSpec] = []
        var options: [VehicleSpec] = []
        while !remaining.isEmpty {
            options.removeAll(keepingCapacity: true)
            for v in remaining {
                let dirs: [Dir] = v.dir.horizontal ? [.E, .W] : [.N, .S]
                for d in dirs {
                    let cand = v.copy(dir: d)
                    if grid.isFree(cand) { options.append(cand) }
                }
            }
            if options.isEmpty {
                // Rare deadlock: lift one vehicle out of the puzzle entirely.
                let drop = remaining.remove(at: rng.nextInt(remaining.count))
                grid.remove(drop)
                continue
            }
            let pick = options[rng.nextInt(options.count)]
            remaining.removeAll { $0.id == pick.id }
            grid.remove(pick)
            peeled.append(pick)
        }
        // Vehicles are listed so that reversed order == removal order.
        let placed = peeled.reversed().enumerated().map { i, v in v.copy(id: i) }
        if placed.count < Swift.max(3, Kt.toInt(Float(p.vehicles) * minFill)) { return nil }

        // Colours: balanced round-robin over a shuffled order.
        let colorPool = Array(Array(JamColor.allCases.indices).kotlinShuffled(rng).prefix(p.colors))
        let order = Array(placed.indices).kotlinShuffled(rng)
        var colorOf = [Int](repeating: 0, count: placed.count)
        for (i, idx) in order.enumerated() { colorOf[idx] = colorPool[i % colorPool.count] }

        var vehicles: [VehicleSpec] = []
        vehicles.reserveCapacity(placed.count)
        for (i, v) in placed.enumerated() {
            vehicles.append(v.copy(color: colorOf[i], mystery: rng.nextFloat() < p.mysteryRatio))
        }

        // Queue: removal order is reverse placement; each group may drift up to `scramble` places.
        let scramble = scrambleOverride ?? p.scramble
        let removal = Array(vehicles.reversed())
        var drift: [(key: Float, order: Int)] = []
        drift.reserveCapacity(removal.count)
        for i in removal.indices { drift.append((Float(i) + rng.nextFloat() * scramble, i)) }
        drift.sort { $0.key != $1.key ? $0.key < $1.key : $0.order < $1.order }
        var queue: [Int] = []
        queue.reserveCapacity(removal.reduce(0) { $0 + $1.type.seats })
        for k in drift {
            let v = removal[k.order]
            for _ in 0..<v.type.seats { queue.append(v.color) }
        }

        return Level(
            number: n,
            cols: cols,
            rows: rows,
            mask: mask,
            vehicles: vehicles,
            queue: queue,
            rotation: p.rotation,
            difficulty: p.difficulty,
            colorCount: p.colors
        )
    }
}
