import Foundation
import AVFoundation

/// One shared AVAudioEngine for sound effects and music.
/// SFX go through a pool of voices (player → varispeed → sfx mixer); music has two crossfading decks.
public final class AudioSystem: @unchecked Sendable {
    public static let shared = AudioSystem()

    public let engine = AVAudioEngine()
    public let sfxMixer = AVAudioMixerNode()
    public let musicMixer = AVAudioMixerNode()
    /// Canonical format for every SFX buffer: 48 kHz mono float.
    public let sfxFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    public let musicFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    private let lock = NSLock()
    private var started = false
    private var observers: [NSObjectProtocol] = []

    public var sfxVolume: Float {
        get { sfxMixer.outputVolume }
        set { sfxMixer.outputVolume = newValue }
    }

    public var musicVolume: Float {
        get { musicMixer.outputVolume }
        set { musicMixer.outputVolume = newValue }
    }

    private init() {
        engine.attach(sfxMixer)
        engine.attach(musicMixer)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: nil)
    }

    /// Configures the session as `.ambient` (respects the silent switch, mixes with the user's own audio) and starts the engine.
    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard !started else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended { self.restart() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.restart() })
        #endif
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restart() })
        engine.prepare()
        try? engine.start()
        started = true
    }

    /// Starts the engine if needed. Returns false when it still isn't running (e.g. right after a route or
    /// configuration change): calling `AVAudioPlayerNode.play()` then raises an exception, so skip the sound.
    @discardableResult
    public func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        do { try engine.start() } catch { return false }
        return engine.isRunning
    }

    public func restart() {
        if !engine.isRunning {
            try? engine.start()
        }
        NotificationCenter.default.post(name: .gameAudioRestarted, object: nil)
    }

    /// Pause/resume the whole engine (app background/foreground).
    public func suspend() { engine.pause() }
    public func resume() { if !engine.isRunning { try? engine.start() } }

    /// True when the user is already playing their own music/podcast; games should keep their music quiet then.
    public var otherAudioIsPlaying: Bool {
        #if os(iOS)
        AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        #else
        false
        #endif
    }

    // MARK: Buffers

    /// Makes a mono 48 kHz buffer from float samples (already at 48 kHz).
    public func buffer(samples: [Float]) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: sfxFormat, frameCapacity: AVAudioFrameCount(max(1, samples.count)))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buf
    }

    /// Loads an audio file and converts it to `format` (mono SFX format by default).
    public func loadBuffer(url: URL, format: AVAudioFormat? = nil) -> AVAudioPCMBuffer? {
        let target = format ?? sfxFormat
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let srcFormat = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard let src = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: max(1, frames)) else { return nil }
        do { try file.read(into: src) } catch { return nil }
        if srcFormat.sampleRate == target.sampleRate && srcFormat.channelCount == target.channelCount
            && srcFormat.commonFormat == target.commonFormat && !srcFormat.isInterleaved {
            return src
        }
        guard let converter = AVAudioConverter(from: srcFormat, to: target) else { return nil }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        let ratio = target.sampleRate / srcFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(src.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if fed { outStatus.pointee = .endOfStream; return nil }
            fed = true
            outStatus.pointee = .haveData
            return src
        }
        if status == .error { return nil }
        return out
    }
}

public extension Notification.Name {
    static let gameAudioRestarted = Notification.Name("GameKit.audioRestarted")
}
