import Foundation

/// Helpers that reproduce Kotlin/JVM numeric semantics exactly. Use them in every ported generator,
/// physics step and rule engine so iOS and Android produce identical results.
public enum Kt {
    // MARK: Conversions

    /// Kotlin `Float.toInt()` / `Double.toInt()`: NaN → 0, saturates at Int32 bounds, truncates toward zero.
    @inline(__always)
    public static func toInt(_ f: Float) -> Int {
        if f.isNaN { return 0 }
        if f >= 2147483647.0 { return Int(Int32.max) }
        if f <= -2147483648.0 { return Int(Int32.min) }
        return Int(f)
    }

    @inline(__always)
    public static func toInt(_ d: Double) -> Int {
        if d.isNaN { return 0 }
        if d >= 2147483647.0 { return Int(Int32.max) }
        if d <= -2147483648.0 { return Int(Int32.min) }
        return Int(d)
    }

    /// Kotlin `Double.toLong()`.
    @inline(__always)
    public static func toLong(_ d: Double) -> Int64 {
        if d.isNaN { return 0 }
        if d >= 9.223372036854775807e18 { return Int64.max }
        if d <= -9.223372036854775808e18 { return Int64.min }
        return Int64(d)
    }

    /// Kotlin `Float.roundToInt()` (= `Math.round`): rounds half up (toward +∞).
    @inline(__always)
    public static func roundToInt(_ f: Float) -> Int {
        precondition(!f.isNaN, "Cannot round NaN value.")
        if f >= 2147483647.0 { return Int(Int32.max) }
        if f <= -2147483648.0 { return Int(Int32.min) }
        let fl = f.rounded(.down)
        return Int(f - fl >= 0.5 ? fl + 1 : fl)
    }

    /// Kotlin `Double.roundToInt()`.
    @inline(__always)
    public static func roundToInt(_ d: Double) -> Int {
        precondition(!d.isNaN, "Cannot round NaN value.")
        if d >= 2147483647.0 { return Int(Int32.max) }
        if d <= -2147483648.0 { return Int(Int32.min) }
        let fl = d.rounded(.down)
        return Int(d - fl >= 0.5 ? fl + 1 : fl)
    }

    /// Kotlin `Double.roundToLong()`.
    @inline(__always)
    public static func roundToLong(_ d: Double) -> Int64 {
        let fl = d.rounded(.down)
        return toLong(d - fl >= 0.5 ? fl + 1 : fl)
    }

    /// `kotlin.math.round(x)` — rounds half to EVEN (unlike roundToInt).
    @inline(__always)
    public static func round(_ f: Float) -> Float { f.rounded(.toNearestOrEven) }
    @inline(__always)
    public static func round(_ d: Double) -> Double { d.rounded(.toNearestOrEven) }

    // MARK: Integer maths (32-bit wrapping like Kotlin Int)

    /// Kotlin `Int` multiply with wrap-around.
    @inline(__always)
    public static func imul(_ a: Int, _ b: Int) -> Int {
        Int(Int32(truncatingIfNeeded: a) &* Int32(truncatingIfNeeded: b))
    }

    @inline(__always)
    public static func iadd(_ a: Int, _ b: Int) -> Int {
        Int(Int32(truncatingIfNeeded: a) &+ Int32(truncatingIfNeeded: b))
    }

    /// Wrap any value to a Kotlin `Int`.
    @inline(__always)
    public static func int32(_ a: Int) -> Int { Int(Int32(truncatingIfNeeded: a)) }

    /// Kotlin `Int.ushr(n)`.
    @inline(__always)
    public static func ushr(_ a: Int, _ n: Int) -> Int {
        Int(Int32(bitPattern: UInt32(truncatingIfNeeded: a) >> UInt32(n & 31)))
    }

    /// Kotlin `Int.shl(n)` with wrap-around.
    @inline(__always)
    public static func shl(_ a: Int, _ n: Int) -> Int {
        Int(Int32(truncatingIfNeeded: a) << Int32(n & 31))
    }

    /// Kotlin `Long.ushr(n)`.
    @inline(__always)
    public static func ushr(_ a: Int64, _ n: Int) -> Int64 {
        Int64(bitPattern: UInt64(bitPattern: a) >> UInt64(n & 63))
    }

    /// Kotlin `a.mod(b)` (result has the sign of the divisor) — for Int.
    @inline(__always)
    public static func mod(_ a: Int, _ b: Int) -> Int {
        let r = a % b
        return (r != 0 && (r ^ b) < 0) ? r + b : r
    }

    /// Kotlin `a.mod(b)` for Float / Double.
    @inline(__always)
    public static func mod(_ a: Float, _ b: Float) -> Float {
        let r = fmodf(a, b)
        return (r != 0 && (r < 0) != (b < 0)) ? r + b : r
    }

    @inline(__always)
    public static func mod(_ a: Double, _ b: Double) -> Double {
        let r = fmod(a, b)
        return (r != 0 && (r < 0) != (b < 0)) ? r + b : r
    }

