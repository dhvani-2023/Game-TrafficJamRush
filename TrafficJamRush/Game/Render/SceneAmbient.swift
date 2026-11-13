import SwiftUI
import GameKit

// Port of game/render/SceneAmbient.kt.

/// The moving parts of each world's scenery, drawn every frame over the static scene.
/// Per-frame drawing goes through `FrameScope` (no allocations except the two bird strokes).
enum SceneAmbient {

    static func ferrisCenter(_ w: Float, _ base: Float, _ u: Float) -> Offset { Offset(w * 0.74, base - 58 * u) }
    static func millHub(_ w: Float, _ base: Float, _ u: Float) -> Offset { Offset(w * 0.86, base - 64 * u) }

    private struct Triple {
        let a: Float
        let b: Float
        let c: Float
    }

    private static let stars: [Triple] = {
        let r = KotlinRandom(3)
        return (0..<40).map { _ in
            let a = r.nextFloat()
            let b = r.nextFloat()
            let c = r.nextFloat() * 6
            return Triple(a: a, b: b, c: c)
        }
    }()

    private static let flakes: [Triple] = {
        let r = KotlinRandom(4)
        return (0..<60).map { _ in
            let a = r.nextFloat()
            let b = r.nextFloat()
            let c = 0.5 + r.nextFloat()
            return Triple(a: a, b: b, c: c)
        }
    }()

    private static let shootGradient = GradientData([ArtColor.Transparent, ArtColor.White])
    private static let cloudColor = ArtColor.White.copy(alpha: 0.85)

    /// Parts that turn, frozen at rest, for postcards.
    static func staticPose<S: DrawScope>(_ s: inout S, _ th: SceneTheme, _ w: Float, _ base: Float, _ u: Float) {
        switch th.backdrop {
        case .FAIR: s.ferris(ferrisCenter(w, base, u), u, 0)
        case .FARM: s.windmill(millHub(w, base, u), u, 0)
        default: break
        }
    }

