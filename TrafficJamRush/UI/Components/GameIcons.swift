import SwiftUI
import GameKit

// Port of ui/components/GameIcons.kt. Icons are drawn with the same Compose-style code into a
// device-pixel bitmap (100 × 100 design space scaled to the icon size, like the Android Canvas),
// cached per (icon, pixel size) and shown as an image.

enum Icon: CaseIterable, Hashable {
    case COIN, STAR, STAR_EMPTY, LOCK, HOME, MAP, COLLECTION, GARAGE, GEAR, SHUFFLE, CRANE, SORT, AD, GIFT, PLAY, TROPHY, HAND, CHECK, HEART, SAD
    /// Extras (drawn in Extras/ExtrasIcons.swift).
    case UNDO, FLAME
}

/// Chunky, colourful icons drawn in a 100×100 design space.
struct GameIcon: View {
    let icon: Icon
    let size: CGFloat

    init(_ icon: Icon, _ size: CGFloat) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        IconArt.image(icon, size).image
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum IconArt {
    private struct Key: Hashable {
        let icon: Icon
        let px: Int
    }

    private static var cache: [Key: ImageBitmap] = [:]
    private static let lock = NSLock()

    /// The icon at [size] points as a device-scale bitmap (cached).
    static func image(_ icon: Icon, _ size: CGFloat) -> ImageBitmap {
        let k = Art.scale
        let pxSize = max(1, Int((Float(size) * k).rounded()))
        let key = Key(icon: icon, px: pxSize)
        lock.lock()
        if let img = cache[key] {
            lock.unlock()
            return img
        }
        lock.unlock()
        let img = renderBitmap(pxSize, pxSize, scale: k) { s in
            let sc = s.size.minDimension / 100
            s.scale(sc, sc, .Zero) { s in s.drawIcon(icon) }
        }
        lock.lock()
        cache[key] = img
        lock.unlock()
        return img
    }
}

/// Kotlin `starPath`: a 5-point star (10 vertices) around (cx, cy).
func starPath(_ cx: Float, _ cy: Float, _ r: Float, _ inner: Float = 0.48) -> ArtPath {
    ArtPath { p in
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * Double.pi / 5
            let rr = i % 2 == 0 ? r : r * inner
            let x = cx + Float(Double(rr) * Foundation.cos(a))
            let y = cy + Float(Double(rr) * Foundation.sin(a))
            if i == 0 { p.moveTo(x, y) } else { p.lineTo(x, y) }
        }
        p.close()
    }
}

