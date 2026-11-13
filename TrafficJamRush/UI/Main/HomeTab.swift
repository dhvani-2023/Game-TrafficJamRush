import SwiftUI
import GameKit

private let DAILY = [20, 30, 40, 60, 80, 100, 200]

@MainActor private var dailyShownThisSession = false

struct HomeTab: View {
    let player: PlayerState
    let onPlay: () -> Void
    let onSettings: () -> Void
    let onWorld: (Int) -> Void
    /// Extras: open today's Daily Puzzle / start a given level (resume).
    var onDaily: () -> Void = {}
    var onPlayLevel: (Int) -> Void = { _ in }

    @State private var showDaily = false
    @State private var resumeOffer: ExtrasSnapshot? = nil

    private var progress: ProgressRepository { App.container.progress }

    var body: some View {
        let next = player.nextLevel
        let world = collectionOf(next)
        let theme = Themes.forCollection(world)

        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    AvatarTile(54)
                    Spacer().frame(width: 10)
                    CoinPill(player.coins)
                    Spacer(minLength: 0)
                    RoundButton(onClick: onSettings, size: 48) { GameIcon(Icon.GEAR, 32) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Spacer().frame(height: 4)
                GameLogo(scale: 0.82)

                // Current world card
                Button { onWorld(world) } label: {
                    ZStack(alignment: .bottom) {
                        WorldArt(theme)
                            .frame(maxWidth: .infinity)
                            .frame(height: 132)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                OText(Themes.collectionName(world), .Title, size: 20, strokeWidth: 6, align: .leading)
                                    .fixedSize(horizontal: true, vertical: false) // one line, like Android
                                    .layoutPriority(1)
                                Spacer(minLength: 0)
                                GameIcon(Icon.STAR, 20)
                                GText(" \(player.starsIn(world))", .Label, color: .white, titleFont: true)
                            }
                            Spacer().frame(height: 4)
                            let done = player.completedIn(world)
                            GeometryReader { g in
                                Capsule()
                                    .fill(LinearGradient(colors: [Color(argb: 0xFFB2FF59), Color(argb: 0xFF64DD17)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: g.size.width * CGFloat(done) / CGFloat(LEVELS_PER_COLLECTION), height: 10)
                            }
                            .frame(height: 10)
                            .padding(2)
                            .background(Color(argb: 0x66000000), in: Capsule())
                            GText("World \(world) · \(done) / \(LEVELS_PER_COLLECTION) levels", .Small, color: .white.opacity(0.9))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(LinearGradient(colors: [.clear, Color(argb: 0xCC0D2C6B)], startPoint: .top, endPoint: .bottom))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(5)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 24).fill(Color(argb: 0xFF0D2C6B)).offset(y: 6)
                            RoundedRectangle(cornerRadius: 24).fill(Color.white)
                        }
                    )
                }
                .buttonStyle(.plain)
                .offset(y: -14)
                .padding(.horizontal, 26)

                Spacer(minLength: 0)
                TrafficStrip()
                Spacer().frame(height: 10)

                // Play button
                GameButton(
                    next >= TOTAL_LEVELS && player.isCompleted(TOTAL_LEVELS) ? "Replay \(next)" : "Level \(next)",
                    onClick: onPlay,
                    color: ButtonColor.YELLOW,
                    height: 78,
                    fontSize: 36
                )
                .frame(width: 250)
                .repeatingScale(0.96, 1.04, ms: 700)
                Spacer().frame(height: 18)
            }

            // Side buttons
            SideButton(icon: .GIFT, label: "Daily", badge: progress.dailyAvailable) { setDaily(true) }
                .padding(.leading, 10)
                .offset(y: 112)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            Mascot(96)
                .padding(.trailing, 8)
                .offset(y: 112)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            // Extras: Daily Puzzle card + dialog, "Continue level N?" (below the Daily Reward dialog).
            ExtrasHomeLayer(player: player, resumeOffer: $resumeOffer, onDaily: onDaily, onPlayLevel: onPlayLevel,
                            onPromptClosed: { autoDaily() })

            DailyDialog(visible: showDaily, onClose: { setDaily(false) })
        }
        .onAppear {
            // Extras: after a relaunch, "Continue level N?" comes first; the Daily Reward waits for it.
            if let s = ExtrasResumeOffer.take(player) {
                resumeOffer = s
                return
            }
            autoDaily()
        }
    }

    private func autoDaily() {
        if player.loaded && progress.dailyAvailable && !dailyShownThisSession && player.completedCount > 0 {
            dailyShownThisSession = true
            setDaily(true)
        }
    }

    private func setDaily(_ v: Bool) {
        showDaily = v
    }
}

private struct SideButton: View {
    let icon: Icon
    let label: String
    let badge: Bool
    let onClick: () -> Void

