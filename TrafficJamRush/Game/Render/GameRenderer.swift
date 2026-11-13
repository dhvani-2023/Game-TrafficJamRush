import SwiftUI
import CoreText
import GameKit

// Port of game/render/GameRenderer.kt. Draws one frame of a level into a SwiftUI Canvas
// (`Canvas { ctx, size in GameRenderer.drawGame(&ctx, engine, time) }`), in layout points.
// The frame allocates nothing in steady state: sprites, gradients and labels are cached, and
// sort buffers are reused.

@MainActor
enum GameRenderer {

    private enum Layer { case SHADOW, BODY }

    private static var lotScratch: [Vehicle] = []
    private static var movingScratch: [Vehicle] = []
    private static var seatGradients: [GradientData?] = Array(repeating: nil, count: 8)
    private static let lockGradient = GradientData([ArtColor(0xFF9C_E65C), ArtColor(0xFF4C_AF50)])
    private static var adLabel: (u: Float, text: String, img: ImageBitmap)?

    static func drawGame(_ ctx: inout GraphicsContext, _ e: GameEngine, _ timeSec: Float) {
        guard let scene = e.scene, let lay = e.layout, let art = e.art, let pa = e.passengerArt else { return }
        let u = lay.u
        var s = FrameScope(ctx, Size(lay.width, lay.height))
        let shake = e.screenShake
        s.translate(shake.x, shake.y) { s in
            s.drawImage(scene)
            SceneAmbient.draw(&s, lay, e.theme, timeSec)

            // Locked slots and VIP highlight
            for i in 0..<SLOT_COUNT where !e.slots[i].open { lockedSlot(&s, lay, i, timeSec) }
            if e.craneArmed {
                let r = lay.slotRect(VIP_SLOT)
                let a = 0.4 + 0.3 * Kt.sin(timeSec * 8)
                s.drawRoundRect(ArtColor(0xFFFF_D54F), r.topLeft, r.size, CornerRadius(6 * u), alpha: a, style: .stroke(4 * u))
            }

            drawQueue(&s, e, lay, pa, timeSec)

            // Shadows first so no vehicle's shadow falls on another's roof.
            for v in e.vehicles where v.state != .GONE { vehicle(&s, e, art, v, .SHADOW) }

            lotScratch.removeAll(keepingCapacity: true)
            for v in e.vehicles where v.state == .LOT { lotScratch.append(v) }
            sortByY(&lotScratch)
            for v in lotScratch { vehicle(&s, e, art, v, .BODY) }
            if e.craneArmed {
                let a = 0.35 + 0.25 * Kt.sin(timeSec * 9)
                for v in lotScratch {
                    s.drawCircle(ArtColor(0xFFFF_E066), art.bodyW() * 0.55, v.pos, alpha: a, style: .stroke(2.5 * u))
                }
            }

            for v in e.vehicles where v.inSlot { vehicle(&s, e, art, v, .BODY) }
            movingScratch.removeAll(keepingCapacity: true)
            for v in e.vehicles where v.state == .EXITING || (v.state == .DEPARTING && v.departPhase == 1) { movingScratch.append(v) }
            sortByY(&movingScratch)
            for v in movingScratch { vehicle(&s, e, art, v, .BODY) }
            for v in e.vehicles where v.state == .CRANE {
                s.drawLine(ArtColor(0xFF45_5A64), Offset(v.pos.x, -10 * Art.px), v.pos - Offset(0, 6 * u), 2.5 * u, .round)
                s.drawCircle(ArtColor(0xFFFF_C107), 5 * u, v.pos - Offset(0, 6 * u))
                vehicle(&s, e, art, v, .BODY)
            }

            // Walkers hop into vehicles
            let pw = pa.w
            let ph = pa.h
            for w in e.walkers {
                let p = e.walkerPos(w)
                let sc = 1 - w.t * 0.35
                s.withTransform({ t in t.scale(sc, sc, p) }) { s in
                    s.drawImage(pa.get(w.color, Kt.toInt(w.t * 8) % 4), Offset(p.x - pw / 2, p.y - ph))
                }
            }

            e.particles?.draw(&s.ctx)
        }
    }

    /// Stable insertion sort by screen y (Kotlin `sortedBy { it.pos.y }`), in place.
    private static func sortByY(_ a: inout [Vehicle]) {
        if a.count < 2 { return }
        for i in 1..<a.count {
            let v = a[i]
            var j = i - 1
            while j >= 0 && a[j].pos.y > v.pos.y {
                a[j + 1] = a[j]
                j -= 1
            }
            a[j + 1] = v
        }
    }

