import SwiftUI

// Small helpers that reproduce Compose animation specs used by the screens (tween easings,
// `rememberInfiniteTransition` loops) without per-frame allocations.

/// Compose easing curves (cubic Béziers) evaluated on the CPU.
enum TweenEasing {
    /// `FastOutSlowInEasing` = cubic-bezier(0.4, 0, 0.2, 1) (Compose's default tween easing).
    static func fastOutSlowIn(_ t: Double) -> Double { cubicBezier(0.4, 0, 0.2, 1, t) }

    /// `CubicBezierEasing(x1, y1, x2, y2)`.
    static func cubicBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        var u = t
        for _ in 0..<8 {
            let x = bez(u, x1, x2) - t
            if abs(x) < 1e-7 { return bez(u, y1, y2) }
            let d = bezD(u, x1, x2)
            if abs(d) < 1e-6 { break }
            u -= x / d
        }
        // Bisection fallback.
        var lo = 0.0, hi = 1.0
        u = t
        for _ in 0..<40 {
            let x = bez(u, x1, x2)
            if abs(x - t) < 1e-7 { break }
            if x < t { lo = u } else { hi = u }
            u = (lo + hi) / 2
        }
        return bez(u, y1, y2)
    }

    @inline(__always) private static func bez(_ u: Double, _ a: Double, _ b: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }

    @inline(__always) private static func bezD(_ u: Double, _ a: Double, _ b: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
    }
}

/// `animateFloat(from, to, infiniteRepeatable(tween(ms, easing), repeatMode))` sampled `elapsed` seconds after it started.
@inline(__always)
func infiniteFloat(_ elapsed: Double, _ from: Double, _ to: Double, ms: Double, reverse: Bool = false, linear: Bool = false) -> Double {
    let d = ms / 1000
    let cycles = max(0, elapsed) / d
    let k = cycles.rounded(.down)
    var f = cycles - k
    if reverse && Int(k) % 2 == 1 { f = 1 - f }
    let e = linear ? f : TweenEasing.fastOutSlowIn(f)
    return from + (to - from) * e
}

/// Compose `tween(ms)` (FastOutSlowIn) as a SwiftUI animation.
func tweenAnimation(_ ms: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: ms / 1000) }

// MARK: - Repeating effects (rememberInfiniteTransition + RepeatMode.Reverse)

/// Scale that ping-pongs between `from` and `to` with a FastOutSlowIn tween of `ms` each way.
struct RepeatingScale: ViewModifier {
    let from: CGFloat
    let to: CGFloat
    let ms: Double
    var active: Bool = true
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? (on ? to : from) : 1)
            .onAppear { if active { start() } }
            .onChange(of: active) { _, a in if a { start() } else { stop() } }
    }

    private func start() {
        withAnimation(tweenAnimation(ms).repeatForever(autoreverses: true)) { on = true }
    }

    private func stop() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { on = false }
    }
}

/// Rotation (degrees) that ping-pongs between `from` and `to`.
struct RepeatingRotation: ViewModifier {
    let from: Double
    let to: Double
    let ms: Double
    var active: Bool = true
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (on ? to : from) : 0))
            .onAppear { if active { start() } }
            .onChange(of: active) { _, a in if a { start() } else { stop() } }
    }

    private func start() {
        withAnimation(tweenAnimation(ms).repeatForever(autoreverses: true)) { on = true }
    }

    private func stop() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { on = false }
    }
}

/// Vertical offset (points) that ping-pongs between `from` and `to`.
struct RepeatingOffsetY: ViewModifier {
    let from: CGFloat
    let to: CGFloat
    let ms: Double
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .offset(y: on ? to : from)
            .onAppear {
                withAnimation(tweenAnimation(ms).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

extension View {
    func repeatingScale(_ from: CGFloat, _ to: CGFloat, ms: Double, active: Bool = true) -> some View {
        modifier(RepeatingScale(from: from, to: to, ms: ms, active: active))
    }

    func repeatingRotation(_ from: Double, _ to: Double, ms: Double, active: Bool = true) -> some View {
        modifier(RepeatingRotation(from: from, to: to, ms: ms, active: active))
    }

    func repeatingOffsetY(_ from: CGFloat, _ to: CGFloat, ms: Double) -> some View {
        modifier(RepeatingOffsetY(from: from, to: to, ms: ms))
    }
}

/// Clock for `TimelineView`-driven loops: seconds since the view first appeared.
struct LoopClock {
    let start: Date
    init() { start = Date() }
    func elapsed(_ date: Date) -> Double { date.timeIntervalSince(start) }
}

// MARK: - Springs sampled on the CPU

/// Position of a Compose `spring(dampingRatio, stiffness)` (mass 1, zero initial velocity) animating
/// from `from` to `to`, `t` seconds after it started. Used where a value feeds a per-frame Canvas.
func springValue(_ t: Double, from: Double, to: Double, dampingRatio z: Double, stiffness k: Double) -> Double {
    guard t > 0 else { return from }
    let w0 = k.squareRoot()
    let x0 = from - to
    let x: Double
    if z < 1 {
        let wd = w0 * (1 - z * z).squareRoot()
        x = exp(-z * w0 * t) * (x0 * cos(wd * t) + (z * w0 * x0 / wd) * sin(wd * t))
    } else if z == 1 {
        x = exp(-w0 * t) * (x0 + w0 * x0 * t)
    } else {
        let s = (z * z - 1).squareRoot()
        let r1 = -w0 * (z - s)
        let r2 = -w0 * (z + s)
        let c2 = -r1 * x0 / (r2 - r1)
        let c1 = x0 - c2
        x = c1 * exp(r1 * t) + c2 * exp(r2 * t)
    }
    return to + x
}
