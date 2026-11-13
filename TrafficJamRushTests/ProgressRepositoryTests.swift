import XCTest
import GameKit
@testable import TrafficJamRush

/// ProgressRepository: DataStore keys / encodings (java.util.Base64 NO_WRAP of the same byte layouts) and the
/// progress, economy and daily-reward rules of ProgressRepository.kt.
@MainActor
final class ProgressRepositoryTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: Prefs!

    override func setUp() {
        super.setUp()
        let suite = "tjr.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = Prefs(name: "player", defaults: defaults)
    }

    private func repo() -> ProgressRepository {
        let r = ProgressRepository(store: store)
        r.load()
        return r
    }

    func testDefaults() {
        let r = repo()
        let s = r.state
        XCTAssertTrue(s.loaded)
        XCTAssertEqual(s.coins, 0)
        XCTAssertEqual(BoosterType.allCases.map { s.boosterCount($0) }, [2, 2, 2])
        XCTAssertTrue(s.isLevelUnlocked(1))
        XCTAssertFalse(s.isLevelUnlocked(2))
        XCTAssertTrue(s.isCollectionUnlocked(1))
        XCTAssertFalse(s.isCollectionUnlocked(2))
        XCTAssertEqual(s.ownedSkins, ["classic"])
        XCTAssertEqual(s.skin, "classic")
        XCTAssertTrue(s.sound && s.music && s.vibration)
        XCTAssertFalse(s.onboardingDone)
        XCTAssertEqual(s.dailyStreak, 0)
        XCTAssertEqual(s.lastDailyDay, -1)
        XCTAssertEqual(s.nextLevel, 1)
        XCTAssertEqual(s.unlockedLevels.count, TOTAL_LEVELS + 1)
        XCTAssertEqual(s.stars.count, TOTAL_LEVELS + 1)
        XCTAssertEqual(s.unlockedCollections.count, TOTAL_COLLECTIONS + 1)
    }

    func testEncodingsMatchAndroid() {
        let r = repo()
        r.completeLevel(1, 3, 10)
        r.completeLevel(2, 1, 20)
        // Android: encodeBits → bit i of byte i/8, Base64.NO_WRAP (standard alphabet, padded).
        var lv = [UInt8](repeating: 0, count: (TOTAL_LEVELS + 1 + 7) / 8)
        lv[0] = 0b0000_1110 // levels 1, 2, 3
        XCTAssertEqual(defaults.string(forKey: "player.levels"), Data(lv).base64EncodedString())
        var st = [UInt8](repeating: 0, count: TOTAL_LEVELS + 1)
        st[1] = 3
        st[2] = 1
        XCTAssertEqual(defaults.string(forKey: "player.stars"), Data(st).base64EncodedString())
        XCTAssertEqual(defaults.string(forKey: "player.collections"), Data([0b10, 0, 0, 0, 0, 0, 0]).base64EncodedString())
        XCTAssertEqual(defaults.string(forKey: "player.collections"), "AgAAAAAAAA==")
        XCTAssertEqual(defaults.integer(forKey: "player.coins"), 30)
        XCTAssertEqual(defaults.integer(forKey: "player.booster_SHUFFLE"), 2)
        XCTAssertEqual(defaults.integer(forKey: "player.booster_CRANE"), 2)
        XCTAssertEqual(defaults.integer(forKey: "player.booster_SORT"), 2)
        XCTAssertEqual(defaults.array(forKey: "player.skins") as? [String], ["classic"])
        XCTAssertEqual(defaults.string(forKey: "player.skin"), "classic")
        XCTAssertEqual(defaults.object(forKey: "player.last_daily") as? NSNumber, NSNumber(value: Int64(-1)))
        XCTAssertNotNil(defaults.object(forKey: "player.streak"))
        XCTAssertNotNil(defaults.object(forKey: "player.onboarding"))
        XCTAssertNotNil(defaults.object(forKey: "player.sound"))
        XCTAssertNotNil(defaults.object(forKey: "player.music"))
        XCTAssertNotNil(defaults.object(forKey: "player.vibration"))
    }

    func testRoundTrip() {
        let r = repo()
        r.completeLevel(100, 2, 30) // opens level 101 and collection 2
        r.addBooster(.CRANE, 3)
        r.addBooster(.SORT, -5)
        r.buySkin("taxi")
        r.setMusic(false)
        r.finishOnboarding()
        r.unlockCollection(7)
        let s = repo().state
        XCTAssertEqual(s.starsOf(100), 2)
        XCTAssertTrue(s.isLevelUnlocked(101))
        XCTAssertTrue(s.isCollectionUnlocked(2))
        XCTAssertTrue(s.isCollectionUnlocked(7))
        XCTAssertTrue(s.isLevelUnlocked(601))
        XCTAssertEqual(s.coins, 30)
        XCTAssertEqual(s.boosterCount(.CRANE), 5)
        XCTAssertEqual(s.boosterCount(.SORT), 0)
        XCTAssertEqual(s.ownedSkins, ["classic", "taxi"])
        XCTAssertEqual(s.skin, "taxi")
        XCTAssertFalse(s.music)
        XCTAssertTrue(s.onboardingDone)
    }

    func testCompleteLevelRules() {
        let r = repo()
        XCTAssertFalse(r.completeLevel(1, 2, 10))
        XCTAssertEqual(r.state.starsOf(1), 2)
        XCTAssertFalse(r.completeLevel(1, 1, 10))
        XCTAssertEqual(r.state.starsOf(1), 2, "stars only go up")
        XCTAssertEqual(r.state.coins, 20)
        XCTAssertEqual(r.state.nextLevel, 2)
        XCTAssertTrue(r.completeLevel(100, 3, 0), "level 101 opens collection 2")
        XCTAssertFalse(r.completeLevel(100, 3, 0))
        XCTAssertFalse(r.completeLevel(TOTAL_LEVELS, 1, 0))
        XCTAssertEqual(r.state.completedCount, 3)
        XCTAssertEqual(r.state.completedIn(1), 2)
        XCTAssertEqual(r.state.starsIn(1), 5)
        XCTAssertEqual(collectionOf(100), 1)
        XCTAssertEqual(collectionOf(101), 2)
        XCTAssertEqual(firstLevelOf(3), 201)
    }

    func testCoins() {
        let r = repo()
        r.addCoins(50)
        XCTAssertFalse(r.spendCoins(60))
        XCTAssertTrue(r.spendCoins(50))
        XCTAssertEqual(r.state.coins, 0)
        r.addCoins(-10)
        XCTAssertEqual(r.state.coins, 0, "never negative")
    }

    func testDailyStreak() {
        let r = repo()
        let day: Int64 = 20_000
        r.clock = { day * 86_400_000 + 5_000 }
        XCTAssertTrue(r.dailyAvailable)
        XCTAssertEqual(r.dailyIndex, 0)
        r.claimDaily(50)
        XCTAssertFalse(r.dailyAvailable)
        XCTAssertEqual(r.state.dailyStreak, 1)
        XCTAssertEqual(r.state.lastDailyDay, day)
        XCTAssertEqual(r.dailyIndex, 1)
        r.clock = { (day + 1) * 86_400_000 }
        XCTAssertTrue(r.dailyAvailable)
        XCTAssertEqual(r.dailyIndex, 1)
        r.claimDaily(60)
        XCTAssertEqual(r.state.dailyStreak, 2)
        r.clock = { (day + 3) * 86_400_000 }
        XCTAssertEqual(r.dailyIndex, 0, "streak broken")
        r.claimDaily(50)
        XCTAssertEqual(r.state.dailyStreak, 1)
        XCTAssertEqual(r.state.coins, 160)
    }

    func testResetKeepsSettings() {
        let r = repo()
        r.setSound(false)
        r.setVibration(false)
        r.completeLevel(1, 3, 99)
        r.resetProgress()
        let s = r.state
        XCTAssertFalse(s.sound)
        XCTAssertTrue(s.music)
        XCTAssertFalse(s.vibration)
        XCTAssertTrue(s.onboardingDone)
        XCTAssertTrue(s.loaded)
        XCTAssertEqual(s.coins, 0)
        XCTAssertEqual(s.starsOf(1), 0)
        XCTAssertFalse(s.isLevelUnlocked(2))
    }

    func testDecodesAndroidSave() {
        // A save written by Android's ProgressRepository: levels 1-9 unlocked, stars 3,3,2 on 1-3, 2 collections.
        var lv = [UInt8](repeating: 0, count: 626)
        lv[0] = 0xFE
        lv[1] = 0x03
        var st = [UInt8](repeating: 0, count: 5001)
        st[1] = 3
        st[2] = 3
        st[3] = 2
        store.set("levels", Data(lv).base64EncodedString())
        store.set("stars", Data(st).base64EncodedString())
        store.set("collections", Data([0b110]).base64EncodedString())
        store.set("coins", 1234)
        store.set("booster_SHUFFLE", 7)
        store.set("skins", Set(["classic", "neon"]))
        store.set("skin", "neon")
        store.set("last_daily", Int64(20_500))
        store.set("streak", 4)
        let s = repo().state
        XCTAssertEqual((1...10).map { s.isLevelUnlocked($0) }, [true, true, true, true, true, true, true, true, true, false])
        XCTAssertEqual(s.starsOf(1), 3)
        XCTAssertEqual(s.starsOf(3), 2)
        XCTAssertEqual(s.nextLevel, 4)
        XCTAssertTrue(s.isCollectionUnlocked(1), "collection 1 is always open")
        XCTAssertTrue(s.isCollectionUnlocked(2))
        XCTAssertFalse(s.isCollectionUnlocked(3))
        XCTAssertEqual(s.coins, 1234)
        XCTAssertEqual(s.boosterCount(.SHUFFLE), 7)
        XCTAssertEqual(s.boosterCount(.CRANE), 2)
        XCTAssertEqual(s.ownedSkins, ["classic", "neon"])
        XCTAssertEqual(s.skin, "neon")
        XCTAssertEqual(s.lastDailyDay, 20_500)
        XCTAssertEqual(s.dailyStreak, 4)
    }
}