    private static func vehicle(_ s: inout FrameScope, _ e: GameEngine, _ art: VehicleArt, _ v: Vehicle, _ layer: Layer) {
        let unit = e.layout.unit
        let pop: Float = v.popT >= 1 ? 1 : easeOutBack(v.popT)
        if pop <= 0.01 { return }
        let bounce: Float = v.bounceT >= 0 ? 1 + 0.07 * Kt.sin(v.bounceT * Float.pi) : 1
        let flip: Float = v.flipT >= 0 ? max(0.08, abs(Kt.cos(v.flipT * Float.pi))) : 1
        let shake: Float = v.shakeT >= 0 ? Kt.sin(v.shakeT * 38) * 6 * (1 - v.shakeT) : 0
        let sc = v.scale * pop * bounce
        let lift = v.lift
        if layer == .SHADOW {
            let bmp = art.shadow(v.type)
            let c = v.pos + Offset(unit * 0.22, unit * 0.36) * sc * (1 + lift * 3)
            s.withTransform({ t in
                t.translate(c.x, c.y)
                t.rotate(v.heading + shake, .Zero)
                t.scale(sc * flip * (1 + lift * 0.2), sc * (1 + lift * 0.2), .Zero)
            }) { s in
                s.drawImage(bmp, Offset(-bmp.width / 2, -bmp.height / 2), alpha: 1 - lift * 0.55)
            }
            return
        }
        let angle = v.heading + shake
        let raise = lift * 26 * e.layout.u
        let roofZ: Float
        // Vehicles holding a fixed heading use the cached 3D sprite; moving ones (and any whose sprite
        // is still being built) are stacked slice by slice, which looks the same at any angle.
        let steady = v.shakeT < 0 && (v.state == .LOT || v.state == .PARKED || (v.state == .DEPARTING && v.departPhase == 0))
        if steady, let comp = art.composite(v.type, v.color, v.mystery, angle) {
            s.withTransform({ t in
                t.translate(v.pos.x, v.pos.y - raise)
                t.rotate(art.residual(angle), .Zero)
                t.scale(sc * flip, sc, .Zero)
            }) { s in
                s.drawImage(comp.bitmap, Offset(-comp.groundX, -comp.groundY))
            }
            roofZ = comp.roofZ
        } else if let slices = art.stackIfReady(v.type, v.color, v.mystery) {
            s.withTransform({ t in
                t.translate(v.pos.x, v.pos.y - raise)
                t.scale(sc * flip, sc, .Zero)
            }) { s in
                art.drawSlices(&s.ctx, slices, v.type, angle, .Zero)
            }
            roofZ = art.roofZ(v.type)
        } else {
            return
        }
        if v.mystery && v.state == .LOT {
            // Upright "?" badge so it reads correctly whatever way the vehicle faces.
            let badge = art.mysteryBadge()
            let c = Offset(v.pos.x, v.pos.y - raise - roofZ * sc)
            let bw = badge.width * sc
            let bh = badge.height * sc
            s.image(badge, CGRect(x: CGFloat(c.x - bw / 2), y: CGFloat(c.y - bh / 2), width: CGFloat(bw), height: CGFloat(bh)), 1)
        }
        if v.inSlot || v.state == .DEPARTING {
            s.withTransform({ t in
                t.translate(v.pos.x, v.pos.y - raise - roofZ * sc)
                t.rotate(v.heading, .Zero)
                t.scale(sc, sc, .Zero)
            }) { s in
                seats(&s, art, v)
            }
        }
    }

    private static func seatGradient(_ color: Int) -> GradientData {
        if let g = seatGradients[color] { return g }
        let col = jamArtColor(color)
        let g = GradientData([col.tint(0.5), col, col.shade(0.8)])
        seatGradients[color] = g
        return g
    }

    private static var seatShades: [ArtColor?] = Array(repeating: nil, count: 8)

    /// Little passenger heads poking out of the roof of a parked vehicle.
    private static func seats(_ s: inout FrameScope, _ art: VehicleArt, _ v: Vehicle) {
        let roof = art.roofRect(v.type)
        let rowsN = v.seats / 2
        let step = roof.height * 0.9 / Float(rowsN)
        let r = min(roof.width * 0.24, step * 0.44)
        let shade: ArtColor
        if let sh = seatShades[v.color] {
            shade = sh
        } else {
            shade = jamArtColor(v.color).shade(0.55)
            seatShades[v.color] = shade
        }
        let grad = seatGradient(v.color)
        let startY = roof.top + roof.height * 0.05 + step / 2
        let px = Art.px
        for i in 0..<v.seats {
            let cx = i % 2 == 0 ? -roof.width * 0.24 : roof.width * 0.24
            let c = Offset(cx, startY + Float(i / 2) * step)
            if i < v.filled {
                s.drawCircle(shade, r + 1 * px, c + Offset(0, 1 * px))
                s.drawCircle(Brush.radial(grad, c - Offset(r * 0.4, r * 0.4), r * 1.5), r, c)
                s.drawCircle(ArtColor.White, r * 0.25, c - Offset(r * 0.38, r * 0.38), alpha: 0.7)
            } else {
                s.drawCircle(ArtColor.Black, r * 0.75, c, alpha: 0.22)
            }
        }
    }

