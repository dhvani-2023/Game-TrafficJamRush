import XCTest
import CoreGraphics
import GameKit
@testable import TrafficJamRush

/// Shared helpers for the extras' tests (headless engines, an isolated Prefs store, pixel reads).
enum ExtrasTest {
    struct NoFx: GameFx {
        func sfx(_ s: Sfx, _ rate: Float) {}
        func haptic(_ h: Haptic) {}
    }

    @MainActor
    static func engine(_ level: Level, _ events: @escaping (GameEvent) -> Void = { _ in }) -> GameEngine {
        let e = GameEngine(level, Themes.forLevel(max(1, level.number)), Skin.CLASSIC, fx: NoFx(), onEvent: events, headless: true)
        e.setSize(393, 852, 59, 34)
        return e
    }

    @MainActor
    static func engine(_ n: Int, _ events: @escaping (GameEvent) -> Void = { _ in }) -> GameEngine {
        engine(LevelGenerator.generate(n), events)
    }

    /// Steps the engine (and the extras session, like the game loop does) at 60 Hz.
    @MainActor
    static func run(_ e: GameEngine, _ x: ExtrasSession? = nil, _ seconds: Float) {
        var t: Float = 0
        while t < seconds {
            e.update(1 / 60)
            x?.tick(1 / 60)
            t += 1 / 60
        }
    }

    /// Steps until [cond] holds (at most [limit] seconds). Returns whether it did.
    @MainActor
    @discardableResult
    static func runUntil(_ e: GameEngine, _ x: ExtrasSession? = nil, limit: Float = 10, _ cond: () -> Bool) -> Bool {
        var t: Float = 0
        while t < limit {
            if cond() { return true }
            e.update(1 / 60)
            x?.tick(1 / 60)
            t += 1 / 60
        }
        return cond()
    }

    @MainActor
    static func vehicle(_ e: GameEngine, _ id: Int) -> Vehicle { e.vehicles.first { $0.id == id }! }

    static func store() -> (Prefs, UserDefaults) {
        let suite = "tjr.extras.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return (Prefs(name: "player", defaults: d), d)
    }

    /// RGBA8 pixels (top row first).
    static func pixels(_ img: CGImage) -> [UInt8] {
        let w = img.width, h = img.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    static func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let p = pixels(img)
        let i = (y * img.width + x) * 4
        return (p[i], p[i + 1], p[i + 2], p[i + 3])
    }
}
