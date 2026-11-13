import SwiftUI
import GameKit

private struct Page {
    let title: String
    let body: String
}

private let pages: [Page] = [
    Page(title: "Tap to Drive", body: "Every vehicle drives the way its arrow points. Tap one with a clear road and it zooms off to a parking spot."),
    Page(title: "Match the Colors", body: "Passengers only board a vehicle of their own color. Cars seat 4, vans 6 and buses 10."),
    Page(title: "Keep a Spot Free", body: "Parking spots are limited. Fill them all with the wrong colors and you're stuck, so plan ahead or use a booster!"),
    Page(title: "5000 Levels", body: "Travel through 50 colorful worlds, from busy stations to space ports. Ready to clear the jam?"),
]

struct OnboardingScreen: View {
    let onFinished: () -> Void

    @State private var page = 0

    var body: some View {
        SkyBackground {
            SunRays(color: Color(argb: 0x33FFFFFF))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -180)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageContent(index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color(argb: 0xFFFFD54F) : Color.white.opacity(0.5))
                            .frame(width: i == page ? 30 : 12, height: 12)
                            .padding(.horizontal, 4)
                    }
                }
                .animation(.compose(), value: page)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)

                let last = page == pages.count - 1
                GameButton(
                    last ? "Let's Go!" : "Next",
                    onClick: {
                        if last {
                            App.container.progress.finishOnboarding()
                            onFinished()
                        } else {
                            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)) { page += 1 }
                        }
                    },
                    color: last ? ButtonColor.GREEN : ButtonColor.ORANGE,
                    height: 64,
                    fontSize: 28
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
                Spacer().frame(height: 12)
            }
        }
        .onAppear { App.container.audio.playMusic(Music.Home) }
        .onChange(of: page) { _, p in
            if p > 0 { App.container.audio.play(Sfx.Whoosh) }
        }
    }

    @ViewBuilder
    private func pageContent(_ index: Int) -> some View {
        let p = pages[index]
        VStack(spacing: 0) {
            Spacer().frame(height: 28)
            ZStack {
                switch index {
                case 0: TapDemo(active: page == 0)
                case 1: MatchDemo(active: page == 1)
                case 2: SlotsDemo(active: page == 2)
                default: WorldsDemo(active: page == 3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 330)
            .background(Color.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 3))
            Spacer().frame(height: 28)
            OText(p.title, .Display, size: 38, color: Color(argb: 0xFFFFE14D), outline: Color(argb: 0xFF0D2C6B), strokeWidth: 12)
            Spacer().frame(height: 12)
            GText(p.body, .Body, color: .white, size: 18, align: .center, lineHeight: 25)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }
}

// --- Illustrations ------------------------------------------------------------------------------

/// Plays a sound each time `on` turns true (Compose `LaunchedEffect(cond) { if (cond) play }`).
private struct SoundTrigger: View {
    let on: Bool
    let sfx: Sfx

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: on) { _, v in if v { App.container.audio.play(sfx) } }
    }
}

private struct LotPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack { content() }
            .frame(width: 270, height: 270)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 26).fill(Color(argb: 0xFFB9BBB2)).offset(y: 6)
                    RoundedRectangle(cornerRadius: 26).fill(Color(argb: 0xFFD4D6CF))
                }
            )
    }
}

@inline(__always) private func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }

private struct TapDemo: View {
    let active: Bool
    @State private var clock = LoopClock()

    var body: some View {
        LotPanel {
            TimelineView(.animation(minimumInterval: nil, paused: !active)) { tl in
                let p = Float(infiniteFloat(clock.elapsed(tl.date), 0, 1, ms: 2600, linear: true))
                let drive = clamp01((p - 0.38) / 0.4)
                let ease = drive * drive
                let hand: Float = p < 0.25 ? p / 0.25 : 1
                let press: CGFloat = (p >= 0.28 && p <= 0.38) ? 0.85 : 1
                let handAlpha: Float = p > 0.6 ? clamp01(1 - (p - 0.6) * 4) : 1
                ZStack {
                    // Blocked bus and two neighbours
                    VehicleSprite(VehicleType.BUS, JamColor.BLUE.ordinal, Skin.CLASSIC, 22)
                        .offset(x: -70, y: 10)
                    VehicleSprite(VehicleType.VAN, JamColor.GREEN.ordinal, Skin.CLASSIC, 22, rotation: 90)
                        .offset(x: -14, y: -60)
                    VehicleSprite(VehicleType.CAR, JamColor.RED.ordinal, Skin.CLASSIC, 22, rotation: 90)
                        .opacity(p > 0.85 ? 0 : 1)
                        .offset(x: 40 + 220 * CGFloat(ease), y: 40)
                    SoundTrigger(on: p > 0.3 && p < 0.33, sfx: Sfx.Tap)
                    GameIcon(Icon.HAND, 70)
                        .scaleEffect(press)
                        .opacity(Double(handAlpha))
                        .offset(x: 130 - 80 * CGFloat(hand), y: 140 - 80 * CGFloat(hand))
                }
            }
        }
    }
}

private struct MatchDemo: View {
    let active: Bool
    @State private var clock = LoopClock()
    @State private var pa = PassengerArt(18, 32)

