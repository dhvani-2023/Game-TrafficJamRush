import SwiftUI
import Observation
import GameKit

/// Root content (Kotlin `MainActivity.setContent`). The Android fake `AdOverlay` is gone: rewarded ads go
/// through GameKit `Ads`, which never shows a placeholder.
struct MainActivity: View {
    var body: some View {
        CarTrafficJamTheme {
            AppNavHost(debugLevel: MainActivity.debugLevel)
        }
        .gameChrome()
    }

    /// Debug builds can jump straight into a level: launch with `-debug_level N`
    /// (Android: `adb shell am start ... --ei debug_level N`).
    static var debugLevel: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "debug_level")
        #else
        return 0
        #endif
    }
}

/// NavHost destinations ("splash", "onboarding", "main", "game/{level}", "web/{doc}").
enum Route: Hashable {
    case splash
    case onboarding
    case main
    case game(Int)
    case web(String)
    /// Extras: the Daily Puzzle of a local epoch day.
    case daily(Int)
}

/// Minimal `NavController`: a back stack with Compose's `navigate { popUpTo; launchSingleTop }` rules.
@MainActor
@Observable
final class NavController {
    private(set) var backStack: [Route]
    /// True while the last change was a pop (pop transitions only fade).
    private(set) var popping = false

    init(start: Route) { backStack = [start] }

    var current: Route { backStack.last ?? .main }

    func navigate(_ route: Route, popUpTo: Route? = nil, inclusive: Bool = false, launchSingleTop: Bool = false) {
        var stack = backStack
        if let p = popUpTo, let i = stack.lastIndex(of: p) {
            stack.removeSubrange((inclusive ? i : i + 1)...)
        }
        if launchSingleTop, stack.last == route { return }
        stack.append(route)
        apply(stack, pop: false)
    }

    func popBackStack() {
        guard backStack.count > 1 else { return }
        apply(Array(backStack.dropLast()), pop: true)
    }

    func popBackStack(_ route: Route, inclusive: Bool) {
        guard let i = backStack.lastIndex(of: route) else { return }
        let stack = Array(backStack[..<(inclusive ? i : i + 1)])
        guard !stack.isEmpty else { return }
        apply(stack, pop: true)
    }

    private func apply(_ stack: [Route], pop: Bool) {
        popping = pop
        withAnimation(NavMotion.enter) { backStack = stack }
    }
}

/// Compose NavHost transitions: enter fadeIn(260) + scaleIn(0.96), exit fadeOut(200); pops only fade.
enum NavMotion {
    static let enter = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.26)
    static let exit = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)

    static let push = AnyTransition.asymmetric(
        insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.96)).animation(enter),
        removal: AnyTransition.opacity.animation(exit)
    )
    static let pop = AnyTransition.asymmetric(
        insertion: AnyTransition.opacity.animation(enter),
        removal: AnyTransition.opacity.animation(exit)
    )
}

struct AppNavHost: View {
    let debugLevel: Int
    @State private var nav = NavController(start: .splash)

    var body: some View {
        ZStack {
            // MaterialTheme background (GameColors.SkyBottom) shows through cross-fades.
            Color(argb: 0xFF1E88E5).ignoresSafeArea()
            destination(nav.current)
                .id(nav.current)
                .transition(nav.popping ? NavMotion.pop : NavMotion.push)
        }
        .task(id: debugLevel) {
            guard debugLevel > 0 else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            nav.navigate(.main, popUpTo: .splash, inclusive: true)
            nav.navigate(.game(min(max(debugLevel, 1), TOTAL_LEVELS)))
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .splash:
            SplashScreen { onboarded in
                nav.navigate(onboarded ? .main : .onboarding, popUpTo: .splash, inclusive: true)
            }
        case .onboarding:
            OnboardingScreen {
                nav.navigate(.main, popUpTo: .onboarding, inclusive: true)
            }
        case .main:
            MainScreen(
                onPlay: { level in nav.navigate(.game(level), launchSingleTop: true) },
                onOpenDoc: { doc in nav.navigate(.web(doc)) },
                onDaily: { nav.navigate(.daily(ExtrasDay.today().epochDay), launchSingleTop: true) }
            )
        case .game(let level):
            GameScreen(
                levelNumber: level,
                onHome: { nav.popBackStack(.main, inclusive: false) },
                onPlayLevel: { next in nav.navigate(.game(next), popUpTo: .main) }
            )
        case .web(let doc):
            WebScreen(doc: doc) { nav.popBackStack() }
        case .daily(let day):
            GameScreen(
                levelNumber: 0,
                onHome: { nav.popBackStack(.main, inclusive: false) },
                onPlayLevel: { next in nav.navigate(.game(next), popUpTo: .main) },
                daily: ExtrasDay(day)
            )
        }
    }
}
