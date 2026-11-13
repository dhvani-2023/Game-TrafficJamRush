import Foundation

/// Where a rewarded ad was requested from (mirrors Android placement strings).
public struct AdPlacement: Hashable, Sendable, ExpressibleByStringLiteral {
    public let id: String
    public init(_ id: String) { self.id = id }
    public init(stringLiteral value: String) { id = value }
}

/// Rewarded-ad seam. The default gateway grants rewards directly (no fake ad is ever shown);
/// an AdMob adapter can be plugged in later without touching game code.
@MainActor
public protocol RewardedAdGateway: AnyObject {
    /// Whether "watch ad" buttons should be visible.
    var isAvailable: Bool { get }
    /// Shows an ad if one is loaded; `completion(true)` means the reward should be granted.
    func show(_ placement: AdPlacement, completion: @escaping (Bool) -> Void)
}

/// Ships when no ad network is configured: every rewarded action is granted immediately.
@MainActor
public final class InstantRewardGateway: RewardedAdGateway {
    public init() {}
    public var isAvailable: Bool { true }
    public func show(_ placement: AdPlacement, completion: @escaping (Bool) -> Void) { completion(true) }
}

@MainActor
public enum Ads {
    public static var rewarded: RewardedAdGateway = InstantRewardGateway()
    /// When false, UI should say "Free" / "Get" instead of "Watch ad".
    public static var usesRealAds = false
}
