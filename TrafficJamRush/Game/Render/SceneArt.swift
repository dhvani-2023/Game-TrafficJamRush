import SwiftUI
import CoreGraphics
import GameKit

// Port of game/render/SceneArt.kt. Everything is painted in device pixels (like Android's
// px-based bitmaps): the points layout is scaled by the screen scale first.

/// Paints everything that never moves during a level, plus the world postcards for menus.
enum SceneArt {

    /// The static scene for [layout] (points); a full-screen bitmap at device scale.
    static func render(_ layout: GameLayout, _ level: Level, _ theme: SceneTheme) -> ImageBitmap {
        let k = Art.scale
        let lay = GameLayout(layout.width * k, layout.height * k, layout.topInset * k, layout.bottomInset * k, level)
        return renderBitmap(Kt.toInt(lay.width), Kt.toInt(lay.height), scale: k) { s in
            paint(&s, lay, level, theme)
        }
    }

    // --- Textures ---------------------------------------------------------------------------

    fileprivate static func noiseTile(_ base: ArtColor, _ size: Int, _ seed: Int, _ speckles: Int, _ spread: Float) -> ImageBitmap {
        renderBitmap(size, size) { s in
            s.drawRect(base)
            let rnd = KotlinRandom(seed)
            let sz = Float(size)
            for _ in 0..<4 {
                let c = base.shade(0.97 + rnd.nextFloat() * 0.05).copy(alpha: 0.35)
                let r = sz * (0.15 + rnd.nextFloat() * 0.25)
                let x = rnd.nextFloat() * sz
                let y = rnd.nextFloat() * sz
                s.drawCircle(c, r, Offset(x, y))
            }
            for _ in 0..<speckles {
                let f = 1 + (rnd.nextFloat() - 0.5) * spread
                let r = 0.5 + rnd.nextFloat() * 1.1
                let x = rnd.nextFloat() * sz
                let y = rnd.nextFloat() * sz
                s.drawCircle(base.shade(f), r, Offset(x, y))
            }
        }
    }

    fileprivate static func grassTile(_ base: ArtColor, _ size: Int) -> ImageBitmap {
        renderBitmap(size, size) { s in
            s.drawRect(base)
            let rnd = KotlinRandom(5)
            let sz = Float(size)
            let light = base.tint(0.14)
            let dark = base.shade(0.86)
            for _ in 0..<260 {
                let x = rnd.nextFloat() * sz
                let y = rnd.nextFloat() * sz
                let c = rnd.nextBoolean() ? light : dark
                let ex = x + (rnd.nextFloat() - 0.5) * 3
                let ey = y - 2 - rnd.nextFloat() * 4
                s.drawLine(c, Offset(x, y), Offset(ex, ey), 1.1, .round)
            }
            let dots = [ArtColor.White, ArtColor(0xFFFF_EB3B), ArtColor(0xFFFF_8A80)]
            for it in 0..<5 {
                let c = dots[it % 3]
                let x = rnd.nextFloat() * sz
                let y = rnd.nextFloat() * sz
                s.drawCircle(c.copy(alpha: 0.9), 1.6, Offset(x, y))
            }
        }
    }

    // --- Full game scene --------------------------------------------------------------------

    private static func paint(_ s: inout BitmapScope, _ lay: GameLayout, _ level: Level, _ th: SceneTheme) {
        let u = lay.u
        let w = s.size.width
        let px = Kt.toInt(96 * u / 2).coerceAtLeast(64)

        // Grass under everything
        s.textured(grassTile(th.pal.outside, px), .Zero, s.size)

        // Sky + backdrop
        let floorTop = lay.topInset + 120 * u
        s.sky(th, w, floorTop, lay.topInset)
        backdrop(&s, th, w, lay.topInset, floorTop, u)

        // Platform floor
        s.floor(th, Offset(0, floorTop), Size(w, lay.slotsTop - floorTop), u, px)
        s.drawRect(Brush.verticalGradient([ArtColor(0x3300_0000), ArtColor.Transparent], floorTop, floorTop + 10 * u), Offset(0, floorTop), Size(w, 10 * u))
        s.floorProps(th, lay, u)
        s.queueBarrier(lay, th, u)

        // Platform edge: tactile strip + curb
        s.drawRect(ArtColor(0xFFFF_D54F), Offset(0, lay.slotsTop - 9 * u), Size(w, 4 * u))
        var dx = 2 * u
        while dx < w {
            s.drawCircle(ArtColor(0xFFF9_A825), 0.8 * u, Offset(dx, lay.slotsTop - 7 * u))
            dx += 4 * u
        }
        s.drawRect(ArtColor(0xFFE9_ECEF), Offset(0, lay.slotsTop - 4 * u), Size(w, 4 * u))
        s.drawRect(ArtColor(0xFFB4_BAC2), Offset(0, lay.slotsTop), Size(w, 3 * u))

        // Parking stalls
        s.textured(noiseTile(th.pal.slotBand, px, 11, 500, 0.18), Offset(0, lay.slotsTop + 3 * u), Size(w, lay.slotsBottom - lay.slotsTop - 3 * u))
        for i in 0...VIP_SLOT { s.stall(lay, i, u) }

        // Road
        s.textured(noiseTile(th.pal.road, px, 3, 600, 0.22), Offset(0, lay.roadTop), Size(w, lay.roadBottom - lay.roadTop))
        s.drawRect(ArtColor.Black.copy(alpha: 0.18), Offset(0, lay.roadTop), Size(w, 3 * u))
        s.drawRect(ArtColor.White.copy(alpha: 0.85), Offset(0, lay.roadTop + 3 * u), Size(w, 2 * u))
        s.drawRect(ArtColor.White.copy(alpha: 0.85), Offset(0, lay.roadBottom - 3 * u), Size(w, 2 * u))
        s.drawLine(th.dark ? ArtColor(0xFFFF_E066) : ArtColor.White.copy(alpha: 0.7), Offset(0, lay.roadY), Offset(w, lay.roadY), 2.4 * u,
                   pathEffect: PathEffect.dashPathEffect([14 * u, 12 * u]))
        // Manhole cover
        s.drawCircle(th.pal.road.shade(0.75), 6 * u, Offset(w * 0.7, lay.roadY + 6 * u))
        s.drawCircle(th.pal.road.shade(0.9), 4.5 * u, Offset(w * 0.7, lay.roadY + 6 * u), style: .stroke(1 * u))

        s.lot(lay, level, th, u, px)

        // Hedge and flowers along the bottom
        let barTop = lay.lotRect.bottom + 8 * u
        let n = Kt.toInt(w / (22 * u))
        for kk in 0...n {
            let x = Float(kk) * 22 * u + 6 * u
            s.bush(Offset(x, barTop + 6 * u), 13 * u, th.pal.outside.shade(0.85))
        }
    }

    // --- Postcards --------------------------------------------------------------------------

    private struct PostcardKey: Hashable {
        let theme: Int
        let w: Int
        let h: Int
    }

    private static var postcards: [PostcardKey: ImageBitmap] = [:]
    private static let postcardLock = NSLock()

    /// Cached postcard, if it has been painted already.
    static func cachedPostcard(_ th: SceneTheme, _ wPx: Int, _ hPx: Int) -> ImageBitmap? {
        postcardLock.lock()
        defer { postcardLock.unlock() }
        return postcards[PostcardKey(theme: Themes.indexOf(th), w: wPx, h: hPx)]
    }

    /// A small scenic card of a world: sky, backdrop, floor and road. Sizes in device pixels.
    /// Thread-safe (menus paint postcards off the main thread).
    static func postcard(_ th: SceneTheme, _ wPx: Int, _ hPx: Int) -> ImageBitmap {
        let key = PostcardKey(theme: Themes.indexOf(th), w: wPx, h: hPx)
        postcardLock.lock()
        if let p = postcards[key] {
            postcardLock.unlock()
            return p
        }
        postcardLock.unlock()
        let img = renderBitmap(wPx, hPx) { s in
            let w = Float(wPx)
            let h = Float(hPx)
            let u = w / 290
            let base = min(w / 2.6, h * 0.64)
            let tile = Kt.toInt(48 * u).coerceAtLeast(24)
            s.sky(th, w, base, 0)
            backdrop(&s, th, w, 0, base, u)
            SceneAmbient.staticPose(&s, th, w, base, u)
            s.floor(th, Offset(0, base), Size(w, h - base), u, tile)
            let roadTop = base + (h - base) * 0.42
            let roadH = (h - base) * 0.42
            s.drawRect(th.pal.road, Offset(0, roadTop), Size(w, roadH))
            s.drawRect(ArtColor.White.copy(alpha: 0.8), Offset(0, roadTop), Size(w, roadH * 0.06))
            s.drawLine(ArtColor.White.copy(alpha: 0.7), Offset(0, roadTop + roadH / 2), Offset(w, roadTop + roadH / 2), roadH * 0.06,
                       pathEffect: PathEffect.dashPathEffect([w * 0.05, w * 0.04]))
            s.textured(grassTile(th.pal.outside, tile), Offset(0, roadTop + roadH), Size(w, h - roadTop - roadH))
        }
        postcardLock.lock()
        postcards[key] = img
        postcardLock.unlock()
        return img
    }

