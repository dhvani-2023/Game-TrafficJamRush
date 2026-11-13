import UIKit
import SwiftUI
import Observation
import GameKit

private let REVIVE_PRICE = 120

private func rewardFor(_ level: Int) -> Int {
    switch LevelGenerator.get(level).difficulty {
    case .NORMAL: return 10
    case .HARD: return 20
    case .SUPER_HARD: return 30
    }
}

struct GameScreen: View {
    let levelNumber: Int
    let onHome: () -> Void
    let onPlayLevel: (Int) -> Void
    /// Extras: play this day's Daily Puzzle instead of a numbered level.
    var daily: ExtrasDay? = nil

    @State private var attempt = 0

    var body: some View {
        // key(levelNumber, attempt): Retry rebuilds the whole session.
        GameSession(
            levelNumber: levelNumber,
            daily: daily,
            onHome: onHome,
            onRetry: { attempt += 1 },
            onNext: { onPlayLevel(daily != nil ? App.container.progress.now.nextLevel : min(levelNumber + 1, TOTAL_LEVELS)) }
        )
        .id(attempt)
        .onAppear { App.container.audio.playMusic(Music.Game) }
    }
}

private enum Overlay { case NONE, PAUSE, PROP, REVIVE, FAIL, WIN, SLOT, UNDO }

/// Engine, frame loop and event queue of one attempt (Kotlin `remember(levelNumber) { GameEngine(...) }`
/// plus the event `Channel`).
@MainActor
private final class SessionModel {
    let engine: GameEngine
    let loop = GameLoop()
    let events: AsyncStream<GameEvent>
    private let sink: AsyncStream<GameEvent>.Continuation
    /// Extras: undo log + rewind animation, autosave / resume of this level.
    let extras: ExtrasSession

    init(level: Level, theme: SceneTheme, skin: Skin, levelNumber: Int, daily: ExtrasDay? = nil) {
        let audio = App.container.audio
        var c: AsyncStream<GameEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
        sink = c
        let engine = GameEngine(
            level, theme, skin,
            fx: AnyGameFx(sfx: { s, rate in audio.play(s, rate) }, haptic: { h in audio.haptic(h) }),
            patterns: ExtrasPatterns.enabled
        )
        self.engine = engine
        let extras = ExtrasSession(engine: engine, levelNumber: levelNumber, day: daily)
        self.extras = extras
        // Engine callbacks fire mid-frame; queue them and handle them in order in a task.
        let sink = self.sink
        engine.onEvent = { e in sink.yield(e) }
        loop.onTick = { dt in
            engine.update(Float(dt))
            extras.tick(Float(dt))
        }
    }

    func finish() {
        loop.stop()
        sink.finish()
    }
}

/// Creates the session model once per view identity (a `@State` initial value would be rebuilt on every
/// parent update).
@MainActor
private final class SessionHolder {
    private var model: SessionModel?

    func get(_ levelNumber: Int, _ daily: ExtrasDay? = nil) -> SessionModel {
        if let m = model { return m }
        let m = SessionModel(
            level: daily.map { ExtrasDailyPuzzle.level($0) } ?? LevelGenerator.get(levelNumber),
            theme: daily.map { ExtrasDailyPuzzle.theme($0) } ?? Themes.forLevel(levelNumber),
            skin: Skin.of(App.container.progress.now.skin),
            levelNumber: levelNumber,
            daily: daily
        )
        // Extras: Home ▸ "Continue level N?" hands its snapshot to the matching session.
        if ExtrasFeatures.autosave { m.extras.resume = App.container.extras.takeResume(levelNumber: levelNumber, day: daily?.epochDay) }
        model = m
        return m
    }
}

private struct GameSession: View {
    let levelNumber: Int
    let daily: ExtrasDay?
    let onHome: () -> Void
    let onRetry: () -> Void
    let onNext: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var holder = SessionHolder()
    @State private var overlay: Overlay = .NONE
    @State private var prop: BoosterType = .SHUFFLE
    @State private var slotIndex = -1
    @State private var stars = 0
    @State private var toast: String? = nil
    @State private var toastId = 0
    @State private var newWorld: String? = nil
    @State private var dailyResult: ExtrasDailyResult? = nil

    private var progress: ProgressRepository { App.container.progress }
    private var audio: AudioManager { App.container.audio }
    private var ads: RewardedAdManager { App.container.ads }

