import Foundation
import AVFoundation

/// Gap-free looping music with linear-gain crossfades (like Android MediaPlayer volume ramps) and ducking.
/// Tracks are decoded to memory once. `fade` arguments are durations in seconds.
public final class MusicPlayer: @unchecked Sendable {
    private final class Deck {
        let player = AVAudioPlayerNode()
        var track: String?
        var volume: Float = 0
        var from: Float = 0
        var target: Float = 0
        var start: TimeInterval = 0
        var duration: TimeInterval = 0
    }

    private let system: AudioSystem
    private var decks: [Deck] = []
    private var active = 0
    private var tracks: [String: AVAudioPCMBuffer] = [:]
    private var timer: Timer?
    private let lock = NSLock()
    private var layered = false
    private var layeredWeight: Float = 0
    private var hintObserver: NSObjectProtocol?

    /// Music on/off from settings. Turning it back on restarts the wanted track.
    public var enabled = true { didSet { applyLevels(fade: 0.4) } }
    /// Music volume 0...1 (linear gain).
    public var volume: Float = 1 { didSet { applyLevels(fade: 0.15) } }
    /// Temporary duck multiplier (pause menus, dialogs): 1 = none.
    public private(set) var duck: Float = 1
    /// Per-track gain multipliers.
    public var trackGain: [String: Float] = [:]

    /// The track that should be playing (nil = silence).
    public private(set) var currentTrack: String?

    public init(system: AudioSystem = .shared) {
        self.system = system
        for _ in 0..<2 {
            let d = Deck()
            system.engine.attach(d.player)
            system.engine.connect(d.player, to: system.musicMixer, format: system.musicFormat)
            d.player.volume = 0
            decks.append(d)
        }
        #if os(iOS)
        hintObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyLevels(fade: 0.6) }
        #endif
    }

    // MARK: Tracks

    public func register(_ name: String, buffer: AVAudioPCMBuffer) {
        lock.lock(); tracks[name] = buffer; lock.unlock()
    }

    /// Mono samples at 48 kHz → stereo buffer.
    public func register(_ name: String, samples: [Float]) {
        let buf = AVAudioPCMBuffer(pcmFormat: system.musicFormat, frameCapacity: AVAudioFrameCount(max(1, samples.count)))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            buf.floatChannelData![1].update(from: src.baseAddress!, count: samples.count)
        }
        register(name, buffer: buf)
    }

    /// Loads `name.(caf|m4a|wav)` from the bundle into memory (stereo 48 kHz).
    @discardableResult
    public func load(_ name: String, bundle: Bundle = .main, subdirectory: String? = nil) -> Bool {
        for ext in ["caf", "m4a", "wav"] {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory),
               let buf = system.loadBuffer(url: url, format: system.musicFormat) {
                register(name, buffer: buf)
                return true
            }
        }
        return false
    }

    public func has(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return tracks[name] != nil
    }

    private func buffer(_ name: String) -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        return tracks[name]
    }

    // MARK: Playback

    /// Crossfades to `name` over `fade` seconds (no-op if it is already playing). `nil` fades out and stops.
    public func play(_ name: String?, fade: TimeInterval = 0.75) {
        if layered { layered = false; for d in decks { ramp(d, to: 0, over: fade) } }
        currentTrack = name
        applyLevels(fade: fade)
    }

    /// Two synced tracks whose mix follows `weightB` (e.g. day/night versions of one song).
    public func playLayered(_ a: String, _ b: String, weightB: Float, fade: TimeInterval = 0.75) {
        guard let ba = buffer(a), let bb = buffer(b) else { return }
        if !layered || decks[0].track != a || decks[1].track != b || !decks[0].player.isPlaying {
            for d in decks { d.player.stop(); d.volume = 0; d.player.volume = 0 }
            decks[0].track = a
            decks[1].track = b
            guard ensureEngine() else { return }
            decks[0].player.scheduleBuffer(ba, at: nil, options: [.loops], completionHandler: nil)
            decks[1].player.scheduleBuffer(bb, at: nil, options: [.loops], completionHandler: nil)
            let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05))
            decks[0].player.play(at: start)
            decks[1].player.play(at: start)
        }
        layered = true
        currentTrack = a
        layeredWeight = max(0, min(1, weightB))
        applyLevels(fade: fade)
    }

    public func setDuck(_ value: Float, fade: TimeInterval = 0.3) {
        duck = max(0, min(1, value))
        applyLevels(fade: fade)
    }

    public func stop(fade: TimeInterval = 0.5) {
        layered = false
        currentTrack = nil
        for d in decks { ramp(d, to: 0, over: fade) }
    }

    // MARK: Levels

    private func level(for track: String?) -> Float {
        guard enabled, let track else { return 0 }
        let other: Float = system.otherAudioIsPlaying ? 0 : 1
        return volume * duck * (trackGain[track] ?? 1) * other
    }

    /// False when the engine can't run right now; the decks then stay stopped and the next `play`/`setDuck` retries.
    private func ensureEngine() -> Bool {
        system.ensureRunning() && decks.allSatisfy { $0.player.engine != nil }
    }

    /// Starts `name` from the beginning on the idle deck, which becomes the active one.
    private func startFresh(_ name: String, _ buf: AVAudioPCMBuffer) {
        active = 1 - active
        let d = decks[active]
        d.player.stop()
        d.track = name
        d.volume = 0
        d.player.volume = 0
        guard ensureEngine() else { return }
        d.player.scheduleBuffer(buf, at: nil, options: [.loops], completionHandler: nil)
        d.player.play()
    }

    private func applyLevels(fade: TimeInterval) {
        if layered {
            let base = level(for: decks[0].track)
            ramp(decks[0], to: base * (1 - layeredWeight), over: fade)
            ramp(decks[1], to: base * layeredWeight, over: fade)
            return
        }
        if let want = currentTrack, level(for: want) > 0 {
            let cur = decks[active]
            if cur.track != want || !cur.player.isPlaying, let buf = buffer(want) {
                startFresh(want, buf)
            }
        }
        for (i, d) in decks.enumerated() {
            let wanted = i == active && d.track != nil && d.track == currentTrack
            ramp(d, to: wanted ? level(for: d.track) : 0, over: fade)
        }
    }

    private func ramp(_ d: Deck, to target: Float, over seconds: TimeInterval) {
        d.from = d.volume
        d.target = target
        d.start = ProcessInfo.processInfo.systemUptime
        d.duration = max(0.0001, seconds)
        if seconds <= 0.0001 {
            d.volume = target
            d.player.volume = target
        }
        startTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        var moving = false
        for d in decks {
            if d.volume != d.target {
                let p = Float(min(1, (now - d.start) / d.duration))
                d.volume = p >= 1 ? d.target : d.from + (d.target - d.from) * p
                d.player.volume = d.volume
                moving = true
            }
            // A deck that faded to silence and is not wanted stops (no silent playback).
            if !layered && d.volume == 0 && d.target == 0 && d.track != nil && !(d === decks[active] && d.track == currentTrack && level(for: d.track) > 0) {
                d.player.stop()
                d.track = nil
            }
        }
        if !moving {
            timer?.invalidate()
            timer = nil
        }
    }
}
