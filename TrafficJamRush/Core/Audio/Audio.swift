import Foundation
import GameKit

// Port of core/audio/Audio.kt: SoundPool → GameKit SoundBank, MediaPlayer → GameKit MusicPlayer,
// Vibrator → GameKit Haptics. Sound files are Resources/Audio/<res>.caf (same base names as res/raw).

enum Sfx: String, CaseIterable {
    case Click, Open, Close, Tap, Bump, EngineGo, Park, Pop1, Pop2, Pop3, Full, Horn, Coin, CoinBurst,
         Star1, Star2, Star3, Win, Fail, Unlock, Whoosh, Booster, Crane, Warning

    /// res/raw base name.
    var res: String {
        switch self {
        case .Click: "ui_click"
        case .Open: "ui_open"
        case .Close: "ui_close"
        case .Tap: "tap"
        case .Bump: "bump"
        case .EngineGo: "engine_go"
        case .Park: "park"
        case .Pop1: "board_pop1"
        case .Pop2: "board_pop2"
        case .Pop3: "board_pop3"
        case .Full: "vehicle_full"
        case .Horn: "depart_horn"
        case .Coin: "coin"
        case .CoinBurst: "coin_burst"
        case .Star1: "star1"
        case .Star2: "star2"
        case .Star3: "star3"
        case .Win: "win_fanfare"
        case .Fail: "fail"
        case .Unlock: "unlock"
        case .Whoosh: "whoosh"
        case .Booster: "booster"
        case .Crane: "crane"
        case .Warning: "warning"
        }
    }

    var volume: Float {
        switch self {
        case .Click: 0.8
        case .Open: 0.7
        case .Close: 0.7
        case .Tap: 0.7
        case .EngineGo: 0.75
        case .Park: 0.7
        case .Pop1, .Pop2, .Pop3: 0.55
        case .Full: 0.8
        case .Horn: 0.65
        case .Coin: 0.8
        case .Whoosh: 0.7
        case .Warning: 0.8
        default: 1
        }
    }

    var name: String { rawValue }
    static var entries: [Sfx] { allCases }
}

enum Music: String, CaseIterable {
    case Home, Game

    var res: String {
        switch self {
        case .Home: "music_home"
        case .Game: "music_game"
        }
    }
}

enum Haptic: String, CaseIterable { case Tap, Bump, Success, Fail }

/// Sound effects, background music and vibration behind one switchboard.
@MainActor
final class AudioManager {

    var soundOn = true
    var vibrationOn = true {
        didSet { Haptics.enabled = vibrationOn }
    }
    var musicOn = true {
        didSet { if musicOn != oldValue { applyMusic() } }
    }

    private let bank: SoundBank
    private let music: MusicPlayer
    private var current: Music?
    private var inForeground = true

    /// MediaPlayer.setVolume(0.45f, 0.45f)
    private static let musicVolume: Float = 0.45

    init(system: AudioSystem = .shared) {
        system.start()
        // SoundPool.Builder().setMaxStreams(10)
        bank = SoundBank(voices: 10, system: system)
        for s in Sfx.allCases {
            // Repeats of the same sound within 30 ms are dropped to avoid phasing.
            bank.load(s.res, minGap: 0.030)
        }
        music = MusicPlayer(system: system)
        music.volume = Self.musicVolume
        for m in Music.allCases { music.load(m.res) }
    }

    /// Plays a sound; repeats of the same sound within 30 ms are dropped to avoid phasing.
    func play(_ sfx: Sfx, _ rate: Float = 1, _ volume: Float = 1) {
        if !soundOn { return }
        let v = (sfx.volume * volume).coerceIn(0, 1)
        bank.play(sfx.res, volume: v, rate: rate.coerceIn(0.5, 2))
    }

    // --- Music ------------------------------------------------------------------------------

    func playMusic(_ m: Music) {
        if current == m && music.currentTrack != nil {
            applyMusic()
            return
        }
        current = m
        applyMusic()
    }

    func setForeground(_ fg: Bool) {
        inForeground = fg
        applyMusic()
    }

    /// Silences music while an ad plays (GameKit duck multiplier, so the track keeps its place).
    func duck(_ on: Bool) {
        music.setDuck(on ? 0 : 1, fade: 0.2)
    }

    /// Music plays only when it is on and the app is in the foreground (`duck` is applied on top).
    private func applyMusic() {
        let wanted = musicOn && inForeground
        music.enabled = wanted
        if wanted, let current {
            music.play(current.res, fade: 0.3)
        }
    }

    // --- Haptics ----------------------------------------------------------------------------

    func haptic(_ h: Haptic) {
        if !vibrationOn { return }
        switch h {
        case .Tap: Haptics.tap(0.5) // createOneShot(12, 90): a short, light tick
        case .Bump: Haptics.medium(200.0 / 255.0) // createOneShot(35, 200): amplitude 200/255
        case .Success: Haptics.pattern(timings: [0, 30, 60, 40], amplitudes: [0, 180, 0, 255])
        case .Fail: Haptics.pattern(timings: [0, 80, 80, 120], amplitudes: [0, 200, 0, 160])
        }
    }
}
