#if canImport(UIKit)
import UIKit
import QuartzCore
import Observation

/// Display-synced game loop. Runs at the screen's refresh rate (120 Hz on ProMotion when the app's Info.plist
/// sets `CADisableMinimumFrameDurationOnPhone`). Views read `frame` to redraw every tick.
@MainActor
@Observable
public final class GameLoop {
    /// Increments every display frame; read it in a view's `body` to redraw each frame.
    public private(set) var frame: Int = 0
    /// Seconds of unpaused game time.
    public private(set) var time: Double = 0
    /// Last frame's delta in seconds (clamped).
    public private(set) var dt: Double = 0

    public var isPaused: Bool = false {
        didSet { if !isPaused { lastTimestamp = nil } }
    }

    /// Called every display frame with the clamped delta (seconds), before `frame` changes.
    @ObservationIgnored public var onTick: ((Double) -> Void)?

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored public var maxDelta: Double = 0.1
    @ObservationIgnored private let preferred: Float

    public init(preferredFPS: Float = 120) {
        self.preferred = preferredFPS
    }

    public func start() {
        guard link == nil else { return }
        let proxy = LinkProxy(self)
        let l = CADisplayLink(target: proxy, selector: #selector(LinkProxy.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: preferred, preferred: preferred)
        l.add(to: .main, forMode: .common)
        link = l
        lastTimestamp = nil
    }

    public func stop() {
        link?.invalidate()
        link = nil
    }

    fileprivate func step(_ timestamp: CFTimeInterval) {
        guard !isPaused else { lastTimestamp = timestamp; return }
        let d = lastTimestamp.map { min(maxDelta, max(0, timestamp - $0)) } ?? (1.0 / 60.0)
        lastTimestamp = timestamp
        dt = d
        time += d
        onTick?(d)
        frame &+= 1
    }

    private final class LinkProxy: NSObject {
        weak var owner: GameLoop?
        init(_ o: GameLoop) { owner = o }
        @objc func tick(_ link: CADisplayLink) {
            let ts = link.targetTimestamp
            MainActor.assumeIsolated { owner?.step(ts) }
        }
    }
}
#endif

/// Fixed-step accumulator with an interpolation factor (`alpha`) for smooth rendering between steps.
public struct FixedStepper: Sendable {
    public let step: Double
    public let maxSteps: Int
    public private(set) var accumulator: Double = 0

    public init(hz: Double, maxSteps: Int = 8) {
        step = 1.0 / hz
        self.maxSteps = maxSteps
    }

    /// Advances by `dt` and calls `body` once per fixed step. Returns the interpolation alpha in [0, 1).
    @discardableResult
    public mutating func advance(_ dt: Double, _ body: () -> Void) -> Double {
        accumulator += dt
        var n = 0
        while accumulator >= step && n < maxSteps {
            body()
            accumulator -= step
            n += 1
        }
        if n == maxSteps { accumulator = min(accumulator, step) }
        return accumulator / step
    }

    public mutating func reset() { accumulator = 0 }
}