    var body: some View {
        Button {
            App.container.audio.play(Sfx.Click)
            onClick()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    GameIcon(icon, 48)
                        .repeatingRotation(-8, 8, ms: 500, active: badge)
                        .frame(width: 62, height: 62)
                        .background(
                            LinearGradient(colors: [Color(argb: 0xFFFFE9B0), Color(argb: 0xFFFFC46B)], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white, lineWidth: 3))
                    OText(label, .Button, size: 15, strokeWidth: 5)
                        .offset(y: -8)
                }
                .frame(width: 78, height: 78)
                if badge {
                    GText("!", .Button, size: 13)
                        .frame(width: 20, height: 20)
                        .background(Color(argb: 0xFFF2453D), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                }
            }
            .frame(width: 78, height: 78)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A strip of road with a few vehicles cruising past.
private struct TrafficStrip: View {
    @State private var clock = LoopClock()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pad = w * 0.35
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in TrafficStrip.drawRoad(&ctx, size) }
                TimelineView(.animation) { tl in
                    let t = clock.elapsed(tl.date)
                    let a = CGFloat(infiniteFloat(t, 0, 1, ms: 5200, linear: true))
                    let b = CGFloat(infiniteFloat(t, 0, 1, ms: 3800, linear: true))
                    ZStack(alignment: .topLeading) {
                        VehicleSprite(VehicleType.VAN, JamColor.GREEN.ordinal, Skin.CLASSIC, 11, rotation: 90)
                            .offset(x: -pad + a * (w + pad * 2), y: 14)
                        VehicleSprite(VehicleType.BUS, JamColor.BLUE.ordinal, Skin.CLASSIC, 11, rotation: -90)
                            .offset(x: -pad + (1 - b) * (w + pad * 2), y: 46)
                        VehicleSprite(VehicleType.CAR, JamColor.PINK.ordinal, Skin.CLASSIC, 11, rotation: 90)
                            .offset(x: -pad + (a + 0.5).truncatingRemainder(dividingBy: 1) * (w + pad * 2), y: 14)
                    }
                }
            }
        }
        .frame(height: 96)
    }

    static func drawRoad(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: 10)), with: .color(Color(argb: 0xFF8BC34A)))
        ctx.fill(Path(CGRect(x: 0, y: 10, width: w, height: 76)), with: .color(Color(argb: 0xFF5B6270)))
        ctx.fill(Path(CGRect(x: 0, y: 12, width: w, height: 2)), with: .color(.white))
        ctx.fill(Path(CGRect(x: 0, y: 82, width: w, height: 2)), with: .color(.white))
        var line = Path()
        line.move(to: CGPoint(x: 0, y: 48))
        line.addLine(to: CGPoint(x: w, y: 48))
        ctx.stroke(line, with: .color(Color(argb: 0xFFFFD54F)), style: StrokeStyle(lineWidth: 3, dash: [18, 14]))
        ctx.fill(Path(CGRect(x: 0, y: 86, width: w, height: 10)), with: .color(Color(argb: 0xFF7CB342)))
    }
}

private struct DailyDialog: View {
    let visible: Bool
    let onClose: () -> Void

    @State private var claimed = false

    var body: some View {
        let progress = App.container.progress
        let idx = progress.dailyIndex
        let available = progress.dailyAvailable
        GameDialog(visible: visible, onDismiss: onClose) {
            GamePanel("Daily Reward", frame: Color(argb: 0xFFFF8A1F), onClose: onClose) {
                GText("Come back every day for bigger prizes!", .Body, align: .center)
                Spacer().frame(height: 12)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { d in
                            DayTile(day: d, today: idx, canClaim: available && !claimed)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    GeometryReader { g in
                        // weights 1, 1, 2 with 8 pt gaps
                        let unit = (g.size.width - 16) / 4
                        HStack(spacing: 8) {
                            DayTile(day: 4, today: idx, canClaim: available && !claimed).frame(width: unit)
                            DayTile(day: 5, today: idx, canClaim: available && !claimed).frame(width: unit)
                            DayTile(day: 6, today: idx, canClaim: available && !claimed).frame(width: unit * 2)
                        }
                    }
                    .frame(height: 92)
                }
                Spacer().frame(height: 18)
                if available && !claimed {
                    HStack(spacing: 10) {
                        GameButton("Claim", onClick: {
                            progress.claimDaily(DAILY[idx])
                            App.container.audio.play(Sfx.CoinBurst)
                            claimed = true
                        }, color: ButtonColor.GREEN, fontSize: 20)
                        .frame(maxWidth: .infinity)
                        GameButton("x2", onClick: {
                            App.container.ads.showRewarded("daily_x2", onReward: {
                                progress.claimDaily(DAILY[idx] * 2)
                                App.container.audio.play(Sfx.CoinBurst)
                                claimed = true
                            })
                        }, color: ButtonColor.ORANGE, fontSize: 20, leading: AdBadge.icon(28))
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    GText("Come back tomorrow!", .Label, color: Color(argb: 0xFF2E7D32), size: 18)
                }
            }
        }
        .task(id: claimed) {
            guard claimed else { return }
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            onClose()
        }
    }
}

private struct DayTile: View {
    let day: Int
    let today: Int
    let canClaim: Bool

    var body: some View {
        let isToday = day == today && canClaim
        let done = day < today || (day == today && !canClaim)
        let colors: [Color] = isToday
            ? [Color(argb: 0xFFFFF59D), Color(argb: 0xFFFFC107)]
            : done ? [Color(argb: 0xFFC8E6C9), Color(argb: 0xFF81C784)]
            : [Color(argb: 0xFFFFFFFF), Color(argb: 0xFFFFE6C7)]
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                GText("Day \(day + 1)", .Small, color: Color(argb: 0xFF8A4B14), size: 12, titleFont: true)
                GameIcon(day == 6 ? Icon.GIFT : Icon.COIN, 36)
                GText("\(DAILY[day])", .Label, color: Color(argb: 0xFF6D3A00), size: 15, titleFont: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if done {
                GameIcon(Icon.CHECK, 34).offset(x: 4, y: -6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isToday ? Color(argb: 0xFFFF8F00) : Color(argb: 0xFFE0B97F), lineWidth: 2.5))
        .repeatingScale(1, 1.06, ms: 500, active: isToday)
    }
}
