import Foundation

/// Fast playouts used to check that generated levels can be finished with the open slots (port of Solver.kt).
enum Solver {

    static func solves(_ level: Level) -> Bool { solvesIntended(level) || solvesGreedy(level) }

    /// Drives vehicles in reverse placement order, parking only when the queue needs it.
    static func solvesIntended(_ level: Level) -> Bool {
        let order = Array(level.vehicles.reversed())
        var next = 0
        return playout(level) { grid, _, _ in
            while next < order.count && !grid.occ.contains(order[next].id) { next += 1 }
            return next < order.count && grid.isFree(order[next]) ? order[next] : nil
        }
    }

    /// Always picks a free vehicle matching the queue front, else the colour needed soonest.
    static func solvesGreedy(_ level: Level) -> Bool {
        playout(level) { grid, remaining, front in
            let free = remaining.filter { grid.isFree($0) }
            if let match = free.first(where: { $0.color == level.queue[front] }) { return match }
            // Kotlin minByOrNull: the first minimum wins.
            var best: VehicleSpec?
            var bestKey = Int.max
            for v in free {
                var i = front
                while i < level.queue.count && level.queue[i] != v.color { i += 1 }
                if best == nil || i < bestKey {
                    best = v
                    bestKey = i
                }
            }
            return best
        }
    }

    private static func playout(_ level: Level, _ pick: (LotGrid, [VehicleSpec], Int) -> VehicleSpec?) -> Bool {
        let grid = LotGrid(level.cols, level.rows)
        for v in level.vehicles { grid.put(v) }
        var remaining = level.vehicles
        var parkedColor = [Int](repeating: 0, count: level.openSlots)
        var parkedSeats = [Int](repeating: 0, count: level.openSlots)
        var parked = 0
        var front = 0
        let queue = level.queue
        var guardCount = 0
        while guardCount < 100_000 {
            guardCount += 1
            // Board as many as possible.
            var boarded = true
            while boarded && front < queue.count {
                boarded = false
                for s in 0..<parked where parkedColor[s] == queue[front] && parkedSeats[s] > 0 {
                    parkedSeats[s] -= 1
                    front += 1
                    if parkedSeats[s] == 0 {
                        var k = s
                        while k < parked - 1 {
                            parkedColor[k] = parkedColor[k + 1]
                            parkedSeats[k] = parkedSeats[k + 1]
                            k += 1
                        }
                        parked -= 1
                    }
                    boarded = true
                    break
                }
            }
            if front >= queue.count { return true }
            if parked >= level.openSlots { return false }
            guard let v = pick(grid, remaining, front) else { return false }
            grid.remove(v)
            if let i = remaining.firstIndex(of: v) { remaining.remove(at: i) }
            parkedColor[parked] = v.color
            parkedSeats[parked] = v.type.seats
            parked += 1
        }
        return false
    }
}