    private func showToast(_ msg: String) {
        toast = msg
        toastId += 1
        let id = toastId
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if toastId == id { toast = nil }
        }
    }

    var body: some View {
        let m = holder.get(levelNumber, daily)
        let engine = m.engine
        let level = engine.level
        let theme = engine.theme
        let reward = daily != nil ? (dailyResult?.reward ?? 0) : rewardFor(levelNumber)
        let player = progress.state
        let extras = App.container.extras

        GeometryReader { geo in
            let size = geo.size
            // The reader ignores the safe area (full-bleed scene), so its own insets read 0: use the window's.
            let window = WindowInsets.current
            let topInset = max(geo.safeAreaInsets.top, window.top)
            // Android hides its navigation bar; on iOS the boosters keep clear of most of the home-indicator zone.
            let bottomInset = max(0, max(geo.safeAreaInsets.bottom, window.bottom) - 16)
            let dialogW = max(0, size.width - 44)

            ZStack(alignment: .topLeading) {
                theme.outside
                GameCanvas(model: m)
                    .frame(width: size.width, height: size.height)

                if engine.ready {
                    Hud(level: levelNumber, difficulty: level.difficulty, coins: player.coins, topInset: topInset,
                        onPause: { overlay = .PAUSE }, title: daily != nil ? "Daily Puzzle" : nil)
                    QueueSign(engine: engine)
                    TutorialLayer(engine: engine, width: size.width)
                    BoosterBar(
                        engine: engine,
                        counts: player.boosters,
                        bottomInset: bottomInset,
                        onBooster: { type in
                            if engine.phase != .PLAYING { return }
                            if progress.state.boosterCount(type) > 0 {
                                if useBooster(engine, type) { progress.addBooster(type, -1) }
                            } else {
                                prop = type
                                overlay = .PROP
                            }
                        },
                        undoCount: extras.undoCount,
                        onUndo: {
                            if engine.phase != .PLAYING { return }
                            if m.extras.undoTarget() == nil {
                                showToast("Nothing to undo")
                            } else if extras.undoCount > 0 {
                                if m.extras.undo() { extras.addUndo(-1) }
                            } else {
                                overlay = .UNDO
                            }
                        }
                    )
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                }

                if level.difficulty != .NORMAL {
                    DifficultyBanner(difficulty: level.difficulty, screenHeight: size.height)
                        .frame(width: size.width, height: size.height)
                }

                GameToast(toast)
                    .offset(y: -40)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)

                CraneBanner(armed: engine.craneArmed) {
                    engine.craneArmed = false
                    progress.addBooster(.CRANE, 1)
                }
                .frame(width: size.width, height: size.height)

                // --- Dialogs ---

                PauseDialog(
                    visible: overlay == .PAUSE,
                    sound: player.sound, music: player.music, vibration: player.vibration,
                    onSound: { progress.setSound($0) }, onMusic: { progress.setMusic($0) }, onVibration: { progress.setVibration($0) },
                    onResume: { overlay = .NONE },
                    onRestart: { overlay = .NONE; onRetry() },
                    onHome: { overlay = .NONE; onHome() }
                )

                PropDialog(
                    visible: overlay == .PROP,
                    type: prop,
                    coins: player.coins,
                    onDismiss: { overlay = .NONE },
                    onBuy: {
                        if progress.spendCoins(prop.price) {
                            overlay = .NONE
                            audio.play(Sfx.Coin)
                            if !useBooster(engine, prop) { progress.addBooster(prop, 1) }
                        } else {
                            showToast("Not enough coins")
                        }
                    },
                    onAd: {
                        let type = prop
                        ads.showRewarded("booster_\(type.name)", onReward: {
                            overlay = .NONE
                            if !useBooster(engine, type) { progress.addBooster(type, 1) }
                        })
                    }
                )

                ExtrasUndoDialog(
                    visible: overlay == .UNDO,
                    coins: player.coins,
                    onDismiss: { overlay = .NONE },
                    onBuy: {
                        if progress.spendCoins(ExtrasRepository.UNDO_PRICE) {
                            overlay = .NONE
                            audio.play(Sfx.Coin)
                            if !m.extras.undo() { extras.addUndo(1) }
                        } else {
                            showToast("Not enough coins")
                        }
                    },
                    onAd: {
                        ads.showRewarded("booster_UNDO", onReward: {
                            overlay = .NONE
                            if !m.extras.undo() { extras.addUndo(1) }
                        })
                    }
                )

                ReviveDialog(
                    visible: overlay == .REVIVE,
                    coins: player.coins,
                    onBuy: {
                        if progress.spendCoins(REVIVE_PRICE) {
                            overlay = .NONE
                            engine.revive()
                        } else {
                            showToast("Not enough coins")
                        }
                    },
                    onAd: { ads.showRewarded("revive", onReward: { overlay = .NONE; engine.revive() }) },
                    onGiveUp: {
                        audio.play(Sfx.Fail)
                        audio.haptic(Haptic.Fail)
                        m.extras.clearSave()
                        overlay = .FAIL
                    }
                )

                FailDialog(
                    visible: overlay == .FAIL,
                    width: dialogW,
                    onRetry: { overlay = .NONE; onRetry() },
                    onSkip: {
                        ads.showRewarded("skip_level", onReward: {
                            _ = progress.completeLevel(levelNumber, 1, 0)
                            overlay = .NONE
                            onNext()
                        })
                    },
                    onHome: { overlay = .NONE; onHome() },
                    canSkip: daily == nil
                )

                WinDialog(
                    visible: overlay == .WIN,
                    levelNumber: levelNumber,
                    stars: stars,
                    reward: reward,
                    newWorld: newWorld,
                    onDouble: { done in
                        ads.showRewarded("double_coins", onReward: {
                            progress.addCoins(reward)
                            done()
                        })
                    },
                    onNext: { overlay = .NONE; onNext() },
                    onHome: { overlay = .NONE; onHome() },
                    title: daily != nil ? "Puzzle Solved!" : "Level Complete!",
                    subtitle: daily.map { "Daily Puzzle · \($0.label)" },
                    nextLabel: daily != nil ? "Level \(player.nextLevel)" : "Next",
                    streak: dailyResult
                )

                WatchAdDialog(
                    visible: overlay == .SLOT,
                    title: "Extra Spot",
                    message: Ads.usesRealAds
                        ? "Watch a short ad to open this parking spot for the rest of the level."
                        : "Open this parking spot for free for the rest of the level.",
                    onWatch: {
                        ads.showRewarded("slot", onReward: {
                            overlay = .NONE
                            if slotIndex >= 0 { engine.unlockSlot(slotIndex) }
                        })
                    },
                    onDismiss: { overlay = .NONE }
                )
            }
            .frame(width: size.width, height: size.height)
            .onAppear {
                engine.setSize(Float(size.width), Float(size.height), Float(topInset), Float(bottomInset))
                m.extras.applyResume()
                m.loop.start()
            }
            .onChange(of: size) { _, s in
                engine.setSize(Float(s.width), Float(s.height), Float(topInset), Float(bottomInset))
            }
            .onChange(of: topInset) { _, t in
                engine.setSize(Float(size.width), Float(size.height), Float(t), Float(bottomInset))
            }
            .onChange(of: bottomInset) { _, b in
                engine.setSize(Float(size.width), Float(size.height), Float(topInset), Float(b))
            }
        }
        .ignoresSafeArea()
        .onDisappear {
            m.finish()
            m.extras.clearSave()
        }
        .onChange(of: overlay) { _, o in m.loop.isPaused = o == .PAUSE }
        .onChange(of: scenePhase) { _, phase in
            let ended = overlay == .FAIL || overlay == .WIN || engine.phase == .WON
            // Calls, Control Center and app switches pause the level like the gear button does.
            if phase != .active && overlay == .NONE && engine.phase == .PLAYING { overlay = .PAUSE }
            // Extras: iOS may end the app while it is away; save the level for "Continue level N?".
            if phase != .active && !ended { m.extras.autosave() }
        }
        .task {
            for await e in m.events {
                await handle(e, engine)
            }
        }
    }

    private func handle(_ e: GameEvent, _ engine: GameEngine) async {
        switch e {
        case .Won(let s):
            stars = s
            holder.get(levelNumber, daily).extras.clearSave()
            if let daily {
                dailyResult = ExtrasDailyPuzzle.finish(daily)
            } else {
                let opened = progress.completeLevel(levelNumber, s, rewardFor(levelNumber))
                if opened { newWorld = Themes.collectionName(collectionOf(levelNumber + 1)) }
            }
            audio.play(Sfx.Win)
            audio.haptic(Haptic.Success)
            try? await Task.sleep(nanoseconds: 900_000_000)
            overlay = .WIN
        case .Stuck:
            try? await Task.sleep(nanoseconds: 250_000_000)
            overlay = .REVIVE
        case .LockedSlot(let index):
            slotIndex = index
            overlay = .SLOT
        case .NoSpace:
            showToast("All parking spots are full!")
        case .VipBusy:
            showToast("The VIP spot is taken right now")
        }
    }
}

