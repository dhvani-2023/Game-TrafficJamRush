import Foundation
import Observation
import GameKit

// Port of core/data/ProgressRepository.kt. DataStore "player" → GameKit Prefs(name: "player") with the same keys
// and encodings: coins (Int), levels / collections (Base64 bitsets, bit i of byte i/8), stars (Base64 of 5001
// bytes), skins (string set), skin, sound, music, vibration, onboarding, streak, last_daily (epoch day, Long),
// booster_SHUFFLE / booster_CRANE / booster_SORT. Writes are synchronous (UserDefaults).

/// Holds the player's progress in memory for instant UI reads and writes every change through to Prefs.
/// Kotlin `state.collectAsState()` / `now` → read `state` (observable) or `now`.
@Observable
@MainActor
final class ProgressRepository {

    private(set) var state = PlayerState()
    var now: PlayerState { state }

    /// Internal so the extras (ExtrasRepository) keep their keys in this same store.
    @ObservationIgnored let store: Prefs

    private enum K {
        static let coins = "coins"
        static let levels = "levels"
        static let stars = "stars"
        static let collections = "collections"
        static let skins = "skins"
        static let skin = "skin"
        static let sound = "sound"
        static let music = "music"
        static let vibration = "vibration"
        static let onboarding = "onboarding"
        static let streak = "streak"
        static let lastDaily = "last_daily"
        static func booster(_ t: BoosterType) -> String { "booster_\(t.name)" }
    }

    init(store: Prefs = Prefs(name: "player")) {
        self.store = store
    }

    func load() {
        let p = store
        let d = PlayerState()
        var s = PlayerState()
        s.coins = p.contains(K.coins) ? p.int(K.coins) : d.coins
        var boosters: [BoosterType: Int] = [:]
        for t in BoosterType.allCases { boosters[t] = p.contains(K.booster(t)) ? p.int(K.booster(t)) : 2 }
        s.boosters = boosters
        s.unlockedLevels = p.optionalString(K.levels).flatMap { Self.decodeBits($0, TOTAL_LEVELS + 1) } ?? d.unlockedLevels
        s.stars = p.optionalString(K.stars).flatMap { Self.decodeBytes($0, TOTAL_LEVELS + 1) } ?? d.stars
        s.unlockedCollections = p.optionalString(K.collections).flatMap { Self.decodeBits($0, TOTAL_COLLECTIONS + 1) } ?? d.unlockedCollections
        s.ownedSkins = p.contains(K.skins) ? p.stringSet(K.skins) : d.ownedSkins
        s.skin = p.optionalString(K.skin) ?? d.skin
        s.sound = p.bool(K.sound, true)
        s.music = p.bool(K.music, true)
        s.vibration = p.bool(K.vibration, true)
        s.onboardingDone = p.bool(K.onboarding, false)
        s.dailyStreak = p.int(K.streak, 0)
        s.lastDailyDay = p.long(K.lastDaily, -1)
        s.loaded = true
        // Level 1 and collection 1 are always open.
        s.unlockedLevels[1] = true
        s.unlockedCollections[1] = true
        state = s
    }

    private func mutate(_ block: (PlayerState) -> PlayerState) {
        state = block(state)
        persist()
    }

    private func persist() { write(store, state) }

    private func write(_ p: Prefs, _ s: PlayerState) {
        p.set(K.coins, s.coins)
        for t in BoosterType.allCases { p.set(K.booster(t), s.boosterCount(t)) }
        p.set(K.levels, Self.encodeBits(s.unlockedLevels))
        p.set(K.stars, Data(s.stars.map { UInt8(bitPattern: $0) }).base64EncodedString())
        p.set(K.collections, Self.encodeBits(s.unlockedCollections))
        p.set(K.skins, s.ownedSkins)
        p.set(K.skin, s.skin)
        p.set(K.sound, s.sound)
        p.set(K.music, s.music)
        p.set(K.vibration, s.vibration)
        p.set(K.onboarding, s.onboardingDone)
        p.set(K.streak, s.dailyStreak)
        p.set(K.lastDaily, s.lastDailyDay)
    }

    // --- Progress ---------------------------------------------------------------------------

