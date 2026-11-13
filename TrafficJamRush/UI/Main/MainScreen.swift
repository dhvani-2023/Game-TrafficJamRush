import SwiftUI
import GameKit

enum Tab: Int, CaseIterable {
    case LEVELS, COLLECTIONS, HOME, GARAGE, SETTINGS

    var label: String {
        switch self {
        case .LEVELS: return "Levels"
        case .COLLECTIONS: return "Worlds"
        case .HOME: return "Home"
        case .GARAGE: return "Garage"
        case .SETTINGS: return "Settings"
        }
    }

    var icon: Icon {
        switch self {
        case .LEVELS: return .MAP
        case .COLLECTIONS: return .COLLECTION
        case .HOME: return .HOME
        case .GARAGE: return .GARAGE
        case .SETTINGS: return .GEAR
        }
    }
}

private enum LockRequest: Equatable {
    case Level(n: Int)
    case Collection(c: Int)
}

/// `rememberSaveable` state of the main screen: survives a trip into a level and back.
@MainActor
enum MainScreenMemory {
    static var tab: Tab = .HOME
}

struct MainScreen: View {
    let onPlay: (Int) -> Void
    let onOpenDoc: (String) -> Void
    /// Extras: open today's Daily Puzzle.
    var onDaily: () -> Void = {}

    @State private var tab: Tab = MainScreenMemory.tab
    @State private var scrollToCollection = 0
    @State private var lock: LockRequest? = nil

    private var audio: AudioManager { App.container.audio }
    private var progress: ProgressRepository { App.container.progress }

    var body: some View {
        let player = progress.state
        ZStack {
            SkyBackground {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        ZStack {
                            tabContent(tab, player)
                                .id(tab)
                                .transition(.asymmetric(
                                    insertion: AnyTransition.opacity.animation(tweenAnimation(220)),
                                    removal: AnyTransition.opacity.animation(tweenAnimation(160))
                                ))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Android hides its navigation bar; on iOS the bar keeps clear of most of the home-indicator zone.
                        BottomBar(selected: tab, bottomInset: max(0, geo.safeAreaInsets.bottom - 16)) { t in
                            if t != tab { audio.play(Sfx.Click) }
                            withAnimation(tweenAnimation(220)) { tab = t }
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }

            WatchAdDialog(
                visible: lock != nil,
                title: lockTitle,
                message: lockMessage,
                onWatch: {
                    let r = lock
                    App.container.ads.showRewarded("unlock", onReward: {
                        switch r {
                        case .Level(let n): progress.unlockLevel(n)
                        case .Collection(let c):
                            progress.unlockCollection(c)
                            scrollToCollection = c
                        case nil: break
                        }
                        lock = nil
                    })
                },
                onDismiss: { lock = nil }
            )
        }
        .onAppear { audio.playMusic(Music.Home) }
        .onChange(of: tab) { _, t in MainScreenMemory.tab = t }
    }

    private var lockTitle: String {
        if case .Collection = lock { return "Locked World" }
        return "Locked Level"
    }

    private var lockMessage: String {
        let watch = Ads.usesRealAds
        switch lock {
        case .Level(let n):
            return watch ? "Level \(n) is locked.\nWatch a short ad to unlock it now!"
                : "Level \(n) is locked.\nUnlock it now for free!"
        case .Collection(let c):
            return watch ? "\(Themes.collectionName(c)) is locked.\nWatch a short ad to open this world!"
                : "\(Themes.collectionName(c)) is locked.\nOpen this world now for free!"
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private func tabContent(_ t: Tab, _ player: PlayerState) -> some View {
        switch t {
        case .HOME:
            HomeTab(
                player: player,
                onPlay: { onPlay(player.nextLevel) },
                onSettings: { setTab(.SETTINGS) },
                onWorld: { c in scrollToCollection = c; setTab(.LEVELS) },
                onDaily: onDaily,
                onPlayLevel: { n in onPlay(n) }
            )
        case .LEVELS:
            LevelsTab(
                player: player,
                scrollToCollection: scrollToCollection,
                onScrolled: { scrollToCollection = 0 },
                onLevel: { n in
                    if player.isLevelUnlocked(n) { onPlay(n) } else { lock = .Level(n: n) }
                }
            )
        case .COLLECTIONS:
            CollectionsTab(player: player, onOpen: { c in
                if player.isCollectionUnlocked(c) {
                    scrollToCollection = c
                    setTab(.LEVELS)
                } else {
                    lock = .Collection(c: c)
                }
            })
        case .GARAGE:
            GarageTab(player: player)
        case .SETTINGS:
            SettingsTab(player: player, onOpenDoc: onOpenDoc)
        }
    }

    private func setTab(_ t: Tab) {
        withAnimation(tweenAnimation(220)) { tab = t }
    }
}

private struct BottomBar: View {
    let selected: Tab
    let bottomInset: CGFloat
    let onSelect: (Tab) -> Void

    var body: some View {
        GeometryReader { geo in
            let total = Tab.allCases.reduce(CGFloat(0)) { $0 + weight($1) }
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { t in
                    BottomBarItem(tab: t, selected: t == selected)
                        .frame(width: geo.size.width * weight(t) / total, height: 74)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(t) }
                }
            }
            .animation(.compose(dampingRatio: 0.7), value: selected)
        }
        .frame(height: 74)
        .padding(.bottom, bottomInset)
        .background(BottomBar.background)
    }

    private func weight(_ t: Tab) -> CGFloat { t == selected ? 1.45 : 1 }

    private static var background: some View {
        VStack(spacing: 0) {
            Color(argb: 0xFFFFF3D6).frame(height: 4)
            LinearGradient(colors: [Color(argb: 0xFF3D8BFF), Color(argb: 0xFF1C5BD0)], startPoint: .top, endPoint: .bottom)
        }
        .background(Color(argb: 0xFF0E3A8C))
    }
}

private struct BottomBarItem: View {
    let tab: Tab
    let selected: Bool

    var body: some View {
        ZStack {
            if selected {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(argb: 0xFF7FB8FF), Color(argb: 0xFF3C82F0)], startPoint: .top, endPoint: .bottom))
                    .padding(.horizontal, 2)
                    .padding(.top, 4)
            }
            // divider
            Rectangle()
                .fill(Color(argb: 0x33000000))
                .frame(width: 1)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
            GameIcon(tab.icon, 42)
                .scaleEffect(selected ? 1.25 : 1)
                .animation(.compose(dampingRatio: 0.5), value: selected)
                .offset(y: selected ? -16 : 0)
                .animation(.compose(dampingRatio: 0.5, stiffness: 500), value: selected)
            if selected {
                OText(tab.label, .Button, size: 15, outline: Color(argb: 0xFF0E3A8C), strokeWidth: 5)
                    .padding(.bottom, 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}