@MainActor
private func useBooster(_ engine: GameEngine, _ type: BoosterType) -> Bool {
    switch type {
    case .SHUFFLE: engine.shuffle(); return true
    case .CRANE: return engine.armCrane()
    case .SORT: engine.useSort(); return true
    }
}

// --- Board ------------------------------------------------------------------------------------

/// The full-screen board. Redraws once per display frame (the loop's `frame` is the only state read),
/// and passes taps straight to the engine, which maps them through the inverse board rotation.
private struct GameCanvas: View {
    let model: SessionModel
    @State private var touching = false

    var body: some View {
        let loop = model.loop
        let engine = model.engine
        let extras = model.extras
        // Capture the per-frame values inside the closure: SwiftUI skips a Canvas redraw when its
        // captures look unchanged, so reading `frame` only in `body` would freeze the board.
        let tick = loop.frame
        let time = Float(loop.time)
        Canvas(rendersAsynchronously: false) { ctx, size in
            _ = tick
            GameRenderer.drawGame(&ctx, engine, time)
            extras.draw(&ctx)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if touching { return }
                    touching = true
                    engine.onTap(Offset(Float(v.startLocation.x), Float(v.startLocation.y)))
                }
                .onEnded { _ in touching = false }
        )
    }
}

// --- HUD --------------------------------------------------------------------------------------

