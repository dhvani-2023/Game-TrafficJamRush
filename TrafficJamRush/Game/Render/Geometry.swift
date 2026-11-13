import CoreGraphics
import GameKit

// Compose geometry (`androidx.compose.ui.geometry`) ported with Float components, so layout and
// engine maths keep Kotlin's Float behaviour. Shared by the engine, the layout and the renderer.

/// Compose `Offset`.
struct Offset: Hashable {
    var x: Float
    var y: Float

    @inline(__always) init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    @inline(__always) init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    static let Zero = Offset(0, 0)
    static let Infinite = Offset(.infinity, .infinity)
    /// Compose `Offset.Unspecified` (NaN components).
    static let Unspecified = Offset(.nan, .nan)

    var isUnspecified: Bool { x.isNaN || y.isNaN }
    var isFinite: Bool { x.isFinite && y.isFinite }

    /// `sqrt(x * x + y * y)` like Compose.
    @inline(__always) func getDistance() -> Float { Kt.sqrt(x * x + y * y) }
    @inline(__always) func getDistanceSquared() -> Float { x * x + y * y }

    var cg: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }

    @inline(__always) static func + (a: Offset, b: Offset) -> Offset { Offset(a.x + b.x, a.y + b.y) }
    @inline(__always) static func - (a: Offset, b: Offset) -> Offset { Offset(a.x - b.x, a.y - b.y) }
    @inline(__always) static func * (a: Offset, k: Float) -> Offset { Offset(a.x * k, a.y * k) }
    @inline(__always) static func / (a: Offset, k: Float) -> Offset { Offset(a.x / k, a.y / k) }
    @inline(__always) static prefix func - (a: Offset) -> Offset { Offset(-a.x, -a.y) }
    @inline(__always) static func += (a: inout Offset, b: Offset) { a = a + b }
    @inline(__always) static func -= (a: inout Offset, b: Offset) { a = a - b }
}

/// Compose `Size`.
struct Size: Hashable {
    var width: Float
    var height: Float

    @inline(__always) init(_ width: Float, _ height: Float) {
        self.width = width
        self.height = height
    }

    @inline(__always) init(width: Float, height: Float) {
        self.width = width
        self.height = height
    }

    static let Zero = Size(0, 0)

    var minDimension: Float { Swift.min(abs(width), abs(height)) }
    var maxDimension: Float { Swift.max(abs(width), abs(height)) }
    var center: Offset { Offset(width / 2, height / 2) }
    var cg: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }

    @inline(__always) static func * (a: Size, k: Float) -> Size { Size(a.width * k, a.height * k) }
    @inline(__always) static func / (a: Size, k: Float) -> Size { Size(a.width / k, a.height / k) }
}

/// Compose `Rect` (left, top, right, bottom).
struct Rect: Hashable {
    var left: Float
    var top: Float
    var right: Float
    var bottom: Float

    @inline(__always) init(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    init(left: Float, top: Float, right: Float, bottom: Float) {
        self.init(left, top, right, bottom)
    }

    init(_ offset: Offset, _ size: Size) {
        self.init(offset.x, offset.y, offset.x + size.width, offset.y + size.height)
    }

    static let Zero = Rect(0, 0, 0, 0)

    var width: Float { right - left }
    var height: Float { bottom - top }
    var size: Size { Size(width, height) }
    var topLeft: Offset { Offset(left, top) }
    var topRight: Offset { Offset(right, top) }
    var bottomLeft: Offset { Offset(left, bottom) }
    var bottomRight: Offset { Offset(right, bottom) }
    var center: Offset { Offset(left + width / 2, top + height / 2) }
    var minDimension: Float { Swift.min(abs(width), abs(height)) }
    var maxDimension: Float { Swift.max(abs(width), abs(height)) }
    var isEmpty: Bool { left >= right || top >= bottom }
    var cg: CGRect { CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(width), height: CGFloat(height)) }

    func inflate(_ delta: Float) -> Rect { Rect(left - delta, top - delta, right + delta, bottom + delta) }
    func deflate(_ delta: Float) -> Rect { inflate(-delta) }
    func translate(_ offset: Offset) -> Rect { Rect(left + offset.x, top + offset.y, right + offset.x, bottom + offset.y) }
    func translate(_ dx: Float, _ dy: Float) -> Rect { Rect(left + dx, top + dy, right + dx, bottom + dy) }

    /// Compose semantics: left/top inclusive, right/bottom exclusive.
    func contains(_ p: Offset) -> Bool { p.x >= left && p.x < right && p.y >= top && p.y < bottom }
}

/// Compose `CornerRadius`.
struct CornerRadius: Hashable {
    var x: Float
    var y: Float

    @inline(__always) init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    @inline(__always) init(_ r: Float) {
        self.x = r
        self.y = r
    }

    static let Zero = CornerRadius(0)
}

extension CGPoint {
    /// Bridge to the Float geometry used by the game.
    var offset: Offset { Offset(Float(x), Float(y)) }
}

extension CGSize {
    var asSize: Size { Size(Float(width), Float(height)) }
}

extension CGRect {
    var asRect: Rect { Rect(Float(minX), Float(minY), Float(maxX), Float(maxY)) }
}
