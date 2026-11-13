import Foundation
import GameKit

/// A local calendar day, counted like `Days.epochDay` (days since 1970-01-01 of the device's local date).
struct ExtrasDay: Hashable {
    let epochDay: Int
    let year: Int
    let month: Int
    let dayOfMonth: Int
    /// 1 = Sunday … 7 = Saturday.
    let weekday: Int

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    init(_ epochDay: Int) {
        self.epochDay = epochDay
        let c = Self.utc.dateComponents([.year, .month, .day, .weekday], from: Date(timeIntervalSince1970: TimeInterval(epochDay) * 86_400))
        year = c.year ?? 1970
        month = c.month ?? 1
        dayOfMonth = c.day ?? 1
        weekday = c.weekday ?? 5
    }

    static func today(_ date: Date = Date()) -> ExtrasDay { ExtrasDay(Days.epochDay(date)) }

    /// yyyyMMdd (the daily seed), same as `Days.yyyymmdd` for this local date.
    var yyyymmdd: Int { year * 10_000 + month * 100 + dayOfMonth }
    var isWeekend: Bool { weekday == 1 || weekday == 7 }

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let weekdayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    /// "NOV" (calendar badge).
    var monthBadge: String { Self.months[month - 1] }
    /// "S", "M", … (strip tiles).
    var weekdayLetter: String { Self.weekdayLetters[weekday - 1] }
    /// "Sat, Nov 8".
    var label: String { "\(Self.weekdayNames[weekday - 1]), \(Self.monthNames[month - 1]) \(dayOfMonth)" }
}

/// One extra level per local day, built by the game's own LevelGenerator rules (`LevelGenerator.build` +
/// `Solver.solvesIntended`, the same attempt loop as `generate`) from a date-derived seed. Normal levels are
/// untouched: their seeds and the 12-level cache are never used here.
enum ExtrasDailyPuzzle {

    /// Streak reward: 50 + 10 × streak (the streak including the day just solved), at most 150.
    static func reward(streak: Int) -> Int { min(150, 50 + 10 * max(0, streak)) }

    private static func mix(_ v: UInt64) -> UInt64 {
        var r = SplitMix64(seed: v)
        return r.nextRaw()
    }

    /// 64-bit generator seed for the day.
    static func seed(_ day: ExtrasDay) -> Int64 {
        Int64(bitPattern: mix(UInt64(day.yyyymmdd) ^ 0xDA11_9E5E_ED00_0000))
    }

    /// The difficulty-curve level number the puzzle is generated as: a mid-game level (16…78) that changes daily,
    /// a Hard level (odd multiple of 5) on weekends and a Normal one (never a multiple of 5) on weekdays.
    static func number(_ day: ExtrasDay) -> Int {
        var n = 16 + Int(mix(UInt64(day.yyyymmdd) &* 31 &+ 7) % 60)
        if day.isWeekend {
            n = n / 5 * 5
            if n % 10 == 0 { n += 5 }
        } else if n % 5 == 0 {
            n += 1
        }
        return n
    }

    /// Scene backdrop for the day (one of the ten worlds).
    static func theme(_ day: ExtrasDay) -> SceneTheme {
        Themes.all[Int(mix(UInt64(day.yyyymmdd) ^ 0x7E3E) % UInt64(Themes.all.count))]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (day: Int, level: Level)?

    /// The day's level (cached for the last day asked for).
    static func level(_ day: ExtrasDay) -> Level {
        lock.lock()
        defer { lock.unlock() }
        if let c = cached, c.day == day.epochDay { return c.level }
        let l = generate(day)
        cached = (day.epochDay, l)
        return l
    }

    /// LevelGenerator.generate's loop with the day's seed in place of `n·7919 + 104729·attempt + 17`.
    static func generate(_ day: ExtrasDay) -> Level {
        let n = number(day)
        let seed = seed(day)
        for attempt in 0..<12 {
            let rng = KotlinRandom(seed &+ 104_729 &* Int64(attempt))
            if let level = LevelGenerator.build(n, rng, scrambleOverride: attempt >= 8 ? 0 : nil, minFill: 0.7),
               Solver.solvesIntended(level) {
                return level
            }
        }
        // Scramble 0 always solves in removal order.
        for k in 0..<20 {
            if let level = LevelGenerator.build(n, KotlinRandom(seed &+ 31 &* Int64(k) &+ 1), scrambleOverride: 0, minFill: 0.4) {
                return level
            }
        }
        return LevelGenerator.generate(n)
    }

    /// Records the session's day as solved and pays the streak reward. nil if that day was already solved.
    @MainActor
    static func finish(_ day: ExtrasDay) -> ExtrasDailyResult? {
        let c = App.container
        guard let r = c.extras.completePuzzle(day.epochDay) else { return nil }
        c.progress.addCoins(r.reward)
        return r
    }
}
