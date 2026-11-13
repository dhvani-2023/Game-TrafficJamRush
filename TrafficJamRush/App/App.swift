import SwiftUI
import Observation
import GameKit

/// Process-wide singletons. Small enough that a DI framework would be overkill.
@MainActor
final class AppContainer {
    let progress: ProgressRepository
    let audio: AudioManager
    /// Kotlin `FakeAdManager`; on iOS every rewarded request goes through GameKit `Ads` (no fake ad screen).
    let ads: RewardedAdManager
    /// iOS extras (daily puzzle, undo booster, autosave, colour-blind symbols); keys live in the same "player" store.
    let extras: ExtrasRepository

    init() {
        progress = ProgressRepository()
        audio = AudioManager()
        ads = RewardedAdManager(audio: audio)
        extras = ExtrasRepository(store: progress.store)
    }
}

/// Kotlin `App` (the Application subclass). `App.container` is the same process-wide accessor.
/// The SwiftUI entry point is `TrafficJamRushApp` (it conforms to `SwiftUI.App`).
@MainActor
enum App {
    static let container = AppContainer()

    private static var created = false

    /// Kotlin `App.onCreate`: register fonts, load progress, then keep the audio switches in sync with the
    /// saved settings (Kotlin collects `progress.state` and copies sound / vibration / music).
    static func onCreate() {
        guard !created else { return }
        created = true
        FontRegistry.registerAll()
        Haptics.prepare()
        container.progress.load()
        syncAudioSettings()
    }

    private static func syncAudioSettings() {
        let c = container
        withObservationTracking {
            let s = c.progress.state
            c.audio.soundOn = s.sound
            c.audio.vibrationOn = s.vibration
            c.audio.musicOn = s.music
        } onChange: {
            // Fires before the new value is stored; re-read it on the next main-actor turn.
            Task { @MainActor in syncAudioSettings() }
        }
    }

    /// Kotlin `ProcessLifecycleOwner` onStart / onStop.
    static func setForeground(_ fg: Bool) {
        container.audio.setForeground(fg)
    }
}
