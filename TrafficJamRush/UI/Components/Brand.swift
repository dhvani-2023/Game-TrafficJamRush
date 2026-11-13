import SwiftUI
import GameKit

// Port of ui/components/Brand.kt: the logo, Coney the traffic-cone mascot, menu vehicle sprites
// and the rotating sun rays.

/// Compose `FastOutSlowInEasing` (cubic-bezier 0.4, 0, 0.2, 1).
private func fastOutSlowIn(_ t: Double) -> Double {
    if t <= 0 { return 0 }
    if t >= 1 { return 1 }
    func bez(_ u: Double, _ a: Double, _ b: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }
    var lo = 0.0, hi = 1.0, u = t
    for _ in 0..<24 {
        let x = bez(u, 0.4, 0.2)
        if abs(x - t) < 1e-6 { break }
        if x < t { lo = u } else { hi = u }
        u = (lo + hi) / 2
    }
    return bez(u, 0, 1)
}

/// `infiniteRepeatable(tween(ms), RepeatMode.Reverse)` from 0 to 1, sampled at [elapsed] seconds.
private func pingPong(_ elapsed: Double, _ seconds: Double) -> Double {
    let cycles = max(0, elapsed) / seconds
    let k = cycles.rounded(.down)
    var f = cycles - k
    if Int(k) % 2 == 1 { f = 1 - f }
    return fastOutSlowIn(f)
}

/// "TRAFFIC JAM RUSH" stacked logo with a gentle idle wobble.
struct GameLogo: View {
    var scale: CGFloat = 1
    @State private var wobble = false

    init(scale: CGFloat = 1) { self.scale = scale }

    var body: some View {
        VStack(spacing: 0) {
            OutlinedText("TRAFFIC", style: GameText.Display, color: Color(argb: 0xFFFF_E14D), outline: Color(argb: 0xFF7A_3B00),
                         strokeWidth: 14, fontSize: 40)
                .fixedSize()
            OutlinedText("JAM", style: GameText.Display, color: Color(argb: 0xFFFF_8A1F), outline: Color(argb: 0xFF6B_2300),
                         strokeWidth: 18, fontSize: 72)
                .fixedSize()
                .offset(y: -14)
            OutlinedText("RUSH", style: GameText.Display, color: .white, outline: Color(argb: 0xFF7F_0000), strokeWidth: 10, fontSize: 36)
                .fixedSize()
                .offset(y: -2)
                .padding(.horizontal, 22)
                .background {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 14, style: .circular).fill(Color(argb: 0xFF8E_1B1B)).offset(y: 5)
                        RoundedRectangle(cornerRadius: 14, style: .circular)
                            .fill(LinearGradient(colors: [Color(argb: 0xFFFF_6E6E), Color(argb: 0xFFE5_3935)], startPoint: .top, endPoint: .bottom))
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 4, style: .circular).fill(Color.white.opacity(0.3))
                                .frame(width: max(0, g.size.width - 20), height: 8)
                                .offset(x: 10, y: 4)
                        }
                    }
                }
                .rotationEffect(.degrees(-4))
                .offset(y: -26)
        }
        .rotationEffect(.degrees(Motion.reduce ? 0 : (wobble ? 1.5 : -1.5)))
        .scaleEffect(scale)
        .onAppear {
            guard !Motion.reduce else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.8).repeatForever(autoreverses: true)) { wobble = true }
        }
    }
}

/// Coney, the traffic-cone mascot.
struct Mascot: View {
    let size: CGFloat
    @State private var start = Date()

    init(_ size: CGFloat) { self.size = size }

