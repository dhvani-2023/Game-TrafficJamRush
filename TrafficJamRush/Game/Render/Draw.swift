import SwiftUI
import CoreGraphics
import CoreText
import GameKit
#if canImport(UIKit)
import UIKit
#endif

// A small Compose-style drawing layer so the Kotlin drawing code ports line by line.
//  - `BitmapScope` draws with Core Graphics into bitmaps (sprites, textures, the static scene),
//    in device pixels, exactly like Android's `renderBitmap` (Density 1).
//  - `FrameScope` draws per frame into a SwiftUI `GraphicsContext` (layout points) without
//    allocating: rects, ovals, rounded rects and lines never build path objects.

enum Art {
    /// Device pixels per point for every pre-rendered sprite (@3x on current iPhones).
    static var scale: Float = {
        #if canImport(UIKit)
        if Thread.isMainThread {
            return MainActor.assumeIsolated { Float(UIScreen.main.scale) }
        }
        #endif
        return 3
    }()

    /// One device pixel in points; Android "px" literals in per-frame code are multiplied by this.
    static var px: Float { 1 / scale }
}

// MARK: - Colour

/// Compose `Color` for the art code: sRGB stored with 8 bits per channel like Compose's sRGB colours.
struct ArtColor: Hashable {
    let argb: UInt32

    @inline(__always) init(_ argb: UInt32) { self.argb = argb }

    /// Compose `Color(red, green, blue, alpha)` (sRGB floats, quantised to 8 bits).
    init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        @inline(__always) func q(_ v: Float) -> UInt32 { UInt32(Int(v.coerceIn(0, 1) * 255 + 0.5)) }
        argb = (q(alpha) << 24) | (q(red) << 16) | (q(green) << 8) | q(blue)
    }

    var a: Float { Float((argb >> 24) & 0xFF) / 255 }
    var r: Float { Float((argb >> 16) & 0xFF) / 255 }
    var g: Float { Float((argb >> 8) & 0xFF) / 255 }
    var b: Float { Float(argb & 0xFF) / 255 }
    var rgb: UInt32 { argb & 0x00FF_FFFF }

    static let White = ArtColor(0xFFFF_FFFF)
    static let Black = ArtColor(0xFF00_0000)
    static let Transparent = ArtColor(0x0000_0000)

    func copy(alpha: Float) -> ArtColor { ArtColor(red: r, green: g, blue: b, alpha: alpha) }

    var color: Color { Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a)) }
    var cgColor: CGColor { CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }

    init(_ c: Color) {
        let res = c.resolve(in: EnvironmentValues())
        self.init(red: res.red, green: res.green, blue: res.blue, alpha: res.opacity)
    }
}

/// `Color.shade`: scales RGB (Art.kt).
extension ArtColor {
    func shade(_ f: Float) -> ArtColor {
        ArtColor(red: (r * f).coerceIn(0, 1), green: (g * f).coerceIn(0, 1), blue: (b * f).coerceIn(0, 1), alpha: a)
    }

    /// `Color.tint`: `lerp(this, White, f)` (Compose lerps in Oklab).
    func tint(_ f: Float) -> ArtColor { lerp(self, .White, f) }

    /// `Color.gray`: `lerp(this, Color(0xFF8A8F98), f)`.
    func gray(_ f: Float) -> ArtColor { lerp(self, ArtColor(0xFF8A_8F98), f) }
}

/// Compose `lerp(Color, Color, fraction)`: interpolates in Oklab, result in sRGB.
func lerp(_ start: ArtColor, _ stop: ArtColor, _ fraction: Float) -> ArtColor {
    let s = Oklab.from(start)
    let e = Oklab.from(stop)
    let t = fraction
    let L = s.0 + (e.0 - s.0) * t
    let A = s.1 + (e.1 - s.1) * t
    let B = s.2 + (e.2 - s.2) * t
    let alpha = start.a + (stop.a - start.a) * t
    let rgb = Oklab.toSrgb(L, A, B)
    return ArtColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
}

