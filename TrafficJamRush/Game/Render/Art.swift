import SwiftUI
import CoreGraphics
import GameKit

// Port of game/render/Art.kt.

// MARK: - Colours

/// `JamColor` body colours (Model.kt), in ordinal order.
private let jamHex: [UInt32] = [0xFFF2_453D, 0xFF2F_7CF6, 0xFF3D_BE4B, 0xFFFF_C21A, 0xFFFF_6FB5, 0xFF9B_5CF0, 0xFFFF_8A1F, 0xFF23_C9D9]
private let jamSwiftUIColors: [Color] = jamHex.map { Color(argb: $0) }

/// Kotlin `jamColor(i)`: the body colour of passenger / vehicle colour index [i].
func jamColor(_ i: Int) -> Color { jamSwiftUIColors[i] }

/// `jamColor` as an art colour (for Core Graphics / per-frame drawing).
func jamArtColor(_ i: Int) -> ArtColor { ArtColor(jamHex[i]) }

let MysteryColor = ArtColor(0xFF9B_A3AE)

// MARK: - Skins

enum Skin: String, CaseIterable, Identifiable {
    case CLASSIC = "classic"
    case CANDY = "candy"
    case RETRO = "retro"
    case TAXI = "taxi"
    case RACING = "racing"
    case SAFARI = "safari"
    case CHROME = "chrome"
    case TOY = "toy"
    case NEON = "neon"
    case GALAXY = "galaxy"
    case GOLDEN = "golden"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .CLASSIC: return "Classic"
        case .CANDY: return "Candy Pop"
        case .RETRO: return "Retro Cruiser"
        case .TAXI: return "City Cab"
        case .RACING: return "Speedway"
        case .SAFARI: return "Safari"
        case .CHROME: return "Chrome Shine"
        case .TOY: return "Toy Bricks"
        case .NEON: return "Neon Glow"
        case .GALAXY: return "Galaxy"
        case .GOLDEN: return "Royal Gold"
        }
    }

    var tagline: String {
        switch self {
        case .CLASSIC: return "Glossy factory paint"
        case .CANDY: return "Pastel paint with sugar stripes"
        case .RETRO: return "Two-tone, chrome and whitewalls"
        case .TAXI: return "Checker trim and roof light"
        case .RACING: return "Race stripes, numbers and wings"
        case .SAFARI: return "Camo paint and a loaded roof rack"
        case .CHROME: return "Mirror metal with dark glass"
        case .TOY: return "Snap-together plastic studs"
        case .NEON: return "Glowing edges and underglow"
        case .GALAXY: return "Deep-space paint full of stars"
        case .GOLDEN: return "Gold trim fit for a VIP"
        }
    }

    var price: Int {
        switch self {
        case .CLASSIC: return 0
        case .CANDY: return 300
        case .RETRO: return 500
        case .TAXI: return 600
        case .RACING: return 800
        case .SAFARI: return 900
        case .CHROME: return 1000
        case .TOY: return 1200
        case .NEON: return 1500
        case .GALAXY: return 1800
        case .GOLDEN: return 2500
        }
    }

    /// Kotlin `Skin.entries`.
    static var entries: [Skin] { allCases }

    static func of(_ id: String) -> Skin { allCases.first { $0.id == id } ?? .CLASSIC }
}

/// `VehicleType.ordinal` without depending on how the model enum is backed.
@inline(__always) func vehicleOrdinal(_ t: VehicleType) -> Int {
    switch t {
    case .CAR: return 0
    case .VAN: return 1
    case .BUS: return 2
    }
}

// MARK: - Vehicles

/// Pseudo-3D vehicles built by sprite stacking: each vehicle is a pile of thin horizontal
/// slices (tyres, bumpers, body, light band, glass, roof) drawn one pixel above the other.
/// Rotating every slice by the heading before stacking gives a convincing toy-car look at any
/// angle. Finished stacks are cached per (type, colour, angle bucket).
///
/// iOS: `unit` and every public measurement are in points; slices are built in device pixels
/// (one slice per pixel of height, like Android) and cropped to their content to save memory.
/// `composite` never blocks: a missing sprite is built on a background queue (several in
/// parallel) and nil is returned, so the renderer draws that vehicle slice by slice meanwhile
/// (`stackIfReady` + `drawSlices`); moving vehicles are always drawn slice by slice.
/// `compositeNow` is the synchronous Kotlin behaviour.
final class VehicleArt: @unchecked Sendable {
    let unit: Float
    let skin: Skin
    let pad: Float
    /// Extras: colour-blind symbol sticker on the roof (baked into the slice stack, so every cached composite has it).
    let patterns: Bool

    /// Device pixels per point.
    let k: Float
    private let unitPx: Float
    private let padPx: Float

    init(_ unit: Float, _ skin: Skin, patterns: Bool = false) {
        self.unit = unit
        self.skin = skin
        self.patterns = patterns
        pad = unit * 0.5
        k = Art.scale
        unitPx = unit * Art.scale
        padPx = unitPx * 0.5
    }

    convenience init(unit: Float, skin: Skin) { self.init(unit, skin) }

    /// Body width in points.
    func bodyW() -> Float { unit * 2 * 0.84 }
    /// Body length in points.
    func bodyL(_ type: VehicleType) -> Float { unit * Float(type.length) - unit * 0.32 }

    private func bodyWpx() -> Float { unitPx * 2 * 0.84 }
    private func bodyLpx(_ type: VehicleType) -> Float { unitPx * Float(type.length) - unitPx * 0.32 }
    private func sliceW() -> Int { Int((bodyWpx() * 1.2 + padPx * 2).rounded(.up)) }
    private func sliceH(_ type: VehicleType) -> Int { Int((bodyLpx(type) + padPx * 2).rounded(.up)) }

    /// Vertical pixels per unit of body width; tuned for a ~50° camera.
    private let lift: Float = 0.95

    // --- Public API -------------------------------------------------------------------------

    final class Composite {
        let bitmap: ImageBitmap
        /// Ground centre inside the bitmap, in points.
        let groundX: Float
        let groundY: Float
        /// Roof height above the ground, in points.
        let roofZ: Float

        init(_ bitmap: ImageBitmap, _ groundX: Float, _ groundY: Float, _ roofZ: Float) {
            self.bitmap = bitmap
            self.groundX = groundX
            self.groundY = groundY
            self.roofZ = roofZ
        }
    }

    /// One slice of the stack: a cropped bitmap placed at (dx, dy) device pixels inside the
    /// sliceW × sliceH frame, z pixels above the ground, darkened to q/50 (50 = untouched).
    struct Slice {
        let z: Int
        let base: ImageBitmap
        let q: Int
        let dx: Int
        let dy: Int
    }

    private let lock = NSLock()
    private var stacks: [Int: [Slice]] = [:]
    private var stackLocks: [Int: NSLock] = [:]
    private var composites: [Int64: (comp: Composite, used: UInt64)] = [:]
    private var useClock: UInt64 = 0
    private var pending = Set<Int64>()
    private var pendingStacks = Set<Int>()
    private var shadows: [Int: ImageBitmap] = [:]
    private var darkCache: [DarkKey: ImageBitmap] = [:]
    private var badges: [Int: ImageBitmap] = [:]

    private struct DarkKey: Hashable {
        let src: ObjectIdentifier
        let q: Int
    }

