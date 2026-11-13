import SwiftUI
import GameKit

/// SwiftUI entry point (Android: `App` + `MainActivity`).
@main
struct TrafficJamRushApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(GameAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        App.onCreate()
    }

    var body: some Scene {
        WindowGroup {
            MainActivity()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: App.setForeground(true)
            case .background: App.setForeground(false)
            default: break
            }
        }
    }
}
