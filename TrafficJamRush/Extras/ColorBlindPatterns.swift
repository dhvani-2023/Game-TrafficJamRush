import SwiftUI
import GameKit

/// Colour-blind mode: every JamColor gets a distinct symbol, drawn as a sticker on the vehicle roofs and a badge
/// on the passenger shirts. Both are baked into the sprite caches (VehicleArt's slice stack, so every cached
/// composite carries it, and PassengerArt's frames): nothing extra is drawn per frame.
enum ExtrasPatterns {

    /// Shapes chosen to stay distinct when a vehicle turns (N/E/S/W plus the board's ±14°/±22° tilt): the
    /// diamond is a tall rhombus so it never reads as a tilted square, and nothing is pointed like the roof
    /// arrow (a triangle would look like a second arrow).
    enum Symbol: Int, CaseIterable {
        case heart, square, clover, star, circle, moon, plus, diamond
    }

    /// RED ♥, BLUE ■, GREEN ♣, YELLOW ★, PINK ●, PURPLE ☾, ORANGE ✚, CYAN ◆.
    static func symbol(_ color: Int) -> Symbol { Symbol(rawValue: Kt.mod(color, 8))! }

    static let ink = ArtColor(0xFF3E_4652)

    /// True when the toggle is on (read when a level's sprite caches are created).
    @MainActor static var enabled: Bool { ExtrasFeatures.colorBlindPatterns && App.container.extras.colorBlind }

    /// The symbol of [color] filled in [fill], centred on [c], fitting a circle of radius [r]. [hole] paints the
    /// crescent's bite (the background it sits on).
    static func drawSymbol<S: DrawScope>(_ s: inout S, _ color: Int, _ c: Offset, _ r: Float, _ fill: ArtColor, hole: ArtColor) {
        switch symbol(color) {
        case .heart:
            let p = ArtPath { p in
                // The game's HEART icon outline, scaled from its 100×100 box (visual centre 50, 55).
                func x(_ v: Float) -> Float { c.x + (v - 50) / 44 * r }
                func y(_ v: Float) -> Float { c.y + (v - 55) / 44 * r }
                p.moveTo(x(50), y(92))
                p.cubicTo(x(10), y(64), x(4), y(40), x(16), y(24))
                p.cubicTo(x(28), y(8), x(46), y(14), x(50), y(30))
                p.cubicTo(x(54), y(14), x(72), y(8), x(84), y(24))
                p.cubicTo(x(96), y(40), x(90), y(64), x(50), y(92))
                p.close()
            }
            s.drawPath(p, fill)
        case .square:
            let h = r * 0.74
            s.drawRoundRect(fill, Offset(c.x - h, c.y - h), Size(2 * h, 2 * h), CornerRadius(r * 0.18))
        case .clover:
            let lobe = r * 0.4
            s.drawCircle(fill, lobe, Offset(c.x, c.y - r * 0.5))
            s.drawCircle(fill, lobe, Offset(c.x - r * 0.48, c.y + r * 0.06))
            s.drawCircle(fill, lobe, Offset(c.x + r * 0.48, c.y + r * 0.06))
            s.drawCircle(fill, r * 0.3, Offset(c.x, c.y - r * 0.08))
            let stem = ArtPath { p in
                p.moveTo(c.x - r * 0.1, c.y)
                p.lineTo(c.x + r * 0.1, c.y)
                p.lineTo(c.x + r * 0.3, c.y + r * 0.95)
                p.lineTo(c.x - r * 0.3, c.y + r * 0.95)
                p.close()
            }
            s.drawPath(stem, fill)
        case .star:
            s.drawPath(starPath(c.x, c.y + r * 0.06, r * 1.02, 0.47), fill)
        case .circle:
            s.drawCircle(fill, r * 0.74, c)
        case .moon:
            s.drawCircle(fill, r * 0.86, c)
            s.drawCircle(hole, r * 0.7, Offset(c.x + r * 0.42, c.y - r * 0.26))
        case .plus:
            let t = r * 0.27
            let l = r * 0.86
            s.drawRoundRect(fill, Offset(c.x - t, c.y - l), Size(2 * t, 2 * l), CornerRadius(t * 0.5))
            s.drawRoundRect(fill, Offset(c.x - l, c.y - t), Size(2 * l, 2 * t), CornerRadius(t * 0.5))
        case .diamond:
            let p = ArtPath { p in
                p.moveTo(c.x, c.y - r * 1.02)
                p.lineTo(c.x + r * 0.62, c.y)
                p.lineTo(c.x, c.y + r * 1.02)
                p.lineTo(c.x - r * 0.62, c.y)
                p.close()
            }
            s.drawPath(p, fill)
        }
    }

    /// White sticker with a dark rim and the colour's symbol (the house style of the mystery "?" badge).
    static func sticker<S: DrawScope>(_ s: inout S, _ color: Int, _ c: Offset, _ radius: Float, rim: Float) {
        s.drawCircle(ink, radius + rim, c)
        s.drawCircle(ArtColor.White, radius, c)
        drawSymbol(&s, color, c, radius * 0.6, ink, hole: .White)
    }

    /// Roof sticker in VehicleArt's slice space (device pixels, north-facing): it sits on the shaft of the roof
    /// arrow, behind the arrow head, so the direction stays readable.
    static func roofSticker(_ s: inout BitmapScope, _ color: Int, _ type: VehicleType, _ cab: Rect, _ bw: Float) {
        // Same arrow geometry as VehicleArt.roofCap.
        let la = min(bw * 1.02, cab.height * 0.9)
        let acx = cab.center.x
        let acy = cab.center.y + (type == .BUS ? -cab.height * 0.08 : 0)
        let r = min(la * 0.27, bw * 0.25)
        let c = Offset(acx, acy + la * 0.25)
        s.drawCircle(ArtColor(0x5500_0000), r + 1.5, c + Offset(bw * 0.03, bw * 0.05))
        sticker(&s, color, c, r, rim: 1.5)
    }

    /// Shirt badge in PassengerArt's bitmap space (device pixels).
    static func shirtBadge(_ s: inout BitmapScope, _ color: Int, _ c: Offset, _ r: Float, _ rim: ArtColor) {
        s.drawCircle(rim, r + max(1, r * 0.12), c)
        s.drawCircle(ArtColor.White, r, c)
        drawSymbol(&s, color, c, r * 0.64, ink, hole: .White)
    }
}

/// The colour's symbol as a SwiftUI view (Settings preview), drawn with the same code as the sprites.
struct ExtrasSymbolBadge: View {
    let color: Int
    let size: CGFloat

    var body: some View {
        Canvas { ctx, sz in
            var s = FrameScope(ctx, Size(Float(sz.width), Float(sz.height)))
            let r = Float(min(sz.width, sz.height)) / 2
            let c = Offset(Float(sz.width) / 2, Float(sz.height) / 2)
            s.drawCircle(jamArtColor(color), r, c)
            s.drawCircle(ArtColor.White, r * 0.72, c)
            ExtrasPatterns.drawSymbol(&s, color, c, r * 0.44, ExtrasPatterns.ink, hole: .White)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Under the Settings toggle while it is on: the eight colours with their symbols.
struct ExtrasColorBlindPreview: View {
    let on: Bool

    var body: some View {
        ZStack {
            if on {
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { c in
                        ExtrasSymbolBadge(color: c, size: 28)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .animation(.gameSnappy, value: on)
    }
}
