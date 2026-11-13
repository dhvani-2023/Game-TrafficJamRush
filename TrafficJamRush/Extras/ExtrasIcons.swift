import SwiftUI
import GameKit

// Icons for the extras, drawn in the same 100×100 design space and chunky style as GameIcons.swift
// (Icon.UNDO and Icon.FLAME dispatch here, so they are cached and shown by GameIcon like every other icon).

extension BitmapScope {

    /// Undo booster: a fat anticlockwise arrow pulling a little car back.
    mutating func extrasUndo() {
        extrasCar(Offset(58, 76), ArtColor(0xFF2F_7CF6), 0.46)
        let c = Offset(54, 52)
        let r: Float = 30
        let start: Float = 22
        let sweep: Float = -202
        let box = Offset(c.x - r, c.y - r)
        let size = Size(2 * r, 2 * r)
        let a = Double(start + sweep) * Double.pi / 180
        let ca = Float(Foundation.cos(a)), sa = Float(Foundation.sin(a))
        let tip = Offset(c.x + r * ca, c.y + r * sa)
        // Anticlockwise travel direction at the end of the arc, and the outward normal.
        let dir = Offset(sa, -ca)
        let n = Offset(ca, sa)
        let head = ArtPath { p in
            p.moveTo(tip.x + dir.x * 19, tip.y + dir.y * 19)
            p.lineTo(tip.x + n.x * 15, tip.y + n.y * 15)
            p.lineTo(tip.x - n.x * 15, tip.y - n.y * 15)
            p.close()
        }
        let dark = ArtColor(0xFFB3_4700)
        let face = Brush.verticalGradient([ArtColor(0xFFFF_E082), ArtColor(0xFFFF_B300), ArtColor(0xFFFF_8F00)], 18, 86)
        drawArc(dark, start, sweep, false, box, size, style: .stroke(19, cap: .round))
        drawPath(head, dark, style: .stroke(7, join: .round))
        drawPath(head, dark)
        drawArc(face, start, sweep, false, box, size, style: .stroke(11, cap: .round))
        drawPath(head, face)
        // Gloss along the top of the arc.
        drawArc(ArtColor.White.copy(alpha: 0.45), -150, 70, false, Offset(c.x - r + 2, c.y - r + 2), Size(2 * r - 4, 2 * r - 4),
                style: .stroke(3, cap: .round))
    }

    /// Streak flame.
    mutating func extrasFlame() {
        let outer = ArtPath { p in
            p.moveTo(52, 4)
            p.cubicTo(66, 24, 88, 38, 84, 64)
            p.cubicTo(81, 86, 66, 96, 50, 96)
            p.cubicTo(32, 96, 16, 85, 16, 64)
            p.cubicTo(16, 48, 28, 40, 33, 24)
            p.cubicTo(38, 34, 42, 39, 47, 41)
            p.cubicTo(44, 27, 46, 15, 52, 4)
            p.close()
        }
        drawPath(outer, ArtColor(0xFF8E_1B1B), style: .stroke(8, join: .round))
        drawPath(outer, Brush.verticalGradient([ArtColor(0xFFFF_D54F), ArtColor(0xFFFF_7043), ArtColor(0xFFE5_3935)], 8, 96))
        let inner = ArtPath { p in
            p.moveTo(51, 44)
            p.cubicTo(60, 57, 69, 63, 67, 76)
            p.cubicTo(65, 88, 57, 92, 50, 92)
            p.cubicTo(41, 92, 33, 86, 33, 76)
            p.cubicTo(33, 65, 44, 59, 51, 44)
            p.close()
        }
        drawPath(inner, Brush.verticalGradient([ArtColor(0xFFFF_FDE7), ArtColor(0xFFFF_E082), ArtColor(0xFFFF_C107)], 44, 92))
        drawOval(ArtColor.White.copy(alpha: 0.5), Offset(26, 50), Size(9, 18))
    }

    /// The menu car of GameIcons (same outline), for the extras' icons.
    mutating func extrasCar(_ c: Offset, _ color: ArtColor, _ k: Float = 1) {
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
}

/// A desk-calendar page showing [day] (month band + date), for the Daily Puzzle card. Drawn live so the date is
/// always today's.
struct ExtrasCalendarBadge: View {
    let day: ExtrasDay
    var size: CGFloat = 50

    var body: some View {
        let w = size
        let h = size * 1.06
        let band = h * 0.32
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: w * 0.2, style: .continuous)
                .fill(Color(argb: 0xFF8E_1B1B))
                .offset(y: 3)
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: [Color(argb: 0xFFFF_6E6E), Color(argb: 0xFFE5_3935)], startPoint: .top, endPoint: .bottom)
                    GText(day.monthBadge, .Small, color: .white, size: w * 0.22, titleFont: true)
                        .offset(y: 1)
                }
                .frame(height: band)
                ZStack {
                    LinearGradient(colors: [.white, Color(argb: 0xFFFF_F3DA)], startPoint: .top, endPoint: .bottom)
                    GText("\(day.dayOfMonth)", .Title, color: Color(argb: 0xFF3E_2723), size: w * 0.46, titleFont: true)
                        .offset(y: -1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: w * 0.2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: w * 0.2, style: .continuous).strokeBorder(Color.white, lineWidth: 2))
            // Binder rings
            HStack(spacing: w * 0.3) {
                Capsule().fill(Color(argb: 0xFF37_474F)).frame(width: w * 0.09, height: band * 0.55)
                Capsule().fill(Color(argb: 0xFF37_474F)).frame(width: w * 0.09, height: band * 0.55)
            }
            .offset(y: -band * 0.18)
        }
        .frame(width: w, height: h)
        .accessibilityElement()
        .accessibilityLabel(day.label)
    }
}