private struct Hud: View {
    let level: Int
    let difficulty: Difficulty
    let coins: Int
    let topInset: CGFloat
    let onPause: () -> Void
    /// Extras: replaces "Level N" (Daily Puzzle).
    var title: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            RoundButton(onClick: onPause, size: 44) { GameIcon(Icon.GEAR, 30) }
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                OText(title ?? "Level \(level)", .Title, size: 22, strokeWidth: 6)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 5)
                    .background(Color(argb: 0x66000000), in: RoundedRectangle(cornerRadius: 18))
                if difficulty != .NORMAL {
                    GText(difficulty.label ?? "", .Small, color: .white, size: 11, titleFont: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(difficulty == .HARD ? Color(argb: 0xFFFF6D00) : Color(argb: 0xFFD500F9),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .offset(y: -3)
                }
            }
            Spacer(minLength: 0)
            CoinPill(coins)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .padding(.top, topInset)
    }
}

private struct QueueSign: View {
    let engine: GameEngine
    @State private var bumpKey = 0

    var body: some View {
        let lay = engine.layout!
        let remaining = engine.remaining
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                OText("\(remaining)", .Title, size: 22, outline: Color(argb: 0xFF0D2C6B), strokeWidth: 5)
                GText("Queue", .Small, color: Color(argb: 0xFFFFE082), size: 12, titleFont: true)
                    .offset(y: -4)
            }
            .padding(.vertical, 2)
            .frame(width: 78)
            .background(LinearGradient(colors: [Color(argb: 0xFF64B5F6), Color(argb: 0xFF1E88E5)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 8))
            .padding(3)
            .background(Color(argb: 0xFF0D47A1), in: RoundedRectangle(cornerRadius: 10))
            .frame(width: 84)
            // bump.snapTo(1.18f); bump.animateTo(1f, spring(dampingRatio = 0.4f, stiffness = 600f))
            .keyframeAnimator(initialValue: CGFloat(1), trigger: bumpKey) { content, s in
                content.scaleEffect(s)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(1.18)
                    SpringKeyframe(1, spring: Spring(mass: 1, stiffness: 600, damping: 2 * 0.4 * 600.0.squareRoot()))
                }
            }
            Rectangle()
                .fill(Color(argb: 0xFF546E7A))
                .frame(width: 6, height: 14)
        }
        .frame(width: 84)
        .offset(x: CGFloat(lay.queueSign.x) - 42, y: CGFloat(lay.queueSign.y) - 26)
        .allowsHitTesting(false)
        .onAppear { bumpKey += 1 }
        .onChange(of: remaining) { _, _ in bumpKey += 1 }
    }
}

private struct TutorialLayer: View {
    let engine: GameEngine
    let width: CGFloat