fileprivate extension BitmapScope {
    mutating func drawIcon(_ icon: Icon) {
        switch icon {
        case .COIN: coin()
        case .STAR: star(ArtColor(0xFFFF_D54F), ArtColor(0xFFFF_8F00))
        case .STAR_EMPTY: star(ArtColor(0xFF8D_99AE), ArtColor(0xFF5C_6680))
        case .LOCK: lock()
        case .HOME: home()
        case .MAP: map()
        case .COLLECTION: collection()
        case .GARAGE: car(Offset(50, 56), ArtColor(0xFFF2_453D))
        case .GEAR: gear()
        case .SHUFFLE: shuffle()
        case .CRANE: crane()
        case .SORT: sort()
        case .AD: ad()
        case .GIFT: gift()
        case .PLAY:
            let p = ArtPath { p in p.moveTo(30, 18); p.lineTo(84, 50); p.lineTo(30, 82); p.close() }
            drawPath(p, ArtColor.White)
            drawPath(p, ArtColor(0x3300_0000), style: .stroke(4, join: .round))
        case .TROPHY: trophy()
        case .HAND: hand()
        case .HEART: heart()
        case .SAD: sad()
        case .UNDO: extrasUndo()
        case .FLAME: extrasFlame()
        case .CHECK:
            let p = ArtPath { p in p.moveTo(18, 52); p.lineTo(42, 76); p.lineTo(84, 26) }
            drawPath(p, ArtColor(0xFF1B_5E20), style: .stroke(20, cap: .round, join: .round))
            drawPath(p, ArtColor(0xFF76_FF03), style: .stroke(12, cap: .round, join: .round))
        }
    }

    mutating func coin() {
        drawCircle(ArtColor(0xFFB2_6A00), 47, Offset(50, 53))
        drawCircle(Brush.radialGradient([ArtColor(0xFFFF_F59D), ArtColor(0xFFFF_C107), ArtColor(0xFFFF_8F00)], Offset(38, 36), 60), 45, Offset(50, 50))
        drawCircle(ArtColor(0xFFE6_9500), 33, Offset(50, 50), style: .stroke(4))
        // embossed car
        let c = ArtColor(0xFFD9_8300)
        drawRoundRect(c, Offset(30, 46), Size(40, 14), CornerRadius(6))
        drawRoundRect(c, Offset(38, 36), Size(24, 14), CornerRadius(6))
        drawRoundRect(ArtColor(0xFFFF_E082), Offset(41, 39), Size(18, 8), CornerRadius(3))
        drawCircle(c, 6, Offset(38, 62))
        drawCircle(c, 6, Offset(62, 62))
        drawOval(ArtColor.White.copy(alpha: 0.55), Offset(24, 16), Size(24, 12))
    }

    mutating func star(_ fill: ArtColor, _ edge: ArtColor) {
        let p = starPath(50, 54, 46)
        drawPath(starPath(50, 58, 46), edge.shade(0.7))
        drawPath(p, Brush.verticalGradient([fill.tint(0.35), fill, edge], 10, 95))
        drawPath(p, edge, style: .stroke(4, join: .round))
        drawOval(ArtColor.White.copy(alpha: 0.5), Offset(36, 30), Size(16, 10))
    }

    mutating func lock() {
        drawArc(ArtColor(0xFF5D_6B82), 180, 180, false, Offset(28, 14), Size(44, 48), style: .stroke(11))
        drawArc(ArtColor(0xFF9B_A8BF), 180, 180, false, Offset(28, 14), Size(44, 48), style: .stroke(5))
        drawRoundRect(ArtColor(0xFF8A_5A00), Offset(18, 42), Size(64, 50), CornerRadius(12))
        drawRoundRect(Brush.verticalGradient([ArtColor(0xFFFF_E082), ArtColor(0xFFFF_B300)], 40, 90), Offset(18, 40), Size(64, 48), CornerRadius(12))
        drawCircle(ArtColor(0xFF6D_4C00), 7, Offset(50, 60))
        drawRoundRect(ArtColor(0xFF6D_4C00), Offset(47, 60), Size(6, 16), CornerRadius(3))
    }

    mutating func home() {
        drawRoundRect(ArtColor(0xFF8D_6E63), Offset(66, 14), Size(10, 22), CornerRadius(2))
        drawRoundRect(ArtColor(0xFFC7_9A6B), Offset(20, 44), Size(60, 48), CornerRadius(6))
        drawRoundRect(Brush.verticalGradient([ArtColor(0xFFFF_F3E0), ArtColor(0xFFFF_E0B2)]), Offset(22, 44), Size(56, 44), CornerRadius(6))
        let roof = ArtPath { p in p.moveTo(8, 50); p.lineTo(50, 10); p.lineTo(92, 50); p.close() }
        drawPath(roof, Brush.verticalGradient([ArtColor(0xFFFF_6F5E), ArtColor(0xFFD3_2F2F)], 10, 50))
        drawPath(roof, ArtColor(0xFF8E_1B1B), style: .stroke(4, join: .round))
        drawRoundRect(ArtColor(0xFFFF_B300), Offset(40, 60), Size(20, 28), CornerRadius(10, 10))
        drawCircle(ArtColor(0xFF8D_6E00), 2.5, Offset(55, 75))
    }

    mutating func map() {
        let panels = [ArtColor(0xFF81_D4FA), ArtColor(0xFF4F_C3F7), ArtColor(0xFF81_D4FA)]
        for i in 0..<3 {
            let x = 12 + Float(i) * 26
            let even = i % 2 == 0
            let p = ArtPath { p in
                p.moveTo(x, even ? 22 : 14)
                p.lineTo(x + 26, even ? 14 : 22)
                p.lineTo(x + 26, even ? 82 : 90)
                p.lineTo(x, even ? 90 : 82)
                p.close()
            }
            drawPath(p, panels[i])
            drawPath(p, ArtColor(0xFF02_77BD), style: .stroke(3, join: .round))
        }
        let route = ArtPath { p in
            p.moveTo(20, 76)
            p.cubicTo(36, 50, 50, 80, 62, 50)
            p.quadraticTo(70, 34, 78, 36)
        }
        drawPath(route, ArtColor(0xFFE5_3935), style: .stroke(4, cap: .round, pathEffect: PathEffect.dashPathEffect([7, 6])))
        drawCircle(ArtColor(0xFFE5_3935), 10, Offset(78, 28))
        drawCircle(ArtColor.White, 4, Offset(78, 28))
    }

    mutating func collection() {
        rotate(-14, Offset(50, 50)) { s in s.card(ArtColor(0xFF9B_5CF0)) }
        rotate(8, Offset(50, 50)) { s in s.card(ArtColor(0xFF2F_7CF6)) }
        card(ArtColor(0xFFFF_C21A))
        car(Offset(50, 56), ArtColor(0xFFF2_453D), 0.48)
    }

    mutating func card(_ c: ArtColor) {
        drawRoundRect(c.shade(0.6), Offset(24, 14), Size(52, 74), CornerRadius(9))
        drawRoundRect(Brush.verticalGradient([c.tint(0.3), c]), Offset(26, 14), Size(48, 70), CornerRadius(8))
        drawRoundRect(ArtColor.White.copy(alpha: 0.85), Offset(31, 20), Size(38, 40), CornerRadius(5))
    }

    mutating func car(_ c: Offset, _ color: ArtColor, _ k: Float = 1) {
        scale(k, k, c) { s in
            s.drawRoundRect(ArtColor(0xFF22_2222), Offset(c.x - 34, c.y + 6), Size(68, 8), CornerRadius(4))
            let body = ArtPath { p in
                p.moveTo(c.x - 42, c.y + 12); p.lineTo(c.x - 42, c.y - 4); p.quadraticTo(c.x - 40, c.y - 10, c.x - 30, c.y - 12)
                p.lineTo(c.x - 20, c.y - 28); p.quadraticTo(c.x - 16, c.y - 32, c.x - 8, c.y - 32); p.lineTo(c.x + 16, c.y - 32)
                p.quadraticTo(c.x + 22, c.y - 32, c.x + 26, c.y - 26); p.lineTo(c.x + 34, c.y - 12)
                p.quadraticTo(c.x + 42, c.y - 10, c.x + 42, c.y - 2); p.lineTo(c.x + 42, c.y + 12); p.close()
            }
            s.drawPath(body, Brush.verticalGradient([color.tint(0.3), color, color.shade(0.75)], c.y - 32, c.y + 12))
            s.drawPath(body, color.shade(0.5), style: .stroke(3.5, join: .round))
            let glass = ArtPath { p in
                p.moveTo(c.x - 24, c.y - 13); p.lineTo(c.x - 15, c.y - 26); p.lineTo(c.x - 1, c.y - 26); p.lineTo(c.x - 1, c.y - 13); p.close()
                p.moveTo(c.x + 3, c.y - 13); p.lineTo(c.x + 3, c.y - 26); p.lineTo(c.x + 16, c.y - 26); p.lineTo(c.x + 25, c.y - 13); p.close()
            }
            s.drawPath(glass, ArtColor(0xFF90_CAF9))
            s.drawRoundRect(ArtColor(0xFFFF_F59D), Offset(c.x + 34, c.y - 6), Size(8, 6), CornerRadius(3))
            for wx: Float in [-24, 24] {
                s.drawCircle(ArtColor(0xFF26_3238), 11, Offset(c.x + wx, c.y + 12))
                s.drawCircle(ArtColor(0xFFB0_BEC5), 5, Offset(c.x + wx, c.y + 12))
            }
        }
    }

    mutating func gear() {
        let c = Offset(50, 50)
        for i in 0..<8 {
            rotate(Float(i) * 45, c) { s in
                s.drawRoundRect(ArtColor(0xFF15_65C0), Offset(42, 6), Size(16, 20), CornerRadius(4))
            }
        }
        drawCircle(ArtColor(0xFF15_65C0), 36, c)
        drawCircle(Brush.radialGradient([ArtColor(0xFF90_CAF9), ArtColor(0xFF42_A5F5)], Offset(40, 40), 50), 31, c)
        drawCircle(ArtColor(0xFF15_65C0), 13, c)
        drawCircle(ArtColor.White, 9, c)
    }

    mutating func circleArrow(_ start: Float, _ color: ArtColor) {
        drawArc(color.shade(0.7), start, 140, false, Offset(14, 14), Size(72, 72), style: .stroke(14, cap: .round))
        drawArc(color, start, 140, false, Offset(14, 14), Size(72, 72), style: .stroke(9, cap: .round))
        let a = Double(start + 140) * Double.pi / 180
        let ca = Float(Foundation.cos(a)), sa = Float(Foundation.sin(a))
        let tip = Offset(50 + 36 * ca, 50 + 36 * sa)
        let dir = Offset(-sa, ca)
        let n = Offset(ca, sa)
        let p = ArtPath { p in
            p.moveTo(tip.x + dir.x * 14, tip.y + dir.y * 14)
            p.lineTo(tip.x + n.x * 12, tip.y + n.y * 12)
            p.lineTo(tip.x - n.x * 12, tip.y - n.y * 12)
            p.close()
        }
        drawPath(p, color)
    }

    mutating func shuffle() {
        circleArrow(200, ArtColor(0xFF66_BB6A))
        circleArrow(20, ArtColor(0xFF42_A5F5))
        car(Offset(50, 56), ArtColor(0xFF9B_5CF0), 0.45)
    }

    mutating func crane() {
        drawLine(ArtColor(0xFF45_5A64), Offset(50, 4), Offset(50, 34), 4)
        drawArc(ArtColor(0xFFFF_B300), 0, 180, false, Offset(40, 26), Size(20, 18), style: .stroke(5, cap: .round))
        car(Offset(50, 66), ArtColor(0xFF9B_5CF0), 0.82)
        let crown = ArtPath { p in
            p.moveTo(62, 84); p.lineTo(64, 70); p.lineTo(72, 78); p.lineTo(80, 66); p.lineTo(88, 78); p.lineTo(96, 70); p.lineTo(98, 84); p.close()
        }
        drawPath(crown, ArtColor(0xFFFF_D54F))
        drawPath(crown, ArtColor(0xFFF5_7F17), style: .stroke(3, join: .round))
    }

    mutating func sort() {
        let r = ArtPath { p in p.moveTo(8, 30); p.lineTo(44, 30); p.lineTo(44, 18); p.lineTo(64, 38); p.lineTo(44, 58); p.lineTo(44, 46); p.lineTo(8, 46); p.close() }
        drawPath(r, ArtColor(0xFF29_B6F6))
        drawPath(r, ArtColor(0xFF02_77BD), style: .stroke(3, join: .round))
        let l = ArtPath { p in p.moveTo(60, 62); p.lineTo(24, 62); p.lineTo(24, 50); p.lineTo(4, 70); p.lineTo(24, 90); p.lineTo(24, 78); p.lineTo(60, 78); p.close() }
        drawPath(l, ArtColor(0xFF66_BB6A))
        drawPath(l, ArtColor(0xFF2E_7D32), style: .stroke(3, join: .round))
        drawCircle(ArtColor(0xFF7E_57C2), 13, Offset(78, 38))
        drawRoundRect(ArtColor(0xFF7E_57C2), Offset(62, 54), Size(32, 36), CornerRadius(14))
        drawCircle(ArtColor.White.copy(alpha: 0.5), 4, Offset(74, 34))
    }

    mutating func ad() {
        drawRoundRect(ArtColor(0xFF0D_47A1), Offset(8, 22), Size(84, 62), CornerRadius(12))
        drawRoundRect(Brush.verticalGradient([ArtColor(0xFF64_B5F6), ArtColor(0xFF1E_88E5)]), Offset(8, 18), Size(84, 62), CornerRadius(12))
        for i in 0..<4 { drawRoundRect(ArtColor.White.copy(alpha: 0.85), Offset(16 + Float(i) * 20, 22), Size(10, 7), CornerRadius(2)) }
        let p = ArtPath { p in p.moveTo(40, 38); p.lineTo(64, 52); p.lineTo(40, 66); p.close() }
        drawPath(p, ArtColor.White)
    }

    mutating func gift() {
        drawRoundRect(ArtColor(0xFFB7_1C1C), Offset(14, 42), Size(72, 52), CornerRadius(8))
        drawRoundRect(Brush.verticalGradient([ArtColor(0xFFFF_6E6E), ArtColor(0xFFE5_3935)]), Offset(14, 40), Size(72, 50), CornerRadius(8))
        drawRoundRect(ArtColor(0xFFD3_2F2F), Offset(8, 30), Size(84, 18), CornerRadius(6))
        drawRoundRect(ArtColor(0xFFFF_7961), Offset(8, 28), Size(84, 16), CornerRadius(6))
        drawRect(ArtColor(0xFFFF_D54F), Offset(43, 28), Size(14, 62))
        drawOval(ArtColor(0xFFFF_D54F), Offset(22, 10), Size(28, 22), style: .stroke(7))
        drawOval(ArtColor(0xFFFF_D54F), Offset(50, 10), Size(28, 22), style: .stroke(7))
        drawCircle(ArtColor(0xFFFF_B300), 7, Offset(50, 28))
    }

    mutating func trophy() {
        drawArc(ArtColor(0xFFFF_B300), 90, 180, false, Offset(8, 20), Size(30, 36), style: .stroke(7))
        drawArc(ArtColor(0xFFFF_B300), -90, 180, false, Offset(62, 20), Size(30, 36), style: .stroke(7))
        let cup = ArtPath { p in p.moveTo(22, 14); p.lineTo(78, 14); p.quadraticTo(78, 62, 50, 66); p.quadraticTo(22, 62, 22, 14); p.close() }
        drawPath(cup, Brush.horizontalGradient([ArtColor(0xFFFF_E082), ArtColor(0xFFFF_C107), ArtColor(0xFFFF_8F00)], 22, 78))
        drawRect(ArtColor(0xFFFF_8F00), Offset(44, 64), Size(12, 14))
        drawRoundRect(ArtColor(0xFF8D_6E63), Offset(28, 78), Size(44, 14), CornerRadius(4))
        drawPath(starPath(50, 36, 12), ArtColor.White.copy(alpha: 0.9))
    }

    mutating func hand() {
        // A white glove pointing up-left, with a dark outline.
        let p = ArtPath { p in
            p.moveTo(30, 6)
            p.quadraticTo(38, 2, 42, 10)
            p.lineTo(46, 40)
            p.quadraticTo(52, 34, 58, 40)
            p.quadraticTo(64, 36, 70, 42)
            p.quadraticTo(78, 40, 82, 48)
            p.lineTo(86, 70)
            p.quadraticTo(88, 90, 70, 96)
            p.lineTo(46, 96)
            p.quadraticTo(36, 92, 30, 82)
            p.lineTo(16, 60)
            p.quadraticTo(14, 52, 22, 52)
            p.quadraticTo(28, 54, 32, 62)
            p.lineTo(24, 14)
            p.quadraticTo(24, 8, 30, 6)
            p.close()
        }
        drawPath(p, ArtColor(0x5500_0000), style: .stroke(10, join: .round))
        drawPath(p, Brush.verticalGradient([ArtColor.White, ArtColor(0xFFE3_E8F0)]))
        drawPath(p, ArtColor(0xFF4A_3A2A), style: .stroke(4, join: .round))
        drawLine(ArtColor(0xFF4A_3A2A), Offset(58, 41), Offset(60, 56), 3, .round)
        drawLine(ArtColor(0xFF4A_3A2A), Offset(70, 43), Offset(72, 58), 3, .round)
        drawRoundRect(ArtColor(0xFF42_A5F5), Offset(42, 88), Size(36, 10), CornerRadius(4))
    }

    mutating func heart() {
        let p = ArtPath { p in
            p.moveTo(50, 90)
            p.cubicTo(10, 62, 4, 40, 16, 24)
            p.cubicTo(28, 8, 46, 14, 50, 30)
            p.cubicTo(54, 14, 72, 8, 84, 24)
            p.cubicTo(96, 40, 90, 62, 50, 90)
            p.close()
        }
        drawPath(p, ArtColor(0xFF8E_1B1B), style: .stroke(8, join: .round))
        drawPath(p, Brush.verticalGradient([ArtColor(0xFFFF_8A80), ArtColor(0xFFF2_453D), ArtColor(0xFFC6_2828)], 10, 90))
        drawOval(ArtColor.White.copy(alpha: 0.55), Offset(22, 24), Size(18, 12))
        car(Offset(52, 56), ArtColor.White, 0.42)
        drawCircle(ArtColor(0xFF5F_C12F), 14, Offset(80, 76))
        drawLine(ArtColor.White, Offset(72, 76), Offset(88, 76), 5, .round)
        drawLine(ArtColor.White, Offset(80, 68), Offset(80, 84), 5, .round)
    }

    mutating func sad() {
        drawCircle(ArtColor(0xFFB2_6A00), 46, Offset(50, 53))
        drawCircle(Brush.radialGradient([ArtColor(0xFFFF_F59D), ArtColor(0xFFFF_CA28), ArtColor(0xFFFF_9800)], Offset(40, 36), 62), 44, Offset(50, 50))
        // squeezed eyes
        for sx: Float in [-1, 1] {
            let p = ArtPath { p in
                p.moveTo(50 + sx * 30, 34); p.lineTo(50 + sx * 14, 40); p.lineTo(50 + sx * 30, 46)
            }
            drawPath(p, ArtColor(0xFF4E_342E), style: .stroke(5, cap: .round, join: .round))
        }
        drawOval(ArtColor(0xFF6D_2E1F), Offset(32, 56), Size(36, 26))
        drawOval(ArtColor(0xFFE5_7373), Offset(40, 68), Size(20, 12))
        drawOval(ArtColor(0xFF4F_C3F7), Offset(10, 44), Size(10, 16))
        drawOval(ArtColor(0xFF4F_C3F7), Offset(80, 44), Size(10, 16))
    }
}
