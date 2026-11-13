import SwiftUI
import GameKit

/// Accent used for each pack's card so the grid reads as distinct collections.
fileprivate extension Skin {
    func accent() -> ArtColor {
        switch self {
        case .CLASSIC: return ArtColor(0xFF2F8CF6)
        case .CANDY: return ArtColor(0xFFFF6FB5)
        case .RETRO: return ArtColor(0xFF26A69A)
        case .TAXI: return ArtColor(0xFFFFB300)
        case .RACING: return ArtColor(0xFFE53935)
        case .SAFARI: return ArtColor(0xFF7CB342)
        case .CHROME: return ArtColor(0xFF78909C)
        case .TOY: return ArtColor(0xFFFF8A1F)
        case .NEON: return ArtColor(0xFFAA00FF)
        case .GALAXY: return ArtColor(0xFF3D2C8D)
        case .GOLDEN: return ArtColor(0xFFFFA000)
        }
    }

    func previewColor() -> Int {
        let c: JamColor
        switch self {
        case .TAXI, .GOLDEN: c = .YELLOW
        case .CANDY: c = .PINK
        case .RACING: c = .RED
        case .SAFARI: c = .GREEN
        case .NEON: c = .CYAN
        case .GALAXY: c = .PURPLE
        case .RETRO: c = .CYAN
        case .TOY: c = .ORANGE
        default: c = .BLUE
        }
        return c.ordinal
    }
}

struct GarageTab: View {
    let player: PlayerState

    @State private var previewId: String
    @State private var type: VehicleType = .BUS
    @State private var color: Int

    init(player: PlayerState) {
        self.player = player
        let equipped = Skin.of(player.skin)
        _previewId = State(initialValue: equipped.id)
        _color = State(initialValue: equipped.previewColor())
    }

    private var progress: ProgressRepository { App.container.progress }
    private var audio: AudioManager { App.container.audio }