    var body: some View {
        let lay = engine.layout!
        ZStack(alignment: .topLeading) {
            if let text = engine.tutorialText {
                GText(text, .Label, color: .white, size: 15, align: .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(width: width)
                    .background(Color(argb: 0x99000000))
                    .offset(y: CGFloat(lay.lotRect.top) + 6)
            }
            if let p = engine.tutorialPoint {
                TutorialHand(point: p.cg)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TutorialHand: View {
    let point: CGPoint
    @State private var clock = LoopClock()

    var body: some View {
        TimelineView(.animation) { tl in
            let t = clock.elapsed(tl.date)
            // animateFloat(-8f, 8f) is added to a pixel offset on Android (±4 dp on the reference phone).
            let bob = CGFloat(infiniteFloat(t, -8, 8, ms: 520, reverse: true)) / 2
            let ring = CGFloat(infiniteFloat(t, 1, 2, ms: 700, linear: true))
            ZStack(alignment: .topLeading) {
                Circle()
                    .stroke(Color.white.opacity(Double((2 - ring) * 0.7)), lineWidth: 4)
                    .frame(width: 60 * ring * 0.7, height: 60 * ring * 0.7)
                    .frame(width: 60, height: 60)
                    .offset(x: point.x - 30, y: point.y - 30)
                GameIcon(Icon.HAND, 64)
                    .offset(x: point.x - 14 + bob, y: point.y - 2 + bob)
            }
        }
    }
}

private struct BoosterBar: View {
    let engine: GameEngine
    let counts: [BoosterType: Int]
    let bottomInset: CGFloat
    let onBooster: (BoosterType) -> Void
    /// Extras: the Undo booster (fourth button) when enabled.
    var undoCount: Int = 0
    var onUndo: (() -> Void)? = nil

    var body: some View {
        let h = CGFloat(engine.layout.boosterBarH)
        let undo = ExtrasFeatures.undoBooster ? onUndo : nil
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            BoosterButton(label: "Shuffle", icon: .SHUFFLE, count: counts[.SHUFFLE] ?? 0) { onBooster(.SHUFFLE) }
            Spacer(minLength: 0)
            BoosterButton(label: "Crane", icon: .CRANE, count: counts[.CRANE] ?? 0) { onBooster(.CRANE) }
            Spacer(minLength: 0)
            BoosterButton(label: "Sort", icon: .SORT, count: counts[.SORT] ?? 0) { onBooster(.SORT) }
            Spacer(minLength: 0)
            if let undo {
                BoosterButton(label: "Undo", icon: .UNDO, count: undoCount, onClick: undo)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, undo == nil ? 20 : 6)
        .frame(height: h)
        .padding(.bottom, bottomInset)
    }
}

/// Pressed scale 0.92 (Compose `scale(if (pressed) 0.92f else 1f)`), click sound on release.
private struct BoosterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

private struct BoosterButton: View {
    let label: String
    let icon: Icon
    let count: Int
    let onClick: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                App.container.audio.play(Sfx.Click)
                onClick()
            } label: {
                VStack(spacing: 0) {
                    Spacer().frame(height: 5)
                    GameIcon(icon, 48)
                    OText(label, .Button, size: 15, outline: Color(argb: 0xFF1E4FA8), strokeWidth: 5)
                    Spacer(minLength: 0)
                }
                .frame(width: 78, height: 80)
                .background(
                    Canvas { ctx, size in BoosterButton.drawFace(&ctx, size) }
                        .frame(width: 78, height: 84)
                        .frame(width: 78, height: 80, alignment: .top)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(BoosterPressStyle())
            .padding(.top, 6)
            .padding(.trailing, 6)

            GText(count > 0 ? "\(count)" : "+", .Button, size: 14)
                .frame(width: 26, height: 26)
                .background(count > 0 ? Color(argb: 0xFFF2453D) : Color(argb: 0xFF5FC12F), in: Circle())
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                .allowsHitTesting(false)
        }
        .frame(width: 84, height: 86)
    }

    /// The 78×80 face; the blue lip below reaches 4 pt past it.
    static func drawFace(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w: CGFloat = 78
        let h: CGFloat = 80
        ctx.fill(Path(roundedRect: CGRect(x: 0, y: 4, width: w, height: h), cornerRadius: 18), with: .color(Color(argb: 0xFF1E5FD0)))
        ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h - 2), cornerRadius: 18), with: .color(.white))
        ctx.fill(Path(roundedRect: CGRect(x: 3, y: 3, width: w - 6, height: h - 8), cornerRadius: 15), with: .linearGradient(
            Gradient(colors: [Color(argb: 0xFFE9F4FF), Color(argb: 0xFFBFDDFF)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
    }
}

private struct CraneBanner: View {
    let armed: Bool
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            if armed {
                // Only the ✕ takes touches; the rest of the pill lets taps reach the board (like Compose).
                HStack(spacing: 0) {
                    GameIcon(Icon.CRANE, 34)
                        .allowsHitTesting(false)
                    Spacer().frame(width: 8)
                    GText("Tap any vehicle to lift it!", .Label, color: .white)
                        .allowsHitTesting(false)
                    Spacer().frame(width: 8)
                    Button(action: onCancel) {
                        GText("✕", .Label, color: .white)
                            .frame(width: 32, height: 32)
                            .background(Color(argb: 0xFFF2453D), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(argb: 0xE61A3A6B))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color(argb: 0xFFFFD54F), lineWidth: 2))
                        .allowsHitTesting(false)
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: armed)
    }
}

private struct DifficultyBanner: View {
    let difficulty: Difficulty
    let screenHeight: CGFloat
    @State private var show = true

    var body: some View {
        let col = difficulty == .HARD ? Color(argb: 0xFFFF6D00) : Color(argb: 0xFFD500F9)
        ZStack {
            if show {
                ZStack {
                    Color(argb: 0x66000000)
                    OText(difficulty.label ?? "", .Display, size: 42, color: Color(argb: 0xFFFFF59D),
                          outline: Color(argb: 0xFF4A1500), strokeWidth: 10)
                        .repeatingScale(0.96, 1.06, ms: 380)
                        .frame(maxWidth: .infinity)
                        .frame(height: 96)
                        .background(LinearGradient(colors: [.clear, col.opacity(0.9), col, col.opacity(0.9), .clear],
                                                   startPoint: .leading, endPoint: .trailing))
                }
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: AnyTransition.opacity.combined(with: .offset(y: -screenHeight / 6))
                ))
            }
        }
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            App.container.audio.play(Sfx.Whoosh)
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            App.container.audio.play(Sfx.Warning)
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.compose(dampingRatio: 1, stiffness: 400)) { show = false }
        }
    }
}

