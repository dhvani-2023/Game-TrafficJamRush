import XCTest
import GameKit
@testable import TrafficJamRush

/// The extras' save keys (in the existing "player" Prefs store, beside ProgressRepository's), the colour-blind
/// symbols baked into the sprite caches, and the new icons.
@MainActor
final class ExtrasRepositoryAndArtTests: XCTestCase {

    // --- Save keys -----------------------------------------------------------------------------

    func testUndoCountAndColourBlindSetting() {
        let (store, defaults) = ExtrasTest.store()
        let repo = ExtrasRepository(store: store)
        XCTAssertEqual(repo.undoCount, 2, "two to start, like the other boosters")
        XCTAssertFalse(repo.colorBlind, "off by default")
        repo.addUndo(-1)
        repo.addUndo(-5)
        XCTAssertEqual(repo.undoCount, 0, "never negative")
        repo.addUndo(3)
        repo.setColorBlind(true)
        XCTAssertEqual(defaults.integer(forKey: "player.booster_UNDO"), 3)
        XCTAssertEqual(defaults.object(forKey: "player.colorblind") as? Bool, true)
        let again = ExtrasRepository(store: store)
        XCTAssertEqual(again.undoCount, 3)
        XCTAssertTrue(again.colorBlind)
        XCTAssertEqual(ExtrasRepository.UNDO_PRICE, 60)
    }

    func testSharesTheProgressStoreWithoutDisturbingIt() {
        let (store, _) = ExtrasTest.store()
        let progress = ProgressRepository(store: store)
        progress.load()
        let repo = ExtrasRepository(store: store)
        repo.addUndo(4)
        repo.setColorBlind(true)
        _ = repo.completePuzzle(20_000)
        progress.addCoins(10)
        let p2 = ProgressRepository(store: store)
        p2.load()
        XCTAssertEqual(BoosterType.allCases.map { p2.state.boosterCount($0) }, [2, 2, 2])
        XCTAssertEqual(p2.state.coins, 10)
        XCTAssertEqual(ExtrasRepository(store: store).undoCount, 6)
    }

    func testResetProgressKeepsTheSetting() {
        let (store, _) = ExtrasTest.store()
        let repo = ExtrasRepository(store: store)
        repo.addUndo(5)
        repo.setColorBlind(true)
        _ = repo.completePuzzle(20_000)
        repo.saveGame(ExtrasSnapshot(level: 3, day: nil, fingerprint: 0, colors: [], mystery: [], spots: [], filled: [], order: [],
                                     open: [], queue: [], head: 0, boostersUsed: 0, revivesUsed: 0, parkCounter: 0,
                                     craneArmed: false, moves: [], savedAt: 0))
        repo.resetProgress()
        XCTAssertEqual(repo.undoCount, 2)
        XCTAssertEqual(repo.puzzleStreak, 0)
        XCTAssertEqual(repo.puzzleLast, -1)
        XCTAssertEqual(repo.puzzleDays, [])
        XCTAssertNil(repo.savedGame)
        XCTAssertTrue(repo.colorBlind)
        XCTAssertNil(ExtrasRepository(store: store).savedGame)
    }

    // --- Colour-blind symbols ------------------------------------------------------------------

    func testEveryColourHasItsOwnSymbol() {
        let symbols = (0..<8).map { ExtrasPatterns.symbol($0) }
        XCTAssertEqual(Set(symbols).count, 8)
        XCTAssertEqual(ExtrasPatterns.symbol(JamColor.RED.ordinal), .heart)
        XCTAssertEqual(ExtrasPatterns.symbol(JamColor.BLUE.ordinal), .square)
        XCTAssertEqual(ExtrasPatterns.symbol(JamColor.GREEN.ordinal), .clover)
        XCTAssertEqual(ExtrasPatterns.symbol(JamColor.YELLOW.ordinal), .star)
        XCTAssertEqual(ExtrasPatterns.symbol(JamColor.PINK.ordinal), .circle)
        XCTAssertEqual(ExtrasPatterns.symbol(JamColor.PURPLE.ordinal), .moon)
        XCTAssertEqual(ExtrasPatterns.symbol(JamColor.ORANGE.ordinal), .plus)
        XCTAssertEqual(ExtrasPatterns.symbol(JamColor.CYAN.ordinal), .diamond)
    }