private enum Oklab {
    @inline(__always) static func toLinear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : Float(Foundation.pow(Double((c + 0.055) / 1.055), 2.4))
    }

    @inline(__always) static func toGamma(_ c: Float) -> Float {
        c <= 0.0031308 ? c * 12.92 : Float(1.055 * Foundation.pow(Double(c), 1 / 2.4) - 0.055)
    }

    static func from(_ c: ArtColor) -> (Float, Float, Float) {
        let r = toLinear(c.r), g = toLinear(c.g), b = toLinear(c.b)
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l_ = Float(Foundation.cbrt(Double(l))), m_ = Float(Foundation.cbrt(Double(m))), s_ = Float(Foundation.cbrt(Double(s)))
        return (
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    static func toSrgb(_ L: Float, _ A: Float, _ B: Float) -> (Float, Float, Float) {
        let l_ = L + 0.3963377774 * A + 0.2158037573 * B
        let m_ = L - 0.1055613458 * A - 0.0638541728 * B
        let s_ = L - 0.0894841775 * A - 1.2914855480 * B
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return (toGamma(r.coerceIn(0, 1)).coerceIn(0, 1), toGamma(g.coerceIn(0, 1)).coerceIn(0, 1), toGamma(b.coerceIn(0, 1)).coerceIn(0, 1))
    }
}

/// SwiftUI colour helpers used by the UI (same maths as the art colours).
extension Color {
    /// Compose `Color(0xAARRGGBB)` through the art colour (exact 8-bit channels).
    init(_ c: ArtColor) { self = c.color }

    func shade(_ f: Float) -> Color { ArtColor(self).shade(f).color }
    func tint(_ f: Float) -> Color { ArtColor(self).tint(f).color }
    func gray(_ f: Float) -> Color { ArtColor(self).gray(f).color }
    /// Compose `copy(alpha = …)`: replaces the alpha.
    func copy(alpha: Float) -> Color { ArtColor(self).copy(alpha: alpha).color }
}

/// Compose `lerp(Color, Color, fraction)` for SwiftUI colours.
func lerp(_ start: Color, _ stop: Color, _ fraction: Float) -> Color {
    lerp(ArtColor(start), ArtColor(stop), fraction).color
}

// MARK: - Brushes

/// Gradient colours with lazily built Core Graphics / SwiftUI gradients (cached, so static brushes
/// cost nothing per frame).
final class GradientData {
    let colors: [ArtColor]
    let stops: [Float]?

    init(_ colors: [ArtColor], _ stops: [Float]? = nil) {
        self.colors = colors
        self.stops = stops
    }

    private var _cg: CGGradient?
    private var _ui: Gradient?
    private let lock = NSLock()

    var locations: [CGFloat] {
        if let stops { return stops.map { CGFloat($0) } }
        let n = colors.count
        return (0..<n).map { n == 1 ? 0 : CGFloat($0) / CGFloat(n - 1) }
    }

    var cgGradient: CGGradient {
        lock.lock()
        defer { lock.unlock() }
        if let g = _cg { return g }
        let g = CGGradient(colorsSpace: Draw.srgb, colors: colors.map(\.cgColor) as CFArray, locations: locations)!
        _cg = g
        return g
    }

    var gradient: Gradient {
        lock.lock()
        defer { lock.unlock() }
        if let g = _ui { return g }
        let locs = locations
        let g = Gradient(stops: colors.indices.map { Gradient.Stop(color: colors[$0].color, location: locs[$0]) })
        _ui = g
        return g
    }
}

/// Compose `Brush` (solid colour, linear / radial gradient, repeated image shader).
enum Brush {
    case solid(ArtColor)
    case linear(GradientData, Offset, Offset)
    case radial(GradientData, Offset, Float)
    case image(ImageBitmap)

    static func verticalGradient(_ colors: [ArtColor], _ startY: Float = 0, _ endY: Float = .infinity) -> Brush {
        .linear(GradientData(colors), Offset(0, startY), Offset(0, endY))
    }

    static func verticalGradient(stops: [(Float, ArtColor)], startY: Float = 0, endY: Float = .infinity) -> Brush {
        .linear(GradientData(stops.map(\.1), stops.map(\.0)), Offset(0, startY), Offset(0, endY))
    }

    static func horizontalGradient(_ colors: [ArtColor], _ startX: Float = 0, _ endX: Float = .infinity) -> Brush {
        .linear(GradientData(colors), Offset(startX, 0), Offset(endX, 0))
    }

    static func horizontalGradient(stops: [(Float, ArtColor)], startX: Float = 0, endX: Float = .infinity) -> Brush {
        .linear(GradientData(stops.map(\.1), stops.map(\.0)), Offset(startX, 0), Offset(endX, 0))
    }

    static func linearGradient(_ colors: [ArtColor], start: Offset = .Zero, end: Offset = .Infinite) -> Brush {
        .linear(GradientData(colors), start, end)
    }

    static func linearGradient(_ colors: [ArtColor], _ start: Offset, _ end: Offset) -> Brush {
        .linear(GradientData(colors), start, end)
    }

    static func linearGradient(stops: [(Float, ArtColor)], start: Offset = .Zero, end: Offset = .Infinite) -> Brush {
        .linear(GradientData(stops.map(\.1), stops.map(\.0)), start, end)
    }

    static func radialGradient(_ colors: [ArtColor], _ center: Offset = .Unspecified, _ radius: Float = .infinity) -> Brush {
        .radial(GradientData(colors), center, radius)
    }

    static func radialGradient(_ colors: [ArtColor], center: Offset, radius: Float) -> Brush {
        .radial(GradientData(colors), center, radius)
    }
}

protocol BrushConvertible { var asBrush: Brush { get } }
extension ArtColor: BrushConvertible { @inline(__always) var asBrush: Brush { .solid(self) } }
extension Brush: BrushConvertible { @inline(__always) var asBrush: Brush { self } }

// MARK: - Strokes and shapes

enum StrokeCap { case butt, round, square }
enum StrokeJoin { case miter, round, bevel }

/// Compose `PathEffect.dashPathEffect(intervals, phase)`.
struct PathEffect {
    let intervals: [Float]
    let phase: Float
    static func dashPathEffect(_ intervals: [Float], _ phase: Float = 0) -> PathEffect { PathEffect(intervals: intervals, phase: phase) }
}

/// Compose `Stroke`.
struct StrokeSpec {
    var width: Float = 0
    var miter: Float = 4
    var cap: StrokeCap = .butt
    var join: StrokeJoin = .miter
    var pathEffect: PathEffect?
}

/// Compose `DrawStyle` (`Fill` or `Stroke(...)`).
enum DrawStyle {
    case fill
    case stroked(StrokeSpec)

    static func stroke(_ width: Float = 0, miter: Float = 4, cap: StrokeCap = .butt, join: StrokeJoin = .miter, pathEffect: PathEffect? = nil) -> DrawStyle {
        .stroked(StrokeSpec(width: width, miter: miter, cap: cap, join: join, pathEffect: pathEffect))
    }

    static let Fill = DrawStyle.fill
}

/// Compose `Path`, built with the same verbs.
final class ArtPath {
    let cg = CGMutablePath()

    init() {}

    convenience init(_ build: (ArtPath) -> Void) {
        self.init()
        build(self)
    }

    func moveTo(_ x: Float, _ y: Float) { cg.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y))) }
    func lineTo(_ x: Float, _ y: Float) { cg.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y))) }
    func quadraticTo(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        cg.addQuadCurve(to: CGPoint(x: CGFloat(x2), y: CGFloat(y2)), control: CGPoint(x: CGFloat(x1), y: CGFloat(y1)))
    }
    func cubicTo(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float) {
        cg.addCurve(to: CGPoint(x: CGFloat(x3), y: CGFloat(y3)),
                    control1: CGPoint(x: CGFloat(x1), y: CGFloat(y1)),
                    control2: CGPoint(x: CGFloat(x2), y: CGFloat(y2)))
    }
    func close() { cg.closeSubpath() }

    func addRoundRect(_ rect: Rect, _ r: CornerRadius) {
        let (rx, ry) = Draw.clampRadii(rect.cg, CGFloat(r.x), CGFloat(r.y))
        if rx <= 0 || ry <= 0 {
            cg.addRect(rect.cg)
        } else {
            cg.addRoundedRect(in: rect.cg, cornerWidth: rx, cornerHeight: ry)
        }
    }

    func addOval(_ rect: Rect) { cg.addEllipse(in: rect.cg) }
    func addRect(_ rect: Rect) { cg.addRect(rect.cg) }
}

