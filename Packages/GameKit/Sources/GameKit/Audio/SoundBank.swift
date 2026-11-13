import Foundation
import AVFoundation

/// Low-latency sound effects: preloaded buffers + a pool of voices with per-play rate (pitch), volume and pan.
/// Mirrors Android SoundPool usage (rate, ±pitch jitter, per-sound minimum gap, max streams).
public final class SoundBank: @unchecked Sendable {
    private final class Voice {
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        var busyUntil: TimeInterval = 0
        var startedAt: TimeInterval = 0
        var looping = false
    }

    private let system: AudioSystem
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var voices: [Voice] = []
    private var lastPlayed: [String: TimeInterval] = [:]
    private var minGap: [String: TimeInterval] = [:]
    private let lock = NSLock()
    private var nextVoice = 0

    public var enabled = true
    /// Master SFX volume 0...1.
    public var volume: Float = 1 { didSet { system.sfxVolume = volume } }

    public init(voices count: Int = 16, system: AudioSystem = .shared) {
        self.system = system
        for _ in 0..<count {
            let v = Voice()
            system.engine.attach(v.player)
            system.engine.attach(v.varispeed)
            system.engine.connect(v.player, to: v.varispeed, format: system.sfxFormat)
            system.engine.connect(v.varispeed, to: system.sfxMixer, format: system.sfxFormat)
            voices.append(v)
        }
    }

    // MARK: Registration

    public func register(_ name: String, buffer: AVAudioPCMBuffer, minGap gap: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        buffers[name] = buffer
        if gap > 0 { minGap[name] = gap }
    }

    public func register(_ name: String, samples: [Float], minGap gap: TimeInterval = 0) {
        register(name, buffer: system.buffer(samples: samples), minGap: gap)
    }

    /// Loads `name.(caf|wav|m4a)` from the bundle.
    @discardableResult
    public func load(_ name: String, bundle: Bundle = .main, subdirectory: String? = nil, minGap gap: TimeInterval = 0) -> Bool {
        for ext in ["caf", "wav", "m4a"] {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory),
               let buf = system.loadBuffer(url: url) {
                register(name, buffer: buf, minGap: gap)
                return true
            }
        }
        return false
    }

    public func setMinGap(_ name: String, _ gap: TimeInterval) {
        lock.lock(); minGap[name] = gap; lock.unlock()
    }

    public func has(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return buffers[name] != nil
    }

    public var registeredNames: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(buffers.keys)
    }

    public func duration(of name: String) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        guard let b = buffers[name] else { return 0 }
        return Double(b.frameLength) / b.format.sampleRate
    }

    // MARK: Playback

    /// Plays a sound. `rate` 1 = normal (SoundPool rate semantics: changes pitch and speed). Returns a voice id.
    @discardableResult
    public func play(_ name: String, volume vol: Float = 1, rate: Float = 1, pan: Float = 0, loop: Bool = false) -> Int? {
        guard enabled else { return nil }
        lock.lock()
        guard let buf = buffers[name] else { lock.unlock(); return nil }
        let now = ProcessInfo.processInfo.systemUptime
        if let gap = minGap[name], let last = lastPlayed[name], now - last < gap { lock.unlock(); return nil }
        lastPlayed[name] = now
        // pick a free voice, else steal the oldest non-looping one
        var idx = -1
        for i in 0..<voices.count {
            let k = (nextVoice + i) % voices.count
            if !voices[k].looping && voices[k].busyUntil <= now { idx = k; break }
        }
        if idx < 0 {
            var oldest = TimeInterval.greatestFiniteMagnitude
            for (k, v) in voices.enumerated() where !v.looping && v.startedAt < oldest { oldest = v.startedAt; idx = k }
        }
        guard idx >= 0 else { lock.unlock(); return nil }
        nextVoice = (idx + 1) % voices.count
        let v = voices[idx]
        let r = max(0.25, min(4, rate))
        v.startedAt = now
        v.looping = loop
        v.busyUntil = loop ? .greatestFiniteMagnitude : now + Double(buf.frameLength) / buf.format.sampleRate / Double(r) + 0.02
        lock.unlock()

        guard system.ensureRunning(), v.player.engine != nil else {
            lock.lock(); v.looping = false; v.busyUntil = 0; lock.unlock()
            return nil
        }
        v.player.stop()
        v.varispeed.rate = r
        v.player.volume = max(0, min(1, vol))
        v.player.pan = max(-1, min(1, pan))
        v.player.scheduleBuffer(buf, at: nil, options: loop ? [.loops] : [], completionHandler: nil)
        v.player.play()
        return idx
    }

    /// Updates a playing voice (e.g. engine/roll loops whose pitch follows speed).
    public func update(voice id: Int, volume vol: Float? = nil, rate: Float? = nil) {
        guard id >= 0 && id < voices.count else { return }
        let v = voices[id]
        if let vol { v.player.volume = max(0, min(1, vol)) }
        if let rate { v.varispeed.rate = max(0.25, min(4, rate)) }
    }

    public func stop(voice id: Int) {
        guard id >= 0 && id < voices.count else { return }
        lock.lock()
        let v = voices[id]
        v.looping = false
        v.busyUntil = 0
        lock.unlock()
        v.player.stop()
    }

    public func stopAll() {
        lock.lock()
        for v in voices { v.looping = false; v.busyUntil = 0 }
        lock.unlock()
        for v in voices { v.player.stop() }
    }
}