    func testSymbolsAreDistinctShapes() {
        // Render each symbol alone and compare the ink masks.
        var masks: [[Bool]] = []
        for c in 0..<8 {
            let img = renderBitmap(60, 60, scale: 1) { s in
                ExtrasPatterns.drawSymbol(&s, c, Offset(30, 30), 24, ArtColor.Black, hole: ArtColor.White)
            }
            let px = ExtrasTest.pixels(img.cgImage)
            masks.append(stride(from: 0, to: px.count, by: 4).map { px[$0 + 3] > 128 && px[$0] < 100 })
        }
        for i in 0..<8 {
            XCTAssertGreaterThan(masks[i].filter { $0 }.count, 200, "symbol \(i) has ink")
            for j in (i + 1)..<8 {
                let diff = zip(masks[i], masks[j]).filter { $0 != $1 }.count
                XCTAssertGreaterThan(diff, 150, "symbols \(i) and \(j) differ")
            }
        }
    }

    func testRoofStickerIsBakedIntoTheSpriteStack() {
        let plain = VehicleArt(16, .CLASSIC)
        let marked = VehicleArt(16, .CLASSIC, patterns: true)
        for type in VehicleType.allCases {
            let a = plain.stack(type, JamColor.RED.ordinal, false)
            let b = marked.stack(type, JamColor.RED.ordinal, false)
            XCTAssertEqual(b.count, a.count + 1, "\(type.name): one sticker slice on top")
            XCTAssertEqual(b.last!.z, a.map(\.z).max()! + 1)
            XCTAssertEqual(marked.stack(type, 0, true).count, plain.stack(type, 0, true).count, "mystery vehicles show no symbol")
        }
        // The sticker differs per colour (heart vs square).
        let red = ExtrasTest.pixels(marked.stack(.VAN, JamColor.RED.ordinal, false).last!.base.cgImage)
        let blue = ExtrasTest.pixels(marked.stack(.VAN, JamColor.BLUE.ordinal, false).last!.base.cgImage)
        XCTAssertNotEqual(red, blue)
        // Composites (the cached 3D sprites) carry it.
        let c0 = plain.compositeNow(.CAR, JamColor.GREEN.ordinal, false, 90)
        let c1 = marked.compositeNow(.CAR, JamColor.GREEN.ordinal, false, 90)
        XCTAssertNotEqual(ExtrasTest.pixels(c0.bitmap.cgImage), ExtrasTest.pixels(c1.bitmap.cgImage))
    }

    func testShirtBadgeIsBakedIntoPassengerFrames() {
        let plain = PassengerArt(15, 27)
        let marked = PassengerArt(15, 27, patterns: true)
        for c in 0..<8 {
            for f in 0...4 {
                XCTAssertNotEqual(ExtrasTest.pixels(plain.get(c, f).cgImage), ExtrasTest.pixels(marked.get(c, f).cgImage), "colour \(c) frame \(f)")
            }
        }
        // Standing frame: the white badge sits on the chest, beside the symbol.
        let img = marked.get(JamColor.RED.ordinal, 4).cgImage
        let w = Float(img.width), h = Float(img.height)
        let r = w * 0.26
        let p = ExtrasTest.pixel(img, Int(w * 0.5 + r * 0.85), Int(h * 0.56))
        XCTAssertGreaterThan(p.r, 230)
        XCTAssertGreaterThan(p.g, 230)
        XCTAssertGreaterThan(p.b, 230)
    }

    func testEngineBuildsPatternedSpritesWhenAsked() {
        let level = LevelGenerator.generate(3)
        let on = GameEngine(level, Themes.forLevel(3), .CLASSIC, fx: ExtrasTest.NoFx(), patterns: true)
        on.setSize(393, 852, 59, 34)
        XCTAssertTrue(on.art.patterns)
        XCTAssertTrue(on.passengerArt.patterns)
        let off = GameEngine(level, Themes.forLevel(3), .CLASSIC, fx: ExtrasTest.NoFx())
        off.setSize(393, 852, 59, 34)
        XCTAssertFalse(off.art.patterns)
        XCTAssertFalse(off.passengerArt.patterns)
    }

    // --- Icons -----------------------------------------------------------------------------------

    func testNewIconsDraw() {
        for icon in [Icon.UNDO, Icon.FLAME] {
            let px = ExtrasTest.pixels(IconArt.image(icon, 48).cgImage)
            let ink = stride(from: 3, to: px.count, by: 4).filter { px[$0] > 0 }.count
            XCTAssertGreaterThan(ink, px.count / 4 / 5, "\(icon) is drawn")
        }
    }
}
