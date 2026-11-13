import SwiftUI
import GameKit

// Home additions: the "Daily Puzzle" card (calendar badge, flame count, reward) between the Daily gift and Coney,
// its dialog with the 7-day streak strip, and the "Continue level N?" offer after a relaunch. Built from the game's
// own components (GameDialog, GamePanel, GameButton, GameIcon, OText/GText) so they look native.

private let PuzzleFrame = Color(argb: 0xFF8E_5CF0)

/// Shown once per app launch, when Home first appears and a valid autosave exists.
@MainActor
enum ExtrasResumeOffer {
    static var offered = false

    /// The save to offer now (marks it offered). Stale saves (yesterday's daily puzzle, a level that is no longer
    /// unlocked) are dropped instead.
    static func take(_ player: PlayerState) -> ExtrasSnapshot? {
        guard ExtrasFeatures.autosave, !offered, player.loaded else { return nil }
        offered = true
        let repo = App.container.extras
        guard let s = repo.savedGame else { return nil }
        if let d = s.day {
            if d != repo.today() || !ExtrasFeatures.dailyPuzzle {
                repo.clearSavedGame()
                return nil
            }
        } else if !player.isLevelUnlocked(s.level) {
            repo.clearSavedGame()
            return nil
        }
        return s
    }
}

/// Everything the extras add to the Home tab (sits above Home's content, below its Daily Reward dialog).
struct ExtrasHomeLayer: View {
    let player: PlayerState
    @Binding var resumeOffer: ExtrasSnapshot?
    let onDaily: () -> Void
    let onPlayLevel: (Int) -> Void
    /// The resume prompt closed without starting a level (Home may now show its Daily Reward).
    let onPromptClosed: () -> Void

    @State private var showPuzzle = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if ExtrasFeatures.dailyPuzzle {
                    // Between the Daily gift (left) and Coney (right), on the same row.
                    ExtrasDailyPuzzleCard(width: min(224, max(150, geo.size.width - 191))) { showPuzzle = true }
                        .offset(y: 112)
                }
                ExtrasDailyPuzzleDialog(visible: showPuzzle, onPlay: {
                    showPuzzle = false
                    onDaily()
                }, onClose: { showPuzzle = false })
                ExtrasResumeDialog(snapshot: resumeOffer, onContinue: {
                    guard let s = resumeOffer else { return }
                    App.container.extras.pendingResume = s
                    resumeOffer = nil
                    if s.isDaily { onDaily() } else { onPlayLevel(s.level) }
                }, onDiscard: {
                    App.container.extras.clearSavedGame()
                    resumeOffer = nil
                    onPromptClosed()
                }, onClose: {
                    resumeOffer = nil
                    onPromptClosed()
                })
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Card

struct ExtrasDailyPuzzleCard: View {
    let width: CGFloat
    let onOpen: () -> Void