    /// Draws the ambient layer for layout [lay] (points) at time [t] seconds.
    static func draw(_ s: inout FrameScope, _ lay: GameLayout, _ th: SceneTheme, _ t: Float) {
        let u = lay.u
        let w = lay.width
        let top = lay.topInset
        let base = top + 120 * u
        if !th.dark && th.backdrop != .SNOW {
            // Drifting clouds high in the sky
            for k in 0..<2 {
                let fk = Float(k)
                let span = w + 160 * u
                let x = (t * (8 + fk * 5) * u + fk * span * 0.55).truncatingRemainder(dividingBy: span) - 80 * u
                s.ambientCloud(Offset(x, top + (12 + fk * 10) * u), u * (0.5 + fk * 0.12))
            }
            // A pair of birds crossing every ~14 s
            let cycle = t.truncatingRemainder(dividingBy: 14) / 14
            if cycle < 0.6 {
                let bx = -20 * u + cycle / 0.6 * (w + 40 * u)
                for k in 0..<2 {
                    let fk = Float(k)
                    s.bird(Offset(bx - fk * 14 * u, top + (22 + fk * 5) * u + Kt.sin(t * 2 + fk) * 3 * u), u, t + fk * 0.3)
                }
            }
        }
        switch th.backdrop {
        case .FAIR:
            s.ferris(ferrisCenter(w, base, u), u, t * 10)
        case .FARM:
            s.windmill(millHub(w, base, u), u, t * 40)
        case .PIER:
            let sea = top + 66 * u
            let wave = waveArc(u)
            let saved = s.ctx.transform
            let o = s.ctx.opacity
            s.ctx.opacity = o * 0.55
            let style = StrokeStyle(lineWidth: CGFloat(1.5 * u))
            for k in 0..<7 {
                let fk = Float(k)
                let y = sea + 10 * u + Float(k % 3) * 12 * u
                let x = (fk * 61 * u + t * 14 * u * Float(1 + k % 2)).truncatingRemainder(dividingBy: w + 40 * u) - 20 * u
                s.ctx.transform = saved.translatedBy(x: CGFloat(x), y: CGFloat(y))
                s.ctx.stroke(wave, with: .color(.white), style: style)
            }
            s.ctx.transform = saved
            s.ctx.opacity = o
            for k in 0..<6 {
                let fk = Float(k)
                let a = (Kt.sin(t * 3 + fk * 1.7) + 1) / 2
                s.drawCircle(ArtColor.White, 1.3 * u, Offset(Float(k * 57 % 340 + 10) * u, sea + (8 + fk * 5) * u), alpha: a * 0.8)
            }
        case .SNOW:
            for f in flakes {
                let y = (f.b * lay.height + t * 22 * u * f.c).truncatingRemainder(dividingBy: lay.height)
                let x = f.a * w + Kt.sin(t * f.c + f.b * 10) * 6 * u
                s.drawCircle(ArtColor.White, 1.3 * u * f.c, Offset(x, y), alpha: 0.85)
            }
        case .NEON, .SPACE:
            for st in stars {
                let a = (Kt.sin(t * 2.2 + st.c) + 1) / 2
                if a > 0.6 { s.drawCircle(ArtColor.White, 1.4 * u, Offset(st.a * w, top + st.b * 80 * u), alpha: (a - 0.6) * 2.2) }
            }
            if th.backdrop == .NEON {
                let flick: Float = Kt.toInt(t * 7) % 23 == 0 ? 0.2 : 1
                s.drawRoundRect(ArtColor(0xFFFF_4FD8), Offset(w * 0.36 - 4 * u, base - 78 * u), Size(78 * u, 30 * u), CornerRadius(8 * u), alpha: 0.25 * flick)
            } else {
                let blink: Float = Kt.toInt(t * 1.5) % 2 == 0 ? 1 : 0.15
                s.drawCircle(ArtColor(0xFFFF_5252), 2.6 * u, Offset(w * 0.52 + 14 * u, base - 47 * u), alpha: blink)
                let shoot = t.truncatingRemainder(dividingBy: 9) / 9
                if shoot < 0.12 {
                    let p = shoot / 0.12
                    let a = Offset(w * (0.2 + p * 0.5), top + (10 + p * 30) * u)
                    let from = a - Offset(30 * u, 12 * u)
                    s.drawLine(Brush.linear(shootGradient, from, a), from, a, 1.6 * u, .round)
                }
            }
        case .JUNGLE:
            for k in 0..<8 {
                let fk = Float(k)
                let x = Float(k * 47 % 330 + 15) * u + Kt.sin(t * 0.8 + fk) * 10 * u
                let y = base - Float(20 + (k * 13) % 60) * u + Kt.cos(t * 1.1 + fk * 2) * 6 * u
                let a = (Kt.sin(t * 3 + fk) + 1) / 2
                // Color(0x55FFFF8D).copy(alpha = 0.35·a) replaces the alpha.
                s.drawCircle(ArtColor(0xFFFF_FF8D), 5 * u, Offset(x, y), alpha: 0.35 * a)
                s.drawCircle(ArtColor(0xFFFF_FF8D), 1.6 * u, Offset(x, y), alpha: a)
            }
        case .DESERT:
            let p = t.truncatingRemainder(dividingBy: 11) / 11
            let x = -20 * u + p * (w + 40 * u)
            let y = lay.queueY - 4 * u - abs(Kt.sin(p * 40)) * 8 * u
            s.rotate(t * 300, Offset(x, y)) { s in
                s.drawCircle(ArtColor(0xFFB9_8A45), 7 * u, Offset(x, y), style: .stroke(1.6 * u))
                s.drawLine(ArtColor(0xFFB9_8A45), Offset(x - 6 * u, y), Offset(x + 6 * u, y), 1.2 * u)
                s.drawLine(ArtColor(0xFFB9_8A45), Offset(x, y - 6 * u), Offset(x, y + 6 * u), 1.2 * u)
            }
        default:
            break
        }
    }

