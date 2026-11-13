import Foundation
import Observation
import GameKit

/// Saved state of the extras. Keys live in the game's existing `Prefs(name: "player")` store, next to
/// ProgressRepository's (the Undo count uses the same `booster_<NAME>` pattern as the Android boosters).
/// Every change is written through immediately, like ProgressRepository.
@Observable
@MainActor
final class ExtrasRepository {

    enum K {
        static let undo = "booster_UNDO"
        static let colorBlind = "colorblind"
        static let puzzleStreak = "puzzle_streak"
        static let puzzleLast = "puzzle_last"
        static let puzzleDays = "puzzle_days"
        static let savedGame = "autosave"
    }

    /// Undo boosters a new player starts with (like the Android boosters).
    static let UNDO_START = 2
    /// Coin price of one Undo in the booster dialog.
    static let UNDO_PRICE = 60
    /// Solved days kept for the streak strip.
    static let DAYS_KEPT = 31

    private(set) var undoCount = ExtrasRepository.UNDO_START
    private(set) var colorBlind = false
    /// Consecutive days solved, as of `puzzleLast`.
    private(set) var puzzleStreak = 0
    /// Local epoch day (`Days.epochDay`) of the last solved daily puzzle, -1 if none.
    private(set) var puzzleLast = -1
    /// Local epoch days with a solved daily puzzle, ascending (the last `DAYS_KEPT`).
    private(set) var puzzleDays: [Int] = []
    /// Mid-level autosave, if any.
    private(set) var savedGame: ExtrasSnapshot?

    /// Set by Home's "Continue" and taken by the game session that matches it.
    @ObservationIgnored var pendingResume: ExtrasSnapshot?
    /// Local calendar day; tests pin it.
    @ObservationIgnored var today: () -> Int = { Days.epochDay() }

    @ObservationIgnored let store: Prefs

    init(store: Prefs) {
        self.store = store
        load()
    }

    func load() {
        let p = store
        undoCount = p.contains(K.undo) ? p.int(K.undo) : Self.UNDO_START
        colorBlind = p.bool(K.colorBlind, false)
        puzzleStreak = p.int(K.puzzleStreak, 0)
        puzzleLast = p.int(K.puzzleLast, -1)
        puzzleDays = Self.decodeDays(p.string(K.puzzleDays))
        savedGame = p.codable(K.savedGame, as: ExtrasSnapshot.self)
    }

    // --- Undo booster ------------------------------------------------------------------------

    func addUndo(_ n: Int) {
        undoCount = (undoCount + n).coerceAtLeast(0)
        store.set(K.undo, undoCount)
    }

    // --- Colour-blind patterns ---------------------------------------------------------------

    func setColorBlind(_ on: Bool) {
        colorBlind = on
        store.set(K.colorBlind, on)
    }

    // --- Daily puzzle ------------------------------------------------------------------------

    func puzzleSolved(_ day: Int) -> Bool { puzzleLast >= day }

    /// The streak that is still alive on [day] (solved yesterday or today), else 0.
    func puzzleStreakAlive(_ day: Int) -> Int {
        puzzleLast == day || puzzleLast == day - 1 ? puzzleStreak : 0
    }

    /// The streak solving [day]'s puzzle gives (or gave, once solved).
    func puzzleStreakAfterSolving(_ day: Int) -> Int {
        puzzleSolved(day) ? puzzleStreakAlive(day) : puzzleStreakAlive(day) + 1
    }

    /// Records [day]'s puzzle as solved. Returns nil when that day (or a later one) was already solved.
    @discardableResult
    func completePuzzle(_ day: Int) -> ExtrasDailyResult? {
        if puzzleSolved(day) { return nil }
        let streak = puzzleLast == day - 1 ? puzzleStreak + 1 : 1
        puzzleStreak = streak
        puzzleLast = day
        var days = puzzleDays.filter { $0 != day }
        days.append(day)
        days.sort()
        puzzleDays = Array(days.suffix(Self.DAYS_KEPT))
        store.set(K.puzzleStreak, streak)
        store.set(K.puzzleLast, day)
        store.set(K.puzzleDays, Self.encodeDays(puzzleDays))
        return ExtrasDailyResult(day: day, streak: streak, reward: ExtrasDailyPuzzle.reward(streak: streak))
    }

    /// The 7-day strip ending on [day] (oldest first).
    func puzzleWeek(_ day: Int) -> [ExtrasDayMark] {
        let solved = Set(puzzleDays)
        return ((day - 6)...day).map { d in ExtrasDayMark(day: ExtrasDay(d), solved: solved.contains(d), isToday: d == day) }
    }

    // --- Autosave ----------------------------------------------------------------------------

    func saveGame(_ s: ExtrasSnapshot) {
        savedGame = s
        store.setCodable(K.savedGame, s)
    }

    func clearSavedGame() {
        pendingResume = nil
        guard savedGame != nil || store.contains(K.savedGame) else { return }
        savedGame = nil
        store.remove(K.savedGame)
    }

    /// The pending "Continue" snapshot if it belongs to the session that is starting ([day] for daily puzzles).
    func takeResume(levelNumber: Int, day: Int?) -> ExtrasSnapshot? {
        guard let s = pendingResume else { return nil }
        pendingResume = nil
        if let day { return s.day == day ? s : nil }
        return s.day == nil && s.level == levelNumber ? s : nil
    }

    // --- Reset (Settings ▸ Reset Progress) -----------------------------------------------------

    /// Same scope as ProgressRepository.resetProgress: progress goes, settings (the colour-blind toggle) stay.
    func resetProgress() {
        for k in [K.undo, K.puzzleStreak, K.puzzleLast, K.puzzleDays, K.savedGame] { store.remove(k) }
        pendingResume = nil
        load()
    }

    // --- Encoding ----------------------------------------------------------------------------

    static func encodeDays(_ days: [Int]) -> String { days.map(String.init).joined(separator: ",") }

    static func decodeDays(_ s: String) -> [Int] {
        s.split(separator: ",").compactMap { Int($0) }.sorted()
    }
}

/// What solving a daily puzzle paid out.
struct ExtrasDailyResult: Equatable {
    let day: Int
    let streak: Int
    let reward: Int
}

/// One tile of the streak strip.
struct ExtrasDayMark: Equatable {
    let day: ExtrasDay
    let solved: Bool
    let isToday: Bool
}