    var body: some View {
        let ex = App.container.extras
        let today = ExtrasDay(ex.today())
        let solved = ex.puzzleSolved(today.epochDay)
        let streak = ex.puzzleStreakAlive(today.epochDay)
        let reward = ExtrasDailyPuzzle.reward(streak: ex.puzzleStreakAfterSolving(today.epochDay))
        Button {
            App.container.audio.play(Sfx.Click)
            onOpen()
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    ExtrasCalendarBadge(day: today, size: 46)
                        .repeatingRotation(-6, 6, ms: 500, active: !solved && !Motion.reduce)
                    VStack(alignment: .leading, spacing: 1) {
                        OText("Daily Puzzle", .Title, size: 17, outline: Color(argb: 0xFF3B_1F7A), strokeWidth: 5, align: .leading)
                            .fixedSize()
                        HStack(spacing: 3) {
                            GameIcon(Icon.FLAME, 21)
                                .saturation(streak > 0 ? 1 : 0)
                                .opacity(streak > 0 ? 1 : 0.6)
                            OText("\(streak)", .Title, size: 16, outline: Color(argb: 0xFF3B_1F7A), strokeWidth: 4)
                                .fixedSize()
                            Spacer().frame(width: 5)
                            if solved {
                                GameIcon(Icon.CHECK, 19)
                                OText("Solved", .Title, size: 15, color: Color(argb: 0xFFB9_F6CA), outline: Color(argb: 0xFF1B_5E20), strokeWidth: 4)
                                    .fixedSize()
                            } else {
                                GameIcon(Icon.COIN, 19)
                                OText("+\(reward)", .Title, size: 16, color: Color(argb: 0xFFFF_E082), outline: Color(argb: 0xFF3B_1F7A), strokeWidth: 4)
                                    .fixedSize()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 9)
                .padding(.trailing, 6)
                .frame(width: width, height: 72)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(argb: 0xFF3B_1F7A)).offset(y: 4)
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(colors: [Color(argb: 0xFFB3_8CFF), Color(argb: 0xFF8E_5CF0), Color(argb: 0xFF6A_3FD1)],
                                                 startPoint: .top, endPoint: .bottom))
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.22))
                            .frame(height: 10).padding(.horizontal, 16).offset(y: -24)
                        RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white, lineWidth: 3)
                    }
                )
                if !solved {
                    GText("!", .Button, size: 13)
                        .frame(width: 20, height: 20)
                        .background(Color(argb: 0xFFF2_453D), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .offset(x: 5, y: -6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(solved ? "Daily Puzzle, solved. Streak \(streak)." : "Daily Puzzle. Streak \(streak). Reward \(reward) coins.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Dialog

struct ExtrasDailyPuzzleDialog: View {
    let visible: Bool
    let onPlay: () -> Void
    let onClose: () -> Void

    var body: some View {
        let ex = App.container.extras
        let today = ExtrasDay(ex.today())
        let solved = ex.puzzleSolved(today.epochDay)
        let streak = ex.puzzleStreakAlive(today.epochDay)
        let reward = ExtrasDailyPuzzle.reward(streak: ex.puzzleStreakAfterSolving(today.epochDay))
        GameDialog(visible: visible, onDismiss: onClose) {
            GamePanel("Daily Puzzle", frame: PuzzleFrame, onClose: onClose) {
                HStack(spacing: 10) {
                    GameIcon(Icon.FLAME, 60)
                        .saturation(streak > 0 ? 1 : 0)
                        .opacity(streak > 0 ? 1 : 0.55)
                        .repeatingScale(0.94, 1.06, ms: 600, active: streak > 0 && !Motion.reduce)
                    VStack(alignment: .leading, spacing: 0) {
                        OText("\(streak)", .Title, size: 38, color: Color(argb: 0xFFFF_B74D), outline: Color(argb: 0xFF6B_2300), strokeWidth: 8, align: .leading)
                            .fixedSize()
                        GText("day streak", .Label, color: Color(argb: 0xFF8A_4B14), size: 16)
                    }
                    Spacer(minLength: 0)
                    ExtrasCalendarBadge(day: today, size: 54)
                }
                Spacer().frame(height: 12)
                ExtrasWeekStrip(marks: ex.puzzleWeek(today.epochDay))
                Spacer().frame(height: 16)
                if solved {
                    GText("Solved! A new puzzle arrives tomorrow.", .Label, color: Color(argb: 0xFF2E_7D32), size: 17, align: .center)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer().frame(height: 4)
                    ExtrasMidnightCountdown()
                } else {
                    HStack(spacing: 6) {
                        GText("Today's reward", .Label, color: Color(argb: 0xFF8A_4B14), size: 17)
                        GameIcon(Icon.COIN, 30)
                        OText("+\(reward)", .Title, size: 24, color: Color(argb: 0xFFFF_E082), outline: Color(argb: 0xFF7A_3B00), strokeWidth: 6)
                            .fixedSize()
                    }
                    Spacer().frame(height: 14)
                    GameButton("Play", onClick: onPlay, color: .GREEN, leading: GameIcon(Icon.PLAY, 30))
                        .frame(maxWidth: .infinity)
                }
                Spacer().frame(height: 12)
                GText("A new level every day. Solve days in a row: +10 coins per streak day, up to 150.", .Small,
                      color: Color(argb: 0xFF8A_4B14).opacity(0.85), size: 12, align: .center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Seven days ending today: a lit flame on solved days, today highlighted.
struct ExtrasWeekStrip: View {
    let marks: [ExtrasDayMark]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(marks, id: \.day.epochDay) { m in
                ExtrasWeekTile(mark: m)
            }
        }
    }
}

private struct ExtrasWeekTile: View {
    let mark: ExtrasDayMark

    var body: some View {
        let today = mark.isToday
        let colors: [Color] = today
            ? [Color(argb: 0xFFFF_F59D), Color(argb: 0xFFFF_C107)]
            : mark.solved ? [Color(argb: 0xFFFF_E0B2), Color(argb: 0xFFFF_B74D)]
            : [Color(argb: 0xFFFF_FFFF), Color(argb: 0xFFFF_E6C7)]
        VStack(spacing: 1) {
            GText(mark.day.weekdayLetter, .Small, color: Color(argb: 0xFF8A_4B14), size: 12, titleFont: true)
            ZStack {
                if mark.solved {
                    GameIcon(Icon.FLAME, 26)
                } else {
                    Circle()
                        .strokeBorder(Color(argb: 0xFFE0_B97F), style: StrokeStyle(lineWidth: 2.5, dash: today ? [4, 3] : []))
                        .frame(width: 20, height: 20)
                }
            }
            .frame(height: 28)
            GText("\(mark.day.dayOfMonth)", .Small, color: Color(argb: 0xFF6D_3A00), size: 11, titleFont: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 66)
        .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(today ? Color(argb: 0xFFFF_8F00) : Color(argb: 0xFFE0_B97F), lineWidth: today ? 2.5 : 1.5))
        .repeatingScale(1, 1.06, ms: 500, active: today && !mark.solved && !Motion.reduce)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mark.day.label)\(mark.solved ? ", solved" : "")")
    }
}

/// "New puzzle in 5:12:09" until local midnight.
struct ExtrasMidnightCountdown: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let next = Calendar.current.startOfDay(for: tl.date.addingTimeInterval(86_400))
            let s = max(0, Int(next.timeIntervalSince(tl.date)))
            GText(String(format: "New puzzle in %d:%02d:%02d", s / 3600, s / 60 % 60, s % 60), .Label,
                  color: Color(argb: 0xFF8A_4B14), size: 15)
                .monospacedDigit()
        }
    }
}

/// Win dialog line for a solved daily puzzle: the flame and the new streak.
struct ExtrasStreakBadge: View {
    let result: ExtrasDailyResult

    var body: some View {
        HStack(spacing: 6) {
            GameIcon(Icon.FLAME, 36)
                .repeatingScale(0.92, 1.08, ms: 500, active: !Motion.reduce)
            OText(result.streak == 1 ? "Streak started!" : "\(result.streak) day streak!", .Title, size: 22,
                  color: Color(argb: 0xFFFF_CC80), outline: Color(argb: 0xFF6B_2300), strokeWidth: 6)
                .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(Color(argb: 0x66000000), in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Continue level N?

struct ExtrasResumeDialog: View {
    let snapshot: ExtrasSnapshot?
    let onContinue: () -> Void
    let onDiscard: () -> Void
    let onClose: () -> Void

    var body: some View {
        GameDialog(visible: snapshot != nil, onDismiss: onClose) {
            if let s = snapshot {
                GamePanel("Welcome Back!", onClose: onClose) {
                    ZStack(alignment: .bottomTrailing) {
                        if let d = s.day {
                            ExtrasCalendarBadge(day: ExtrasDay(d), size: 84)
                                .frame(width: 104, height: 100)
                        } else {
                            ZStack {
                                Circle().fill(Color(argb: 0xFFB2_6A00)).offset(y: 4)
                                Circle().fill(LinearGradient(colors: [Color(argb: 0xFFFF_F59D), Color(argb: 0xFFFF_C107), Color(argb: 0xFFFF_8F00)],
                                                             startPoint: .top, endPoint: .bottom))
                                Circle().strokeBorder(Color.white, lineWidth: 4)
                                OText("\(s.level)", .Title, size: s.level >= 1000 ? 30 : 38, outline: Color(argb: 0xFF7A_3B00), strokeWidth: 8)
                                    .fixedSize()
                            }
                            .frame(width: 96, height: 96)
                            .frame(width: 104, height: 100)
                        }
                        GameIcon(Icon.PLAY, 26)
                            .frame(width: 38, height: 38)
                            .background(Color(argb: 0xFF5F_C12F), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                    }
                    Spacer().frame(height: 10)
                    GText(s.isDaily ? "Continue today's Daily Puzzle?" : "Continue level \(s.level)?", .Label, size: 20, align: .center)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer().frame(height: 6)
                    GText("Your game was saved when you left. Pick up right where you stopped: "
                          + (s.waiting == 1 ? "1 passenger is still waiting." : "\(s.waiting) passengers are still waiting."),
                          .Body, color: Color(argb: 0xFF8A_4B14), size: 16, align: .center)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer().frame(height: 20)
                    HStack(spacing: 12) {
                        GameButton("Discard", onClick: onDiscard, color: .BLUE, fontSize: 20)
                            .frame(maxWidth: .infinity)
                        GameButton("Continue", onClick: onContinue, color: .GREEN, fontSize: 20)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