/// A primitive the backends know how to draw without building path objects.
enum ArtShape {
    case rect(CGRect)
    case oval(CGRect)
    case roundRect(CGRect, CGFloat, CGFloat)
    case line(CGPoint, CGPoint)
    case path(CGPath)
}

enum Draw {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Skia-style corner clamping: radii larger than half the side shrink proportionally.
    static func clampRadii(_ r: CGRect, _ rx: CGFloat, _ ry: CGFloat) -> (CGFloat, CGFloat) {
        let w = abs(r.width), h = abs(r.height)
        var x = max(0, rx), y = max(0, ry)
        if x <= 0 || y <= 0 { return (0, 0) }
        var scale: CGFloat = 1
        if x * 2 > w { scale = min(scale, w / (2 * x)) }
        if y * 2 > h { scale = min(scale, h / (2 * y)) }
        x *= scale
        y *= scale
        // Core Graphics requires strictly <= half; nudge for rounding.
        x = min(x, w / 2 - 0.0001)
        y = min(y, h / 2 - 0.0001)
        return (max(0, x), max(0, y))
    }

    /// Arc geometry like Android `drawArc` (degrees, clockwise from 3 o'clock).
    static func arcPath(_ oval: CGRect, _ startDeg: Float, _ sweepDeg: Float, _ useCenter: Bool) -> CGPath {
        let p = CGMutablePath()
        let t = CGAffineTransform(translationX: oval.midX, y: oval.midY).scaledBy(x: oval.width / 2, y: oval.height / 2)
        let a0 = CGFloat(startDeg) * .pi / 180
        let a1 = CGFloat(startDeg + sweepDeg) * .pi / 180
        if useCenter { p.move(to: .zero, transform: t) }
        p.addArc(center: .zero, radius: 1, startAngle: a0, endAngle: a1, clockwise: sweepDeg < 0, transform: t)
        if useCenter { p.closeSubpath() }
        return p
    }