    // The PIER wave: an open arc (200°, sweep 140°) of a 22u × 8u oval, built once per u.
    private static var waveCache: (u: Float, path: Path)?

    private static func waveArc(_ u: Float) -> Path {
        if let c = waveCache, c.u == u { return c.path }
        let p = Path(Draw.arcPath(CGRect(x: 0, y: 0, width: CGFloat(22 * u), height: CGFloat(8 * u)), 200, 140, false))
        waveCache = (u, p)
        return p
    }
}

fileprivate extension FrameScope {
    mutating func ambientCloud(_ c: Offset, _ u: Float) {
        let col = ArtColor.White
        let a: Float = 0.85
        drawCircle(col, 14 * u, c, alpha: a)
        drawCircle(col, 11 * u, c + Offset(-16 * u, 4 * u), alpha: a)
        drawCircle(col, 12 * u, c + Offset(16 * u, 3 * u), alpha: a)
        drawRoundRect(col, c + Offset(-26 * u, 2 * u), Size(52 * u, 12 * u), CornerRadius(6 * u), alpha: a)
    }

    mutating func bird(_ c: Offset, _ u: Float, _ t: Float) {
        let flap = Kt.sin(t * 12) * 4 * u
        let p = ArtPath { p in
            p.moveTo(c.x - 6 * u, c.y - flap)
            p.quadraticTo(c.x - 3 * u, c.y - 2 * u, c.x, c.y)
            p.quadraticTo(c.x + 3 * u, c.y - 2 * u, c.x + 6 * u, c.y - flap)
        }
        drawPath(p, ArtColor(0xFF37_474F), style: .stroke(1.5 * u, cap: .round))
    }
}

extension DrawScope {
    mutating func ferris(_ c: Offset, _ u: Float, _ deg: Float) {
        let r = 50 * u
        drawCircle(ArtColor(0xFF8E_24AA), r, c, style: .stroke(4 * u))
        drawCircle(ArtColor(0xFFCE_93D8), r - 6 * u, c, style: .stroke(1.5 * u))
        for k in 0..<10 {
            let a = (Double(k) * 36.0 + Double(deg)) * Double.pi / 180
            let p = Offset(c.x + Float(Double(r) * Foundation.cos(a)), c.y + Float(Double(r) * Foundation.sin(a)))
            drawLine(ArtColor(0xFFCE_93D8), c, p, 1.4 * u)
            drawCircle(ArtColor(0xFFFF_EB3B), 1.8 * u, p)
            drawLine(ArtColor(0xFF6A_1B9A), p, p + Offset(0, 5 * u), 1 * u)
            drawRoundRect(ferrisColors[k % 4], p + Offset(-6 * u, 4 * u), Size(12 * u, 9 * u), CornerRadius(3 * u))
            drawRect(ArtColor.White.copy(alpha: 0.6), p + Offset(-4 * u, 5.5 * u), Size(8 * u, 3 * u))
        }
        drawCircle(ArtColor(0xFFFF_D54F), 5 * u, c)
    }

    mutating func windmill(_ c: Offset, _ u: Float, _ deg: Float) {
        rotate(deg, c) { s in
            for k in 0..<4 {
                s.rotate(Float(k) * 90, c) { s in
                    s.drawLine(ArtColor(0xFF6D_4C41), c, c - Offset(0, 34 * u), 2 * u)
                    s.drawRect(ArtColor(0xFFFF_F8E1), Offset(c.x - 1 * u, c.y - 34 * u), Size(9 * u, 24 * u))
                    s.drawRect(ArtColor(0xFFBC_AAA4), Offset(c.x - 1 * u, c.y - 34 * u), Size(9 * u, 24 * u), style: .stroke(1 * u))
                }
            }
        }
        drawCircle(ArtColor(0xFF5D_4037), 3.5 * u, c)
    }
}

private let ferrisColors = [ArtColor(0xFFFF_7043), ArtColor(0xFF42_A5F5), ArtColor(0xFFFF_CA28), ArtColor(0xFF66_BB6A)]