// --- Dialogs ----------------------------------------------------------------------------------

private struct PauseDialog: View {
    let visible: Bool
    let sound: Bool
    let music: Bool
    let vibration: Bool
    let onSound: (Bool) -> Void
    let onMusic: (Bool) -> Void
    let onVibration: (Bool) -> Void
    let onResume: () -> Void
    let onRestart: () -> Void
    let onHome: () -> Void

    var body: some View {
        GameDialog(visible: visible, onDismiss: onResume) {
            GamePanel("Paused", onClose: onResume) {
                ToggleRow(label: "Sound", value: sound, onChange: onSound)
                ToggleRow(label: "Music", value: music, onChange: onMusic)
                ToggleRow(label: "Vibration", value: vibration, onChange: onVibration)
                Spacer().frame(height: 14)
                GameButton("Resume", onClick: onResume, color: ButtonColor.GREEN)
                    .frame(maxWidth: .infinity)
                Spacer().frame(height: 10)
                HStack(spacing: 10) {
                    GameButton("Restart", onClick: onRestart, color: ButtonColor.ORANGE, height: 54, fontSize: 20)
                        .frame(maxWidth: .infinity)
                    GameButton("Home", onClick: onHome, color: ButtonColor.BLUE, height: 54, fontSize: 20)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct ToggleRow: View {
    let label: String
    let value: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            GText(label, .Label, size: 19)
                .frame(maxWidth: .infinity, alignment: .leading)
            GameToggle(value, onChange: onChange)
        }
        .padding(.vertical, 6)
    }
}

private struct PropDialog: View {
    let visible: Bool
    let type: BoosterType
    let coins: Int
    let onDismiss: () -> Void
    let onBuy: () -> Void
    let onAd: () -> Void

    var body: some View {
        GameDialog(visible: visible, onDismiss: onDismiss) {
            GamePanel(type.title, onClose: onDismiss) {
                GameIcon(PropDialog.icon(type), 92)
                    .frame(width: 124, height: 124)
                    .background(Color(argb: 0xFFFFE6C7), in: RoundedRectangle(cornerRadius: 26))
                    .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color(argb: 0xFFF3C98B), lineWidth: 3))
                Spacer().frame(height: 14)
                GText(type.description, .Body, color: Color(argb: 0xFF8A4B14), size: 17, align: .center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 20)
                HStack(spacing: 12) {
                    GameButton("\(type.price)", onClick: onBuy, color: ButtonColor.GREEN, fontSize: 22,
                               enabled: coins >= type.price, leading: CoinBadge.icon(30))
                        .frame(maxWidth: .infinity)
                    GameButton("Free", onClick: onAd, color: ButtonColor.ORANGE, fontSize: 22, leading: AdBadge.icon(30))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    static func icon(_ t: BoosterType) -> Icon {
        switch t {
        case .SHUFFLE: return .SHUFFLE
        case .CRANE: return .CRANE
        case .SORT: return .SORT
        }
    }
}

private struct ReviveDialog: View {
    let visible: Bool
    let coins: Int
    let onBuy: () -> Void
    let onAd: () -> Void
    let onGiveUp: () -> Void

    var body: some View {
        GameDialog(visible: visible, onDismiss: onGiveUp) {
            GamePanel("Out of Space!", frame: Color(argb: 0xFFF2453D), onClose: onGiveUp) {
                GameIcon(Icon.HEART, 120)
                    .repeatingScale(0.92, 1.08, ms: 420)
                Spacer().frame(height: 8)
                GText("Every parking spot is taken.\nKeep going with an extra spot!", .Body,
                      color: Color(argb: 0xFF8A4B14), size: 17, align: .center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 20)
                HStack(spacing: 12) {
                    GameButton("\(REVIVE_PRICE)", onClick: onBuy, color: ButtonColor.GREEN, fontSize: 22,
                               enabled: coins >= REVIVE_PRICE, leading: CoinBadge.icon(30))
                        .frame(maxWidth: .infinity)
                    GameButton("Revive", onClick: onAd, color: ButtonColor.ORANGE, fontSize: 22, leading: AdBadge.icon(30))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct FailDialog: View {
    let visible: Bool
    let width: CGFloat
    let onRetry: () -> Void
    let onSkip: () -> Void
    let onHome: () -> Void
    /// Extras: no Skip for the Daily Puzzle.
    var canSkip: Bool = true

    var body: some View {
        GameDialog(visible: visible, onDismiss: onHome) {
            VStack(spacing: 0) {
                RibbonBanner("Level Failed", Color(argb: 0xFF7A8BA8))
                    .frame(width: width * 0.9)
                Spacer().frame(height: 16)
                GameIcon(Icon.SAD, 150)
                    .repeatingRotation(-6, 6, ms: 600)
                Spacer().frame(height: 10)
                GText("So close! Want to try again?", .Label, color: .white, size: 18)
                Spacer().frame(height: 28)
                HStack(spacing: 14) {
                    GameButton("Retry", onClick: onRetry, color: ButtonColor.GREEN)
                        .frame(maxWidth: .infinity)
                    if canSkip {
                        GameButton("Skip", onClick: onSkip, color: ButtonColor.PURPLE, leading: AdBadge.icon(30))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: width * 0.92)
                Spacer().frame(height: 12)
                GameButton("Home", onClick: onHome, color: ButtonColor.BLUE, height: 50, fontSize: 19)
                    .frame(width: width * 0.5)
            }
        }
    }
}

private struct WinDialog: View {
    let visible: Bool
    let levelNumber: Int
    let stars: Int
    let reward: Int
    let newWorld: String?
    let onDouble: (_ done: @escaping () -> Void) -> Void
    let onNext: () -> Void
    let onHome: () -> Void
    /// Extras (Daily Puzzle): ribbon title, line under the stars, Next label and the new streak.
    var title: String = "Level Complete!"
    var subtitle: String? = nil
    var nextLabel: String = "Next"
    var streak: ExtrasDailyResult? = nil

    @State private var doubled = false
    @State private var flyKey = 0

    var body: some View {
        GameDialog(visible: visible, onDismiss: nil) {
            ZStack {
                VStack(spacing: 0) {
                    ZStack {
                        WinRays()
                            .frame(width: 300, height: 300)
                        VStack(spacing: 0) {
                            RibbonBanner(title, Color(argb: 0xFFFFA000), fontSize: 28)
                                .frame(width: 320)
                            Spacer().frame(height: 14)
                            StarRow(stars, 72, animate: visible, onStar: { i in
                                App.container.audio.play([Sfx.Star1, Sfx.Star2, Sfx.Star3][i])
                            })
                        }
                    }
                    GText(subtitle ?? "Level \(levelNumber) cleared", .Label, color: .white, size: 17)
                    Spacer().frame(height: 12)
                    HStack(spacing: 0) {
                        GameIcon(Icon.COIN, 40)
                        Spacer().frame(width: 8)
                        OText("+\(doubled ? reward * 2 : reward)", .Title, size: 30, color: Color(argb: 0xFFFFE082))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(argb: 0x66000000), in: RoundedRectangle(cornerRadius: 24))
                    if let newWorld {
                        Spacer().frame(height: 10)
                        GText("New world unlocked: \(newWorld)!", .Label, color: Color(argb: 0xFFB9F6CA), size: 16)
                    }
                    if let streak {
                        Spacer().frame(height: 10)
                        ExtrasStreakBadge(result: streak)
                    }
                    Spacer().frame(height: 26)
                    if !doubled {
                        GameButton("Claim x2", onClick: {
                            onDouble {
                                doubled = true
                                flyKey += 1
                                App.container.audio.play(Sfx.CoinBurst)
                            }
                        }, color: ButtonColor.GREEN, leading: AdBadge.icon(32))
                        .frame(width: 260)
                        Spacer().frame(height: 12)
                    }
                    HStack(spacing: 12) {
                        GameButton("Home", onClick: onHome, color: ButtonColor.BLUE, height: 56, fontSize: 20)
                            .frame(width: (300 - 12) / 2.4)
                        GameButton(nextLabel, onClick: onNext, color: ButtonColor.ORANGE, height: 56, fontSize: nextLabel.count > 6 ? 20 : 24)
                            .frame(width: (300 - 12) * 1.4 / 2.4)
                    }
                    .frame(width: 300)
                }
                if visible { CoinFly(key: flyKey) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: visible) {
            guard visible else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            App.container.audio.play(Sfx.CoinBurst)
            flyKey += 1
        }
    }
}

/// Twelve soft light wedges turning once every 9 s behind the "Level Complete!" ribbon.
private struct WinRays: View {
    @State private var on = false

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let shading = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [Color(argb: 0x66FFF59D), Color(argb: 0x00FFF59D)]),
                center: c, startRadius: 0, endRadius: size.width / 2)
            for i in 0..<12 {
                let a = Double(i) * 30 * .pi / 180
                let a2 = (Double(i) * 30 + 12) * .pi / 180
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + size.width * CGFloat(cos(a)), y: c.y + size.width * CGFloat(sin(a))))
                p.addLine(to: CGPoint(x: c.x + size.width * CGFloat(cos(a2)), y: c.y + size.width * CGFloat(sin(a2))))
                p.closeSubpath()
                ctx.fill(p, with: shading)
            }
        }
        .rotationEffect(.degrees(on ? 360 : 0))
        .onAppear {
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { on = true }
        }
        .allowsHitTesting(false)
    }
}

/// A burst of coins that arcs from the middle of the screen up to the coin counter.
private struct CoinFly: View {
    let key: Int

    var body: some View {
        if key > 0 {
            CoinBurst().id(key)
        }
    }
}

private struct CoinBurst: View {
    @State private var start = Date()
    @State private var done = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            TimelineView(.animation(minimumInterval: nil, paused: done)) { tl in
                let el = tl.date.timeIntervalSince(start)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<10, id: \.self) { i in
                        let raw = (el - Double(i) * 0.055) / 0.65
                        let t = raw <= 0 ? 0 : raw >= 1 ? 1 : TweenEasing.fastOutSlowIn(raw)
                        if t >= 0.001 && t <= 0.999 {
                            let startX = 0.5 + Double((i % 5) - 2) * 0.06
                            let x = startX + (0.86 - startX) * t
                            let y = 0.56 + (0.05 - 0.56) * t - sin(t * .pi) * 0.12
                            GameIcon(Icon.COIN, 34)
                                .scaleEffect(1 - t * 0.4)
                                .offset(x: CGFloat(x) * w - 17, y: CGFloat(y) * h - 17)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .task {
            // Each coin chimes as it lands: 650 ms flight, 55 ms apart, pitch rising.
            try? await Task.sleep(nanoseconds: 650_000_000)
            for i in 0..<10 {
                guard !Task.isCancelled else { return }
                App.container.audio.play(Sfx.Coin, 1 + Float(i) * 0.03)
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
            done = true
        }
    }
}


/// Safe-area insets of the key window (Dynamic Island / notch on top, home indicator at the bottom).
@MainActor
enum WindowInsets {
    static var current: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        return window?.safeAreaInsets ?? .zero
    }
}