    static func makeContext(_ w: Int, _ h: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        // Top-left origin, y down, like Android.
        ctx.translateBy(x: 0, y: CGFloat(max(1, h)))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .default
        return ctx
    }

    static func cgCap(_ c: StrokeCap) -> CGLineCap {
        switch c {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }

    static func cgJoin(_ j: StrokeJoin) -> CGLineJoin {
        switch j {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}

// MARK: - ImageBitmap

/// Compose `ImageBitmap`: a pre-rendered `CGImage` at device scale. `width` / `height` are in points
/// (the units the game draws in); `pixelWidth` / `pixelHeight` are device pixels.
final class ImageBitmap: @unchecked Sendable {
    let cgImage: CGImage
    let scale: Float
    /// SwiftUI image for `GraphicsContext.draw` / `Image` views.
    let image: Image
    let width: Float
    let height: Float

    init(_ cgImage: CGImage, scale: Float = Art.scale) {
        self.cgImage = cgImage
        self.scale = scale
        image = Image(decorative: cgImage, scale: CGFloat(scale), orientation: .up)
        width = Float(cgImage.width) / scale
        height = Float(cgImage.height) / scale
    }

    var pixelWidth: Int { cgImage.width }
    var pixelHeight: Int { cgImage.height }
}

/// Draws [block] into a fresh bitmap of w×h device pixels (Kotlin `renderBitmap`).
func renderBitmap(_ w: Int, _ h: Int, scale: Float = Art.scale, _ block: (inout BitmapScope) -> Void) -> ImageBitmap {
    ImageBitmap(renderCGImage(w, h, block), scale: scale)
}

func renderCGImage(_ w: Int, _ h: Int, _ block: (inout BitmapScope) -> Void) -> CGImage {
    let cg = Draw.makeContext(w, h)
    var s = BitmapScope(cg: cg, size: Size(Float(max(1, w)), Float(max(1, h))))
    block(&s)
    return cg.makeImage()!
}

// MARK: - DrawScope

/// Compose `DrawTransform` builder for `withTransform { … }`.
struct DrawTransform {
    var m: CGAffineTransform = .identity

    mutating func translate(_ left: Float = 0, _ top: Float = 0) {
        m = m.translatedBy(x: CGFloat(left), y: CGFloat(top))
    }

    mutating func rotate(_ degrees: Float, _ pivot: Offset = .Zero) {
        m = m.translatedBy(x: CGFloat(pivot.x), y: CGFloat(pivot.y))
            .rotated(by: CGFloat(degrees) * .pi / 180)
            .translatedBy(x: -CGFloat(pivot.x), y: -CGFloat(pivot.y))
    }

    mutating func scale(_ sx: Float, _ sy: Float, _ pivot: Offset = .Zero) {
        m = m.translatedBy(x: CGFloat(pivot.x), y: CGFloat(pivot.y))
            .scaledBy(x: CGFloat(sx), y: CGFloat(sy))
            .translatedBy(x: -CGFloat(pivot.x), y: -CGFloat(pivot.y))
    }
}

protocol DrawScope {
    /// Size of the drawing area (gradients with open ends resolve against it, like Compose).
    var size: Size { get }
    mutating func fill(_ shape: ArtShape, _ brush: Brush, _ alpha: Float)
    mutating func stroke(_ shape: ArtShape, _ brush: Brush, _ stroke: StrokeSpec, _ alpha: Float)
    mutating func image(_ image: ImageBitmap, _ rect: CGRect, _ alpha: Float)
    mutating func withState(_ transform: CGAffineTransform?, _ clip: CGPath?, _ block: (inout Self) -> Void)
}

extension DrawScope {
    var center: Offset { size.center }

    @inline(__always) private mutating func paint(_ shape: ArtShape, _ brush: Brush, _ alpha: Float, _ style: DrawStyle) {
        switch style {
        case .fill: fill(shape, brush, alpha)
        case .stroked(let s): stroke(shape, brush, s, alpha)
        }
    }

    mutating func drawRect<B: BrushConvertible>(_ b: B, _ topLeft: Offset = .Zero, _ size: Size? = nil, alpha: Float = 1, style: DrawStyle = .fill) {
        let sz = size ?? Size(self.size.width - topLeft.x, self.size.height - topLeft.y)
        paint(.rect(CGRect(x: CGFloat(topLeft.x), y: CGFloat(topLeft.y), width: CGFloat(sz.width), height: CGFloat(sz.height))), b.asBrush, alpha, style)
    }

    mutating func drawRoundRect<B: BrushConvertible>(_ b: B, _ topLeft: Offset = .Zero, _ size: Size? = nil, _ cornerRadius: CornerRadius = .Zero,
                                                     alpha: Float = 1, style: DrawStyle = .fill) {
        let sz = size ?? Size(self.size.width - topLeft.x, self.size.height - topLeft.y)
        let r = CGRect(x: CGFloat(topLeft.x), y: CGFloat(topLeft.y), width: CGFloat(sz.width), height: CGFloat(sz.height))
        let (rx, ry) = Draw.clampRadii(r, CGFloat(cornerRadius.x), CGFloat(cornerRadius.y))
        paint(rx > 0 && ry > 0 ? .roundRect(r, rx, ry) : .rect(r), b.asBrush, alpha, style)
    }

    mutating func drawCircle<B: BrushConvertible>(_ b: B, _ radius: Float? = nil, _ center: Offset? = nil, alpha: Float = 1, style: DrawStyle = .fill) {
        let r = CGFloat(radius ?? size.minDimension / 2)
        let c = center ?? size.center
        paint(.oval(CGRect(x: CGFloat(c.x) - r, y: CGFloat(c.y) - r, width: 2 * r, height: 2 * r)), b.asBrush, alpha, style)
    }

    mutating func drawOval<B: BrushConvertible>(_ b: B, _ topLeft: Offset = .Zero, _ size: Size? = nil, alpha: Float = 1, style: DrawStyle = .fill) {
        let sz = size ?? Size(self.size.width - topLeft.x, self.size.height - topLeft.y)
        paint(.oval(CGRect(x: CGFloat(topLeft.x), y: CGFloat(topLeft.y), width: CGFloat(sz.width), height: CGFloat(sz.height))), b.asBrush, alpha, style)
    }

    mutating func drawLine<B: BrushConvertible>(_ b: B, _ start: Offset, _ end: Offset, _ strokeWidth: Float = 0, _ cap: StrokeCap = .butt,
                                                pathEffect: PathEffect? = nil, alpha: Float = 1) {
        stroke(.line(start.cg, end.cg), b.asBrush, StrokeSpec(width: strokeWidth, cap: cap, pathEffect: pathEffect), alpha)
    }

    mutating func drawPath<B: BrushConvertible>(_ path: ArtPath, _ b: B, alpha: Float = 1, style: DrawStyle = .fill) {
        paint(.path(path.cg), b.asBrush, alpha, style)
    }

    mutating func drawArc<B: BrushConvertible>(_ b: B, _ startAngle: Float, _ sweepAngle: Float, _ useCenter: Bool, _ topLeft: Offset = .Zero,
                                               _ size: Size? = nil, alpha: Float = 1, style: DrawStyle = .fill) {
        let sz = size ?? Size(self.size.width - topLeft.x, self.size.height - topLeft.y)
        let oval = CGRect(x: CGFloat(topLeft.x), y: CGFloat(topLeft.y), width: CGFloat(sz.width), height: CGFloat(sz.height))
        paint(.path(Draw.arcPath(oval, startAngle, sweepAngle, useCenter)), b.asBrush, alpha, style)
    }

    mutating func drawImage(_ img: ImageBitmap, _ topLeft: Offset = .Zero, alpha: Float = 1) {
        image(img, CGRect(x: CGFloat(topLeft.x), y: CGFloat(topLeft.y), width: CGFloat(img.width), height: CGFloat(img.height)), alpha)
    }

    mutating func withTransform(_ t: (inout DrawTransform) -> Void, _ block: (inout Self) -> Void) {
        var dt = DrawTransform()
        t(&dt)
        withState(dt.m, nil, block)
    }

    mutating func translate(_ left: Float = 0, _ top: Float = 0, _ block: (inout Self) -> Void) {
        withState(CGAffineTransform(translationX: CGFloat(left), y: CGFloat(top)), nil, block)
    }

    mutating func rotate(_ degrees: Float, _ pivot: Offset? = nil, _ block: (inout Self) -> Void) {
        var dt = DrawTransform()
        dt.rotate(degrees, pivot ?? size.center)
        withState(dt.m, nil, block)
    }

    mutating func scale(_ sx: Float, _ sy: Float, _ pivot: Offset? = nil, _ block: (inout Self) -> Void) {
        var dt = DrawTransform()
        dt.scale(sx, sy, pivot ?? size.center)
        withState(dt.m, nil, block)
    }

    mutating func clipPath(_ path: ArtPath, _ block: (inout Self) -> Void) {
        withState(nil, path.cg, block)
    }
}

// MARK: - Core Graphics backend

/// Core Graphics draw scope for pre-rendered bitmaps (device pixels, top-left origin).
struct BitmapScope: DrawScope {
    let cg: CGContext
    let size: Size

    private func addShape(_ shape: ArtShape) {
        switch shape {
        case .rect(let r): cg.addRect(r)
        case .oval(let r): cg.addEllipse(in: r)
        case .roundRect(let r, let rx, let ry): cg.addPath(CGPath(roundedRect: r, cornerWidth: rx, cornerHeight: ry, transform: nil))
        case .line(let a, let b):
            cg.move(to: a)
            cg.addLine(to: b)
        case .path(let p): cg.addPath(p)
        }
    }

    private func resolveLinear(_ s: Offset, _ e: Offset) -> (CGPoint, CGPoint) {
        let sx = s.x == .infinity ? size.width : s.x
        let sy = s.y == .infinity ? size.height : s.y
        let ex = e.x == .infinity ? size.width : e.x
        let ey = e.y == .infinity ? size.height : e.y
        return (CGPoint(x: CGFloat(sx), y: CGFloat(sy)), CGPoint(x: CGFloat(ex), y: CGFloat(ey)))
    }

    private func paintGradient(_ brush: Brush, _ alpha: Float) {
        switch brush {
        case .solid: break
        case .linear(let g, let s, let e):
            let (a, b) = resolveLinear(s, e)
            cg.setAlpha(CGFloat(alpha))
            cg.drawLinearGradient(g.cgGradient, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .radial(let g, let c, let r):
            let cc = c.isUnspecified ? size.center : c
            let rr = r == .infinity ? size.minDimension / 2 : r
            cg.setAlpha(CGFloat(alpha))
            cg.drawRadialGradient(g.cgGradient, startCenter: cc.cg, startRadius: 0, endCenter: cc.cg, endRadius: CGFloat(rr),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .image(let img):
            // Repeated image shader: tiles anchored at the scope origin, like ImageShader(Repeated).
            cg.setAlpha(CGFloat(alpha))
            let box = cg.boundingBoxOfClipPath
            let tw = CGFloat(img.pixelWidth), th = CGFloat(img.pixelHeight)
            guard tw > 0, th > 0, box.width.isFinite, box.height.isFinite else { return }
            let x0 = (box.minX / tw).rounded(.down) * tw
            let y0 = (box.minY / th).rounded(.down) * th
            var y = y0
            while y < box.maxY {
                var x = x0
                while x < box.maxX {
                    BitmapScope.drawUpright(cg, img.cgImage, CGRect(x: x, y: y, width: tw, height: th))
                    x += tw
                }
                y += th
            }
        }
    }

    /// Draws a CGImage with its top-left at rect.origin in the flipped (y-down) context.
    static func drawUpright(_ cg: CGContext, _ image: CGImage, _ rect: CGRect) {
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        cg.restoreGState()
    }

    func fill(_ shape: ArtShape, _ brush: Brush, _ alpha: Float) {
        if case .line = shape { return }
        if case .solid(let c) = brush {
            cg.setFillColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a * alpha))
            addShape(shape)
            cg.fillPath()
            return
        }
        cg.saveGState()
        addShape(shape)
        cg.clip()
        paintGradient(brush, alpha)
        cg.restoreGState()
    }

    func stroke(_ shape: ArtShape, _ brush: Brush, _ stroke: StrokeSpec, _ alpha: Float) {
        cg.saveGState()
        cg.setLineWidth(CGFloat(stroke.width))
        cg.setLineCap(Draw.cgCap(stroke.cap))
        cg.setLineJoin(Draw.cgJoin(stroke.join))
        cg.setMiterLimit(CGFloat(stroke.miter))
        if let pe = stroke.pathEffect {
            cg.setLineDash(phase: CGFloat(pe.phase), lengths: pe.intervals.map { CGFloat($0) })
        }
        addShape(shape)
        if case .solid(let c) = brush {
            cg.setStrokeColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a * alpha))
            cg.strokePath()
        } else {
            cg.replacePathWithStrokedPath()
            cg.clip()
            paintGradient(brush, alpha)
        }
        cg.restoreGState()
    }

    func image(_ image: ImageBitmap, _ rect: CGRect, _ alpha: Float) {
        // Bitmap scopes work in device pixels: draw at the image's pixel size.
        let r = CGRect(x: rect.minX, y: rect.minY, width: CGFloat(image.pixelWidth), height: CGFloat(image.pixelHeight))
        cg.saveGState()
        cg.setAlpha(CGFloat(alpha))
        BitmapScope.drawUpright(cg, image.cgImage, r)
        cg.restoreGState()
    }

    /// Draws a raw CGImage (device pixels) with its top-left at [x], [y].
    func drawCGImage(_ image: CGImage, _ x: Float, _ y: Float, alpha: Float = 1) {
        cg.saveGState()
        cg.setAlpha(CGFloat(alpha))
        BitmapScope.drawUpright(cg, image, CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(image.width), height: CGFloat(image.height)))
        cg.restoreGState()
    }