    /// Records a win and opens what comes after it. Returns true if a new collection opened.
    @discardableResult
    func completeLevel(_ level: Int, _ stars: Int, _ coins: Int) -> Bool {
        var openedCollection = false
        mutate { s in
            var s = s
            if stars > Int(s.stars[level]) { s.stars[level] = Int8(truncatingIfNeeded: stars) }
            if level < TOTAL_LEVELS {
                s.unlockedLevels[level + 1] = true
                let nextC = collectionOf(level + 1)
                if !s.unlockedCollections[nextC] {
                    s.unlockedCollections[nextC] = true
                    openedCollection = true
                }
            }
            s.coins = s.coins + coins
            return s
        }
        return openedCollection
    }

    /// Ad reward: opens one level and the collection it lives in.
    func unlockLevel(_ level: Int) {
        mutate { s in
            var s = s
            s.unlockedLevels[level] = true
            s.unlockedCollections[collectionOf(level)] = true
            return s
        }
    }

    /// Ad reward: opens a collection and its first level.
    func unlockCollection(_ c: Int) {
        mutate { s in
            var s = s
            s.unlockedCollections[c] = true
            s.unlockedLevels[firstLevelOf(c)] = true
            return s
        }
    }

    func addCoins(_ n: Int) {
        mutate { s in
            var s = s
            s.coins = (s.coins + n).coerceAtLeast(0)
            return s
        }
    }

    @discardableResult
    func spendCoins(_ n: Int) -> Bool {
        if now.coins < n { return false }
        addCoins(-n)
        return true
    }

    func addBooster(_ t: BoosterType, _ n: Int) {
        mutate { s in
            var s = s
            s.boosters[t] = (s.boosterCount(t) + n).coerceAtLeast(0)
            return s
        }
    }

    func buySkin(_ id: String) {
        mutate { s in
            var s = s
            s.ownedSkins.insert(id)
            s.skin = id
            return s
        }
    }

    func selectSkin(_ id: String) {
        mutate { s in
            var s = s
            s.skin = id
            return s
        }
    }

    // --- Settings ---------------------------------------------------------------------------

    func setSound(_ on: Bool) { mutate { s in var s = s; s.sound = on; return s } }
    func setMusic(_ on: Bool) { mutate { s in var s = s; s.music = on; return s } }
    func setVibration(_ on: Bool) { mutate { s in var s = s; s.vibration = on; return s } }
    func finishOnboarding() { mutate { s in var s = s; s.onboardingDone = true; return s } }

    func resetProgress() {
        mutate { s in
            var fresh = PlayerState()
            fresh.sound = s.sound
            fresh.music = s.music
            fresh.vibration = s.vibration
            fresh.onboardingDone = true
            fresh.loaded = true
            return fresh
        }
    }

    // --- Daily reward -----------------------------------------------------------------------

    /// Kotlin `TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis())`: days since the epoch in UTC.
    /// Tests can pin the clock with `clock`.
    @ObservationIgnored var clock: () -> Int64 = { Days.nowMillis() }

    private func today() -> Int64 { clock() / 86_400_000 }

    var dailyAvailable: Bool { now.lastDailyDay != today() }

    /// Day index 0..6 the next claim will pay out for.
    var dailyIndex: Int {
        let s = now
        let consecutive = s.lastDailyDay == today() - 1 || s.lastDailyDay == today()
        return consecutive ? s.dailyStreak % 7 : 0
    }

    func claimDaily(_ coins: Int) {
        let day = today()
        mutate { s in
            var s = s
            let consecutive = s.lastDailyDay == day - 1
            s.coins = s.coins + coins
            s.dailyStreak = consecutive ? s.dailyStreak + 1 : 1
            s.lastDailyDay = day
            return s
        }
    }

    // --- Encoding ---------------------------------------------------------------------------

    static func encodeBits(_ b: [Bool]) -> String {
        var bytes = [UInt8](repeating: 0, count: (b.count + 7) / 8)
        for i in b.indices where b[i] { bytes[i / 8] |= UInt8(1 << (i % 8)) }
        return Data(bytes).base64EncodedString()
    }

    static func decodeBits(_ s: String, _ size: Int) -> [Bool]? {
        guard let data = Data(base64Encoded: s) else { return nil }
        let bytes = [UInt8](data)
        return (0..<size).map { i in i / 8 < bytes.count && (bytes[i / 8] >> UInt8(i % 8)) & 1 == 1 }
    }

    static func decodeBytes(_ s: String, _ size: Int) -> [Int8]? {
        guard let data = Data(base64Encoded: s) else { return nil }
        let bytes = [UInt8](data)
        return (0..<size).map { i in i < bytes.count ? Int8(bitPattern: bytes[i]) : 0 }
    }
}
