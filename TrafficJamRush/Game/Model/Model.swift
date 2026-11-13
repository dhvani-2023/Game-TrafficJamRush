import Foundation

// Port of game/model/Model.kt.

enum Dir: Int, CaseIterable {
    case N, E, S, W

    var dx: Int {
        switch self {
        case .N: 0
        case .E: 1
        case .S: 0
        case .W: -1
        }
    }

    var dy: Int {
        switch self {
        case .N: -1
        case .E: 0
        case .S: 1
        case .W: 0
        }
    }

    var degrees: Float {
        switch self {
        case .N: 0
        case .E: 90
        case .S: 180
        case .W: 270
        }
    }

    var horizontal: Bool { dx != 0 }
    var ordinal: Int { rawValue }
    var name: String {
        switch self {
        case .N: "N"
        case .E: "E"
        case .S: "S"
        case .W: "W"
        }
    }
    static var entries: [Dir] { allCases }
}

/// Sizes are in grid units; every vehicle is [WIDTH] units wide.
enum VehicleType: Int, CaseIterable {
    case CAR, VAN, BUS

    var length: Int {
        switch self {
        case .CAR: 3
        case .VAN: 4
        case .BUS: 5
        }
    }

    var seats: Int {
        switch self {
        case .CAR: 4
        case .VAN: 6
        case .BUS: 10
        }
    }

    static let WIDTH = 2

    var ordinal: Int { rawValue }
    var name: String {
        switch self {
        case .CAR: "CAR"
        case .VAN: "VAN"
        case .BUS: "BUS"
        }
    }
    static var entries: [VehicleType] { allCases }
}

enum BoosterType: String, CaseIterable {
    case SHUFFLE, CRANE, SORT

    var title: String {
        switch self {
        case .SHUFFLE: "Shuffle"
        case .CRANE: "Crane"
        case .SORT: "Sort"
        }
    }

    var description: String {
        switch self {
        case .SHUFFLE: "Repaint the vehicles in the lot to match who's waiting next."
        case .CRANE: "Lift any vehicle, even a blocked one, straight to the VIP spot."
        case .SORT: "Line up the passengers so they match the parked vehicles."
        }
    }

    var price: Int {
        switch self {
        case .SHUFFLE: 80
        case .CRANE: 60
        case .SORT: 80
        }
    }

    /// Kotlin `name` (also the DataStore key suffix `booster_<name>`).
    var name: String { rawValue }
    var ordinal: Int { BoosterType.allCases.firstIndex(of: self)! }
    static var entries: [BoosterType] { allCases }
}

enum Difficulty: String, CaseIterable {
    case NORMAL, HARD, SUPER_HARD

    var label: String? {
        switch self {
        case .NORMAL: nil
        case .HARD: "HARD LEVEL"
        case .SUPER_HARD: "SUPER HARD"
        }
    }

    var name: String { rawValue }
    static var entries: [Difficulty] { allCases }
}

/// Passenger and vehicle colors; [hex] is the base body color (ARGB).
enum JamColor: Int, CaseIterable {
    case RED, BLUE, GREEN, YELLOW, PINK, PURPLE, ORANGE, CYAN

    var hex: UInt32 {
        switch self {
        case .RED: 0xFFF2453D
        case .BLUE: 0xFF2F7CF6
        case .GREEN: 0xFF3DBE4B
        case .YELLOW: 0xFFFFC21A
        case .PINK: 0xFFFF6FB5
        case .PURPLE: 0xFF9B5CF0
        case .ORANGE: 0xFFFF8A1F
        case .CYAN: 0xFF23C9D9
        }
    }

    var ordinal: Int { rawValue }
    var name: String {
        switch self {
        case .RED: "RED"
        case .BLUE: "BLUE"
        case .GREEN: "GREEN"
        case .YELLOW: "YELLOW"
        case .PINK: "PINK"
        case .PURPLE: "PURPLE"
        case .ORANGE: "ORANGE"
        case .CYAN: "CYAN"
        }
    }
    static var entries: [JamColor] { allCases }
}

/// A vehicle on the grid. (x, y) is its top-left unit; it covers [VehicleType.length] units along
/// its heading axis and [VehicleType.WIDTH] across it.
struct VehicleSpec: Hashable {
    let id: Int
    let type: VehicleType
    let color: Int
    let dir: Dir
    let x: Int
    let y: Int
    let mystery: Bool

    init(_ id: Int, _ type: VehicleType, _ color: Int, _ dir: Dir, _ x: Int, _ y: Int, mystery: Bool = false) {
        self.id = id
        self.type = type
        self.color = color
        self.dir = dir
        self.x = x
        self.y = y
        self.mystery = mystery
    }

    var w: Int { dir.horizontal ? type.length : VehicleType.WIDTH }
    var h: Int { dir.horizontal ? VehicleType.WIDTH : type.length }

    @inline(__always)
    func forEachCell(_ block: (Int, Int) -> Void) {
        for yy in y..<(y + h) { for xx in x..<(x + w) { block(xx, yy) } }
    }

    /// Centre of the footprint in grid units.
    var centerX: Float { Float(x) + Float(w) / 2 }
    var centerY: Float { Float(y) + Float(h) / 2 }

    /// Kotlin data-class `copy`.
    func copy(id: Int? = nil, type: VehicleType? = nil, color: Int? = nil, dir: Dir? = nil, x: Int? = nil, y: Int? = nil, mystery: Bool? = nil) -> VehicleSpec {
        VehicleSpec(id ?? self.id, type ?? self.type, color ?? self.color, dir ?? self.dir, x ?? self.x, y ?? self.y, mystery: mystery ?? self.mystery)
    }
}

/// Identity semantics like the Kotlin class (equals is `===`, hashCode is the number).
final class Level: Hashable {
    let number: Int
    let cols: Int
    let rows: Int
    let mask: [Bool]
    let vehicles: [VehicleSpec]
    let queue: [Int]
    let rotation: Float
    let difficulty: Difficulty
    let colorCount: Int
    let openSlots: Int
    let lockedSlots: Int

    init(number: Int, cols: Int, rows: Int, mask: [Bool], vehicles: [VehicleSpec], queue: [Int], rotation: Float,
         difficulty: Difficulty, colorCount: Int, openSlots: Int = 4, lockedSlots: Int = 3) {
        self.number = number
        self.cols = cols
        self.rows = rows
        self.mask = mask
        self.vehicles = vehicles
        self.queue = queue
        self.rotation = rotation
        self.difficulty = difficulty
        self.colorCount = colorCount
        self.openSlots = openSlots
        self.lockedSlots = lockedSlots
    }

    func inMask(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < cols && y >= 0 && y < rows && mask[y * cols + x] }

    static func == (a: Level, b: Level) -> Bool { a === b }
    func hash(into hasher: inout Hasher) { hasher.combine(number) }
}