    mutating func withState(_ transform: CGAffineTransform?, _ clip: CGPath?, _ block: (inout BitmapScope) -> Void) {
        cg.saveGState()
        if let transform { cg.concatenate(transform) }
        if let clip {
            cg.addPath(clip)
            cg.clip()
        }
        block(&self)
        cg.restoreGState()
    }

    /// Android `canvas.drawText` with a bold system face, centred on [x], baseline at [y].
    func drawText(_ s: String, _ x: Float, _ baseline: Float, _ textSize: Float, _ color: ArtColor, font: CTFont? = nil) {
        let f = font ?? CTFontCreateUIFontForLanguage(.emphasizedSystem, CGFloat(textSize), nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(textSize), nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        cg.saveGState()
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cg.textPosition = CGPoint(x: CGFloat(x) - CGFloat(w) / 2, y: CGFloat(baseline))
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    /// Android `BlurMaskFilter(radius, NORMAL)`: draws only the blurred silhouette of [shape].
    func fillBlurred(_ shape: ArtShape, _ color: ArtColor, blurRadius: Float) {
        // Skia converts a blur radius to sigma = 0.57735·r + 0.5; Core Graphics' shadow blur ≈ 2·sigma.
        let sigma = blurRadius > 0 ? 0.57735 * blurRadius + 0.5 : 0
        let far: CGFloat = 20_000
        cg.saveGState()
        // Shadow offsets live in base (device) space; shifting along x avoids the y-flip.
        cg.setShadow(offset: CGSize(width: far, height: 0), blur: CGFloat(2 * sigma), color: color.cgColor)
        cg.translateBy(x: -far, y: 0)
        cg.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        addShape(shape)
        cg.fillPath()
        cg.restoreGState()
    }
}

// MARK: - SwiftUI GraphicsContext backend

/// Per-frame draw scope over a SwiftUI `GraphicsContext`. Primitive shapes and lines use inline
/// `Path` storage and colours come from a cache, so drawing allocates nothing in steady state.
struct FrameScope: DrawScope {
    var ctx: GraphicsContext
    var size: Size

    init(_ ctx: GraphicsContext, _ size: Size) {
        self.ctx = ctx
        self.size = size
    }

    private static var colorCache: [UInt32: Color] = [:]

    /// Opaque SwiftUI colour for an RGB value (alpha is applied through the context opacity).
    static func opaque(_ c: ArtColor) -> Color {
        let key = c.rgb
        if let col = colorCache[key] { return col }
        let col = ArtColor(0xFF00_0000 | key).color
        colorCache[key] = col
        return col
    }

    private func shading(_ brush: Brush) -> GraphicsContext.Shading {
        switch brush {
        case .solid(let c):
            return .color(FrameScope.opaque(c))
        case .linear(let g, let s, let e):
            let sx = s.x == .infinity ? size.width : s.x
            let sy = s.y == .infinity ? size.height : s.y
            let ex = e.x == .infinity ? size.width : e.x
            let ey = e.y == .infinity ? size.height : e.y
            return .linearGradient(g.gradient, startPoint: CGPoint(x: CGFloat(sx), y: CGFloat(sy)), endPoint: CGPoint(x: CGFloat(ex), y: CGFloat(ey)))
        case .radial(let g, let c, let r):
            let cc = c.isUnspecified ? size.center : c
            let rr = r == .infinity ? size.minDimension / 2 : r
            return .radialGradient(g.gradient, center: cc.cg, startRadius: 0, endRadius: CGFloat(rr))
        case .image(let img):
            return .tiledImage(img.image, origin: .zero, sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1)
        }
    }

    /// [brush] expressed in a frame translated to [origin] and rotated by [angle] radians.
    private static func localized(_ brush: Brush, _ origin: CGPoint, _ angle: CGFloat) -> Brush {
        func map(_ p: Offset) -> Offset {
            if !p.isFinite { return p }
            let x = CGFloat(p.x) - origin.x, y = CGFloat(p.y) - origin.y
            let c = cos(angle), s = sin(angle)
            return Offset(Float(x * c + y * s), Float(-x * s + y * c))
        }
        switch brush {
        case .linear(let g, let st, let en): return .linear(g, map(st), map(en))
        case .radial(let g, let c, let r): return c.isUnspecified ? brush : .radial(g, map(c), r)
        default: return brush
        }
    }

    @inline(__always) private func alphaOf(_ brush: Brush) -> Float {
        if case .solid(let c) = brush { return c.a }
        return 1
    }

    private static func path(_ shape: ArtShape) -> Path {
        switch shape {
        case .rect(let r): return Path(r)
        case .oval(let r): return Path(ellipseIn: r)
        case .roundRect(let r, let rx, let ry): return Path(roundedRect: r, cornerSize: CGSize(width: rx, height: ry))
        case .line(let a, let b):
            var p = Path()
            p.move(to: a)
            p.addLine(to: b)
            return p
        case .path(let p): return Path(p)
        }
    }

    mutating func fill(_ shape: ArtShape, _ brush: Brush, _ alpha: Float) {
        if case .line = shape { return }
        let o = ctx.opacity
        ctx.opacity = o * Double(alpha * alphaOf(brush))
        ctx.fill(FrameScope.path(shape), with: shading(brush))
        ctx.opacity = o
    }

    mutating func stroke(_ shape: ArtShape, _ brush: Brush, _ stroke: StrokeSpec, _ alpha: Float) {
        let o = ctx.opacity
        ctx.opacity = o * Double(alpha * alphaOf(brush))
        defer { ctx.opacity = o }
        let w = CGFloat(stroke.width == 0 ? Art.px : stroke.width)
        if case .line(let a, let b) = shape, stroke.pathEffect == nil {
            // A line is a (rounded) rectangle along its direction: no path object needed.
            let dx = b.x - a.x, dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            let saved = ctx.transform
            let angle = len > 0 ? atan2(dy, dx) : 0
            ctx.translateBy(x: a.x, y: a.y)
            if len > 0 { ctx.rotate(by: .radians(angle)) }
            // Gradients are positioned in the outer space: map them into the line's local frame.
            let sh = shading(FrameScope.localized(brush, a, angle))
            switch stroke.cap {
            case .butt:
                ctx.fill(Path(CGRect(x: 0, y: -w / 2, width: len, height: w)), with: sh)
            case .square:
                ctx.fill(Path(CGRect(x: -w / 2, y: -w / 2, width: len + w, height: w)), with: sh)
            case .round:
                ctx.fill(Path(roundedRect: CGRect(x: -w / 2, y: -w / 2, width: len + w, height: w), cornerSize: CGSize(width: w / 2, height: w / 2)),
                         with: sh)
            }
            ctx.transform = saved
            return
        }
        let style = StrokeStyle(lineWidth: w,
                                lineCap: Draw.cgCap(stroke.cap),
                                lineJoin: Draw.cgJoin(stroke.join),
                                miterLimit: CGFloat(stroke.miter),
                                dash: stroke.pathEffect?.intervals.map { CGFloat($0) } ?? [],
                                dashPhase: CGFloat(stroke.pathEffect?.phase ?? 0))
        ctx.stroke(FrameScope.path(shape), with: shading(brush), style: style)
    }

    mutating func image(_ image: ImageBitmap, _ rect: CGRect, _ alpha: Float) {
        let o = ctx.opacity
        ctx.opacity = o * Double(alpha)
        ctx.draw(image.image, in: rect)
        ctx.opacity = o
    }

    mutating func withState(_ transform: CGAffineTransform?, _ clip: CGPath?, _ block: (inout FrameScope) -> Void) {
        if let clip {
            var inner = self
            if let transform { inner.ctx.concatenate(transform) }
            inner.ctx.clip(to: Path(clip))
            block(&inner)
            return
        }
        let saved = ctx.transform
        if let transform { ctx.concatenate(transform) }
        block(&self)
        ctx.transform = saved
    }
}
