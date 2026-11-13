import Foundation

/// Bit-exact port of `java.util.Random` (48-bit LCG), including `Collections.shuffle`.
/// Android level generators seeded with `java.util.Random(seed)` produce the same levels with this class.
public final class JavaRandom: @unchecked Sendable {
    private var seed: Int64
    private var nextNextGaussian: Double = 0
    private var haveNextNextGaussian = false

    private static let multiplier: Int64 = 0x5DEECE66D
    private static let addend: Int64 = 0xB
    private static let mask: Int64 = (1 << 48) - 1

    public init(_ seed: Int64) {
        self.seed = (seed ^ Self.multiplier) & Self.mask
    }

    public convenience init(_ seed: Int) { self.init(Int64(seed)) }

    public func setSeed(_ seed: Int64) {
        self.seed = (seed ^ Self.multiplier) & Self.mask
        haveNextNextGaussian = false
    }

    /// `protected int next(int bits)`
    @inline(__always)
    public func next(_ bits: Int) -> Int32 {
        seed = (seed &* Self.multiplier &+ Self.addend) & Self.mask
        return Int32(truncatingIfNeeded: seed >> Int64(48 - bits))
    }

    // MARK: Int32 API (exact Java semantics)

    public func nextInt32() -> Int32 { next(32) }

    public func nextInt32(_ bound: Int32) -> Int32 {
        precondition(bound > 0, "bound must be positive")
        var r = next(31)
        let m = bound &- 1
        if bound & m == 0 {
            r = Int32(truncatingIfNeeded: (Int64(bound) &* Int64(r)) >> 31)
        } else {
            var u = r
            while true {
                r = u % bound
                if u &- r &+ m < 0 { u = next(31) } else { break }
            }
        }
        return r
    }

    /// JDK 17+ `nextInt(origin, bound)` (RandomSupport.boundedNextInt).
    public func nextInt32(_ origin: Int32, _ bound: Int32) -> Int32 {
        precondition(origin < bound, "bound must be greater than origin")
        var r = nextInt32()
        let n = bound &- origin
        let m = n &- 1
        if n & m == 0 {
            r = (r & m) &+ origin
        } else if n > 0 {
            var u = Int32(bitPattern: UInt32(bitPattern: r) >> 1)
            while true {
                r = u % n
                if u &+ m &- r < 0 { u = Int32(bitPattern: UInt32(bitPattern: nextInt32()) >> 1) } else { break }
            }
            r = r &+ origin
        } else {
            while r < origin || r >= bound { r = nextInt32() }
        }
        return r
    }

    // MARK: Swift-friendly API (values are still 32-bit Java values)

    public func nextInt() -> Int { Int(next(32)) }
    public func nextInt(_ bound: Int) -> Int { Int(nextInt32(Int32(bound))) }
    public func nextInt(_ origin: Int, _ bound: Int) -> Int { Int(nextInt32(Int32(origin), Int32(bound))) }

    public func nextLong() -> Int64 {
        (Int64(next(32)) << 32) &+ Int64(next(32))
    }

    public func nextBoolean() -> Bool { next(1) != 0 }

    public func nextFloat() -> Float { Float(next(24)) / Float(1 << 24) }

    public func nextDouble() -> Double {
        Double((Int64(next(26)) << 27) &+ Int64(next(27))) * 0x1.0p-53
    }

    public func nextGaussian() -> Double {
        if haveNextNextGaussian {
            haveNextNextGaussian = false
            return nextNextGaussian
        }
        var v1 = 0.0, v2 = 0.0, s = 0.0
        repeat {
            v1 = 2 * nextDouble() - 1
            v2 = 2 * nextDouble() - 1
            s = v1 * v1 + v2 * v2
        } while s >= 1 || s == 0
        let multiplier = (-2 * Foundation.log(s) / s).squareRoot()
        nextNextGaussian = v2 * multiplier
        haveNextNextGaussian = true
        return v1 * multiplier
    }
}

public extension Array {
    /// `java.util.Collections.shuffle(list, rnd)` — also what Kotlin's `shuffle(java.util.Random)` / `shuffled(java.util.Random)` call.
    mutating func javaShuffle(_ rnd: JavaRandom) {
        var i = count
        while i > 1 {
            swapAt(i - 1, rnd.nextInt(i))
            i -= 1
        }
    }

    func javaShuffled(_ rnd: JavaRandom) -> [Element] {
        var copy = self
        copy.javaShuffle(rnd)
        return copy
    }
}
