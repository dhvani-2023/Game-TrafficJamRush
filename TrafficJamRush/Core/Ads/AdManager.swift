import Foundation
import Observation
import GameKit

// Port of core/ads/AdManager.kt. Android shipped a FakeAdManager that showed a countdown overlay (AdOverlay)
// before rewarding. iOS never shows a fake ad: every rewarded request goes to GameKit `Ads.rewarded`, which grants
// instantly in this build and can be backed by a real ad network later without touching game code.

/// Rewarded-ad seam. The UI only ever calls [showRewarded].
@MainActor
protocol AdManager: AnyObject {
    /// Shows a rewarded ad for [placement]; [onReward] runs only if the reward was granted.
    func showRewarded(_ placement: String, onReward: @escaping () -> Void, onClosed: @escaping () -> Void)
}

extension AdManager {
    func showRewarded(_ placement: String, onReward: @escaping () -> Void) {
        showRewarded(placement, onReward: onReward, onClosed: {})
    }
}

/// The app's ad manager (Kotlin `FakeAdManager` in AppContainer). Forwards to `Ads.rewarded`.
@Observable
@MainActor
final class RewardedAdManager: AdManager {

    /// Kept for source compatibility with the Kotlin AdOverlay; always nil because no fake ad is ever shown.
    final class Request {
        let placement: String
        let onReward: () -> Void
        let onClosed: () -> Void

        init(_ placement: String, _ onReward: @escaping () -> Void, _ onClosed: @escaping () -> Void) {
            self.placement = placement
            self.onReward = onReward
            self.onClosed = onClosed
        }
    }

    private(set) var active: Request?

    /// Android's AdOverlay played Sfx.Unlock when a rewarded ad finished; set this to keep that sound.
    @ObservationIgnored weak var audio: AudioManager?
    @ObservationIgnored private var inFlight = false

    init(audio: AudioManager? = nil) {
        self.audio = audio
    }

    /// Whether rewarded buttons say "Watch ad" (real ads) or "FREE" (this build).
    var usesRealAds: Bool { Ads.usesRealAds }
    var isAvailable: Bool { Ads.rewarded.isAvailable }

    func showRewarded(_ placement: String, onReward: @escaping () -> Void, onClosed: @escaping () -> Void) {
        if inFlight { return }
        inFlight = true
        Ads.rewarded.show(AdPlacement(placement)) { [weak self] granted in
            self?.inFlight = false
            if granted {
                self?.audio?.play(.Unlock)
                onReward()
            }
            onClosed()
        }
    }

    /// Kotlin `finish(rewarded)`; nothing is ever pending on iOS.
    func finish(_ rewarded: Bool) {}
}

/// Kotlin name used by AppContainer / AdOverlay.
typealias FakeAdManager = RewardedAdManager