    var body: some View {
        let reduce = Motion.reduce
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduce)) { tl in
            let t = reduce ? 0 : tl.date.timeIntervalSince(start)
            Canvas { ctx, sz in
                let blink = (t / 3.2).truncatingRemainder(dividingBy: 1)
                let bounce = reduce ? 0 : pingPong(t, 0.9)
                var s = FrameScope(ctx, sz.asSize)
                Mascot.draw(&s, Float(min(sz.width, sz.height)) / 100, eyesOpen: blink < 0.95, bounce: Float(bounce))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func draw(_ d: inout FrameScope, _ s: Float, eyesOpen: Bool, bounce: Float) {
        let by = -bounce * 2 * s
        // base
        d.drawRoundRect(ArtColor(0xFF26_3238), Offset(14 * s, 82 * s), Size(72 * s, 12 * s), CornerRadius(5 * s))
        let cone = ArtPath { p in
            p.moveTo(44 * s, 8 * s + by)
            p.quadraticTo(50 * s, 2 * s + by, 56 * s, 8 * s + by)
            p.lineTo(78 * s, 84 * s)
            p.lineTo(22 * s, 84 * s)
            p.close()
        }
        d.drawPath(cone, Brush.horizontalGradient([ArtColor(0xFFFF_A040), ArtColor(0xFFFF_7A00), ArtColor(0xFFE6_5100)], 22 * s, 78 * s))
        d.drawPath(cone, ArtColor(0xFF8A_2E00), style: .stroke(3 * s))
        // stripes
        d.drawRect(ArtColor.White, Offset(34 * s, 30 * s + by * 0.6), Size(32 * s, 8 * s))
        d.drawRect(ArtColor.White, Offset(27 * s, 60 * s), Size(46 * s, 8 * s))
        // face
        let ey = 46 * s + by * 0.5
        if eyesOpen {
            d.drawCircle(ArtColor.White, 6 * s, Offset(42 * s, ey))
            d.drawCircle(ArtColor.White, 6 * s, Offset(58 * s, ey))
            d.drawCircle(ArtColor(0xFF26_3238), 3.4 * s, Offset(43 * s, ey + 0.5 * s))
            d.drawCircle(ArtColor(0xFF26_3238), 3.4 * s, Offset(59 * s, ey + 0.5 * s))
            d.drawCircle(ArtColor.White, 1.2 * s, Offset(44 * s, ey - 1 * s))
            d.drawCircle(ArtColor.White, 1.2 * s, Offset(60 * s, ey - 1 * s))
        } else {
            d.drawLine(ArtColor(0xFF26_3238), Offset(37 * s, ey), Offset(47 * s, ey), 2.5 * s, .round)
            d.drawLine(ArtColor(0xFF26_3238), Offset(53 * s, ey), Offset(63 * s, ey), 2.5 * s, .round)
        }
        d.drawArc(ArtColor(0xFF6D_1B00), 10, 160, false, Offset(43 * s, ey + 3 * s), Size(14 * s, 9 * s), style: .stroke(2.6 * s, cap: .round))
        d.drawCircle(ArtColor(0x66FF_5252), 3.5 * s, Offset(35 * s, ey + 6 * s))
        d.drawCircle(ArtColor(0x66FF_5252), 3.5 * s, Offset(65 * s, ey + 6 * s))
        d.drawOval(ArtColor.White.copy(alpha: 0.4), Offset(40 * s, 12 * s + by), Size(6 * s, 14 * s))
    }
}

/// Mascot inside a framed avatar tile.
struct AvatarTile: View {
    let size: CGFloat

    init(_ size: CGFloat) { self.size = size }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .circular).fill(Color(argb: 0xFF0D_47A1)).offset(y: 3)
            RoundedRectangle(cornerRadius: 14, style: .circular).fill(Color.white)
            RoundedRectangle(cornerRadius: 11, style: .circular)
                .fill(LinearGradient(colors: [Color(argb: 0xFF81_D4FA), Color(argb: 0xFF29_B6F6)], startPoint: .top, endPoint: .bottom))
                .padding(3)
            Mascot(size * 0.84)
        }
        .frame(width: size, height: size)
    }
}

/// Shared art caches for menu sprites, keyed by pixel unit and skin.
enum MenuArt {
    private struct Key: Hashable {
        let unitPx: Int
        let skin: Skin
    }

    private static var cache: [Key: VehicleArt] = [:]

    @MainActor static func get(_ unit: CGFloat, _ skin: Skin) -> VehicleArt {
        let k = Art.scale
        let unitPx = Int((Float(unit) * k).rounded())
        let key = Key(unitPx: unitPx, skin: skin)
        if let a = cache[key] { return a }
        let a = VehicleArt(Float(unitPx) / k, skin)
        cache[key] = a
        return a
    }

    /// Kotlin GarageTab `Skin.previewColor()` (the pack cards' sprite colours).
    static func previewColor(_ skin: Skin) -> Int {
        switch skin {
        case .TAXI, .GOLDEN: return JamColor.YELLOW.ordinal
        case .CANDY: return JamColor.PINK.ordinal
        case .RACING: return JamColor.RED.ordinal
        case .SAFARI: return JamColor.GREEN.ordinal
        case .NEON: return JamColor.CYAN.ordinal
        case .GALAXY: return JamColor.PURPLE.ordinal
        case .RETRO: return JamColor.CYAN.ordinal
        case .TOY: return JamColor.ORANGE.ordinal
        default: return JamColor.BLUE.ordinal
        }
    }