    // --- Backdrops --------------------------------------------------------------------------

    /// The world's signature skyline between [top] and the floor line [base].
    static func backdrop(_ s: inout BitmapScope, _ th: SceneTheme, _ w: Float, _ top: Float, _ base: Float, _ u: Float) {
        let rnd = KotlinRandom(Kt.javaHash(th.name))
        switch th.backdrop {
        case .STATION:
            s.skyline(w, base - 18 * u, u, ArtColor(0xFFB7_D7F0), rnd, 70)
            s.cloud(Offset(70 * u, top + 26 * u), u)
            s.cloud(Offset(250 * u, top + 16 * u), u * 0.8)
            // Canopy on pillars
            s.drawRect(ArtColor(0xFF90_A4AE), Offset(0, top + 38 * u), Size(w, 4 * u))
            s.drawRect(Brush.verticalGradient([ArtColor(0xFFEC_EFF1), ArtColor(0xFFB0_BEC5)], top + 30 * u, top + 40 * u), Offset(0, top + 30 * u), Size(w, 9 * u))
            var x = 30 * u
            while x < w {
                s.drawRect(ArtColor(0xFF78_909C), Offset(x, top + 40 * u), Size(4 * u, base - top - 40 * u))
                x += 90 * u
            }
            s.train(w, top + 50 * u, base, u)
            // Departure board
            let bx = w * 0.62
            s.drawRect(ArtColor(0xFF37_474F), Offset(bx + 18 * u, top + 41 * u), Size(1.5 * u, 8 * u))
            s.drawRoundRect(ArtColor(0xFF26_3238), Offset(bx, top + 46 * u), Size(40 * u, 13 * u), CornerRadius(2 * u))
            for kk in 0..<2 {
                let fk = Float(kk)
                s.drawRect(ArtColor(0xFFFF_C107).copy(alpha: 0.9), Offset(bx + 4 * u, top + 49.5 * u + fk * 4.5 * u), Size((20 + fk * 9) * u, 2 * u))
            }
        case .ZOO:
            s.cloud(Offset(80 * u, top + 24 * u), u)
            s.cloud(Offset(290 * u, top + 34 * u), u * 0.7)
            s.hills(w, base - 6 * u, u, ArtColor(0xFFAE_D581), ArtColor(0xFF8B_C34A), 50)
            for i in 0..<6 {
                let x = Float(22 + i * 64) * u + rnd.nextFloat() * 14 * u
                let sc = u * (0.9 + rnd.nextFloat() * 0.35)
                s.tree(Offset(x, base - 22 * u), sc, ArtColor(0xFF66_BB6A))
            }
            s.giraffe(Offset(w * 0.2, base - 12 * u), u)
            s.elephant(Offset(w * 0.86, base - 10 * u), u)
            s.fence(w, base - 2 * u, u, ArtColor(0xFFB0_7D4E))
            // Arch gate
            let ax = w * 0.55
            for sx: Float in [-42, 34] {
                s.drawRoundRect(ArtColor(0xFF6D_4C41), Offset(ax + sx * u, base - 68 * u), Size(8 * u, 66 * u), CornerRadius(2 * u))
                s.drawRoundRect(ArtColor(0xFF8D_6E63), Offset(ax + (sx + 1.5) * u, base - 68 * u), Size(3 * u, 66 * u), CornerRadius(2 * u))
            }
            s.drawRoundRect(ArtColor(0xFF4E_342E), Offset(ax - 52 * u, base - 84 * u), Size(104 * u, 26 * u), CornerRadius(10 * u))
            s.drawRoundRect(ArtColor(0xFF6D_4C41), Offset(ax - 50 * u, base - 84 * u), Size(100 * u, 22 * u), CornerRadius(9 * u))
            let gems = [ArtColor(0xFFFF_CA28), ArtColor(0xFF66_BB6A), ArtColor(0xFFFF_7043)]
            for kk in 0..<3 { s.drawCircle(gems[kk], 3 * u, Offset(ax - 40 * u + Float(kk) * 40 * u, base - 88 * u)) }
            s.text("ZOO", Offset(ax, base - 73 * u), 15 * u, ArtColor(0xFFFF_E082))
        case .FAIR:
            s.cloud(Offset(60 * u, top + 22 * u), u, ArtColor(0xFFFF_F0F7))
            // Ferris wheel legs (the wheel itself turns in the ambient layer)
            let c = SceneAmbient.ferrisCenter(w, base, u)
            s.drawLine(ArtColor(0xFF7B_1FA2), c, Offset(c.x - 30 * u, base), 4.5 * u, .round)
            s.drawLine(ArtColor(0xFF7B_1FA2), c, Offset(c.x + 30 * u, base), 4.5 * u, .round)
            s.carousel(Offset(w * 0.24, base), u)
            // Bunting
            let bunt = ArtPath { p in
                p.moveTo(0, top + 44 * u)
                p.quadraticTo(w * 0.25, top + 58 * u, w * 0.5, top + 44 * u)
            }
            s.drawPath(bunt, ArtColor(0xFF8D_6E63), style: .stroke(1 * u))
            let flags = [ArtColor(0xFFFF_4081), ArtColor(0xFFFF_EB3B), ArtColor(0xFF29_B6F6), ArtColor(0xFF66_BB6A)]
            for kk in 0..<9 {
                let t = Float(kk) / 9
                let bx = w * 0.5 * t + 6 * u
                let by = top + 44 * u + Float(Foundation.sin(Double(t) * Double.pi)) * 7 * u
                let col = flags[kk % 4]
                s.drawPath(ArtPath { p in
                    p.moveTo(bx - 4 * u, by)
                    p.lineTo(bx + 4 * u, by)
                    p.lineTo(bx, by + 8 * u)
                    p.close()
                }, col)
            }
            s.stand(Offset(w * 0.52, base), u)
        case .PIER:
            s.cloud(Offset(90 * u, top + 24 * u), u)
            s.cloud(Offset(240 * u, top + 38 * u), u * 0.7)
            let sea = top + 66 * u
            s.drawPath(ArtPath { p in
                p.moveTo(0, sea)
                p.quadraticTo(w * 0.2, sea - 18 * u, w * 0.4, sea)
                p.close()
            }, ArtColor(0xFF81_C784))
            s.drawRect(Brush.verticalGradient([ArtColor(0xFF4F_C3F7), ArtColor(0xFF02_88D1), ArtColor(0xFF01_579B)], sea, base), Offset(0, sea), Size(w, base - sea))
            s.lighthouse(Offset(w * 0.84, base - 6 * u), u)
            s.sailboat(Offset(w * 0.32, sea + 22 * u), u)
            s.drawRect(ArtColor(0xFF6D_4C41), Offset(0, base - 14 * u), Size(w, 3 * u))
            var x = 6 * u
            while x < w {
                s.drawRect(ArtColor(0xFF5D_4037), Offset(x, base - 18 * u), Size(4 * u, 18 * u))
                s.drawRect(ArtColor(0xFF8D_6E63), Offset(x + 1 * u, base - 18 * u), Size(1.2 * u, 18 * u))
                x += 28 * u
            }
        case .DESERT:
            s.drawCircle(ArtColor(0xFFFF_E082), 30 * u, Offset(w * 0.8, top + 36 * u))
            s.drawCircle(ArtColor(0xFFFF_F59D), 20 * u, Offset(w * 0.8, top + 36 * u))
            s.hills(w, base - 30 * u, u, ArtColor(0xFFF6_D7A0), ArtColor(0xFFEB_C27C), 26)
            s.pyramid(Offset(w * 0.22, base - 4 * u), 80 * u)
            s.pyramid(Offset(w * 0.42, base - 10 * u), 46 * u)
            s.hills(w, base, u, ArtColor(0xFFF3_CF8E), ArtColor(0xFFE2_AF62), 18)
            s.palm(Offset(w * 0.66, base - 2 * u), u * 0.9)
            s.camel(Offset(w * 0.86, base - 4 * u), u)
            for i in 0..<2 { s.cactus(Offset(Float(120 + i * 160) * u, base - 2 * u), u * 0.8) }
        case .SNOW:
            for i in 0..<3 { s.mountain(Offset(Float(40 + i * 130) * u, base), Float(88 + i % 2 * 18) * u, u) }
            s.cabin(Offset(w * 0.18, base - 2 * u), u)
            for i in 0..<6 {
                let x = Float(60 + i * 52) * u + rnd.nextFloat() * 10 * u
                let sc = u * (0.8 + rnd.nextFloat() * 0.45)
                s.pine(Offset(x, base - 2 * u), sc)
            }
            s.drawRect(ArtColor.White, Offset(0, base - 6 * u), Size(w, 6 * u))
        case .NEON:
            for _ in 0..<50 {
                let a = rnd.nextFloat() * 0.8
                let r = rnd.nextFloat() * 1.3 * u
                let x = rnd.nextFloat() * w
                let y = top + rnd.nextFloat() * 70 * u
                s.drawCircle(ArtColor.White.copy(alpha: a), r, Offset(x, y))
            }
            s.drawCircle(ArtColor(0xFFFF_F9C4), 14 * u, Offset(w * 0.14, top + 28 * u))
            s.drawCircle(ArtColor(0xFF3A_2475), 11 * u, Offset(w * 0.14 + 6 * u, top + 25 * u))
            let windows = [ArtColor(0xFFFF_EB3B), ArtColor(0xFF80_DEEA), ArtColor(0xFFFF_80AB)]
            var x = -10 * u
            while x < w {
                let bw = Float(34 + rnd.nextInt(26)) * u
                let bh = Float(50 + rnd.nextInt(56)) * u
                s.drawRect(Brush.verticalGradient([ArtColor(0xFF2D_2266), ArtColor(0xFF1B_1446)], base - bh, base), Offset(x, base - bh), Size(bw, bh))
                var wy = base - bh + 8 * u
                while wy < base - 8 * u {
                    var wx = x + 5 * u
                    while wx < x + bw - 8 * u {
                        if rnd.nextFloat() < 0.5 {
                            s.drawRect(windows[rnd.nextInt(3)].copy(alpha: 0.85), Offset(wx, wy), Size(4 * u, 5 * u))
                        }
                        wx += 9 * u
                    }
                    wy += 11 * u
                }
                x += bw + 4 * u
            }
            s.neon(Offset(w * 0.36, base - 74 * u), Size(70 * u, 22 * u), ArtColor(0xFFFF_4FD8), u)
            s.neon(Offset(w * 0.7, base - 92 * u), Size(50 * u, 18 * u), ArtColor(0xFF40_E0FF), u)
        case .FARM:
            s.cloud(Offset(70 * u, top + 28 * u), u)
            s.hills(w, base - 10 * u, u, ArtColor(0xFFE6_C17A), ArtColor(0xFFD4_A85A), 40)
            // field stripes
            for kk in 0..<5 {
                let fk = Float(kk)
                s.drawLine(ArtColor(0xFFC5_8F45).copy(alpha: 0.5), Offset(fk * 80 * u, base - 4 * u), Offset(fk * 80 * u + 60 * u, base - 30 * u), 2 * u)
            }
            s.barn(Offset(w * 0.6, base - 2 * u), u)
            let mill = SceneAmbient.millHub(w, base, u)
            s.drawPath(ArtPath { p in
                p.moveTo(mill.x - 7 * u, base - 2 * u)
                p.lineTo(mill.x - 3 * u, mill.y)
                p.lineTo(mill.x + 3 * u, mill.y)
                p.lineTo(mill.x + 7 * u, base - 2 * u)
                p.close()
            }, ArtColor(0xFFEF_EBE9))
            for i in 0..<3 { s.hay(Offset(Float(30 + i * 44) * u, base - 4 * u), u) }
            for i in 0..<3 { s.tree(Offset(Float(300 + i * 26) * u, base - 16 * u), u * 0.8, ArtColor(0xFFFF_8F00)) }
            s.fence(w, base - 2 * u, u, ArtColor(0xFFFF_F3E0))
        case .JUNGLE:
            s.hills(w, base - 20 * u, u, ArtColor(0xFF81_C784), ArtColor(0xFF4C_AF50), 60)
            // Waterfall cliff
            let wx = w * 0.72
            s.drawRoundRect(ArtColor(0xFF79_5548), Offset(wx - 34 * u, base - 96 * u), Size(68 * u, 96 * u), CornerRadius(10 * u))
            s.drawRect(Brush.verticalGradient([ArtColor(0xFFB3_E5FC), ArtColor(0xFF4F_C3F7)], base - 92 * u, base), Offset(wx - 10 * u, base - 92 * u), Size(20 * u, 92 * u))
            s.drawOval(ArtColor.White.copy(alpha: 0.8), Offset(wx - 18 * u, base - 8 * u), Size(36 * u, 8 * u))
            for i in 0..<5 {
                let sc = u * (0.95 + rnd.nextFloat() * 0.25)
                s.palm(Offset(Float(20 + i * 66) * u, base - 2 * u), sc)
            }
            s.tent(Offset(w * 0.42, base), 40 * u, ArtColor(0xFFFF_A726), u)
            for kk in 0..<4 { s.leaf(Offset(Float(kk) * w / 3.2, base + 2 * u), u, kk % 2 == 0) }
        case .SPACE:
            for _ in 0..<70 {
                let a = 0.3 + rnd.nextFloat() * 0.7
                let r = rnd.nextFloat() * 1.4 * u
                let x = rnd.nextFloat() * w
                let y = top + rnd.nextFloat() * 100 * u
                s.drawCircle(ArtColor.White.copy(alpha: a), r, Offset(x, y))
            }
            s.drawCircle(Brush.radialGradient([ArtColor(0xFFFF_AB91), ArtColor(0xFFFF_7043), ArtColor(0xFFBF_360C)], Offset(w * 0.15, top + 30 * u), 30 * u),
                         22 * u, Offset(w * 0.18, top + 38 * u))
            s.drawOval(ArtColor(0xFFFF_CC80), Offset(w * 0.18 - 36 * u, top + 34 * u), Size(72 * u, 9 * u), style: .stroke(2 * u))
            s.drawArc(ArtColor(0xFF26_3238).copy(alpha: 0.7), 180, 180, true, Offset(-20 * u, base - 30 * u), Size(w * 0.7, 60 * u))
            s.dome(Offset(w * 0.12, base), 36 * u)
            s.dome(Offset(w * 0.34, base), 24 * u)
            s.dish(Offset(w * 0.52, base), u)
            s.rocket(Offset(w * 0.8, base), u)
        }
    }
}