    private static func drawQueue(_ s: inout FrameScope, _ e: GameEngine, _ lay: GameLayout, _ pa: PassengerArt, _ time: Float) {
        let pw = pa.w
        let ph = pa.h
        let visible = Kt.toInt(lay.queueVisibleLength / lay.passengerSpacing) + 1
        let last = min(e.queue.count - 1, e.qHead + visible)
        if last < e.qHead { return }
        let px = Art.px
        for i in stride(from: last, through: e.qHead, by: -1) {
            let sv = e.qS[i]
            if sv > lay.queueVisibleLength + 4 * px { continue }
            let p = lay.queuePoint(sv)
            let target = Float(i - e.qHead) * lay.passengerSpacing
            let walking = sv - target > 1 * px
            let bob: Float = walking ? 0 : Kt.sin(time * 3 + Float(i) * 0.7) * 0.6 * lay.u
            s.drawOval(ArtColor.Black, Offset(p.x - pw * 0.42, p.y - ph * 0.08), Size(pw * 0.84, ph * 0.18), alpha: 0.18)
            let frame = walking ? (Kt.toInt(time * 9) + i) % 4 : 4
            s.drawImage(pa.get(e.queue[i], frame), Offset(p.x - pw / 2, p.y - ph - bob))
        }
    }

    /// "AD" on the barrier sign; "FREE" while rewarded ads grant instantly (no real ad network).
    private static func lockLabel(_ u: Float) -> ImageBitmap {
        let text = Ads.usesRealAds ? "AD" : "FREE"
        if let l = adLabel, l.u == u, l.text == text { return l.img }
        let k = Art.scale
        let w = 26 * u * k
        let h = 14 * u * k
        let img = renderBitmap(Kt.toInt(w.rounded(.up)), Kt.toInt(h.rounded(.up)), scale: k) { s in
            // Kotlin: 10u bold, centred, baseline 2.6u below the badge centre (badge top = centre − 8u).
            var size = 10 * u * k
            let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, CGFloat(size), nil)
            if let font {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                ]))
                let tw = Float(CTLineGetTypographicBounds(line, nil, nil, nil))
                let maxW = 23 * u * k
                if tw > maxW { size *= maxW / tw }
            }
            s.drawText(text, w / 2, 8 * u * k + 2.6 * u * k, size, ArtColor.White)
        }
        adLabel = (u, text, img)
        return img
    }

    private static func lockedSlot(_ s: inout FrameScope, _ lay: GameLayout, _ i: Int, _ time: Float) {
        let u = lay.u
        let r = lay.slotRect(i)
        s.drawRoundRect(ArtColor(0xFF3C_4250), r.topLeft + Offset(1.5 * u, 0), Size(r.width - 3 * u, r.height), CornerRadius(3 * u), alpha: 0.5)
        // Striped barrier arm across the stall
        let by = r.top + r.height * 0.62
        let bh = 6 * u
        s.drawRect(ArtColor.Black, Offset(r.left, by + 2 * u), Size(r.width, bh), alpha: 0.25)
        var x = r.left
        var k = 0
        while x < r.right {
            let wdt = min(6 * u, r.right - x)
            s.drawRect(k % 2 == 0 ? ArtColor(0xFFFF_C107) : ArtColor(0xFF26_3238), Offset(x, by), Size(wdt, bh))
            x += 6 * u
            k += 1
        }
        s.drawCircle(ArtColor(0xFFE5_3935), 2.2 * u, Offset(r.left + 3 * u, by + bh / 2))
        let c = Offset(r.center.x, r.top + 18 * u)
        let pulse = 1 + 0.08 * Kt.sin(time * 5 + Float(i))
        s.drawCircle(ArtColor(0xFF2E_7D32), 11 * u * pulse, c + Offset(0, 1.5 * u))
        s.drawCircle(Brush.linear(lockGradient, Offset(0, c.y - 11 * u), Offset(0, c.y + 11 * u)), 11 * u * pulse, c)
        s.drawLine(ArtColor.White, c - Offset(5.5 * u, 0), c + Offset(5.5 * u, 0), 3 * u, .round)
        s.drawLine(ArtColor.White, c - Offset(0, 5.5 * u), c + Offset(0, 5.5 * u), 3 * u, .round)
        let b = Offset(r.center.x, r.top + 38 * u)
        s.drawRoundRect(ArtColor(0xFFE6_5100), b - Offset(13 * u, 7 * u), Size(26 * u, 15 * u), CornerRadius(4 * u))
        s.drawRoundRect(ArtColor(0xFFFF_B300), b - Offset(13 * u, 8 * u), Size(26 * u, 14 * u), CornerRadius(4 * u))
        s.drawImage(lockLabel(u), b - Offset(13 * u, 8 * u))
    }

    private static func easeOutBack(_ t: Float) -> Float {
        let c1: Float = 1.70158
        let c3 = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }
}