    /// Builds every menu sprite's slice stack on a background queue (call once during the splash),
    /// so the splash, home, onboarding and garage cards never build sprites on the main thread.
    @MainActor static func prewarm() {
        var list: [(VehicleType, Int, Skin, CGFloat)] = [
            // Splash
            (.BUS, JamColor.YELLOW.ordinal, .CLASSIC, 13), (.CAR, JamColor.RED.ordinal, .CLASSIC, 13),
            // Home road
            (.VAN, JamColor.GREEN.ordinal, .CLASSIC, 11), (.BUS, JamColor.BLUE.ordinal, .CLASSIC, 11), (.CAR, JamColor.PINK.ordinal, .CLASSIC, 11),
            // Onboarding
            (.BUS, JamColor.BLUE.ordinal, .CLASSIC, 22), (.VAN, JamColor.GREEN.ordinal, .CLASSIC, 22), (.CAR, JamColor.RED.ordinal, .CLASSIC, 22),
            (.VAN, JamColor.BLUE.ordinal, .CLASSIC, 22),
            (.CAR, JamColor.RED.ordinal, .CLASSIC, 12), (.VAN, JamColor.GREEN.ordinal, .CLASSIC, 12), (.BUS, JamColor.YELLOW.ordinal, .CLASSIC, 12),
        ]
        for c in [JamColor.RED, .YELLOW, .PURPLE, .GREEN] { list.append((.CAR, c.ordinal, .CLASSIC, 13)) }
        // Garage pack cards
        for skin in Skin.allCases {
            let pc = previewColor(skin)
            list.append((.VAN, (pc + 3) % 8, skin, 12))
            list.append((.CAR, pc, skin, 16))
        }
        for (type, color, skin, unit) in list {
            _ = get(unit, skin).stackIfReady(type, color, false)
        }
    }
}

/// A 3D vehicle rendered with the in-game sprite stack, for menus. [rotation] is clockwise from north.
/// The slices are stacked straight into the view at the exact angle (same look as Android's cached
/// sprite, with no rotation pass on the main thread). The view has the size of Android's sprite
/// bitmap, so layouts around it match.
struct VehicleSprite: View {
    let type: VehicleType
    let color: Int
    let skin: Skin
    let unit: CGFloat
    var rotation: Float = 0

    init(_ type: VehicleType, _ color: Int, _ skin: Skin, _ unit: CGFloat, rotation: Float = 0) {
        self.type = type
        self.color = color
        self.skin = skin
        self.unit = unit
        self.rotation = rotation
    }

    var body: some View {
        let art = MenuArt.get(unit, skin)
        let slices = art.stack(type, color, false)
        let shadow = art.shadow(type)
        let frame = art.androidFrame(type, color)
        let rotation = rotation
        let type = type
        Canvas { ctx, _ in
            // Android ground point inside its (diagonal-square) bitmap.
            let gx = CGFloat(frame.groundX)
            let gy = CGFloat(frame.groundY)
            var sg = ctx
            sg.translateBy(x: gx + CGFloat(art.unit * 0.22), y: gy + CGFloat(art.unit * 0.36))
            sg.rotate(by: .degrees(Double(rotation)))
            sg.draw(shadow.image, in: CGRect(x: -CGFloat(shadow.width) / 2, y: -CGFloat(shadow.height) / 2,
                                             width: CGFloat(shadow.width), height: CGFloat(shadow.height)))
            var cg = ctx
            art.drawSlices(&cg, slices, type, rotation, Offset(frame.groundX, frame.groundY))
        }
        .frame(width: CGFloat(frame.width), height: CGFloat(frame.height))
        .accessibilityHidden(true)
    }
}

/// Slowly turning sun rays behind titles.
struct SunRays: View {
    var color: Color = Color(argb: 0x55FF_FFFF)
    @State private var start = Date()

    init(color: Color = Color(argb: 0x55FF_FFFF)) { self.color = color }

    var body: some View {
        let reduce = Motion.reduce
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { tl in
            let t = reduce ? 0 : tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let r = (t / 30).truncatingRemainder(dividingBy: 1) * 360
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let m = max(size.width, size.height)
                var wedge = Path()
                wedge.move(to: c)
                wedge.addLine(to: CGPoint(x: c.x + m, y: c.y - m * 0.12))
                wedge.addLine(to: CGPoint(x: c.x + m, y: c.y + m * 0.12))
                wedge.closeSubpath()
                let shading = GraphicsContext.Shading.radialGradient(Gradient(colors: [color, Color(argb: 0x0000_0000)]),
                                                                     center: c, startRadius: 0, endRadius: m * 0.6)
                for i in 0..<16 {
                    var g = ctx
                    g.translateBy(x: c.x, y: c.y)
                    g.rotate(by: .degrees(r + Double(i) * 22.5))
                    g.translateBy(x: -c.x, y: -c.y)
                    g.fill(wedge, with: shading)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