    private static let maxComposites = 160
    /// Background builders (a few at once: composites of one level build in parallel).
    private static let buildQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "trafficjam.vehicleart"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2))
        return q
    }()

    private func bucketOf(_ angle: Float) -> Int {
        let a = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return Kt.roundToInt(a / 2) % 180
    }

    private func compositeKey(_ type: VehicleType, _ color: Int, _ mystery: Bool, _ bucket: Int) -> Int64 {
        (Int64(stackKey(type, color, mystery)) << 9) | Int64(bucket)
    }

    /// The finished 3D sprite for [angle] degrees (clockwise from north), if it is cached.
    /// Never blocks: a missing sprite is queued for a background build and nil is returned (the
    /// renderer then draws the slices directly). Calling it ahead of time pre-warms the cache,
    /// which is what `GameEngine.setSize` does.
    @discardableResult
    func composite(_ type: VehicleType, _ color: Int, _ mystery: Bool, _ angle: Float) -> Composite? {
        let bucket = bucketOf(angle)
        let key = compositeKey(type, color, mystery, bucket)
        lock.lock()
        if let e = composites[key] {
            useClock &+= 1
            composites[key] = (e.comp, useClock)
            lock.unlock()
            return e.comp
        }
        let schedule = !pending.contains(key)
        if schedule { pending.insert(key) }
        lock.unlock()
        if schedule {
            VehicleArt.buildQueue.addOperation { [weak self] in
                guard let self else { return }
                let c = self.buildComposite(type, color, mystery, Float(bucket) * 2)
                self.storeComposite(key, c)
                // Moving vehicles are drawn slice by slice: have the darkened slices ready too.
                for sl in self.stack(type, color, mystery) { _ = self.darkened(sl) }
                self.lock.lock()
                self.pending.remove(key)
                self.lock.unlock()
            }
        }
        return nil
    }

    /// Synchronous `composite` (menus draw the sprite straight away).
    func compositeNow(_ type: VehicleType, _ color: Int, _ mystery: Bool, _ angle: Float) -> Composite {
        let bucket = bucketOf(angle)
        let key = compositeKey(type, color, mystery, bucket)
        if let c = cachedComposite(key) { return c }
        let c = buildComposite(type, color, mystery, Float(bucket) * 2)
        storeComposite(key, c)
        return c
    }

    private func cachedComposite(_ key: Int64) -> Composite? {
        lock.lock()
        defer { lock.unlock() }
        guard let e = composites[key] else { return nil }
        useClock &+= 1
        composites[key] = (e.comp, useClock)
        return e.comp
    }

    private func storeComposite(_ key: Int64, _ c: Composite) {
        lock.lock()
        defer { lock.unlock() }
        useClock &+= 1
        composites[key] = (c, useClock)
        if composites.count > VehicleArt.maxComposites {
            // Access-ordered LinkedHashMap eviction: drop the least recently used.
            if let eldest = composites.min(by: { $0.value.used < $1.value.used })?.key {
                composites.removeValue(forKey: eldest)
            }
        }
    }

    /// Draws the slice stack straight onto [ctx] at any angle, without caching. Used for the
    /// Garage turntable where the angle changes every frame. Coordinates are points.
    func drawLive(_ ctx: inout GraphicsContext, _ type: VehicleType, _ color: Int, _ angle: Float, _ ground: Offset) {
        drawSlices(&ctx, stack(type, color, false), type, angle, ground)
    }

    func drawLive(_ scope: inout FrameScope, _ type: VehicleType, _ color: Int, _ angle: Float, _ ground: Offset) {
        drawLive(&scope.ctx, type, color, angle, ground)
    }

    /// The slice stack if it has been built; otherwise queues it and returns nil (never blocks).
    func stackIfReady(_ type: VehicleType, _ color: Int, _ mystery: Bool) -> [Slice]? {
        let key = stackKey(type, color, mystery)
        lock.lock()
        if let s = stacks[key] {
            lock.unlock()
            return s
        }
        let schedule = !pendingStacks.contains(key)
        if schedule { pendingStacks.insert(key) }
        lock.unlock()
        if schedule {
            VehicleArt.buildQueue.addOperation { [weak self] in
                guard let self else { return }
                let s = self.stack(type, color, mystery)
                for sl in s { _ = self.darkened(sl) }
                self.lock.lock()
                self.pendingStacks.remove(key)
                self.lock.unlock()
            }
        }
        return nil
    }

    /// Slice-by-slice drawing at any angle. [ground] is in the context's units (points).
    func drawSlices(_ ctx: inout GraphicsContext, _ slices: [Slice], _ type: VehicleType, _ angle: Float, _ ground: Offset) {
        let sw = Float(sliceW()) / 2
        let sh = Float(sliceH(type)) / 2
        let saved = ctx.transform
        let rad = CGFloat(angle) * .pi / 180
        let base = saved.translatedBy(x: CGFloat(ground.x), y: CGFloat(ground.y))
        for s in slices {
            let img = darkened(s)
            ctx.transform = base.translatedBy(x: 0, y: -CGFloat(Float(s.z) / k)).rotated(by: rad)
            let r = CGRect(x: CGFloat((Float(s.dx) - sw) / k), y: CGFloat((Float(s.dy) - sh) / k),
                           width: CGFloat(img.width), height: CGFloat(img.height))
            ctx.draw(img.image, in: r)
        }
        ctx.transform = saved
    }

    /// Residual rotation between the requested angle and the cached bucket.
    func residual(_ angle: Float) -> Float {
        let a = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return a - Float(Kt.roundToInt(a / 2)) * 2
    }

    func shadow(_ type: VehicleType) -> ImageBitmap {
        let key = vehicleOrdinal(type)
        lock.lock()
        if let s = shadows[key] {
            lock.unlock()
            return s
        }
        lock.unlock()
        let bw = bodyWpx()
        let bl = bodyLpx(type)
        let neon = skin == .NEON
        let img = renderBitmap(sliceW(), sliceH(type)) { s in
            let color = neon ? ArtColor(red: 120 / 255, green: 220 / 255, blue: 1, alpha: 150 / 255)
                : ArtColor(red: 20 / 255, green: 25 / 255, blue: 45 / 255, alpha: 95 / 255)
            let cx = s.size.width / 2
            let cy = s.size.height / 2
            let r = CGRect(x: CGFloat(cx - bw * 0.52), y: CGFloat(cy - bl * 0.5), width: CGFloat(bw * 1.04), height: CGFloat(bl))
            let (rx, ry) = Draw.clampRadii(r, CGFloat(bw * 0.3), CGFloat(bw * 0.3))
            s.fillBlurred(.roundRect(r, rx, ry), color, blurRadius: unitPx * 0.38)
        }
        lock.lock()
        shadows[key] = img
        lock.unlock()
        return img
    }

    /// Size of Android's composite bitmap (a square of the slice diagonal plus the stack height) and
    /// its ground point, in points. Menu sprites use it so layouts around them match Android.
    func androidFrame(_ type: VehicleType, _ color: Int) -> (width: Float, height: Float, groundX: Float, groundY: Float) {
        let sw = sliceW()
        let sh = sliceH(type)
        let diag = Float(sw * sw + sh * sh).squareRoot()
        let maxZ = (stack(type, color, false).map(\.z).max() ?? 0) + 1
        let w = Int(diag.rounded(.up)) + 2
        let h = Int(diag.rounded(.up)) + maxZ + 2
        return (Float(w) / k, Float(h) / k, Float(w) / 2 / k, (Float(maxZ) + diag / 2 + 1) / k)
    }

    /// Roof rectangle in north-facing local coordinates (origin at footprint centre), in points.
    func roofRect(_ type: VehicleType) -> Rect {
        let bw = bodyW()
        let bl = bodyL(type)
        let g = greenhouse(type)
        return Rect(-bw / 2 + bw * g.inset, -bl / 2 + bl * g.start, bw / 2 - bw * g.inset, -bl / 2 + bl * g.end)
    }

    /// Roof height in points.
    func roofZ(_ type: VehicleType) -> Float { Float(heights(type).roofTop) / k }

    /// Upright "?" badge for mystery vehicles at scale 1 (circle radius bodyW·0.3 plus a 1.5 px rim).
    /// Kotlin draws it per frame with a text paint; here it is pre-rendered once.
    func mysteryBadge() -> ImageBitmap {
        lock.lock()
        if let b = badges[0] {
            lock.unlock()
            return b
        }
        lock.unlock()
        let r = bodyWpx() * 0.3
        let size = Int((2 * (r + 1.5) + 2).rounded(.up))
        let img = renderBitmap(size, size) { s in
            let c = Offset(Float(size) / 2, Float(size) / 2)
            s.drawCircle(ArtColor(0xFF3E_4652), r + 1.5, c)
            s.drawCircle(ArtColor.White, r, c)
            s.drawText("?", c.x, c.y + r * 0.52, r * 1.5, ArtColor(red: 62 / 255, green: 70 / 255, blue: 82 / 255))
        }
        lock.lock()
        badges[0] = img
        lock.unlock()
        return img
    }

    // --- Geometry ---------------------------------------------------------------------------

    private struct Greenhouse {
        let start: Float
        let end: Float
        let inset: Float
        let radius: Float
    }

    private func greenhouse(_ type: VehicleType) -> Greenhouse {
        switch type {
        case .CAR: return Greenhouse(start: 0.26, end: 0.84, inset: 0.11, radius: 0.26)
        case .VAN: return Greenhouse(start: 0.16, end: 0.97, inset: 0.08, radius: 0.22)
        case .BUS: return Greenhouse(start: 0.03, end: 0.985, inset: 0.05, radius: 0.14)
        }
    }

    private func bodyRadius(_ type: VehicleType) -> Float {
        let f: Float
        switch type {
        case .CAR: f = 0.3
        case .VAN: f = 0.22
        case .BUS: f = 0.14
        }
        return bodyWpx() * f
    }

    private struct Heights {
        let tyre: Int
        let bumper: Int
        let lower: Int
        let lights: Int
        let upper: Int
        let glass: Int
        let roofTop: Int
    }

    private func heights(_ type: VehicleType) -> Heights {
        let bw = bodyWpx() * lift
        func px(_ f: Float) -> Int { max(1, Kt.roundToInt(bw * f)) }
        let tyre = px(0.1)
        let bumper = px(0.06)
        let lower = px(type == .CAR ? 0.05 : 0.08)
        let lights = px(0.07)
        let upper = px(0.05)
        let glassF: Float
        switch type {
        case .CAR: glassF = 0.17
        case .VAN: glassF = 0.24
        case .BUS: glassF = 0.26
        }
        let glass = px(glassF)
        let roofTop = tyre / 2 + bumper + lower + lights + upper + glass
        return Heights(tyre: tyre, bumper: bumper, lower: lower, lights: lights, upper: upper, glass: glass, roofTop: roofTop)
    }

    private func wheelSpots(_ type: VehicleType) -> [Float] {
        switch type {
        case .CAR: return [0.19, 0.78]
        case .VAN: return [0.15, 0.8]
        case .BUS: return [0.13, 0.32, 0.82]
        }
    }

    // --- Palette per skin -------------------------------------------------------------------

    private struct Palette {
        let body: ArtColor
        let roof: ArtColor
        let trim: ArtColor
        let glassTop: ArtColor
        let glassBottom: ArtColor
        let edge: ArtColor?
    }

    private func palette(_ base: ArtColor, _ mystery: Bool) -> Palette {
        if mystery {
            return Palette(body: base, roof: base.tint(0.18), trim: ArtColor(0xFF5A_606B), glassTop: ArtColor(0xFF8D_A2BF), glassBottom: ArtColor(0xFF2E_3A4F), edge: nil)
        }
        switch skin {
        case .CLASSIC:
            return Palette(body: base, roof: base.tint(0.14), trim: ArtColor(0xFF3A_3F48), glassTop: ArtColor(0xFF6E_93C4), glassBottom: ArtColor(0xFF1A_2640), edge: nil)
        case .CANDY:
            return Palette(body: base.tint(0.38), roof: base.tint(0.55), trim: ArtColor(0xFFFF_FFFF), glassTop: ArtColor(0xFFC9_E8FF), glassBottom: ArtColor(0xFF6E_8BB5), edge: .White)
        case .RETRO:
            return Palette(body: base.gray(0.12), roof: ArtColor(0xFFFF_F3DA), trim: ArtColor(0xFFD5_DBE2), glassTop: ArtColor(0xFF9E_C3D9), glassBottom: ArtColor(0xFF2F_4A5C), edge: ArtColor(0xFFFF_F3DA))
        case .TAXI:
            return Palette(body: base, roof: base.tint(0.1), trim: ArtColor(0xFF26_282E), glassTop: ArtColor(0xFF8F_B3E0), glassBottom: ArtColor(0xFF22_3250), edge: nil)
        case .RACING:
            return Palette(body: base.shade(1.03), roof: base.tint(0.08), trim: ArtColor(0xFF1E_2128), glassTop: ArtColor(0xFF6E_7F99), glassBottom: ArtColor(0xFF15_1C2A), edge: .White)
        case .SAFARI:
            return Palette(body: base.gray(0.28), roof: base.gray(0.2).tint(0.08), trim: ArtColor(0xFF3B_3328), glassTop: ArtColor(0xFFA9_C6A8), glassBottom: ArtColor(0xFF2C_3B2C), edge: nil)
        case .CHROME:
            return Palette(body: base.gray(0.25).tint(0.15), roof: base.gray(0.2).tint(0.35), trim: ArtColor(0xFFF5_F7FA), glassTop: ArtColor(0xFF3A_414C), glassBottom: ArtColor(0xFF07_090C), edge: ArtColor(0xFFF5_F7FA))
        case .TOY:
            return Palette(body: base, roof: base, trim: base.shade(0.82), glassTop: ArtColor(0xFFBF_E4FF), glassBottom: ArtColor(0xFF5E_88B8), edge: nil)
        case .NEON:
            return Palette(body: ArtColor(0xFF1B_1F2E), roof: ArtColor(0xFF24_2A3D), trim: base, glassTop: base.tint(0.4), glassBottom: base.shade(0.5), edge: base.tint(0.25))
        case .GALAXY:
            return Palette(body: lerp(base.shade(0.42), ArtColor(0xFF2A_1B5C), 0.45), roof: lerp(base.shade(0.5), ArtColor(0xFF3A_2A7A), 0.4),
                           trim: ArtColor(0xFFC9_D2FF), glassTop: ArtColor(0xFFB3_9DFF), glassBottom: ArtColor(0xFF1A_1240), edge: ArtColor(0xFFC9_D2FF))
        case .GOLDEN:
            return Palette(body: base, roof: base.tint(0.12), trim: ArtColor(0xFFFF_C93C), glassTop: ArtColor(0xFF9F_C4F0), glassBottom: ArtColor(0xFF1F_2E4A), edge: ArtColor(0xFFFF_C93C))
        }
    }

    // --- Slices -----------------------------------------------------------------------------

    private func stackKey(_ type: VehicleType, _ color: Int, _ mystery: Bool) -> Int { vehicleOrdinal(type) * 16 + (mystery ? 15 : color) }

    /// (z, slice) pairs, bottom to top. Builds synchronously if needed (one builder per stack).
    func stack(_ type: VehicleType, _ color: Int, _ mystery: Bool) -> [Slice] {
        let key = stackKey(type, color, mystery)
        lock.lock()
        if let s = stacks[key] {
            lock.unlock()
            return s
        }
        let keyLock: NSLock
        if let l = stackLocks[key] {
            keyLock = l
        } else {
            keyLock = NSLock()
            stackLocks[key] = keyLock
        }
        lock.unlock()
        keyLock.lock()
        defer { keyLock.unlock() }
        lock.lock()
        if let s = stacks[key] {
            lock.unlock()
            return s
        }
        lock.unlock()
        let s = buildStack(type, mystery ? MysteryColor : jamArtColor(color), mystery, color)
        lock.lock()
        stacks[key] = s
        lock.unlock()
        return s
    }

    private func buildStack(_ type: VehicleType, _ base: ArtColor, _ mystery: Bool, _ color: Int) -> [Slice] {
        let w = sliceW()
        let h = sliceH(type)
        let bw = bodyWpx()
        let bl = bodyLpx(type)
        let cx = Float(w) / 2
        let cy = Float(h) / 2
        let r = bodyRadius(type)
        let pal = palette(base, mystery)
        let hs = heights(type)
        let gh = greenhouse(type)
        var out: [(Int, ImageBitmap, Int)] = []
        let bodyRect = Rect(cx - bw / 2, cy - bl / 2, cx + bw / 2, cy + bl / 2)

        // Every slice's content lies within the body ± 0.1 bw (tyres, hubs, mirrors) and ± 2 px.
        let cropX = max(0, Int((bodyRect.left - bw * 0.1).rounded(.down)))
        let cropY = max(0, Int((bodyRect.top - 2).rounded(.down)))
        let cropR = min(w, Int((bodyRect.right + bw * 0.1).rounded(.up)))
        let cropB = min(h, Int((bodyRect.bottom + 2).rounded(.up)))
        let cw = cropR - cropX
        let ch = cropB - cropY

        func slice(_ block: (inout BitmapScope) -> Void) -> ImageBitmap {
            let img = renderCGImage(cw, ch) { s in
                // Draw in full-slice coordinates.
                s.translate(-Float(cropX), -Float(cropY)) { s in block(&s) }
            }
            return ImageBitmap(img, scale: k)
        }
        /// Darkening is applied later (composites darken rotated copies, live drawing caches them).
        func dim(_ img: ImageBitmap, _ f: Float) -> (ImageBitmap, Int) { (img, Kt.roundToInt(f.coerceIn(0, 1) * 50)) }
        func add(_ z: Int, _ d: (ImageBitmap, Int)) { out.append((z, d.0, d.1)) }
        func add(_ z: Int, _ img: ImageBitmap) { out.append((z, img, 50)) }

        // Tyres: dark blocks poking out of the sides, hub caps show on the outer face.
        let tyre = slice { s in
            for wy in self.wheelSpots(type) {
                let y = bodyRect.top + bl * wy
                let tl = bl * 0.13
                s.drawRoundRect(ArtColor(0xFF1C_1E22), Offset(bodyRect.left - bw * 0.05, y), Size(bw * 1.1, tl), CornerRadius(bw * 0.06))
                let hub: ArtColor
                if self.skin == .RETRO && !mystery {
                    hub = .White
                } else if self.skin == .GOLDEN && !mystery {
                    hub = ArtColor(0xFFFF_C93C)
                } else {
                    hub = ArtColor(0xFFB8_C0CA)
                }
                s.drawRect(hub, Offset(bodyRect.left - bw * 0.05, y + tl * 0.3), Size(bw * 0.035, tl * 0.4))
                s.drawRect(hub, Offset(bodyRect.right + bw * 0.015, y + tl * 0.3), Size(bw * 0.035, tl * 0.4))
            }
        }
        var z = 0
        for i in 0..<hs.tyre {
            add(z, dim(tyre, 0.75 + 0.25 * Float(i) / Float(hs.tyre)))
            z += 1
        }
        z = hs.tyre / 2

        let bodyPath = ArtPath { $0.addRoundRect(bodyRect, CornerRadius(r)) }

        // Wall slice: body silhouette whose outline pixels carry the side detailing.
        func wall(_ kind: Int) -> ImageBitmap {
            slice { s in
                s.drawPath(bodyPath, pal.body)
                s.clipPath(bodyPath) { s in
                    let front = bl * 0.07
                    switch kind {
                    case 0: // bumpers
                        s.drawRect(pal.trim, Offset(bodyRect.left, bodyRect.top), Size(bw, front))
                        s.drawRect(pal.trim, Offset(bodyRect.left, bodyRect.bottom - front), Size(bw, front))
                        s.drawRect(pal.body.shade(0.8), Offset(bodyRect.left, bodyRect.top + front), Size(bw, bl - 2 * front))
                    case 1: // light band: headlights, grille, tail lights, side decoration
                        s.drawRect(ArtColor(0xFFFF_F7CF), Offset(bodyRect.left, bodyRect.top), Size(bw * 0.3, front))
                        s.drawRect(ArtColor(0xFFFF_F7CF), Offset(bodyRect.right - bw * 0.3, bodyRect.top), Size(bw * 0.3, front))
                        s.drawRect(pal.trim.shade(0.8), Offset(bodyRect.left + bw * 0.36, bodyRect.top), Size(bw * 0.28, front))
                        s.drawRect(ArtColor(0xFFE5_322B), Offset(bodyRect.left, bodyRect.bottom - front), Size(bw * 0.26, front))
                        s.drawRect(ArtColor(0xFFE5_322B), Offset(bodyRect.right - bw * 0.26, bodyRect.bottom - front), Size(bw * 0.26, front))
                        self.sideDecor(&s, bodyRect, pal, mystery)
                    default:
                        if let edge = pal.edge, !mystery, self.skin != .TAXI {
                            s.drawPath(bodyPath, edge, style: .stroke(max(1.5, bw * 0.05)))
                        }
                    }
                }
            }
        }
        let bumper = wall(0)
        let lower = wall(3)
        let lights = wall(1)
        let upper = wall(2)
        for i in 0..<hs.bumper { add(z, dim(bumper, 0.6 + 0.06 * Float(i) / Float(hs.bumper))); z += 1 }
        for i in 0..<hs.lower { add(z, dim(lower, 0.66 + 0.1 * Float(i) / Float(hs.lower))); z += 1 }
        for i in 0..<hs.lights { add(z, dim(lights, 0.8 + 0.08 * Float(i) / Float(hs.lights))); z += 1 }
        for i in 0..<(hs.upper - 1) { add(z, dim(upper, 0.88 + 0.06 * Float(i) / Float(hs.upper))); z += 1 }
        add(z, slice { s in self.hoodCap(&s, type, bodyRect, bodyPath, pal, mystery) })
        z += 1

        // Glass band: cabin silhouette in glass colours with body-coloured pillars.
        let cab = Rect(bodyRect.left + bw * gh.inset, bodyRect.top + bl * gh.start, bodyRect.right - bw * gh.inset, bodyRect.top + bl * gh.end)
        let cabPath = ArtPath { $0.addRoundRect(cab, CornerRadius(bw * gh.radius)) }
        let glass = slice { s in
            s.drawPath(cabPath, Brush.verticalGradient([pal.glassTop, pal.glassBottom], cab.top, cab.bottom))
            s.clipPath(cabPath) { s in
                let pillar = max(1.5, bl * 0.022)
                let pillars: [Float]
                switch type {
                case .CAR: pillars = [0.02, 0.5, 0.97]
                case .VAN: pillars = [0.02, 0.2, 0.45, 0.7, 0.97]
                case .BUS: pillars = (0...9).map { 0.01 + Float($0) * 0.108 }
                }
                for p in pillars {
                    s.drawRect(pal.body, Offset(cab.left, cab.top + cab.height * p - pillar / 2), Size(cab.width, pillar))
                }
                // Reflection streak
                s.drawRect(ArtColor.White.copy(alpha: 0.18), Offset(cab.left, cab.top), Size(cab.width, cab.height * 0.08))
                if self.skin == .NEON && !mystery, let edge = pal.edge {
                    s.drawPath(cabPath, edge, style: .stroke(max(1.5, bw * 0.04)))
                }
            }
        }
        let glassTop = slice { s in s.drawPath(cabPath, pal.body.shade(0.92)) }
        for i in 0..<(hs.glass - 1) { add(z, dim(glass, 0.92 + 0.08 * Float(i) / Float(hs.glass))); z += 1 }
        add(z, dim(glassTop, 0.92))
        z += 1
        add(z, slice { s in self.roofCap(&s, type, cab, cabPath, bodyRect, pal, mystery) })
        let roofZ = z

        // Extras on the roof.
        if type == .BUS && skin != .TOY {
            let ac = Rect(cx - bw * 0.2, cab.top + cab.height * 0.7, cx + bw * 0.2, cab.top + cab.height * 0.86)
            let acSide = slice { s in s.drawRoundRect(ArtColor(0xFFAE_B7C2), ac.topLeft, ac.size, CornerRadius(bw * 0.05)) }
            let acTop = slice { s in
                s.drawRoundRect(ArtColor(0xFFE3_E8EE), ac.topLeft, ac.size, CornerRadius(bw * 0.05))
                for kk in 1...3 {
                    let x = ac.left + ac.width * Float(kk) / 4
                    s.drawLine(ArtColor(0xFFB8_C1CC), Offset(x, ac.top + 2), Offset(x, ac.bottom - 2), 1)
                }
            }
            for kk in 1...max(1, hs.upper) { add(roofZ + kk, acSide) }
            add(roofZ + hs.upper + 1, acTop)
        }
        if !mystery {
            switch skin {
            case .TAXI:
                let sign = Rect(cx - bw * 0.2, cab.top + cab.height * 0.04, cx + bw * 0.2, cab.top + cab.height * (type == .CAR ? 0.2 : 0.1))
                let side = slice { s in s.drawRoundRect(ArtColor(0xFF2A_2A2A), sign.topLeft, sign.size, CornerRadius(bw * 0.04)) }
                let top = slice { s in
                    s.drawRoundRect(ArtColor(0xFFFF_D84A), sign.topLeft, sign.size, CornerRadius(bw * 0.04))
                    s.drawRect(ArtColor(0xFF2A_2A2A), Offset(sign.left + sign.width * 0.2, sign.center.y - 1), Size(sign.width * 0.6, 2))
                }
                let n = max(2, hs.upper + 1)
                for kk in 1...n { add(roofZ + kk, side) }
                add(roofZ + n + 1, top)
            case .RACING:
                if type == .CAR {
                    let wing = Rect(bodyRect.left + bw * 0.02, bodyRect.bottom - bl * 0.1, bodyRect.right - bw * 0.02, bodyRect.bottom - bl * 0.03)
                    let post = slice { s in
                        s.drawRect(ArtColor(0xFF1E_2128), Offset(cx - bw * 0.3, wing.top), Size(bw * 0.06, wing.height))
                        s.drawRect(ArtColor(0xFF1E_2128), Offset(cx + bw * 0.24, wing.top), Size(bw * 0.06, wing.height))
                    }
                    let top = slice { s in
                        s.drawRoundRect(ArtColor(0xFF1E_2128), wing.topLeft, wing.size, CornerRadius(bw * 0.03))
                        s.drawRect(ArtColor.White, Offset(wing.left, wing.center.y - 0.75), Size(wing.width, 1.5))
                    }
                    let base = hs.tyre / 2 + hs.bumper + hs.lower + hs.lights + hs.upper
                    let n = max(2, hs.glass / 2)
                    for kk in 1...n { add(base + kk, post) }
                    add(base + n + 1, top)
                }
            case .SAFARI:
                let rack = Rect(cab.left + bw * 0.08, cab.top + cab.height * (type == .CAR ? 0.8 : 0.78), cab.right - bw * 0.08, cab.bottom - cab.height * 0.03)
                let box = slice { s in s.drawRoundRect(ArtColor(0xFF8D_6E4A), rack.topLeft, rack.size, CornerRadius(bw * 0.04)) }
                let top = slice { s in
                    s.drawRoundRect(ArtColor(0xFFB0_8A5C), rack.topLeft, rack.size, CornerRadius(bw * 0.04))
                    s.drawLine(ArtColor(0xFF6D_5235), Offset(rack.left, rack.center.y), Offset(rack.right, rack.center.y), 1.5)
                    s.drawLine(ArtColor(0xFF6D_5235), Offset(rack.center.x, rack.top), Offset(rack.center.x, rack.bottom), 1.5)
                }
                let n = max(2, hs.upper + 1)
                for kk in 1...n { add(roofZ + kk, box) }
                add(roofZ + n + 1, top)
            case .TOY:
                let studs = studPositions(type, cab, bw)
                let studSide = slice { s in for st in studs { s.drawCircle(pal.body.shade(0.72), bw * 0.1, st) } }
                let studTop = slice { s in
                    for st in studs {
                        s.drawCircle(pal.body.tint(0.14), bw * 0.1, st)
                        s.drawCircle(pal.body.shade(0.85), bw * 0.1, st, style: .stroke(1))
                        s.drawCircle(ArtColor.White.copy(alpha: 0.6), bw * 0.035, st - Offset(bw * 0.03, bw * 0.03))
                    }
                }
                add(roofZ + 1, studSide)
                add(roofZ + 2, studSide)
                add(roofZ + 3, studTop)
            default:
                break
            }
        }
        if patterns && !mystery {
            // Extras: the colour's symbol sticker sits on top of everything on the roof (racks, studs, signs).
            let zTop = (out.map(\.0).max() ?? z) + 1
            add(zTop, slice { s in ExtrasPatterns.roofSticker(&s, color, type, cab, bw) })
        }
        // Stable sort by z (equal heights keep insertion order, like sortedBy).
        let sorted = out.enumerated().sorted { a, b in
            a.element.0 != b.element.0 ? a.element.0 < b.element.0 : a.offset < b.offset
        }
        return sorted.map { Slice(z: $0.element.0, base: $0.element.1, q: $0.element.2, dx: cropX, dy: cropY) }
    }

    private func studPositions(_ type: VehicleType, _ cab: Rect, _ bw: Float) -> [Offset] {
        let step = bw * 0.27
        let rows = Kt.toInt((cab.height - step * 0.6) / step).coerceAtLeast(2)
        var list: [Offset] = []
        for kk in 0..<rows {
            let y = cab.top + step * 0.6 + Float(kk) * step
            list.append(Offset(cab.left + bw * 0.13, y))
            list.append(Offset(cab.right - bw * 0.13, y))
        }
        return list
    }

    private func sideDecor(_ s: inout BitmapScope, _ body: Rect, _ pal: Palette, _ mystery: Bool) {
        if mystery { return }
        let bw = body.width
        let bl = body.height
        switch skin {
        case .TAXI:
            let sq = max(2, bl * 0.045)
            var y = body.top + bl * 0.1
            var kk = 0
            while y < body.bottom - bl * 0.1 {
                let c = kk % 2 == 0 ? ArtColor(0xFF1A_1A1A) : ArtColor.White
                s.drawRect(c, Offset(body.left, y), Size(bw * 0.08, sq))
                s.drawRect(kk % 2 == 0 ? ArtColor.White : ArtColor(0xFF1A_1A1A), Offset(body.right - bw * 0.08, y), Size(bw * 0.08, sq))
                y += sq
                kk += 1
            }
        case .RACING:
            s.drawRect(ArtColor.White, Offset(body.left, body.top + bl * 0.3), Size(bw * 0.08, bl * 0.2))
            s.drawRect(ArtColor.White, Offset(body.right - bw * 0.08, body.top + bl * 0.3), Size(bw * 0.08, bl * 0.2))
        case .GALAXY:
            let rnd = KotlinRandom(Kt.toInt(bl))
            for _ in 0..<10 {
                let x = body.left + rnd.nextFloat() * bw
                let y = body.top + rnd.nextFloat() * bl
                s.drawCircle(ArtColor.White.copy(alpha: 0.9), 0.9, Offset(x, y))
            }
        default:
            break
        }
    }

    // --- Caps (the visible top surfaces) ----------------------------------------------------

    private func hoodCap(_ s: inout BitmapScope, _ type: VehicleType, _ body: Rect, _ bodyPath: ArtPath, _ pal: Palette, _ mystery: Bool) {
        let bw = body.width
        let bl = body.height
        let neon = skin == .NEON && !mystery
        s.drawPath(bodyPath, Brush.horizontalGradient(stops: [
            (0, pal.body.shade(0.86)), (0.25, pal.body), (0.5, pal.body.tint(0.12)), (0.75, pal.body), (1, pal.body.shade(0.86)),
        ], startX: body.left, endX: body.right))
        s.clipPath(bodyPath) { s in
            self.paintwork(&s, body, pal, mystery, hood: true)
            // Headlights and tail lights seen from above.
            let lw = bw * 0.2
            let lh = bl * 0.035
            s.drawRoundRect(ArtColor(0xFFFF_FBE0), Offset(body.left + bw * 0.08, body.top + 1), Size(lw, lh), CornerRadius(lh))
            s.drawRoundRect(ArtColor(0xFFFF_FBE0), Offset(body.right - bw * 0.08 - lw, body.top + 1), Size(lw, lh), CornerRadius(lh))
            s.drawRoundRect(ArtColor(0xFFE5_322B), Offset(body.left + bw * 0.08, body.bottom - lh - 1), Size(lw, lh), CornerRadius(lh))
            s.drawRoundRect(ArtColor(0xFFE5_322B), Offset(body.right - bw * 0.08 - lw, body.bottom - lh - 1), Size(lw, lh), CornerRadius(lh))
            if type == .CAR && !mystery {
                // Hood panel line
                s.drawLine(pal.body.shade(0.82), Offset(body.left + bw * 0.22, body.top + bl * 0.06), Offset(body.left + bw * 0.22, body.top + bl * 0.27), 1)
                s.drawLine(pal.body.shade(0.82), Offset(body.right - bw * 0.22, body.top + bl * 0.06), Offset(body.right - bw * 0.22, body.top + bl * 0.27), 1)
            }
        }
        s.drawPath(bodyPath, neon ? pal.edge! : pal.body.shade(0.6), style: .stroke(neon ? bw * 0.05 : 1.2))
        // mirrors
        let mf: Float
        switch type {
        case .CAR: mf = 0.3
        case .VAN: mf = 0.17
        case .BUS: mf = 0.04
        }
        let my = body.top + bl * mf
        s.drawOval(pal.body.shade(0.75), Offset(body.left - bw * 0.08, my), Size(bw * 0.13, bl * 0.045))
        s.drawOval(pal.body.shade(0.75), Offset(body.right - bw * 0.05, my), Size(bw * 0.13, bl * 0.045))
    }

    private func roofCap(_ s: inout BitmapScope, _ type: VehicleType, _ cab: Rect, _ cabPath: ArtPath, _ body: Rect, _ pal: Palette, _ mystery: Bool) {
        let bw = body.width
        let neon = skin == .NEON && !mystery
        s.drawPath(cabPath, Brush.linearGradient([pal.roof.tint(0.18), pal.roof, pal.roof.shade(0.9)],
                                                 start: Offset(cab.left, cab.top), end: Offset(cab.right, cab.bottom)))
        s.clipPath(cabPath) { s in
            self.paintwork(&s, cab, pal, mystery, hood: false)
            // Glossy highlight along the left edge of the roof
            s.drawRoundRect(ArtColor.White.copy(alpha: self.skin == .CHROME ? 0.45 : 0.22),
                            Offset(cab.left + cab.width * 0.07, cab.top + cab.height * 0.08), Size(cab.width * 0.12, cab.height * 0.6), CornerRadius(cab.width * 0.06))
        }
        s.drawPath(cabPath, neon ? pal.edge! : pal.roof.shade(0.72), style: .stroke(neon ? bw * 0.045 : 1.2))

        // Arrow
        let la = min(bw * 1.02, cab.height * 0.9)
        let wa = bw * 0.62
        let acx = cab.center.x
        let acy = cab.center.y + (type == .BUS ? -cab.height * 0.08 : 0)
        let shadowCol = neon ? ArtColor.Black.copy(alpha: 0.6) : pal.roof.shade(0.45).copy(alpha: 0.55)
        s.drawPath(VehicleArt.arrowPath(acx + bw * 0.03, acy + bw * 0.06, wa, la), shadowCol)
        let arrow = VehicleArt.arrowPath(acx, acy, wa, la)
        s.drawPath(arrow, neon ? pal.edge! : ArtColor.White)
        if !neon { s.drawPath(arrow, pal.roof.shade(0.55).copy(alpha: 0.7), style: .stroke(max(1, bw * 0.025))) }
        s.drawPath(arrow, Brush.verticalGradient([ArtColor.White.copy(alpha: 0), ArtColor(0x2200_0000)], acy - la / 2, acy + la / 2))
        if skin == .GOLDEN && !mystery { s.drawPath(arrow, ArtColor(0xFFFF_C93C), style: .stroke(max(1, bw * 0.03))) }
    }

    /// Skin-specific paint applied to hood and roof caps (clipped to the surface).
    private func paintwork(_ s: inout BitmapScope, _ area: Rect, _ pal: Palette, _ mystery: Bool, hood: Bool) {
        if mystery { return }
        let bw = bodyWpx()
        switch skin {
        case .CANDY:
            let sw = bw * 0.08
            s.drawRect(ArtColor.White.copy(alpha: 0.92), Offset(area.center.x - sw * 2.2, area.top), Size(sw, area.height))
            s.drawRect(ArtColor.White.copy(alpha: 0.92), Offset(area.center.x + sw * 1.2, area.top), Size(sw, area.height))
        case .RACING:
            let sw = bw * 0.14
            s.drawRect(ArtColor.White, Offset(area.center.x - sw * 1.25, area.top), Size(sw, area.height))
            s.drawRect(ArtColor.White, Offset(area.center.x + sw * 0.25, area.top), Size(sw, area.height))
            if hood {
                let c = Offset(area.center.x, area.top + area.height * 0.15)
                s.drawCircle(ArtColor.White, bw * 0.17, c)
                s.drawCircle(ArtColor(0xFF1E_2128), bw * 0.17, c, style: .stroke(1.2))
            }
        case .SAFARI:
            let rnd = KotlinRandom(Kt.toInt(area.width * 31 + area.height))
            let n = Kt.toInt(area.height / bw * 9).coerceIn(8, 40)
            for it in 0..<n {
                let cxx = area.left - bw * 0.1 + rnd.nextFloat() * area.width
                let cyy = area.top + rnd.nextFloat() * area.height
                let col: ArtColor
                switch it % 3 {
                case 0: col = pal.body.shade(0.6)
                case 1: col = ArtColor(0xFF5D_4A2E).copy(alpha: 0.75)
                default: col = pal.body.tint(0.3)
                }
                let ow = bw * (0.22 + rnd.nextFloat() * 0.22)
                let oh = bw * (0.14 + rnd.nextFloat() * 0.16)
                s.drawOval(col, Offset(cxx, cyy), Size(ow, oh))
            }
        case .CHROME:
            s.drawRect(Brush.linearGradient(stops: [
                (0, ArtColor.Black.copy(alpha: 0.18)), (0.3, ArtColor.White.copy(alpha: 0.8)), (0.38, ArtColor.Transparent),
                (0.62, ArtColor.Black.copy(alpha: 0.12)), (0.72, ArtColor.White.copy(alpha: 0.55)), (1, ArtColor.Transparent),
            ], start: Offset(area.left, area.top), end: Offset(area.right, area.top + area.width * 1.2)), area.topLeft, area.size)
        case .RETRO:
            if !hood {
                s.drawRect(ArtColor.White.copy(alpha: 0.25), area.topLeft, area.size)
            } else {
                s.drawRect(pal.trim, Offset(area.left, area.top + area.height * 0.5 - 1), Size(area.width, 2))
            }
        case .GALAXY:
            let rnd = KotlinRandom(Kt.toInt(area.height * 7))
            s.drawRect(Brush.radialGradient([ArtColor(0x557C_4DFF), ArtColor.Transparent], area.center, area.maxDimension * 0.6), area.topLeft, area.size)
            let n = Kt.toInt(area.width * area.height / (bw * bw) * 14).coerceIn(6, 60)
            for _ in 0..<n {
                let a = 0.5 + rnd.nextFloat() * 0.5
                let rr = 0.5 + rnd.nextFloat() * 1.1
                let x = area.left + rnd.nextFloat() * area.width
                let y = area.top + rnd.nextFloat() * area.height
                s.drawCircle(ArtColor.White.copy(alpha: a), rr, Offset(x, y))
            }
        case .GOLDEN:
            s.drawRect(pal.trim, Offset(area.left, area.top), Size(area.width, max(1.5, bw * 0.04)))
            if !hood { s.drawCircle(ArtColor(0xFFFF_C93C).copy(alpha: 0.35), bw * 0.4, area.center) }
        default:
            break
        }
    }

    // --- Composite --------------------------------------------------------------------------

    /// RGB × m/255 with alpha unchanged (LightingColorFilter(mul, 0)) for darkness level q/50.
    private static func darkenCG(_ src: CGImage, _ q: Int) -> CGImage {
        let m = Kt.roundToInt(Float(q) / 50 * 255)
        let w = src.width, h = src.height
        return renderCGImage(w, h) { s in
            s.drawCGImage(src, 0, 0)
            // Black over the existing pixels only.
            s.cg.setBlendMode(.sourceAtop)
            s.cg.setFillColor(red: 0, green: 0, blue: 0, alpha: 1 - CGFloat(m) / 255)
            s.cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    /// The slice's bitmap at its darkness (cached, shared between identical slices).
    func darkened(_ sl: Slice) -> ImageBitmap {
        if sl.q >= 50 { return sl.base }
        let key = DarkKey(src: ObjectIdentifier(sl.base), q: sl.q)
        lock.lock()
        if let d = darkCache[key] {
            lock.unlock()
            return d
        }
        lock.unlock()
        let d = ImageBitmap(VehicleArt.darkenCG(sl.base.cgImage, sl.q), scale: k)
        lock.lock()
        darkCache[key] = d
        lock.unlock()
        return d
    }

    /// Stacks the slices at [angle]. Each distinct slice bitmap is rotated once; the stack is then
    /// assembled with whole-pixel blits (same pixels as rotating every slice, several times faster).
    private func buildComposite(_ type: VehicleType, _ color: Int, _ mystery: Bool, _ angle: Float) -> Composite {
        let slices = stack(type, color, mystery)
        let sw = Float(sliceW())
        let sh = Float(sliceH(type))
        let maxZ = (slices.map(\.z).max() ?? 0) + 1
        let rad = Double(angle) * .pi / 180
        let ca = Float(abs(Foundation.cos(rad))), sa = Float(abs(Foundation.sin(rad)))
        // Bounds of the rotated slice frame.
        let rw = sw * ca + sh * sa
        let rh = sw * sa + sh * ca
        let fw = Int(rw.rounded(.up)) + 2
        let fh = Int(rh.rounded(.up)) + 2
        if angle == 0 {
            // Upright: whole-pixel blits of the cached darkened slices (Core Graphics' fast path).
            let img = renderCGImage(fw, fh + maxZ) { s in
                for sl in slices {
                    let d = self.darkened(sl)
                    s.drawCGImage(d.cgImage, Float(fw) / 2 - sw / 2 + Float(sl.dx), Float(maxZ - sl.z) + Float(fh) / 2 - sh / 2 + Float(sl.dy))
                }
            }
            return Composite(ImageBitmap(img, scale: k), Float(fw) / 2 / k, (Float(maxZ) + Float(fh) / 2) / k, Float(heights(type).roofTop) / k)
        }
        var rotated: [ObjectIdentifier: CGImage] = [:]
        var dark: [DarkKey: CGImage] = [:]
        let img = renderCGImage(fw, fh + maxZ) { s in
            for sl in slices {
                let id = ObjectIdentifier(sl.base)
                let rot: CGImage
                if let r = rotated[id] {
                    rot = r
                } else {
                    rot = renderCGImage(fw, fh) { r in
                        r.cg.translateBy(x: CGFloat(fw) / 2, y: CGFloat(fh) / 2)
                        r.cg.rotate(by: CGFloat(rad))
                        BitmapScope.drawUpright(r.cg, sl.base.cgImage,
                                                CGRect(x: CGFloat(Float(sl.dx) - sw / 2), y: CGFloat(Float(sl.dy) - sh / 2),
                                                       width: CGFloat(sl.base.pixelWidth), height: CGFloat(sl.base.pixelHeight)))
                    }
                    rotated[id] = rot
                }
                var layer = rot
                if sl.q < 50 {
                    let key = DarkKey(src: id, q: sl.q)
                    if let d = dark[key] {
                        layer = d
                    } else {
                        layer = VehicleArt.darkenCG(rot, sl.q)
                        dark[key] = layer
                    }
                }
                // Frame centre lands on (fw/2, maxZ + fh/2 - z): the slice is z pixels above the ground.
                s.drawCGImage(layer, 0, Float(maxZ - sl.z))
            }
        }
        let gx = Float(fw) / 2
        let gy = Float(maxZ) + Float(fh) / 2
        return Composite(ImageBitmap(img, scale: k), gx / k, gy / k, Float(heights(type).roofTop) / k)
    }

    static func arrowPath(_ cx: Float, _ cy: Float, _ w: Float, _ len: Float) -> ArtPath {
        ArtPath { p in
            let head = len * 0.5
            let shaft = w * 0.42
            p.moveTo(cx, cy - len / 2)
            p.lineTo(cx + w / 2, cy - len / 2 + head)
            p.lineTo(cx + shaft / 2, cy - len / 2 + head)
            p.lineTo(cx + shaft / 2, cy + len / 2)
            p.lineTo(cx - shaft / 2, cy + len / 2)
            p.lineTo(cx - shaft / 2, cy - len / 2 + head)
            p.lineTo(cx - w / 2, cy - len / 2 + head)
            p.close()
        }
    }
}

// MARK: - Passengers

/// Glossy jelly people with little faces. Frames 0–3 are a walk cycle, frame 4 is standing.
/// `w` / `h` are in points; bitmaps are drawn in device pixels.
final class PassengerArt {
    let w: Float
    let h: Float
    /// Extras: colour-blind symbol badge on the shirt (baked into the cached frames).
    let patterns: Bool
    private var cache: [ImageBitmap?] = Array(repeating: nil, count: 8 * 8)

    init(_ w: Float, _ h: Float, patterns: Bool = false) {
        self.w = w
        self.h = h
        self.patterns = patterns
    }

    convenience init(w: Float, h: Float) { self.init(w, h) }

    func get(_ color: Int, _ frame: Int = 4) -> ImageBitmap {
        let key = color * 8 + frame
        if let b = cache[key] { return b }
        let b = build(color, frame)
        cache[key] = b
        return b
    }

    /// Pre-builds every colour and frame (cheap: 40 tiny bitmaps).
    func prewarm(colors: Int = 8) {
        for c in 0..<colors { for f in 0...4 { _ = get(c, f) } }
    }

    private func build(_ color: Int, _ frame: Int) -> ImageBitmap {
        let k = Art.scale
        let w = self.w * k
        let h = self.h * k
        let c = jamArtColor(color)
        let walking = frame < 4
        let phase = Float(frame) * Float.pi / 2
        let swing = walking ? Kt.sin(phase) : 0
        let bob = walking ? abs(Kt.cos(phase)) * h * 0.025 : 0
        return renderBitmap(Int(w.rounded(.up)), Int(h.rounded(.up)), scale: k) { s in
            let dark = c.shade(0.62)
            let legTop = h * 0.66 - bob
            let legW = w * 0.2
            func leg(_ s: inout BitmapScope, _ x: Float, _ sw: Float, _ front: Bool) {
                let dx = sw * w * 0.1
                let lift = sw > 0.3 ? h * 0.03 : 0
                s.drawRoundRect(front ? c.shade(0.78) : c.shade(0.62),
                                Offset(x - legW / 2 + dx, legTop), Size(legW, h * 0.98 - legTop - lift), CornerRadius(legW / 2))
            }
            func arm(_ s: inout BitmapScope, _ x: Float, _ sw: Float, _ front: Bool) {
                let dy = sw * h * 0.03
                s.drawRoundRect(front ? c.shade(0.85) : c.shade(0.65),
                                Offset(x - w * 0.09, h * 0.42 - bob + dy), Size(w * 0.18, h * 0.24), CornerRadius(w * 0.09))
            }
            leg(&s, w * 0.37, -swing, false)
            arm(&s, w * 0.14, swing, false)
            leg(&s, w * 0.63, swing, true)
            // torso
            let tTop = h * 0.36 - bob
            s.drawRoundRect(dark, Offset(w * 0.17 - 0.8, tTop - 0.8), Size(w * 0.66 + 1.6, h * 0.38 + 1.6), CornerRadius(w * 0.3))
            s.drawRoundRect(Brush.horizontalGradient([c.tint(0.3), c, c.shade(0.72)], w * 0.17, w * 0.83),
                            Offset(w * 0.17, tTop), Size(w * 0.66, h * 0.38), CornerRadius(w * 0.3))
            s.drawOval(ArtColor.White.copy(alpha: 0.35), Offset(w * 0.27, tTop + h * 0.04), Size(w * 0.16, h * 0.12))
            if self.patterns { ExtrasPatterns.shirtBadge(&s, color, Offset(w * 0.5, tTop + h * 0.2), w * 0.26, dark) }
            arm(&s, w * 0.86, -swing, true)
            // head
            let hc = Offset(w * 0.5, h * 0.21 - bob)
            let hr = w * 0.33
            s.drawCircle(dark, hr + 0.9, hc)
            s.drawCircle(Brush.radialGradient([c.tint(0.5), c, c.shade(0.78)], center: hc - Offset(hr * 0.4, hr * 0.45), radius: hr * 1.5), hr, hc)
            // face
            let eyeY = hc.y + hr * 0.05
            s.drawOval(ArtColor(0xFF1F_2430), Offset(hc.x - hr * 0.42, eyeY - hr * 0.16), Size(hr * 0.2, hr * 0.3))
            s.drawOval(ArtColor(0xFF1F_2430), Offset(hc.x + hr * 0.22, eyeY - hr * 0.16), Size(hr * 0.2, hr * 0.3))
            s.drawCircle(ArtColor.White, hr * 0.06, Offset(hc.x - hr * 0.3, eyeY - hr * 0.08))
            s.drawCircle(ArtColor.White, hr * 0.06, Offset(hc.x + hr * 0.34, eyeY - hr * 0.08))
            s.drawCircle(ArtColor(0x55FF_5A7A), hr * 0.13, Offset(hc.x - hr * 0.58, eyeY + hr * 0.3))
            s.drawCircle(ArtColor(0x55FF_5A7A), hr * 0.13, Offset(hc.x + hr * 0.58, eyeY + hr * 0.3))
            s.drawCircle(ArtColor.White.copy(alpha: 0.7), hr * 0.2, hc - Offset(hr * 0.42, hr * 0.48))
        }
    }
}