    var body: some View {
        let equipped = Skin.of(player.skin)
        let preview = Skin.of(previewId)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    TabHeader(title: "Garage", subtitle: "\(player.ownedSkins.count) of \(Skin.allCases.count) paint packs owned")
                    Showroom(skin: preview, type: type, color: color, coins: player.coins)
                    HStack(spacing: 8) {
                        ForEach(VehicleType.allCases, id: \.self) { t in
                            let sel = t == type
                            Button {
                                audio.play(Sfx.Click)
                                type = t
                            } label: {
                                GText(t.name.lowercased().capitalized, .Label,
                                      color: sel ? .white : Color(argb: 0xFF1A3A6B), size: 15, titleFont: true)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(sel ? Color(argb: 0xFFFF8A1F) : Color.white, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(sel ? Color(argb: 0xFFB34700) : Color(argb: 0xFFBFD3EE), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    HStack(spacing: 0) {
                        ForEach(JamColor.allCases, id: \.self) { c in
                            let sel = c.ordinal == color
                            let base = ArtColor(c.hex)
                            if c != JamColor.allCases.first { Spacer(minLength: 0) }
                            Button {
                                audio.play(Sfx.Click)
                                color = c.ordinal
                            } label: {
                                Circle()
                                    .fill(LinearGradient(colors: [base.tint(0.3).color, base.color], startPoint: .top, endPoint: .bottom))
                                    .overlay(Circle().strokeBorder(sel ? Color.white : Color(argb: 0x55000000), lineWidth: sel ? 3 : 2))
                                    .frame(width: sel ? 34 : 28, height: sel ? 34 : 28)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: 34)
                    .padding(.horizontal, 14)
                    Spacer().frame(height: 12)
                    SkinActions(
                        skin: preview, equipped: equipped, player: player,
                        onBuy: {
                            if progress.spendCoins(preview.price) {
                                audio.play(Sfx.Unlock)
                                progress.buySkin(preview.id)
                            } else {
                                audio.play(Sfx.Warning)
                            }
                        },
                        onAd: {
                            let id = preview.id
                            App.container.ads.showRewarded("skin_\(id)", onReward: { progress.buySkin(id) })
                        },
                        onEquip: {
                            audio.play(Sfx.Unlock)
                            progress.selectSkin(preview.id)
                        }
                    )
                    Spacer().frame(height: 10)
                    GText("PAINT PACKS", .Label, color: .white, size: 18, titleFont: true)
                        .padding(.leading, 16)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Skin.allCases, id: \.self) { skin in
                        PackCard(
                            skin: skin,
                            owned: player.ownedSkins.contains(skin.id),
                            equipped: skin == equipped,
                            previewing: skin == preview
                        ) {
                            audio.play(Sfx.Click)
                            previewId = skin.id
                            color = skin.previewColor()
                        }
                        .padding(.leading, skinOrdinal(skin) % 2 == 0 ? 14 : 0)
                        .padding(.trailing, skinOrdinal(skin) % 2 == 1 ? 14 : 0)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }
}

private func skinOrdinal(_ s: Skin) -> Int { Skin.allCases.firstIndex(of: s) ?? 0 }

/// Holds the turntable's sprite art so it is rebuilt only when the skin or vehicle size changes.
@MainActor
private final class ShowroomArt {
    private var key: String = ""
    private var art: VehicleArt?

    func get(_ unit: Float, _ skin: Skin) -> VehicleArt {
        let k = "\(skin.id)/\(unit)"
        if let a = art, k == key { return a }
        let a = VehicleArt(unit, skin)
        art = a
        key = k
        return a
    }
}

private struct Showroom: View {
    let skin: Skin
    let type: VehicleType
    let color: Int
    let coins: Int

    @State private var clock = LoopClock()
    @State private var popStart = Date()
    @State private var artHolder = ShowroomArt()

    var body: some View {
        let accent = skin.accent()
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [accent.shade(0.45).color, Color(argb: 0xFF1B2440), Color(argb: 0xFF111827)], startPoint: .top, endPoint: .bottom)
            TimelineView(.animation) { tl in
                let t = clock.elapsed(tl.date)
                let angle = Float(infiniteFloat(t, 0, 360, ms: 9000, linear: true))
                let glow = Float(infiniteFloat(t, 0.4, 1, ms: 900, reverse: true))
                // pop.snapTo(0.85f); pop.animateTo(1f, spring(dampingRatio = 0.45f, stiffness = 500f))
                let pop = Float(springValue(tl.date.timeIntervalSince(popStart), from: 0.85, to: 1, dampingRatio: 0.45, stiffness: 500))
                let unitPx: Float = type == .BUS ? 27 : 33
                let art = artHolder.get(unitPx, skin)
                Canvas { ctx, size in
                    Showroom.draw(&ctx, size, skin: skin, accent: accent, type: type, color: color,
                                  art: art, unit: unitPx, angle: angle, glow: glow, pop: pop)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                OText(skin.title, .Title, size: 26, outline: Color(argb: 0xFF0D1530), strokeWidth: 7, align: .leading)
                GText(skin.tagline, .Small, color: .white.opacity(0.85), size: 13)
            }
            .padding(14)
            CoinPill(coins)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipped()
        .onChange(of: "\(skin.id)/\(type.ordinal)/\(color)") { _, _ in popStart = Date() }
    }

    static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, skin: Skin, accent: ArtColor, type: VehicleType, color: Int,
                     art: VehicleArt, unit: Float, angle: Float, glow: Float, pop: Float) {
        let w = size.width
        let h = size.height
        // Spotlights
        for k in [CGFloat(0.18), CGFloat(0.82)] {
            var p = Path()
            p.move(to: CGPoint(x: w * k - 5, y: 0))
            p.addLine(to: CGPoint(x: w * k + 5, y: 0))
            p.addLine(to: CGPoint(x: w * 0.5 + (w * k - w * 0.5) * 0.1 + 60, y: h * 0.8))
            p.addLine(to: CGPoint(x: w * 0.5 + (w * k - w * 0.5) * 0.1 - 60, y: h * 0.8))
            p.closeSubpath()
            ctx.fill(p, with: .linearGradient(
                Gradient(colors: [Color.white.opacity(Double(0.16 * glow)), Color.white.opacity(0)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.8)))
        }
        // Back wall stripes
        for k in 0..<8 {
            ctx.fill(Path(CGRect(x: CGFloat(k) * w / 8, y: 0, width: w / 16, height: h * 0.55)), with: .color(Color.white.opacity(0.03)))
        }
        // Floor
        ctx.fill(Path(CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.45)), with: .linearGradient(
            Gradient(colors: [Color(argb: 0xFF2B3550), Color(argb: 0xFF151B2E)]),
            startPoint: CGPoint(x: 0, y: h * 0.55), endPoint: CGPoint(x: 0, y: h)))
        // Turntable
        let c = CGPoint(x: w / 2, y: h * 0.72)
        let rx = w * 0.4
        let ry = h * 0.17
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry + 6, width: rx * 2, height: ry * 2)), with: .color(Color.black.opacity(0.45)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry + 4, width: rx * 2, height: ry * 2)), with: .color(Color(argb: 0xFF3C4766)))
        let top = Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
        ctx.fill(top, with: .linearGradient(
            Gradient(colors: [Color(argb: 0xFF7D8BB0), Color(argb: 0xFF4A5677)]),
            startPoint: CGPoint(x: 0, y: c.y - ry), endPoint: CGPoint(x: 0, y: c.y + ry)))
        ctx.stroke(top, with: .color(accent.copy(alpha: 0.55 + 0.3 * glow).color), lineWidth: 2)
        let dotB = accent.tint(0.4).color
        for k in 0..<16 {
            let a = (Double(k) * 22.5 + Double(angle)) * .pi / 180
            let p = CGPoint(x: c.x + rx * 0.92 * CGFloat(cos(a)), y: c.y + ry * 0.92 * CGFloat(sin(a)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.75, y: p.y - 1.75, width: 3.5, height: 3.5)),
                     with: .color(k % 2 == 0 ? Color(argb: 0xFFFFF59D) : dotB))
        }
        // Vehicle
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.scaleBy(x: CGFloat(pop), y: CGFloat(pop))
        g.translateBy(x: -c.x, y: -c.y)
        let shadow = art.shadow(type)
        var sg = g
        sg.translateBy(x: c.x + CGFloat(unit * 0.2), y: c.y + CGFloat(unit * 0.3))
        sg.rotate(by: .degrees(Double(angle)))
        sg.draw(shadow.image, in: CGRect(x: -CGFloat(shadow.width) / 2, y: -CGFloat(shadow.height) / 2,
                                         width: CGFloat(shadow.width), height: CGFloat(shadow.height)))
        if skin == .NEON {
            g.fill(Path(ellipseIn: CGRect(x: c.x - rx * 0.55, y: c.y - ry * 0.5, width: rx * 1.1, height: ry)),
                   with: .color(jamArtColor(color).copy(alpha: 0.35).color))
        }
        art.drawLive(&g, type, color, angle, Offset(Float(c.x), Float(c.y)))
    }
}

private struct SkinActions: View {
    let skin: Skin
    let equipped: Skin
    let player: PlayerState
    let onBuy: () -> Void
    let onAd: () -> Void
    let onEquip: () -> Void