// MARK: - Scene pieces (Kotlin `DrawScope.xxx` extensions)

fileprivate extension BitmapScope {

    mutating func textured(_ tile: ImageBitmap, _ topLeft: Offset, _ size: Size) {
        drawRect(Brush.image(tile), topLeft, size)
    }

    mutating func sky(_ th: SceneTheme, _ w: Float, _ bottom: Float, _ top: Float) {
        drawRect(Brush.verticalGradient([th.pal.skyTop, th.pal.skyBottom], 0, bottom), .Zero, Size(w, bottom))
        if !th.dark {
            let c = Offset(w * 0.82, top + 22)
            drawCircle(Brush.radialGradient([ArtColor.White.copy(alpha: 0.55), ArtColor.Transparent], c, w * 0.35), w * 0.35, c)
        }
    }

    // --- Floors -----------------------------------------------------------------------------

    mutating func floor(_ th: SceneTheme, _ tl: Offset, _ sz: Size, _ u: Float, _ px: Int) {
        let c = th.pal.platform
        let pxf = Float(px)
        let tile: ImageBitmap
        switch th.backdrop {
        case .PIER, .FARM:
            tile = renderBitmap(px, px) { s in
                s.drawRect(c)
                let ph = pxf / 4
                for kk in 0..<4 {
                    let fk = Float(kk)
                    s.drawRect(c.shade(kk % 2 == 0 ? 1 : 0.95), Offset(0, fk * ph), Size(pxf, ph))
                    s.drawLine(c.shade(0.72), Offset(0, fk * ph), Offset(pxf, fk * ph), 1.2)
                    let sx = Float((kk * 37) % px)
                    s.drawLine(c.shade(0.78), Offset(sx, fk * ph), Offset(sx, (fk + 1) * ph), 1.2)
                    s.drawCircle(c.shade(0.6), 0.9, Offset(sx + 4, fk * ph + ph / 2))
                }
            }
        case .DESERT, .SNOW:
            tile = SceneArt.noiseTile(c, px, 21, 260, 0.1)
        case .ZOO, .JUNGLE:
            tile = renderBitmap(px, px) { s in
                s.drawRect(c.shade(0.85))
                let rnd = KotlinRandom(9)
                for _ in 0..<14 {
                    let o = Offset(rnd.nextFloat() * pxf, rnd.nextFloat() * pxf)
                    let col = c.shade(0.95 + rnd.nextFloat() * 0.12)
                    s.drawRoundRect(col, o, Size(pxf * 0.28, pxf * 0.2), CornerRadius(pxf * 0.08))
                }
            }
        case .FAIR:
            tile = renderBitmap(px, px) { s in
                let h = pxf / 2
                s.drawRect(c)
                s.drawRect(c.shade(0.9), .Zero, Size(h, h))
                s.drawRect(c.shade(0.9), Offset(h, h), Size(h, h))
            }
        case .SPACE:
            tile = renderBitmap(px, px) { s in
                s.drawRect(c)
                s.drawRect(c.shade(0.8), .Zero, Size(pxf, pxf), style: .stroke(1.5))
                for kk in 1...3 {
                    let x = Float(kk) * pxf / 4
                    s.drawLine(c.tint(0.08), Offset(x, 0), Offset(x, pxf), 0.8)
                }
            }
        default:
            tile = renderBitmap(px, px) { s in
                let h = pxf / 2
                for i in 0..<2 {
                    for j in 0..<2 {
                        s.drawRect(c.shade((i + j) % 2 == 0 ? 1 : 0.96), Offset(Float(i) * h, Float(j) * h), Size(h, h))
                    }
                }
                for kk in 0...2 {
                    let p = Float(kk) * h
                    s.drawLine(c.shade(0.82), Offset(p, 0), Offset(p, pxf), 1)
                    s.drawLine(c.shade(0.82), Offset(0, p), Offset(pxf, p), 1)
                }
                if th.dark { s.drawRect(th.pal.accent.copy(alpha: 0.12), Offset(1, 1), Size(h - 2, h - 2)) }
            }
        }
        textured(tile, tl, sz)
    }

    mutating func floorProps(_ th: SceneTheme, _ lay: GameLayout, _ u: Float) {
        let y = lay.queueY - 30 * u
        let w = size.width
        lampPost(Offset(14 * u, lay.queueY - 2 * u), u, th)
        switch th.backdrop {
        case .STATION, .NEON, .SPACE:
            bench(Offset(w * 0.52, y + 2 * u), u, th.dark ? ArtColor(0xFF7C_4DFF) : ArtColor(0xFF5C_6BC0))
            plantPot(Offset(w * 0.86, y + 4 * u), u)
        case .ZOO, .JUNGLE, .FARM:
            bush(Offset(w * 0.5, y + 2 * u), 14 * u, th.pal.accent)
            bush(Offset(w * 0.9, y + 2 * u), 12 * u, th.pal.accent.shade(0.85))
        case .FAIR:
            balloon(Offset(w * 0.86, y - 20 * u), u, ArtColor(0xFFFF_4081))
            balloon(Offset(w * 0.9, y - 26 * u), u, ArtColor(0xFFFF_EB3B))
            balloon(Offset(w * 0.82, y - 24 * u), u, ArtColor(0xFF29_B6F6))
        case .PIER:
            for kk in 0..<3 {
                drawCircle(ArtColor(0xFFE5_3935), 4 * u, Offset(w * (0.5 + Float(kk) * 0.18), y + 6 * u), style: .stroke(2 * u))
            }
        case .SNOW:
            snowman(Offset(w * 0.88, y + 8 * u), u)
        case .DESERT:
            cactus(Offset(w * 0.88, y + 10 * u), u * 0.7)
        }
    }

    mutating func queueBarrier(_ lay: GameLayout, _ th: SceneTheme, _ u: Float) {
        let postY = lay.queueY - 24 * u
        let rope = th.dark ? ArtColor(0xFFE0_40FB) : ArtColor(0xFFC6_2828)
        var xs: [Float] = []
        var x = lay.queueStartX + 34 * u
        while x < lay.queueEndX - 26 * u {
            xs.append(x)
            x += 44 * u
        }
        if xs.count > 1 {
            for kk in 0..<(xs.count - 1) {
                let a = Offset(xs[kk], postY)
                let b = Offset(xs[kk + 1], postY)
                let p = ArtPath { p in
                    p.moveTo(a.x, a.y)
                    p.quadraticTo((a.x + b.x) / 2, a.y + 7 * u, b.x, b.y)
                }
                drawPath(p, rope.shade(0.6), style: .stroke(2.6 * u, cap: .round))
                drawPath(p, rope, style: .stroke(1.6 * u, cap: .round))
            }
        }
        for x in xs {
            drawOval(ArtColor.Black.copy(alpha: 0.18), Offset(x - 4 * u, postY + 14 * u), Size(8 * u, 3 * u))
            drawRoundRect(ArtColor(0xFFB8_860B), Offset(x - 1.3 * u, postY), Size(2.6 * u, 16 * u), CornerRadius(u))
            drawRoundRect(ArtColor(0xFFFF_D54F), Offset(x - 0.7 * u, postY), Size(1 * u, 16 * u), CornerRadius(u))
            drawCircle(ArtColor(0xFFFF_C107), 2.4 * u, Offset(x, postY))
            drawCircle(ArtColor.White.copy(alpha: 0.6), 0.8 * u, Offset(x - 0.8 * u, postY - 0.8 * u))
        }
    }

    // --- Stalls -----------------------------------------------------------------------------

    mutating func stall(_ lay: GameLayout, _ i: Int, _ u: Float) {
        let r = lay.slotRect(i)
        if i == VIP_SLOT {
            drawRoundRect(ArtColor(0xFF8E_1B1B), r.topLeft + Offset(0, 2 * u), r.size, CornerRadius(6 * u))
            drawRoundRect(Brush.verticalGradient([ArtColor(0xFFE5_3935), ArtColor(0xFFB7_1C1C)], r.top, r.bottom), r.topLeft, r.size, CornerRadius(6 * u))
            drawRoundRect(ArtColor(0xFFFF_D54F), r.topLeft + Offset(3 * u, 3 * u), Size(r.width - 6 * u, r.height - 6 * u), CornerRadius(4 * u), style: .stroke(1.6 * u))
            crown(Offset(r.center.x, r.top + 18 * u), 9 * u)
            text("VIP", Offset(r.center.x, r.bottom - 14 * u), 11 * u, ArtColor(0xFFFF_E082))
            return
        }
        let line = 2.6 * u
        drawRect(ArtColor.Black.copy(alpha: 0.15), Offset(r.left - line / 2 + u, r.top + u), Size(line, r.height))
        drawRect(ArtColor.White, Offset(r.left - line / 2, r.top), Size(line, r.height))
        if i == SLOT_COUNT - 1 { drawRect(ArtColor.White, Offset(r.right - line / 2, r.top), Size(line, r.height)) }
        // wheel stop
        drawRoundRect(ArtColor(0xFF9E_A4AC), Offset(r.left + r.width * 0.2, r.top + 4 * u), Size(r.width * 0.6, 4 * u), CornerRadius(1.5 * u))
        drawRoundRect(ArtColor(0xFFDC_E0E5), Offset(r.left + r.width * 0.2, r.top + 3 * u), Size(r.width * 0.6, 2.5 * u), CornerRadius(1.5 * u))
        text("\(i + 1)", Offset(r.center.x, r.bottom - 7 * u), 9 * u, ArtColor.White.copy(alpha: 0.55))
    }

    // --- Lot --------------------------------------------------------------------------------

    mutating func lot(_ lay: GameLayout, _ level: Level, _ th: SceneTheme, _ u: Float, _ px: Int) {
        let lot = lay.lotRect
        let r = CornerRadius(18 * u)
        // Curb with a visible side
        drawRoundRect(ArtColor.Black.copy(alpha: 0.18), lot.topLeft + Offset(0, 8 * u), lot.size, r)
        drawRoundRect(ArtColor(0xFFA9_AFB6), lot.topLeft + Offset(0, 4 * u), lot.size, r)
        drawRoundRect(ArtColor(0xFFE6_E9EC), lot.topLeft - Offset(3 * u, 3 * u), Size(lot.width + 6 * u, lot.height + 6 * u), CornerRadius(20 * u))
        // Asphalt
        let asphalt = SceneArt.noiseTile(th.pal.lot, px, 17, 520, 0.12)
        let inner = lot.deflate(3 * u)
        let clip = ArtPath { $0.addRoundRect(inner, CornerRadius(15 * u)) }
        clipPath(clip) { s in
            s.textured(asphalt, inner.topLeft, inner.size)
            s.drawRect(Brush.verticalGradient([ArtColor.Black.copy(alpha: 0.12), ArtColor.Transparent], inner.top, inner.top + 18 * u),
                       inner.topLeft, Size(inner.width, 18 * u))
        }
        // Driving loop with chevrons
        let t = lay.track
        let loop = Rect(t.left, t.top + 22 * u, t.right, t.bottom)
        drawRoundRect(ArtColor.White.copy(alpha: 0.45), loop.topLeft, loop.size, CornerRadius(18 * u),
                      style: .stroke(1.6 * u, pathEffect: PathEffect.dashPathEffect([8 * u, 8 * u])))
        for y in [loop.center.y - 30 * u, loop.center.y + 40 * u] {
            chevron(Offset(loop.left, y), u, up: true)
            chevron(Offset(loop.right, y), u, up: true)
        }
        // P markers in the corners
        text("P", Offset(lot.left + 18 * u, lot.bottom - 16 * u), 14 * u, ArtColor.White.copy(alpha: 0.35))
        text("P", Offset(lot.right - 18 * u, lot.bottom - 16 * u), 14 * u, ArtColor.White.copy(alpha: 0.35))

        // Board pad in the level's shape with a painted border
        let pad = th.pal.lot.shade(0.9)
        withTransform({ t in
            t.translate(lay.boardCenter.x, lay.boardCenter.y)
            t.rotate(lay.rotationDeg, .Zero)
        }) { s in
            let unit = lay.unit
            let ox = Float(-level.cols) / 2 * unit
            let oy = Float(-level.rows) / 2 * unit
            let g = unit * 0.35
            for gy in 0..<level.rows {
                for gx in 0..<level.cols where level.inMask(gx, gy) {
                    s.drawRect(pad, Offset(ox + Float(gx) * unit - g, oy + Float(gy) * unit - g), Size(unit + 2 * g, unit + 2 * g))
                }
            }
            let lw = 1.6 * u
            let paint = ArtColor.White.copy(alpha: 0.8)
            for gy in 0..<level.rows {
                for gx in 0..<level.cols where level.inMask(gx, gy) {
                    let x0 = ox + Float(gx) * unit - g
                    let y0 = oy + Float(gy) * unit - g
                    let x1 = ox + Float(gx + 1) * unit + g
                    let y1 = oy + Float(gy + 1) * unit + g
                    if !level.inMask(gx, gy - 1) { s.drawLine(paint, Offset(x0, y0), Offset(x1, y0), lw) }
                    if !level.inMask(gx, gy + 1) { s.drawLine(paint, Offset(x0, y1), Offset(x1, y1), lw) }
                    if !level.inMask(gx - 1, gy) { s.drawLine(paint, Offset(x0, y0), Offset(x0, y1), lw) }
                    if !level.inMask(gx + 1, gy) { s.drawLine(paint, Offset(x1, y0), Offset(x1, y1), lw) }
                }
            }
        }
    }

    mutating func chevron(_ c: Offset, _ u: Float, up: Bool) {
        let d: Float = up ? 1 : -1
        let p = ArtPath { p in
            p.moveTo(c.x - 5 * u, c.y + d * 3 * u)
            p.lineTo(c.x, c.y - d * 3 * u)
            p.lineTo(c.x + 5 * u, c.y + d * 3 * u)
        }
        drawPath(p, ArtColor.White.copy(alpha: 0.55), style: .stroke(2.2 * u, cap: .round, join: .round))
    }

    // --- Props ------------------------------------------------------------------------------

    mutating func skyline(_ w: Float, _ base: Float, _ u: Float, _ color: ArtColor, _ rnd: KotlinRandom, _ maxH: Float) {
        var x: Float = 0
        while x < w {
            let bw = Float(20 + rnd.nextInt(30)) * u
            let bh = (20 + rnd.nextFloat() * maxH) * u
            drawRect(color, Offset(x, base - bh), Size(bw - 3 * u, bh))
            x += bw
        }
    }

    mutating func train(_ w: Float, _ top: Float, _ base: Float, _ u: Float) {
        let h = base - top - 4 * u
        let carW = 200 * u
        var x = -30 * u
        while x < w {
            drawRoundRect(ArtColor(0xFF78_909C), Offset(x, top + 4 * u), Size(carW, h), CornerRadius(14 * u))
            drawRoundRect(Brush.verticalGradient([ArtColor.White, ArtColor(0xFFE3_E8EE), ArtColor(0xFFCF_D8DC)], top, top + h), Offset(x, top), Size(carW, h), CornerRadius(14 * u))
            // windows
            var wx = x + 12 * u
            while wx < x + carW - 30 * u {
                drawRoundRect(ArtColor(0xFF37_475E), Offset(wx, top + 10 * u), Size(26 * u, 18 * u), CornerRadius(4 * u))
                drawRoundRect(Brush.linearGradient([ArtColor(0x66FF_FFFF), ArtColor.Transparent], Offset(wx, top + 10 * u), Offset(wx + 20 * u, top + 28 * u)),
                              Offset(wx, top + 10 * u), Size(26 * u, 18 * u), CornerRadius(4 * u))
                wx += 34 * u
            }
            // door
            let dx = x + carW - 46 * u
            drawRoundRect(ArtColor(0xFFB0_BEC5), Offset(dx, top + 6 * u), Size(24 * u, h - 8 * u), CornerRadius(3 * u))
            drawRoundRect(ArtColor(0xFF8F_B4D9), Offset(dx + 3 * u, top + 10 * u), Size(18 * u, 16 * u), CornerRadius(3 * u))
            drawLine(ArtColor(0xFF90_A4AE), Offset(dx + 12 * u, top + 6 * u), Offset(dx + 12 * u, top + h - 2 * u), 1 * u)
            drawRect(ArtColor(0xFFFF_8F3A), Offset(x + 4 * u, top + h - 22 * u), Size(carW - 8 * u, 5 * u))
            drawRect(ArtColor(0xFF37_474F), Offset(x + 4 * u, top + h - 17 * u), Size(carW - 8 * u, 3 * u))
            x += carW + 6 * u
        }
    }

    mutating func cloud(_ c: Offset, _ u: Float, _ color: ArtColor = .White) {
        drawOval(ArtColor.Black.copy(alpha: 0.04), c + Offset(-28 * u, 10 * u), Size(60 * u, 10 * u))
        let col = color.copy(alpha: 0.95)
        drawCircle(col, 14 * u, c)
        drawCircle(col, 11 * u, c + Offset(-16 * u, 4 * u))
        drawCircle(col, 12 * u, c + Offset(16 * u, 3 * u))
        drawRoundRect(col, c + Offset(-26 * u, 2 * u), Size(52 * u, 12 * u), CornerRadius(6 * u))
        drawCircle(ArtColor.White.copy(alpha: 0.6), 6 * u, c + Offset(-4 * u, -5 * u))
    }

    mutating func hills(_ w: Float, _ base: Float, _ u: Float, _ light: ArtColor, _ dark: ArtColor, _ height: Float) {
        let hh = height * u
        let p = ArtPath { p in
            p.moveTo(0, base)
            p.lineTo(0, base - hh * 0.5)
            p.cubicTo(w * 0.2, base - hh, w * 0.35, base - hh * 0.2, w * 0.55, base - hh * 0.6)
            p.cubicTo(w * 0.75, base - hh, w * 0.9, base - hh * 0.3, w, base - hh * 0.65)
            p.lineTo(w, base)
            p.close()
        }
        drawPath(p, Brush.verticalGradient([light, dark], base - hh, base))
    }

    mutating func tree(_ c: Offset, _ u: Float, _ color: ArtColor) {
        drawOval(ArtColor.Black.copy(alpha: 0.12), Offset(c.x - 10 * u, c.y + 9 * u), Size(20 * u, 5 * u))
        drawRoundRect(ArtColor(0xFF6D_4C41), Offset(c.x - 3 * u, c.y - 6 * u), Size(6 * u, 18 * u), CornerRadius(2 * u))
        drawCircle(color.shade(0.75), 17 * u, c + Offset(2 * u, -12 * u))
        drawCircle(color, 14 * u, c + Offset(-3 * u, -16 * u))
        drawCircle(color.tint(0.12), 9 * u, c + Offset(-6 * u, -20 * u))
        drawCircle(color.tint(0.35), 4 * u, c + Offset(-9 * u, -24 * u))
    }

    mutating func bush(_ c: Offset, _ s: Float, _ color: ArtColor) {
        drawOval(ArtColor.Black.copy(alpha: 0.12), Offset(c.x - s, c.y + s * 0.3), Size(s * 2, s * 0.5))
        drawCircle(color.shade(0.78), s * 0.7, c + Offset(s * 0.35, 0))
        drawCircle(color, s * 0.75, c + Offset(-s * 0.3, -s * 0.1))
        drawCircle(color.tint(0.15), s * 0.5, c + Offset(0, -s * 0.35))
        drawCircle(color.tint(0.4), s * 0.15, c + Offset(-s * 0.2, -s * 0.55))
    }

    mutating func pine(_ c: Offset, _ u: Float) {
        drawRect(ArtColor(0xFF6D_4C41), Offset(c.x - 2.5 * u, c.y - 8 * u), Size(5 * u, 8 * u))
        for kk in 0..<3 {
            let y0 = c.y - 6 * u - Float(kk) * 12 * u
            let wdt = Float(26 - kk * 6) * u
            drawPath(ArtPath { p in
                p.moveTo(c.x, y0 - 20 * u); p.lineTo(c.x + wdt / 2, y0); p.lineTo(c.x - wdt / 2, y0); p.close()
            }, ArtColor(0xFF2E_7D32))
            drawPath(ArtPath { p in
                p.moveTo(c.x, y0 - 20 * u); p.lineTo(c.x + wdt / 2, y0); p.lineTo(c.x, y0); p.close()
            }, ArtColor(0xFF1B_5E20))
            drawPath(ArtPath { p in
                p.moveTo(c.x, y0 - 20 * u); p.lineTo(c.x + wdt / 4, y0 - 10 * u); p.lineTo(c.x - wdt / 4, y0 - 9 * u); p.close()
            }, ArtColor.White)
        }
    }

    mutating func palm(_ c: Offset, _ u: Float) {
        let top = c + Offset(8 * u, -66 * u)
        let trunk = ArtPath { p in
            p.moveTo(c.x, c.y)
            p.quadraticTo(c.x + 2 * u, c.y - 40 * u, top.x, top.y)
        }
        drawPath(trunk, ArtColor(0xFF6D_4C41), style: .stroke(7 * u, cap: .round))
        drawPath(trunk, ArtColor(0xFF8D_6E63), style: .stroke(3 * u, cap: .round, pathEffect: PathEffect.dashPathEffect([3 * u, 3 * u])))
        for kk in 0..<7 {
            rotate(Float(kk) * 52 - 20, top) { s in
                s.drawOval(ArtColor(0xFF2E_7D32), top + Offset(0, -5 * u), Size(34 * u, 11 * u))
                s.drawOval(ArtColor(0xFF43_A047), top + Offset(2 * u, -4 * u), Size(28 * u, 6 * u))
            }
        }
        drawCircle(ArtColor(0xFF5D_4037), 4 * u, top + Offset(-3 * u, 5 * u))
        drawCircle(ArtColor(0xFF5D_4037), 4 * u, top + Offset(4 * u, 6 * u))
    }

    mutating func leaf(_ c: Offset, _ u: Float, _ flip: Bool) {
        rotate(flip ? -30 : 30, c) { s in
            s.drawOval(ArtColor(0xFF1B_5E20), c - Offset(18 * u, 10 * u), Size(36 * u, 14 * u))
            s.drawLine(ArtColor(0xFF66_BB6A), c - Offset(16 * u, 3 * u), c + Offset(16 * u, -3 * u), 1.2 * u)
        }
    }

    mutating func cactus(_ c: Offset, _ u: Float) {
        let g = ArtColor(0xFF55_8B2F)
        let l = ArtColor(0xFF7C_B342)
        drawRoundRect(g, Offset(c.x - 6 * u, c.y - 44 * u), Size(12 * u, 44 * u), CornerRadius(6 * u))
        drawRoundRect(l, Offset(c.x - 3 * u, c.y - 42 * u), Size(3 * u, 40 * u), CornerRadius(2 * u))
        drawRoundRect(g, Offset(c.x - 18 * u, c.y - 32 * u), Size(9 * u, 20 * u), CornerRadius(5 * u))
        drawRect(g, Offset(c.x - 13 * u, c.y - 17 * u), Size(9 * u, 6 * u))
        drawRoundRect(g, Offset(c.x + 9 * u, c.y - 36 * u), Size(9 * u, 18 * u), CornerRadius(5 * u))
        drawRect(g, Offset(c.x + 4 * u, c.y - 23 * u), Size(9 * u, 6 * u))
        drawCircle(ArtColor(0xFFFF_4081), 3 * u, Offset(c.x, c.y - 45 * u))
    }

    mutating func hay(_ c: Offset, _ u: Float) {
        drawOval(ArtColor.Black.copy(alpha: 0.12), Offset(c.x - 18 * u, c.y - 3 * u), Size(36 * u, 6 * u))
        drawRoundRect(Brush.verticalGradient([ArtColor(0xFFFF_E082), ArtColor(0xFFFF_B300)], c.y - 22 * u, c.y), Offset(c.x - 17 * u, c.y - 22 * u), Size(34 * u, 22 * u), CornerRadius(6 * u))
        drawLine(ArtColor(0xFFE6_9500), Offset(c.x - 17 * u, c.y - 11 * u), Offset(c.x + 17 * u, c.y - 11 * u), 1.5 * u)
    }

    mutating func tent(_ c: Offset, _ s: Float, _ color: ArtColor, _ u: Float) {
        drawPath(ArtPath { p in
            p.moveTo(c.x, c.y - s * 1.1); p.lineTo(c.x + s * 0.75, c.y); p.lineTo(c.x - s * 0.75, c.y); p.close()
        }, color)
        drawPath(ArtPath { p in
            p.moveTo(c.x, c.y - s * 1.1); p.lineTo(c.x + s * 0.75, c.y); p.lineTo(c.x + s * 0.2, c.y); p.close()
        }, color.shade(0.8))
        drawPath(ArtPath { p in
            p.moveTo(c.x, c.y - s * 0.6); p.lineTo(c.x + s * 0.2, c.y); p.lineTo(c.x - s * 0.2, c.y); p.close()
        }, ArtColor(0xFF4E_342E))
        drawLine(color.shade(0.5), Offset(c.x, c.y - s * 1.1), Offset(c.x, c.y - s * 1.3), 2 * u)
    }

    mutating func balloon(_ c: Offset, _ u: Float, _ color: ArtColor) {
        drawLine(ArtColor(0x99FF_FFFF), c + Offset(0, 9 * u), c + Offset(0, 30 * u), 0.8 * u)
        drawOval(Brush.radialGradient([color.tint(0.4), color], c - Offset(3 * u, 4 * u), 12 * u), c - Offset(7 * u, 9 * u), Size(14 * u, 18 * u))
        drawCircle(ArtColor.White.copy(alpha: 0.6), 2.2 * u, c - Offset(3 * u, 4 * u))
    }

    mutating func fence(_ w: Float, _ y: Float, _ u: Float, _ color: ArtColor) {
        drawRect(color.shade(0.82), Offset(0, y - 14 * u), Size(w, 3 * u))
        drawRect(color.shade(0.82), Offset(0, y - 6 * u), Size(w, 3 * u))
        var x = 4 * u
        let post = color.tint(0.25)
        while x < w {
            drawRoundRect(color, Offset(x, y - 20 * u), Size(5 * u, 20 * u), CornerRadius(2 * u))
            drawRect(post, Offset(x + 1 * u, y - 19 * u), Size(1.4 * u, 18 * u))
            x += 14 * u
        }
    }

    mutating func bench(_ c: Offset, _ u: Float, _ color: ArtColor) {
        drawOval(ArtColor.Black.copy(alpha: 0.15), Offset(c.x - 4 * u, c.y + 1 * u), Size(60 * u, 5 * u))
        drawRoundRect(color.shade(0.7), Offset(c.x, c.y - 16 * u), Size(52 * u, 8 * u), CornerRadius(2 * u))
        drawRoundRect(color, Offset(c.x, c.y - 9 * u), Size(52 * u, 6 * u), CornerRadius(2 * u))
        drawRect(ArtColor(0xFF45_5A64), Offset(c.x + 4 * u, c.y - 3 * u), Size(3 * u, 4 * u))
        drawRect(ArtColor(0xFF45_5A64), Offset(c.x + 45 * u, c.y - 3 * u), Size(3 * u, 4 * u))
    }

    mutating func plantPot(_ c: Offset, _ u: Float) {
        drawOval(ArtColor.Black.copy(alpha: 0.15), Offset(c.x - 9 * u, c.y - 1 * u), Size(18 * u, 4 * u))
        drawPath(ArtPath { p in
            p.moveTo(c.x - 7 * u, c.y - 12 * u); p.lineTo(c.x + 7 * u, c.y - 12 * u); p.lineTo(c.x + 5 * u, c.y); p.lineTo(c.x - 5 * u, c.y); p.close()
        }, ArtColor(0xFFD8_4315))
        bush(Offset(c.x, c.y - 16 * u), 9 * u, ArtColor(0xFF43_A047))
    }

    mutating func lampPost(_ c: Offset, _ u: Float, _ th: SceneTheme) {
        drawOval(ArtColor.Black.copy(alpha: 0.15), Offset(c.x - 9 * u, c.y - 3 * u), Size(18 * u, 6 * u))
        drawRect(ArtColor(0xFF37_474F), Offset(c.x - 2 * u, c.y - 78 * u), Size(4 * u, 78 * u))
        drawRect(ArtColor(0xFF54_6E7A), Offset(c.x - 1 * u, c.y - 78 * u), Size(1 * u, 78 * u))
        drawRoundRect(ArtColor(0xFF37_474F), Offset(c.x - 8 * u, c.y - 95 * u), Size(16 * u, 20 * u), CornerRadius(3 * u))
        let glow = th.dark ? ArtColor(0xFFFF_F59D) : ArtColor(0xFFE3_F2FD)
        drawRoundRect(glow, Offset(c.x - 5.5 * u, c.y - 92 * u), Size(11 * u, 14 * u), CornerRadius(2 * u))
        if th.dark {
            let gc = Offset(c.x, c.y - 85 * u)
            drawCircle(Brush.radialGradient([ArtColor(0x66FF_F59D), ArtColor.Transparent], gc, 30 * u), 30 * u, gc)
        }
    }

    mutating func crown(_ c: Offset, _ s: Float) {
        let p = ArtPath { p in
            p.moveTo(c.x - s, c.y + s * 0.6); p.lineTo(c.x - s, c.y - s * 0.4); p.lineTo(c.x - s * 0.45, c.y + s * 0.05)
            p.lineTo(c.x, c.y - s * 0.7); p.lineTo(c.x + s * 0.45, c.y + s * 0.05); p.lineTo(c.x + s, c.y - s * 0.4)
            p.lineTo(c.x + s, c.y + s * 0.6); p.close()
        }
        drawPath(p, Brush.verticalGradient([ArtColor(0xFFFF_F59D), ArtColor(0xFFFF_C107)], c.y - s, c.y + s))
        drawPath(p, ArtColor(0xFFE6_5100), style: .stroke(s * 0.12, join: .round))
    }

    mutating func giraffe(_ c: Offset, _ u: Float) {
        let y = ArtColor(0xFFFF_C94D)
        let b = ArtColor(0xFFB0_702A)
        drawPath(ArtPath { p in
            p.moveTo(c.x - 4 * u, c.y - 20 * u); p.lineTo(c.x + 4 * u, c.y - 20 * u); p.lineTo(c.x + 10 * u, c.y - 70 * u); p.lineTo(c.x + 2 * u, c.y - 72 * u); p.close()
        }, y)
        drawRoundRect(y, Offset(c.x - 4 * u, c.y - 80 * u), Size(20 * u, 11 * u), CornerRadius(5 * u))
        drawLine(b, Offset(c.x + 3 * u, c.y - 80 * u), Offset(c.x + 2 * u, c.y - 86 * u), 1.6 * u, .round)
        drawLine(b, Offset(c.x + 8 * u, c.y - 80 * u), Offset(c.x + 8 * u, c.y - 86 * u), 1.6 * u, .round)
        drawCircle(ArtColor(0xFF3E_2723), 1.4 * u, Offset(c.x + 6 * u, c.y - 76 * u))
        for kk in 0..<4 {
            let fk = Float(kk)
            drawCircle(b, 2 * u, Offset(c.x + 2 * u + fk * 1.8 * u, c.y - 30 * u - fk * 10 * u))
        }
    }

    mutating func elephant(_ c: Offset, _ u: Float) {
        let g = ArtColor(0xFF90_A4AE)
        drawOval(g, Offset(c.x - 22 * u, c.y - 30 * u), Size(40 * u, 26 * u))
        drawCircle(g, 12 * u, Offset(c.x - 22 * u, c.y - 32 * u))
        drawOval(g.shade(0.85), Offset(c.x - 24 * u, c.y - 40 * u), Size(14 * u, 18 * u))
        drawPath(ArtPath { p in
            p.moveTo(c.x - 32 * u, c.y - 30 * u)
            p.quadraticTo(c.x - 40 * u, c.y - 18 * u, c.x - 34 * u, c.y - 8 * u)
        }, g, style: .stroke(5 * u, cap: .round))
        drawCircle(ArtColor(0xFF26_3238), 1.4 * u, Offset(c.x - 26 * u, c.y - 35 * u))
        drawCircle(ArtColor.White.copy(alpha: 0.4), 4 * u, Offset(c.x - 4 * u, c.y - 26 * u))
    }

    mutating func carousel(_ c: Offset, _ u: Float) {
        drawRoundRect(ArtColor(0xFFCE_93D8), Offset(c.x - 40 * u, c.y - 10 * u), Size(80 * u, 10 * u), CornerRadius(3 * u))
        for kk in 0..<5 {
            let x = c.x - 32 * u + Float(kk) * 16 * u
            drawLine(ArtColor(0xFFFF_D54F), Offset(x, c.y - 10 * u), Offset(x, c.y - 46 * u), 1.6 * u)
        }
        let horses = [ArtColor.White, ArtColor(0xFFFF_CDD2), ArtColor(0xFFBB_DEFB), ArtColor(0xFFFF_F9C4)]
        for kk in 0..<4 {
            drawRoundRect(horses[kk], Offset(c.x - 30 * u + Float(kk) * 16 * u, c.y - 26 * u + Float(kk % 2) * 5 * u), Size(10 * u, 7 * u), CornerRadius(3 * u))
        }
        let roof = ArtPath { p in
            p.moveTo(c.x, c.y - 74 * u); p.lineTo(c.x + 46 * u, c.y - 46 * u); p.lineTo(c.x - 46 * u, c.y - 46 * u); p.close()
        }
        drawPath(roof, ArtColor(0xFFEC_407A))
        for kk in 0..<4 {
            let fk = Float(kk)
            drawPath(ArtPath { p in
                p.moveTo(c.x, c.y - 74 * u)
                p.lineTo(c.x - 46 * u + fk * 23 * u + 11 * u, c.y - 46 * u)
                p.lineTo(c.x - 46 * u + fk * 23 * u, c.y - 46 * u)
                p.close()
            }, ArtColor.White)
        }
        for kk in 0..<8 { drawCircle(ArtColor(0xFFFF_EB3B), 2 * u, Offset(c.x - 42 * u + Float(kk) * 12 * u, c.y - 46 * u)) }
        drawCircle(ArtColor(0xFFFF_D54F), 4 * u, Offset(c.x, c.y - 76 * u))
    }

    mutating func stand(_ c: Offset, _ u: Float) {
        drawRoundRect(ArtColor(0xFFFF_F3E0), Offset(c.x - 20 * u, c.y - 26 * u), Size(40 * u, 26 * u), CornerRadius(3 * u))
        for kk in 0..<5 {
            drawRect(kk % 2 == 0 ? ArtColor(0xFFFF_4081) : ArtColor.White, Offset(c.x - 24 * u + Float(kk) * 9.6 * u, c.y - 38 * u), Size(9.6 * u, 12 * u))
        }
        drawCircle(ArtColor(0xFFF8_BBD0), 7 * u, Offset(c.x + 8 * u, c.y - 46 * u))
        drawLine(ArtColor(0xFFFF_F3E0), Offset(c.x + 8 * u, c.y - 40 * u), Offset(c.x + 8 * u, c.y - 34 * u), 1.4 * u)
    }

    mutating func lighthouse(_ c: Offset, _ u: Float) {
        let p = ArtPath { p in
            p.moveTo(c.x - 14 * u, c.y); p.lineTo(c.x - 9 * u, c.y - 82 * u); p.lineTo(c.x + 9 * u, c.y - 82 * u); p.lineTo(c.x + 14 * u, c.y); p.close()
        }
        drawPath(p, Brush.horizontalGradient([ArtColor.White, ArtColor(0xFFE0_E0E0)], c.x - 14 * u, c.x + 14 * u))
        for kk in 0..<3 {
            let fk = Float(kk)
            drawRect(ArtColor(0xFFE5_3935), Offset(c.x - (13 - fk * 1.5) * u, c.y - (20 + fk * 22) * u), Size((26 - fk * 3) * u, 9 * u))
        }
        drawRoundRect(ArtColor(0xFF37_474F), Offset(c.x - 11 * u, c.y - 92 * u), Size(22 * u, 10 * u), CornerRadius(2 * u))
        drawRect(ArtColor(0xFFFF_EE58), Offset(c.x - 7 * u, c.y - 91 * u), Size(14 * u, 8 * u))
        drawPath(ArtPath { p in
            p.moveTo(c.x - 12 * u, c.y - 92 * u); p.lineTo(c.x, c.y - 102 * u); p.lineTo(c.x + 12 * u, c.y - 92 * u); p.close()
        }, ArtColor(0xFFC6_2828))
    }

    mutating func sailboat(_ c: Offset, _ u: Float) {
        drawPath(ArtPath { p in
            p.moveTo(c.x - 22 * u, c.y); p.lineTo(c.x + 22 * u, c.y); p.lineTo(c.x + 15 * u, c.y + 9 * u); p.lineTo(c.x - 15 * u, c.y + 9 * u); p.close()
        }, ArtColor(0xFFFF_7043))
        drawLine(ArtColor(0xFF5D_4037), Offset(c.x, c.y), Offset(c.x, c.y - 34 * u), 1.6 * u)
        drawPath(ArtPath { p in
            p.moveTo(c.x + 1 * u, c.y - 33 * u); p.lineTo(c.x + 18 * u, c.y - 3 * u); p.lineTo(c.x + 1 * u, c.y - 3 * u); p.close()
        }, ArtColor.White)
        drawPath(ArtPath { p in
            p.moveTo(c.x - 1 * u, c.y - 26 * u); p.lineTo(c.x - 13 * u, c.y - 3 * u); p.lineTo(c.x - 1 * u, c.y - 3 * u); p.close()
        }, ArtColor(0xFFFF_F59D))
    }

    mutating func pyramid(_ c: Offset, _ s: Float) {
        drawPath(ArtPath { p in
            p.moveTo(c.x, c.y - s); p.lineTo(c.x + s, c.y); p.lineTo(c.x - s, c.y); p.close()
        }, ArtColor(0xFFE6_BB73))
        drawPath(ArtPath { p in
            p.moveTo(c.x, c.y - s); p.lineTo(c.x + s, c.y); p.lineTo(c.x + s * 0.15, c.y); p.close()
        }, ArtColor(0xFFC9_9A52))
        for kk in 1...4 {
            let y = c.y - s * Float(kk) / 5
            let hw = s * (1 - Float(kk) / 5)
            drawLine(ArtColor(0xFFB9_8A45).copy(alpha: 0.5), Offset(c.x - hw, y), Offset(c.x + hw, y), 1)
        }
    }

    mutating func camel(_ c: Offset, _ u: Float) {
        let col = ArtColor(0xFFC6_8B4E)
        drawOval(col, Offset(c.x - 20 * u, c.y - 30 * u), Size(36 * u, 16 * u))
        drawCircle(col, 8 * u, Offset(c.x - 4 * u, c.y - 30 * u))
        drawPath(ArtPath { p in
            p.moveTo(c.x + 14 * u, c.y - 24 * u)
            p.quadraticTo(c.x + 24 * u, c.y - 30 * u, c.x + 22 * u, c.y - 42 * u)
        }, col, style: .stroke(5 * u, cap: .round))
        drawOval(col, Offset(c.x + 18 * u, c.y - 46 * u), Size(12 * u, 7 * u))
        let legs: [Float] = [-16, -8, 4, 12]
        for dx in legs { drawLine(col.shade(0.85), Offset(c.x + dx * u, c.y - 16 * u), Offset(c.x + dx * u, c.y), 2.5 * u) }
    }

    mutating func mountain(_ c: Offset, _ hgt: Float, _ u: Float) {
        drawPath(ArtPath { p in
            p.moveTo(c.x - hgt, c.y); p.lineTo(c.x, c.y - hgt); p.lineTo(c.x + hgt, c.y); p.close()
        }, ArtColor(0xFF90_A4AE))
        drawPath(ArtPath { p in
            p.moveTo(c.x, c.y - hgt); p.lineTo(c.x + hgt, c.y); p.lineTo(c.x + hgt * 0.2, c.y); p.close()
        }, ArtColor(0xFF78_909C))
        let cap = ArtPath { p in
            p.moveTo(c.x - hgt * 0.3, c.y - hgt * 0.7); p.lineTo(c.x, c.y - hgt); p.lineTo(c.x + hgt * 0.3, c.y - hgt * 0.7)
            p.lineTo(c.x + hgt * 0.12, c.y - hgt * 0.76); p.lineTo(c.x - 2 * u, c.y - hgt * 0.68); p.lineTo(c.x - hgt * 0.14, c.y - hgt * 0.75); p.close()
        }
        drawPath(cap, ArtColor.White)
    }

    mutating func cabin(_ c: Offset, _ u: Float) {
        drawRect(ArtColor(0xFF8D_5A3B), Offset(c.x - 22 * u, c.y - 26 * u), Size(44 * u, 26 * u))
        for kk in 0..<4 {
            let y = c.y - 26 * u + Float(kk) * 6.5 * u
            drawLine(ArtColor(0xFF6D_4027), Offset(c.x - 22 * u, y), Offset(c.x + 22 * u, y), 1 * u)
        }
        drawPath(ArtPath { p in
            p.moveTo(c.x - 28 * u, c.y - 24 * u); p.lineTo(c.x, c.y - 44 * u); p.lineTo(c.x + 28 * u, c.y - 24 * u); p.close()
        }, ArtColor.White)
        drawRect(ArtColor(0xFF6D_4027), Offset(c.x + 10 * u, c.y - 48 * u), Size(6 * u, 12 * u))
        drawRect(ArtColor(0xFFFF_E082), Offset(c.x - 14 * u, c.y - 18 * u), Size(10 * u, 9 * u))
    }

    mutating func snowman(_ c: Offset, _ u: Float) {
        drawOval(ArtColor.Black.copy(alpha: 0.12), Offset(c.x - 12 * u, c.y - 2 * u), Size(24 * u, 5 * u))
        drawCircle(ArtColor.White, 11 * u, Offset(c.x, c.y - 10 * u))
        drawCircle(ArtColor.White, 8 * u, Offset(c.x, c.y - 26 * u))
        drawCircle(ArtColor(0xFFE3_F2FD), 8 * u, Offset(c.x + 2 * u, c.y - 26 * u), style: .stroke(1 * u))
        drawCircle(ArtColor(0xFF26_3238), 1.2 * u, Offset(c.x - 3 * u, c.y - 28 * u))
        drawCircle(ArtColor(0xFF26_3238), 1.2 * u, Offset(c.x + 3 * u, c.y - 28 * u))
        drawPath(ArtPath { p in
            p.moveTo(c.x, c.y - 26 * u); p.lineTo(c.x + 7 * u, c.y - 25 * u); p.lineTo(c.x, c.y - 24 * u); p.close()
        }, ArtColor(0xFFFF_7043))
        drawRect(ArtColor(0xFFE5_3935), Offset(c.x - 8 * u, c.y - 20 * u), Size(16 * u, 3 * u))
    }

    mutating func barn(_ c: Offset, _ u: Float) {
        drawRect(Brush.horizontalGradient([ArtColor(0xFFD3_2F2F), ArtColor(0xFFB7_1C1C)], c.x - 40 * u, c.x + 40 * u), Offset(c.x - 40 * u, c.y - 56 * u), Size(80 * u, 56 * u))
        for kk in 0..<6 {
            let x = c.x - 40 * u + Float(kk) * 16 * u
            drawLine(ArtColor(0xFF9A_1B1B), Offset(x, c.y - 56 * u), Offset(x, c.y), 1 * u)
        }
        let roof = ArtPath { p in
            p.moveTo(c.x - 48 * u, c.y - 54 * u); p.lineTo(c.x - 24 * u, c.y - 80 * u); p.lineTo(c.x + 24 * u, c.y - 80 * u); p.lineTo(c.x + 48 * u, c.y - 54 * u); p.close()
        }
        drawPath(roof, ArtColor(0xFF5D_4037))
        drawPath(roof, ArtColor(0xFF3E_2723), style: .stroke(2 * u))
        drawRect(ArtColor.White, Offset(c.x - 14 * u, c.y - 36 * u), Size(28 * u, 36 * u), style: .stroke(2.5 * u))
        drawLine(ArtColor.White, Offset(c.x - 14 * u, c.y - 36 * u), Offset(c.x + 14 * u, c.y), 2.5 * u)
        drawLine(ArtColor.White, Offset(c.x + 14 * u, c.y - 36 * u), Offset(c.x - 14 * u, c.y), 2.5 * u)
        drawCircle(ArtColor(0xFFFF_F8E1), 6 * u, Offset(c.x, c.y - 64 * u))
    }

    mutating func neon(_ tl: Offset, _ s: Size, _ color: ArtColor, _ u: Float) {
        drawRoundRect(ArtColor(0xFF12_0D30), tl, s, CornerRadius(4 * u))
        for kk in stride(from: 3, through: 1, by: -1) {
            let fk = Float(kk)
            drawRoundRect(color.copy(alpha: 0.12 * fk), tl - Offset(fk * 1.5 * u, fk * 1.5 * u), Size(s.width + fk * 3 * u, s.height + fk * 3 * u),
                          CornerRadius(6 * u), style: .stroke(2 * u))
        }
        drawRoundRect(color, tl, s, CornerRadius(4 * u), style: .stroke(1.6 * u))
        drawLine(color, tl + Offset(s.width * 0.2, s.height * 0.5), tl + Offset(s.width * 0.8, s.height * 0.5), 2 * u, .round)
    }

    mutating func dome(_ c: Offset, _ r: Float) {
        drawArc(Brush.radialGradient([ArtColor(0xFFE0_F7FA), ArtColor(0xFF4D_D0E1), ArtColor(0xFF00_838F)], c - Offset(r * 0.3, r * 0.6), r * 1.4),
                180, 180, true, Offset(c.x - r, c.y - r), Size(r * 2, r * 2))
        drawArc(ArtColor.White.copy(alpha: 0.5), 200, 60, false, Offset(c.x - r * 0.8, c.y - r * 0.8), Size(r * 1.6, r * 1.6), style: .stroke(r * 0.08))
        drawRect(ArtColor(0xFF45_5A64), Offset(c.x - r, c.y - r * 0.08), Size(r * 2, r * 0.08))
    }

    mutating func dish(_ c: Offset, _ u: Float) {
        drawLine(ArtColor(0xFF90_A4AE), c, c - Offset(0, 26 * u), 3 * u)
        drawArc(ArtColor(0xFFEC_EFF1), 20, 180, true, Offset(c.x - 18 * u, c.y - 46 * u), Size(36 * u, 26 * u))
        drawLine(ArtColor(0xFF90_A4AE), c - Offset(-2 * u, 34 * u), c - Offset(-14 * u, 46 * u), 1.5 * u)
        drawCircle(ArtColor(0xFFFF_5252), 2.5 * u, c - Offset(-14 * u, 47 * u))
    }

    mutating func rocket(_ c: Offset, _ u: Float) {
        drawRect(ArtColor(0xFF54_6E7A), Offset(c.x - 26 * u, c.y - 104 * u), Size(5 * u, 104 * u))
        for kk in 0..<6 {
            let fk = Float(kk)
            drawLine(ArtColor(0xFF78_909C), Offset(c.x - 26 * u, c.y - fk * 18 * u), Offset(c.x - 21 * u, c.y - fk * 18 * u - 9 * u), 1.4 * u)
        }
        let body = ArtPath { p in
            p.moveTo(c.x, c.y - 112 * u)
            p.quadraticTo(c.x + 16 * u, c.y - 88 * u, c.x + 14 * u, c.y - 26 * u)
            p.lineTo(c.x - 14 * u, c.y - 26 * u)
            p.quadraticTo(c.x - 16 * u, c.y - 88 * u, c.x, c.y - 112 * u)
            p.close()
        }
        drawPath(body, Brush.horizontalGradient([ArtColor.White, ArtColor(0xFFCF_D8DC)], c.x - 14 * u, c.x + 14 * u))
        drawCircle(ArtColor(0xFF29_B6F6), 6 * u, Offset(c.x, c.y - 74 * u))
        drawCircle(ArtColor.White.copy(alpha: 0.6), 2 * u, Offset(c.x - 2 * u, c.y - 76 * u))
        drawPath(ArtPath { p in
            p.moveTo(c.x - 14 * u, c.y - 48 * u); p.lineTo(c.x - 26 * u, c.y - 18 * u); p.lineTo(c.x - 12 * u, c.y - 26 * u); p.close()
        }, ArtColor(0xFFE5_3935))
        drawPath(ArtPath { p in
            p.moveTo(c.x + 14 * u, c.y - 48 * u); p.lineTo(c.x + 26 * u, c.y - 18 * u); p.lineTo(c.x + 12 * u, c.y - 26 * u); p.close()
        }, ArtColor(0xFFE5_3935))
        drawRect(ArtColor(0xFF37_474F), Offset(c.x - 36 * u, c.y - 18 * u), Size(72 * u, 14 * u))
    }

    /// Kotlin `DrawScope.text`: bold, centred on c.x, baseline at c.y + size·0.35.
    func text(_ s: String, _ c: Offset, _ size: Float, _ color: ArtColor) {
        drawText(s, c.x, c.y + size * 0.35, size, color)
    }
}