    private static let colors: [JamColor] = [.BLUE, .BLUE, .BLUE, .PINK, .PINK]

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: nil, paused: !active)) { tl in
                let p = Float(infiniteFloat(clock.elapsed(tl.date), 0, 1, ms: 3000, linear: true))
                ZStack(alignment: .leading) {
                    // slot
                    ZStack {
                        VehicleSprite(VehicleType.VAN, JamColor.BLUE.ordinal, Skin.CLASSIC, 22)
                    }
                    .frame(width: 74, height: 130)
                    .background(Color(argb: 0x22000000), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white, lineWidth: 3))
                    .offset(x: 18)
                    // passengers walking left into the van
                    ForEach(0..<MatchDemo.colors.count, id: \.self) { i in
                        let c = MatchDemo.colors[i]
                        let k = clamp01(p * 1.6 - Float(i) * 0.18)
                        let boarded = c == .BLUE && k >= 1
                        let walk: Float = c == .BLUE ? 70 * k : 54 * clamp01(p * 1.6 - 0.54)
                        let x = 110 + 30 * Float(i) - walk
                        let hop = abs(Kt.sin(p * 40 + Float(i))) * 4
                        if !boarded {
                            let img = pa.get(c.ordinal)
                            img.image
                                .resizable()
                                .frame(width: CGFloat(img.width), height: CGFloat(img.height))
                                .offset(x: CGFloat(x), y: CGFloat(-hop))
                        }
                    }
                }
                .frame(width: 280, height: 170)
            }
            Spacer().frame(height: 10)
            HStack(alignment: .bottom, spacing: 16) {
                SeatBadge(type: .CAR, color: JamColor.RED.ordinal, seats: 4)
                SeatBadge(type: .VAN, color: JamColor.GREEN.ordinal, seats: 6)
                SeatBadge(type: .BUS, color: JamColor.YELLOW.ordinal, seats: 10)
            }
        }
    }
}

private struct SeatBadge: View {
    let type: VehicleType
    let color: Int
    let seats: Int

    var body: some View {
        VStack(spacing: 0) {
            VehicleSprite(type, color, Skin.CLASSIC, 12, rotation: 90)
            Spacer().frame(height: 6)
            GText("\(seats) seats", .Small, color: .white, size: 13)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(argb: 0x66000000), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct SlotsDemo: View {
    let active: Bool
    @State private var clock = LoopClock()

    private static let colors: [JamColor] = [.RED, .YELLOW, .PURPLE, .GREEN]
    private static let boosters: [Icon] = [.SHUFFLE, .CRANE, .SORT]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { tl in
            let p = Float(infiniteFloat(clock.elapsed(tl.date), 0, 1, ms: 3400, linear: true))
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(0..<SlotsDemo.colors.count, id: \.self) { i in
                        let k = clamp01((p - Float(i) * 0.12) / 0.12)
                        ZStack {
                            VehicleSprite(VehicleType.CAR, SlotsDemo.colors[i].ordinal, Skin.CLASSIC, 13)
                                .opacity(Double(k))
                                .offset(y: (1 - CGFloat(k)) * 60)
                        }
                        .frame(width: 54, height: 96)
                        .background(p > 0.55 && p < 0.8 ? Color(argb: 0x55F2453D) : Color(argb: 0x22000000),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white, lineWidth: 3))
                    }
                }
                Spacer().frame(height: 18)
                let warn: CGFloat = p > 0.55 ? 1 : 0
                ZStack {
                    if p < 0.78 {
                        GText("No spots left!", .Label, color: .white, size: 18)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(argb: 0xFFF2453D), in: RoundedRectangle(cornerRadius: 14))
                            .scaleEffect(0.8 + warn * 0.2)
                            .opacity(Double(warn))
                    } else {
                        let k = CGFloat(clamp01((p - 0.78) / 0.1))
                        HStack(spacing: 14) {
                            ForEach(0..<3, id: \.self) { j in
                                GameIcon(SlotsDemo.boosters[j], 64).scaleEffect(k)
                            }
                        }
                    }
                }
                .frame(height: 80)
            }
        }
    }
}

private struct WorldsDemo: View {
    let active: Bool
    @State private var clock = LoopClock()

    private static let shown = [0, 2, 5, 9]

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: !active)) { tl in
                let fan = CGFloat(infiniteFloat(clock.elapsed(tl.date), 0.85, 1, ms: 1600, reverse: true))
                ZStack {
                    ForEach(0..<WorldsDemo.shown.count, id: \.self) { i in
                        let theme = Themes.all[WorldsDemo.shown[i]]
                        let fi = CGFloat(i) - 1.5
                        ZStack(alignment: .bottom) {
                            WorldArt(theme)
                            GText(theme.name, .Small, color: .white, size: 11, align: .center)
                                .padding(4)
                                .frame(maxWidth: .infinity)
                                .background(Color(argb: 0x99000000))
                        }
                        .frame(width: 110, height: 158)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(5)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 18).fill(Color(argb: 0xFF0D2C6B)).offset(y: 5)
                                RoundedRectangle(cornerRadius: 18).fill(Color.white)
                            }
                        )
                        .rotationEffect(.degrees(Double(fi * 13 * fan)))
                        .offset(x: fi * 46 * fan, y: abs(fi) * 10)
                    }
                }
            }
            OText("50 Worlds", .Title, size: 26, outline: Color(argb: 0xFF0D2C6B), strokeWidth: 7)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Mascot(80)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            GameIcon(Icon.TROPHY, 60)
                .background(Circle().stroke(Color.white.opacity(0.4), lineWidth: 3))
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
