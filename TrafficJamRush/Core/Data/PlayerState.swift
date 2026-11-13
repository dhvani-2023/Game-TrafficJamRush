import Foundation

// Port of core/data/PlayerState.kt.

let TOTAL_LEVELS = 5000
let LEVELS_PER_COLLECTION = 100
let TOTAL_COLLECTIONS = TOTAL_LEVELS / LEVELS_PER_COLLECTION

func collectionOf(_ level: Int) -> Int { (level - 1) / LEVELS_PER_COLLECTION + 1 }
func firstLevelOf(_ collection: Int) -> Int { (collection - 1) * LEVELS_PER_COLLECTION + 1 }

/// Snapshot of everything the player owns (a value: every change produces a new state, like the Kotlin copies).
/// Index 0 is unused so level/collection numbers index directly.
struct PlayerState {
    var coins: Int = 0
    var boosters: [BoosterType: Int] = Dictionary(uniqueKeysWithValues: BoosterType.allCases.map { ($0, 2) })
    var unlockedLevels: [Bool] = PlayerState.defaultUnlockedLevels
    var stars: [Int8] = [Int8](repeating: 0, count: TOTAL_LEVELS + 1)
    var unlockedCollections: [Bool] = PlayerState.defaultUnlockedCollections
    var ownedSkins: Set<String> = ["classic"]
    var skin: String = "classic"
    var sound: Bool = true
    var music: Bool = true
    var vibration: Bool = true
    var onboardingDone: Bool = false
    var dailyStreak: Int = 0
    var lastDailyDay: Int64 = -1
    var loaded: Bool = false

    static var defaultUnlockedLevels: [Bool] {
        var a = [Bool](repeating: false, count: TOTAL_LEVELS + 1)
        a[1] = true
        return a
    }

    static var defaultUnlockedCollections: [Bool] {
        var a = [Bool](repeating: false, count: TOTAL_COLLECTIONS + 1)
        a[1] = true
        return a
    }

    func isLevelUnlocked(_ level: Int) -> Bool { level >= 1 && level <= TOTAL_LEVELS && unlockedLevels[level] }
    func starsOf(_ level: Int) -> Int { level >= 1 && level <= TOTAL_LEVELS ? Int(stars[level]) : 0 }
    func isCompleted(_ level: Int) -> Bool { starsOf(level) > 0 }
    func isCollectionUnlocked(_ c: Int) -> Bool { c >= 1 && c <= TOTAL_COLLECTIONS && unlockedCollections[c] }
    func boosterCount(_ type: BoosterType) -> Int { boosters[type] ?? 0 }

    /// The level the big Play button starts: lowest unlocked level not yet beaten.
    var nextLevel: Int {
        for l in 1...TOTAL_LEVELS where unlockedLevels[l] && stars[l] == 0 { return l }
        return TOTAL_LEVELS
    }

    var completedCount: Int { stars.reduce(0) { $0 + ($1 > 0 ? 1 : 0) } }

    func completedIn(_ collection: Int) -> Int {
        let start = firstLevelOf(collection)
        var n = 0
        for l in start..<(start + LEVELS_PER_COLLECTION) where stars[l] > 0 { n += 1 }
        return n
    }

    func starsIn(_ collection: Int) -> Int {
        let start = firstLevelOf(collection)
        var n = 0
        for l in start..<(start + LEVELS_PER_COLLECTION) { n += Int(stars[l]) }
        return n
    }
}