    var body: some View {
        let owned = player.ownedSkins.contains(skin.id)
        HStack(spacing: 10) {
            if skin == equipped {
                HStack(spacing: 0) {
                    GameIcon(Icon.CHECK, 28)
                    GText("  Equipped on all vehicles", .Label, color: Color(argb: 0xFF2E7D32), size: 16)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(argb: 0xFFE8F5E9), in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color(argb: 0xFF43A047), lineWidth: 3))
            } else if owned {
                GameButton("Equip", onClick: onEquip, color: ButtonColor.BLUE, height: 58)
                    .frame(maxWidth: .infinity)
            } else {
                GameButton("\(skin.price)", onClick: onBuy, color: ButtonColor.GREEN, height: 58, fontSize: 22,
                           enabled: player.coins >= skin.price, leading: CoinBadge.icon(30))
                    .frame(maxWidth: .infinity)
                GameButton("Free", onClick: onAd, color: ButtonColor.ORANGE, height: 58, fontSize: 22, leading: AdBadge.icon(30))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
    }
}

private struct PackCard: View {
    let skin: Skin
    let owned: Bool
    let equipped: Bool
    let previewing: Bool
    let onClick: () -> Void

    var body: some View {
        let accent = skin.accent()
        Button(action: onClick) {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [accent.tint(0.45).color, accent.tint(0.15).color], startPoint: .top, endPoint: .bottom)
                    GeometryReader { g in
                        Ellipse()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: g.size.width * 0.76, height: g.size.height * 0.36)
                            .offset(x: g.size.width * 0.12, y: g.size.height * 0.55)
                    }
                    HStack(alignment: .center, spacing: 0) {
                        VehicleSprite(VehicleType.VAN, (skin.previewColor() + 3) % 8, skin, 12, rotation: 60)
                            .offset(x: 14, y: -6)
                        VehicleSprite(VehicleType.CAR, skin.previewColor(), skin, 16, rotation: 60)
                            .offset(x: -26, y: 8)
                    }
                    .repeatingOffsetY(-2, 2, ms: 1300)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if equipped {
                        GText("IN USE", .Small, color: .white, size: 11, titleFont: true)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(argb: 0xFF43A047), in: RoundedRectangle(cornerRadius: 8))
                            .padding(6)
                    }
                }
                .frame(height: 116)
                VStack(alignment: .leading, spacing: 0) {
                    GText(skin.title, .Label, color: Color(argb: 0xFF3E2723), size: 16, titleFont: true, lineLimit: 1)
                    Spacer().frame(height: 2)
                    if owned {
                        HStack(spacing: 0) {
                            GameIcon(Icon.CHECK, 16)
                            GText(" Owned", .Small, color: Color(argb: 0xFF2E7D32))
                        }
                    } else {
                        HStack(spacing: 0) {
                            GameIcon(Icon.COIN, 16)
                            GText(" \(skin.price)", .Small, color: Color(argb: 0xFF8A4B14), titleFont: true)
                            Spacer().frame(width: 6)
                            GText("or", .Small, color: Color(argb: 0xFF8A4B14))
                            Spacer().frame(width: 4)
                            GameIcon(Icon.AD, 16)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(argb: 0xFFFFF8E7))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(4)
            .background(CardBack(radius: 20, face: previewing ? Color(argb: 0xFFFFD54F) : .white))
            .scaleEffect(previewing ? 1.03 : 1)
        }
        .buttonStyle(.plain)
    }
}
