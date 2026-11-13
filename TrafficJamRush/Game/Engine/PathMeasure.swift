import Foundation

// Android's Compose `Path` + `PathMeasure` (android.graphics.PathMeasure → Skia SkContourMeasure) for the
// paths the engine builds: moveTo / lineTo / quadraticTo. Quads are flattened exactly like Skia
// (recursive halving while the midpoint deviates more than 0.5 px, 30-bit t values), distances are
// arc-length along the flattened segments, and positions / tangents are evaluated on the true curve.
// Checked against real Skia in TrafficJamRushTests/PathMeasureTests (Golden/pathmeasure.json).

/// Minimal path recorder (Kotlin `androidx.compose.ui.graphics.Path`; named so it does not shadow SwiftUI.Path).
struct EnginePath {
    enum Verb { case move, line, quad }

    private(set) var verbs: [Verb] = []
    /// move: 1 point, line: 1 point, quad: 2 points (control, end).
    private(set) var points: [Offset] = []

    init() {}

    mutating func moveTo(_ x: Float, _ y: Float) {
        verbs.append(.move)
        points.append(Offset(x, y))
    }

    mutating func lineTo(_ x: Float, _ y: Float) {
        if verbs.isEmpty { moveTo(0, 0) }
        verbs.append(.line)
        points.append(Offset(x, y))
    }

    mutating func quadraticTo(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        if verbs.isEmpty { moveTo(0, 0) }
        verbs.append(.quad)
        points.append(Offset(x1, y1))
        points.append(Offset(x2, y2))
    }

    var isEmpty: Bool { verbs.isEmpty }
}

final class PathMeasure {
    private struct Segment {
        var distance: Float
        var ptIndex: Int
        var tValue: Int32
        var isQuad: Bool
    }

    private static let kMaxTValue: Int32 = 0x3FFF_FFFF
    private static let kMaxTReciprocal: Float = 1 / Float(kMaxTValue)
    /// CHEAP_DIST_LIMIT / resScale (resScale is 1 for android.graphics.PathMeasure).
    private static let tolerance: Float = 0.5

    private var segments: [Segment] = []
    private var pts: [Offset] = []
    private(set) var length: Float = 0

    init() {}

    convenience init(_ path: EnginePath, _ forceClosed: Bool = false) {
        self.init()
        setPath(path, forceClosed)
    }

    /// Measures the first contour of `path` (`forceClosed` is not needed by the game and is ignored).
    func setPath(_ path: EnginePath?, _ forceClosed: Bool) {
        segments.removeAll(keepingCapacity: true)
        pts.removeAll(keepingCapacity: true)
        length = 0
        guard let path else { return }
        var ptIndex = -1
        var distance: Float = 0
        var haveSeenMoveTo = false
        var last = Offset.Zero
        var pi = 0
        for verb in path.verbs {
            switch verb {
            case .move:
                if haveSeenMoveTo { break }
                let p = path.points[pi]
                pi += 1
                ptIndex += 1
                pts.append(p)
                haveSeenMoveTo = true
                last = p
                continue
            case .line:
                let p1 = path.points[pi]
                pi += 1
                let prevD = distance
                distance = computeLineSeg(last, p1, distance, ptIndex)
                if distance > prevD {
                    pts.append(p1)
                    ptIndex += 1
                }
                last = p1
                continue
            case .quad:
                let c = path.points[pi]
                let e = path.points[pi + 1]
                pi += 2
                let prevD = distance
                distance = computeQuadSegs(last, c, e, distance, 0, Self.kMaxTValue, ptIndex)
                if distance > prevD {
                    pts.append(c)
                    pts.append(e)
                    ptIndex += 2
                }
                last = e
                continue
            }
            break // a second moveTo ends the first contour
        }
        if !distance.isFinite || segments.isEmpty {
            segments.removeAll()
            pts.removeAll()
            return
        }
        length = distance
    }

    private func computeLineSeg(_ p0: Offset, _ p1: Offset, _ distance: Float, _ ptIndex: Int) -> Float {
        let d = Self.pointDistance(p0, p1)
        let prevD = distance
        let next = distance + d
        if next > prevD {
            segments.append(Segment(distance: next, ptIndex: ptIndex, tValue: Self.kMaxTValue, isQuad: false))
        }
        return next
    }

    private func computeQuadSegs(_ p0: Offset, _ p1: Offset, _ p2: Offset, _ distance: Float, _ mint: Int32, _ maxt: Int32, _ ptIndex: Int) -> Float {
        if ((maxt - mint) >> 10) != 0 && Self.quadTooCurvy(p0, p1, p2) {
            // SkChopQuadAtHalf
            let p01 = Self.interp(p0, p1, 0.5)
            let p12 = Self.interp(p1, p2, 0.5)
            let mid = Self.interp(p01, p12, 0.5)
            let halft = (mint + maxt) >> 1
            var d = computeQuadSegs(p0, p01, mid, distance, mint, halft, ptIndex)
            d = computeQuadSegs(mid, p12, p2, d, halft, maxt, ptIndex)
            return d
        }
        let d = Self.pointDistance(p0, p2)
        let prevD = distance
        let next = distance + d
        if next > prevD {
            segments.append(Segment(distance: next, ptIndex: ptIndex, tValue: maxt, isQuad: true))
        }
        return next
    }

