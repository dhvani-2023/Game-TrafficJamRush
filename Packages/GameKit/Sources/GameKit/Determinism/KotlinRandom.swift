import Foundation

/// Bit-exact port of Kotlin's `kotlin.random.Random(seed)` (XorWowRandom) and the base `Random` helpers.
/// `Random(seed: Int)` and `Random(seed: Long)` give identical generators for seeds inside the Int range,
/// so one initializer covers both.
public final class KotlinRandom: @unchecked Sendable {
    private var x: Int32, y: Int32, z: Int32, w: Int32, v: Int32, addend: Int32

    /// `Random(seed: Long)` = `XorWowRandom(seed.toInt(), seed.shr(32).toInt())`
    public convenience init(_ seed: Int64) {
        self.init(seed1: Int32(truncatingIfNeeded: seed), seed2: Int32(truncatingIfNeeded: seed >> 32))
    }

    /// `Random(seed: Int)` = `XorWowRandom(seed, seed.shr(31))`. Pass a Kotlin `Int` seed (it is truncated to 32 bits).
    public convenience init(intSeed seed: Int) {
        let s = Int32(truncatingIfNeeded: seed)
        self.init(seed1: s, seed2: s >> 31)
    }

    /// Swift `Int` seeds are treated as Kotlin `Long` seeds.
    public convenience init(_ seed: Int) { self.init(Int64(seed)) }

    public init(seed1: Int32, seed2: Int32) {
        x = seed1
        y = seed2
        z = 0
        w = 0
        v = ~seed1
        addend = (seed1 << 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        precondition((x | y | z | w | v) != 0, "Initial state must have at least one non-zero element.")
        for _ in 0..<64 { _ = nextInt32() }
    }

    @inline(__always)
    private static func ushr(_ a: Int32, _ n: Int32) -> Int32 {
        Int32(bitPattern: UInt32(bitPattern: a) >> UInt32(n & 31))
    }

    @inline(__always)
    public func nextInt32() -> Int32 {
        var t = x
        t = t ^ Self.ushr(t, 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362437
        return t &+ addend
    }

    @inline(__always)
    public func nextBits(_ bitCount: Int) -> Int32 {
        let r = nextInt32()
        if bitCount == 0 { return 0 }
        return Self.ushr(r, Int32(32 - bitCount))
    }

    @inline(__always)
    private static func fastLog2(_ value: Int32) -> Int { 31 - value.leadingZeroBitCount }

    public func nextInt32(_ from: Int32, _ until: Int32) -> Int32 {
        precondition(until > from, "Random range is empty: [\(from), \(until)).")
        let n = until &- from
        if n > 0 || n == Int32.min {
            let rnd: Int32
            if n & (0 &- n) == n {
                rnd = nextBits(Self.fastLog2(n))
            } else {
                var vv: Int32
                var bits: Int32
                repeat {
                    bits = Self.ushr(nextInt32(), 1)
                    vv = bits % n
                } while bits &- vv &+ (n &- 1) < 0
                rnd = vv
            }
            return from &+ rnd
        } else {
            while true {
                let rnd = nextInt32()
                if rnd >= from && rnd < until { return rnd }
            }
        }
    }

    public func nextInt32(_ until: Int32) -> Int32 { nextInt32(0, until) }

    // MARK: Swift-friendly API

    public func nextInt() -> Int { Int(nextInt32()) }
    public func nextInt(_ until: Int) -> Int { Int(nextInt32(0, Int32(until))) }
    public func nextInt(_ from: Int, _ until: Int) -> Int { Int(nextInt32(Int32(from), Int32(until))) }
    /// `nextInt(range: IntRange)`; `in: a...b` mirrors Kotlin's `a..b`.
    public func nextInt(in range: ClosedRange<Int>) -> Int {
        if range.upperBound < Int(Int32.max) {
            return nextInt(range.lowerBound, range.upperBound + 1)
        } else if range.lowerBound > Int(Int32.min) {
            return nextInt(range.lowerBound - 1, range.upperBound) + 1
        } else {
            return nextInt()
        }
    }

    public func nextLong() -> Int64 {
        (Int64(nextInt32()) << 32) &+ Int64(nextInt32())
    }

    public func nextLong(_ until: Int64) -> Int64 { nextLong(0, until) }

    public func nextLong(_ from: Int64, _ until: Int64) -> Int64 {
        precondition(until > from, "Random range is empty")
        let n = until &- from
        if n > 0 {
            let rnd: Int64
            if n & (0 &- n) == n {
                let nLow = Int32(truncatingIfNeeded: n)
                let nHigh = Int32(truncatingIfNeeded: Int64(bitPattern: UInt64(bitPattern: n) >> 32))
                if nLow != 0 {
                    rnd = Int64(nextBits(Self.fastLog2(nLow))) & 0xFFFF_FFFF
                } else if nHigh == 1 {
                    rnd = Int64(nextInt32()) & 0xFFFF_FFFF
                } else {
                    rnd = (Int64(nextBits(Self.fastLog2(nHigh))) << 32) &+ (Int64(nextInt32()) & 0xFFFF_FFFF)
                }
            } else {
                var vv: Int64
                var bits: Int64
                repeat {
                    bits = Int64(bitPattern: UInt64(bitPattern: nextLong()) >> 1)
                    vv = bits % n
                } while bits &- vv &+ (n &- 1) < 0
                rnd = vv
            }
            return from &+ rnd
        } else {
            while true {
                let rnd = nextLong()
                if rnd >= from && rnd < until { return rnd }
            }
        }
    }

    public func nextBoolean() -> Bool { nextBits(1) != 0 }

    public func nextDouble() -> Double {
        let hi = Int64(nextBits(26))
        let lo = Int64(nextBits(27))
        return Double((hi << 27) &+ lo) / Double(Int64(1) << 53)
    }

    public func nextDouble(_ until: Double) -> Double { nextDouble(0.0, until) }

    public func nextDouble(_ from: Double, _ until: Double) -> Double {
        precondition(until > from, "Random range is empty")
        let size = until - from
        let r: Double
        if size.isInfinite && from.isFinite && until.isFinite {
            let r1 = nextDouble() * (until / 2 - from / 2)
            r = from + r1 + r1
        } else {
            r = from + nextDouble() * size
        }
        return r >= until ? until.nextDown : r
    }

    public func nextFloat() -> Float { Float(nextBits(24)) / Float(1 << 24) }
}

public extension Array {
    /// Kotlin `MutableList.shuffle(random: kotlin.random.Random)`.
    mutating func kotlinShuffle(_ random: KotlinRandom) {
        var i = count - 1
        while i >= 1 {
            let j = random.nextInt(i + 1)
            swapAt(i, j)
            i -= 1
        }
    }

    /// Kotlin `Iterable.shuffled(random: kotlin.random.Random)`.
    func kotlinShuffled(_ random: KotlinRandom) -> [Element] {
        var copy = self
        copy.kotlinShuffle(random)
        return copy
    }

    /// Kotlin `Collection.random(random)`.
    func kotlinRandom(_ random: KotlinRandom) -> Element {
        precondition(!isEmpty, "Collection is empty.")
        return self[random.nextInt(count)]
    }
}