    /// Kotlin/Java `Float % Float` (truncated remainder) = fmod.
    @inline(__always)
    public static func rem(_ a: Float, _ b: Float) -> Float { fmodf(a, b) }
    @inline(__always)
    public static func rem(_ a: Double, _ b: Double) -> Double { fmod(a, b) }

    // MARK: Math — Kotlin's Float functions go through Double (java.lang.Math) and back.

    @inline(__always) public static func sin(_ f: Float) -> Float { Float(Foundation.sin(Double(f))) }
    @inline(__always) public static func cos(_ f: Float) -> Float { Float(Foundation.cos(Double(f))) }
    @inline(__always) public static func tan(_ f: Float) -> Float { Float(Foundation.tan(Double(f))) }
    @inline(__always) public static func asin(_ f: Float) -> Float { Float(Foundation.asin(Double(f))) }
    @inline(__always) public static func acos(_ f: Float) -> Float { Float(Foundation.acos(Double(f))) }
    @inline(__always) public static func atan(_ f: Float) -> Float { Float(Foundation.atan(Double(f))) }
    @inline(__always) public static func atan2(_ y: Float, _ x: Float) -> Float { Float(Foundation.atan2(Double(y), Double(x))) }
    @inline(__always) public static func sqrt(_ f: Float) -> Float { Float(Double(f).squareRoot()) }
    @inline(__always) public static func pow(_ a: Float, _ b: Float) -> Float { Float(Foundation.pow(Double(a), Double(b))) }
    @inline(__always) public static func exp(_ f: Float) -> Float { Float(Foundation.exp(Double(f))) }
    @inline(__always) public static func ln(_ f: Float) -> Float { Float(Foundation.log(Double(f))) }
    @inline(__always) public static func log10(_ f: Float) -> Float { Float(Foundation.log10(Double(f))) }
    @inline(__always) public static func log2(_ f: Float) -> Float { Float(Foundation.log(Double(f)) / Foundation.log(2.0)) }
    @inline(__always) public static func hypot(_ a: Float, _ b: Float) -> Float { Float(Foundation.hypot(Double(a), Double(b))) }
    @inline(__always) public static func floor(_ f: Float) -> Float { f.rounded(.down) }
    @inline(__always) public static func ceil(_ f: Float) -> Float { f.rounded(.up) }
    @inline(__always) public static func abs(_ f: Float) -> Float { Swift.abs(f) }
    @inline(__always) public static func sign(_ f: Float) -> Float { f > 0 ? 1 : (f < 0 ? -1 : f) }

    /// Kotlin `log2(x: Double)` = ln(x) / LN2.
    @inline(__always) public static func log2(_ d: Double) -> Double { Foundation.log(d) / Foundation.log(2.0) }

    /// Kotlin `min`/`max` on floats follow java.lang.Math (NaN propagates, -0.0 < 0.0).
    @inline(__always)
    public static func min(_ a: Float, _ b: Float) -> Float {
        if a.isNaN || b.isNaN { return .nan }
        if a == 0 && b == 0 { return a.sign == .minus ? a : b }
        return a <= b ? a : b
    }

    @inline(__always)
    public static func max(_ a: Float, _ b: Float) -> Float {
        if a.isNaN || b.isNaN { return .nan }
        if a == 0 && b == 0 { return a.sign == .minus ? b : a }
        return a >= b ? a : b
    }

    // MARK: Hashes

    /// Java `String.hashCode()` over UTF-16 code units.
    public static func javaHash(_ s: String) -> Int {
        var h: Int32 = 0
        for u in s.utf16 { h = h &* 31 &+ Int32(u) }
        return Int(h)
    }

    /// Java `Long.hashCode()`.
    @inline(__always)
    public static func longHash(_ v: Int64) -> Int {
        Int(Int32(truncatingIfNeeded: v ^ Int64(bitPattern: UInt64(bitPattern: v) >> 32)))
    }

    /// Java `Float.floatToIntBits`.
    @inline(__always)
    public static func floatToIntBits(_ f: Float) -> Int {
        if f.isNaN { return 0x7fc00000 }
        return Int(Int32(bitPattern: f.bitPattern))
    }
}

// MARK: - Kotlin-style range clamps

public extension Comparable {
    @inline(__always)
    func coerceIn(_ lo: Self, _ hi: Self) -> Self {
        precondition(lo <= hi, "Cannot coerce value to an empty range")
        return self < lo ? lo : (self > hi ? hi : self)
    }

    @inline(__always)
    func coerceAtLeast(_ lo: Self) -> Self { self < lo ? lo : self }

    @inline(__always)
    func coerceAtMost(_ hi: Self) -> Self { self > hi ? hi : self }
}

public extension FloatingPoint {
    /// Linear interpolation `a + (b - a) * t`.
    @inline(__always)
    static func lerp(_ a: Self, _ b: Self, _ t: Self) -> Self { a + (b - a) * t }
}