    @inline(__always)
    private static func quadTooCurvy(_ p0: Offset, _ p1: Offset, _ p2: Offset) -> Bool {
        // diff = -a/4 + b/2 - c/4
        let dx = p1.x * 0.5 - (p0.x + p2.x) * 0.5 * 0.5
        let dy = p1.y * 0.5 - (p0.y + p2.y) * 0.5 * 0.5
        return Swift.max(abs(dx), abs(dy)) > tolerance
    }

    @inline(__always)
    private static func interp(_ a: Offset, _ b: Offset, _ t: Float) -> Offset {
        Offset(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    @inline(__always)
    private static func pointDistance(_ a: Offset, _ b: Offset) -> Float {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let mag2 = dx * dx + dy * dy
        if mag2.isFinite { return mag2.squareRoot() }
        let xx = Double(dx)
        let yy = Double(dy)
        return Float((xx * xx + yy * yy).squareRoot())
    }

    @inline(__always)
    private static func scalarT(_ t: Int32) -> Float { Float(t) * kMaxTReciprocal }

    /// SkContourMeasure::distanceToSegment.
    private func distanceToSegment(_ distance: Float) -> (Int, Float) {
        // SkTSearch: first segment whose distance is >= `distance`.
        var lo = 0
        var hi = segments.count - 1
        while lo < hi {
            let mid = lo + ((hi - lo) >> 1)
            if segments[mid].distance < distance { lo = mid + 1 } else { hi = mid }
        }
        var index = hi
        if segments[hi].distance < distance { index = hi + 1 }
        index = Swift.min(index, segments.count - 1)
        let seg = segments[index]
        var startT: Float = 0
        var startD: Float = 0
        if index > 0 {
            let prev = segments[index - 1]
            startD = prev.distance
            if prev.ptIndex == seg.ptIndex { startT = Self.scalarT(prev.tValue) }
        }
        let t = startT + (Self.scalarT(seg.tValue) - startT) * (distance - startD) / (seg.distance - startD)
        return (index, t)
    }

    /// Position and unit tangent at `distance` (pinned to 0...length). Unspecified (NaN) when nothing was measured.
    func getPosTan(_ distance: Float) -> (pos: Offset, tan: Offset) {
        if distance.isNaN || segments.isEmpty { return (.Unspecified, .Unspecified) }
        let d = distance < 0 ? 0 : (distance > length ? length : distance)
        let (index, t) = distanceToSegment(d)
        if t.isNaN { return (.Unspecified, .Unspecified) }
        let seg = segments[index]
        let i = seg.ptIndex
        if !seg.isQuad {
            let p0 = pts[i]
            let p1 = pts[i + 1]
            let pos = Offset(p0.x + (p1.x - p0.x) * t, p0.y + (p1.y - p0.y) * t)
            return (pos, Self.normalize(p1.x - p0.x, p1.y - p0.y))
        }
        let p0 = pts[i]
        let p1 = pts[i + 1]
        let p2 = pts[i + 2]
        // SkQuadCoeff: A = P2 - 2·P1 + P0, B = 2·(P1 - P0), C = P0; eval = (A·t + B)·t + C
        let bx = (p1.x - p0.x) + (p1.x - p0.x)
        let by = (p1.y - p0.y) + (p1.y - p0.y)
        let ax = p2.x - (p1.x + p1.x) + p0.x
        let ay = p2.y - (p1.y + p1.y) + p0.y
        let pos = Offset((ax * t + bx) * t + p0.x, (ay * t + by) * t + p0.y)
        // SkEvalQuadTangentAt
        var tx: Float
        var ty: Float
        if (t == 0 && p0 == p1) || (t == 1 && p1 == p2) {
            tx = p2.x - p0.x
            ty = p2.y - p0.y
        } else {
            let b2x = p1.x - p0.x
            let b2y = p1.y - p0.y
            let a2x = p2.x - p1.x - b2x
            let a2y = p2.y - p1.y - b2y
            tx = a2x * t + b2x
            ty = a2y * t + b2y
            tx = tx + tx
            ty = ty + ty
        }
        return (pos, Self.normalize(tx, ty))
    }

    func getPosition(_ distance: Float) -> Offset { getPosTan(distance).pos }
    func getTangent(_ distance: Float) -> Offset { getPosTan(distance).tan }

    /// SkPoint::setNormalize (double-precision length, like set_point_length).
    @inline(__always)
    private static func normalize(_ x: Float, _ y: Float) -> Offset {
        let xx = Double(x)
        let yy = Double(y)
        let scale = 1.0 / (xx * xx + yy * yy).squareRoot()
        let nx = Float(Double(x) * scale)
        let ny = Float(Double(y) * scale)
        if !nx.isFinite || !ny.isFinite || (nx == 0 && ny == 0) { return .Zero }
        return Offset(nx, ny)
    }
}
