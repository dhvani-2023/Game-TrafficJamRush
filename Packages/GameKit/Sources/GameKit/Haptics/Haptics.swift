#if canImport(UIKit)
import UIKit
import CoreHaptics

/// Haptic feedback with named levels (mirrors the Android Vibrator patterns) plus Core Haptics helpers.
@MainActor
public enum Haptics {
    public static var enabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()

    public static func prepare() {
        light.prepare(); medium.prepare(); selection.prepare()
    }

    public static func tick() { guard enabled else { return }; selection.selectionChanged() }
    public static func tap(_ intensity: CGFloat = 0.6) { guard enabled else { return }; light.impactOccurred(intensity: intensity) }
    public static func softTap(_ intensity: CGFloat = 0.7) { guard enabled else { return }; soft.impactOccurred(intensity: intensity) }
    public static func rigidTap(_ intensity: CGFloat = 0.8) { guard enabled else { return }; rigid.impactOccurred(intensity: intensity) }
    public static func medium(_ intensity: CGFloat = 1) { guard enabled else { return }; medium.impactOccurred(intensity: intensity) }
    public static func heavy(_ intensity: CGFloat = 1) { guard enabled else { return }; heavy.impactOccurred(intensity: intensity) }
    public static func success() { guard enabled else { return }; notify.notificationOccurred(.success) }
    public static func warning() { guard enabled else { return }; notify.notificationOccurred(.warning) }
    public static func error() { guard enabled else { return }; notify.notificationOccurred(.error) }

    /// Android-style waveform: alternating off/on durations in ms with amplitudes 0...255.
    public static func pattern(timings: [Int], amplitudes: [Int]) {
        guard enabled else { return }
        HapticEngine.shared.playWaveform(timings: timings, amplitudes: amplitudes)
    }
}

/// Core Haptics engine for transient patterns and continuous rumbles (engines, painting, rolling).
@MainActor
public final class HapticEngine {
    public static let shared = HapticEngine()
    private var engine: CHHapticEngine?
    private var continuous: CHHapticAdvancedPatternPlayer?
    public let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {
        guard supported else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        try? engine?.start()
    }

    public func playTransient(intensity: Float, sharpness: Float, delay: TimeInterval = 0) {
        guard Haptics.enabled, let engine else { return }
        let e = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: delay)
        if let p = try? CHHapticPattern(events: [e], parameters: []), let pl = try? engine.makePlayer(with: p) {
            try? engine.start()
            try? pl.start(atTime: CHHapticTimeImmediate)
        }
    }

    public func playWaveform(timings: [Int], amplitudes: [Int]) {
        guard let engine else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        var events: [CHHapticEvent] = []
        var t: TimeInterval = 0
        for (i, ms) in timings.enumerated() {
            let amp = i < amplitudes.count ? amplitudes[i] : 255
            let dur = Double(ms) / 1000
            if amp > 0 && dur > 0 {
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(amp) / 255),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ], relativeTime: t, duration: dur))
            }
            t += dur
        }
        guard !events.isEmpty, let p = try? CHHapticPattern(events: events, parameters: []),
              let pl = try? engine.makePlayer(with: p) else { return }
        try? engine.start()
        try? pl.start(atTime: CHHapticTimeImmediate)
    }

    /// Starts (or updates) a continuous rumble; call `stopContinuous()` to end it.
    public func setContinuous(intensity: Float, sharpness: Float) {
        guard Haptics.enabled, let engine else { return }
        if continuous == nil {
            let e = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
            ], relativeTime: 0, duration: 30)
            guard let p = try? CHHapticPattern(events: [e], parameters: []),
                  let pl = try? engine.makeAdvancedPlayer(with: p) else { return }
            pl.loopEnabled = true
            try? engine.start()
            try? pl.start(atTime: CHHapticTimeImmediate)
            continuous = pl
        }
        try? continuous?.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: max(0, min(1, intensity)), relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: max(-1, min(1, sharpness - 0.5)), relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    public func stopContinuous() {
        try? continuous?.stop(atTime: CHHapticTimeImmediate)
        continuous = nil
    }
}
#endif
