import Foundation

/// Building blocks for synthesized sound effects (ports of the Android in-code synths).
/// Everything renders at 48 kHz float for full-bandwidth, alias-free sound.
public enum Synth {
    public static let sampleRate: Double = 48_000

    public static func frames(_ seconds: Double) -> Int { max(1, Int(seconds * sampleRate)) }

    /// Deterministic noise (LCG), like the Android synths, so sounds are identical every launch.
    public struct Noise {
        private var state: UInt32
        public init(seed: UInt32 = 0x1234_5678) { state = seed }
        public mutating func next() -> Float {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: state)) / Float(Int32.max)
        }
    }

    public enum Wave { case sine, triangle, square, saw }

    @inline(__always)
    public static func osc(_ wave: Wave, phase: Double) -> Float {
        let p = phase - phase.rounded(.down)
        switch wave {
        case .sine: return Float(Foundation.sin(2 * .pi * p))
        case .triangle: return Float(4 * abs(p - 0.5) - 1)
        case .square: return p < 0.5 ? 1 : -1
        case .saw: return Float(2 * p - 1)
        }
    }

    /// Soft clipper to keep summed layers clean.
    @inline(__always)
    public static func softClip(_ x: Float) -> Float { tanhf(x) }

    /// Normalises a buffer to `peak`.
    public static func normalize(_ s: inout [Float], peak: Float = 0.9) {
        var m: Float = 0
        for v in s { m = max(m, abs(v)) }
        guard m > 0 else { return }
        let g = peak / m
        for i in s.indices { s[i] *= g }
    }

    /// Short fade in/out (in seconds) to avoid clicks.
    public static func declick(_ s: inout [Float], fadeIn: Double = 0.002, fadeOut: Double = 0.004) {
        let a = min(s.count, frames(fadeIn)), b = min(s.count, frames(fadeOut))
        for i in 0..<a { s[i] *= Float(i) / Float(max(1, a)) }
        for i in 0..<b { s[s.count - 1 - i] *= Float(i) / Float(max(1, b)) }
    }

    /// Mixes `src` into `dst` starting at `offset` seconds with gain.
    public static func mix(_ dst: inout [Float], _ src: [Float], at offset: Double = 0, gain: Float = 1) {
        let o = Int(offset * sampleRate)
        if dst.count < o + src.count { dst += [Float](repeating: 0, count: o + src.count - dst.count) }
        for i in 0..<src.count { dst[o + i] += src[i] * gain }
    }

    /// Resamples a buffer generated at another rate (e.g. 44.1 kHz recipes) to 48 kHz with cubic interpolation.
    public static func resample(_ src: [Float], from rate: Double) -> [Float] {
        guard rate != sampleRate, src.count > 1 else { return src }
        let ratio = rate / sampleRate
        let n = Int(Double(src.count) / ratio)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let x = Double(i) * ratio
            let i1 = Int(x)
            let t = Float(x - Double(i1))
            let p0 = src[max(0, i1 - 1)], p1 = src[min(src.count - 1, i1)]
            let p2 = src[min(src.count - 1, i1 + 1)], p3 = src[min(src.count - 1, i1 + 2)]
            let a = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3
            let b = p0 - 2.5 * p1 + 2 * p2 - 0.5 * p3
            let c = -0.5 * p0 + 0.5 * p2
            out[i] = ((a * t + b) * t + c) * t + p1
        }
        return out
    }
}
