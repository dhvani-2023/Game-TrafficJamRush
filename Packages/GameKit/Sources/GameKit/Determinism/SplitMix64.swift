import Foundation

/// Classic SplitMix64 (Steele, Lea, Flood). Each Android project derives its own `nextInt`/`nextDouble`
/// on top of `nextLong()`; ports should call `nextRaw()` and copy those derivations from the Kotlin source.
public struct SplitMix64: Sendable {
    public var state: UInt64

    public init(seed: UInt64) { state = seed }
    public init(seed: Int64) { state = UInt64(bitPattern: seed) }

    @inline(__always)
    public mutating func nextRaw() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The raw value as a Kotlin `Long`.
    @inline(__always)
    public mutating func nextLong() -> Int64 { Int64(bitPattern: nextRaw()) }
}

/// Plain xorshift64 step used by several generators (`x ^= x shl 13; x ^= x ushr 7; x ^= x shl 17`).
@inline(__always)
public func xorshift64(_ x: inout UInt64) -> UInt64 {
    x ^= x << 13
    x ^= x >> 7
    x ^= x << 17
    return x
}
