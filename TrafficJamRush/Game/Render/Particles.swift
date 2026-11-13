import SwiftUI
import GameKit

// Port of game/engine/Particles.kt. Particles are pooled: spawning reuses dead instances, so a
// running level allocates nothing once the pool has warmed up.

enum PKind { case SMOKE, SPARK, CONFETTI, STAR, RING }

final class Particle {
    var kind: PKind
    var x: Float
    var y: Float
    var vx: Float
    var vy: Float
    var life: Float
    var size: Float
    var color: Color
    var rot: Float
    var spin: Float
    var gravity: Float
    var age: Float = 0

    init(_ kind: PKind, _ x: Float, _ y: Float, _ vx: Float, _ vy: Float, _ life: Float, _ size: Float, _ color: Color,
         rot: Float = 0, spin: Float = 0, gravity: Float = 0) {
        self.kind = kind
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.life = life
        self.size = size
        self.color = color
        self.rot = rot
        self.spin = spin
        self.gravity = gravity
    }

    fileprivate func reset(_ kind: PKind, _ x: Float, _ y: Float, _ vx: Float, _ vy: Float, _ life: Float, _ size: Float, _ color: Color,
                           rot: Float, spin: Float, gravity: Float) {
        self.kind = kind
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.life = life
        self.size = size
        self.color = color
        self.rot = rot
        self.spin = spin
        self.gravity = gravity
        self.age = 0
    }

    var p: Float { (age / life).coerceIn(0, 1) }
}

final class Particles {
    private let u: Float
    private(set) var list: [Particle] = []
    private var pool: [Particle] = []
    private let rnd = KotlinRandom(7)

    static let smokeColor = Color(argb: 0xFFF2F2F2)
    static let sparkColor = Color(argb: 0xFFFFE066)
    static let starColor = Color(argb: 0xFFFFF59D)
    private static let confettiColors: [Color] = [0xFFF2453D, 0xFF2F7CF6, 0xFF3DBE4B, 0xFFFFC21A, 0xFFFF6FB5, 0xFF9B5CF0, 0xFF23C9D9].map { Color(argb: $0) }

    /// Unit "star" of radius 1 (four quadratic petals), drawn with a transform so frames allocate no paths.
    private static let unitStar: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -1))
        p.addQuadCurve(to: CGPoint(x: 1, y: 0), control: .zero)
        p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: .zero)
        p.addQuadCurve(to: CGPoint(x: -1, y: 0), control: .zero)
        p.addQuadCurve(to: CGPoint(x: 0, y: -1), control: .zero)
        p.closeSubpath()
        return p
    }()

    init(_ u: Float) {
        self.u = u
        list.reserveCapacity(512)
        pool.reserveCapacity(512)
    }

    private func spawn(_ kind: PKind, _ x: Float, _ y: Float, _ vx: Float, _ vy: Float, _ life: Float, _ size: Float, _ color: Color,
                       rot: Float = 0, spin: Float = 0, gravity: Float = 0) {
        if let p = pool.popLast() {
            p.reset(kind, x, y, vx, vy, life, size, color, rot: rot, spin: spin, gravity: gravity)
            list.append(p)
        } else {
            list.append(Particle(kind, x, y, vx, vy, life, size, color, rot: rot, spin: spin, gravity: gravity))
        }
    }

    func update(_ dt: Float) {
        var w = 0
        for i in 0..<list.count {
            let p = list[i]
            p.age += dt
            if p.age >= p.life {
                pool.append(p)
                continue
            }
            p.vy += p.gravity * dt
            if p.kind == .SMOKE {
                p.vx *= 0.92
                p.vy *= 0.92
            }
            if p.kind == .CONFETTI { p.vx *= 0.985 }
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.rot += p.spin * dt
            list[w] = p
            w += 1
        }
        if w < list.count { list.removeLast(list.count - w) }
        let excess = list.count - 400
        if excess > 0 {
            for k in 0..<excess { pool.append(list[k]) }
            list.removeFirst(excess)
        }
    }

    func clear() {
        pool.append(contentsOf: list)
        list.removeAll(keepingCapacity: true)
    }

    func smoke(_ at: Offset, _ dirX: Float = 0, _ dirY: Float = 0, count: Int = 3) {
        for _ in 0..<count {
            let x = at.x + rnd.nextFloat() * 4 * u
            let y = at.y + rnd.nextFloat() * 4 * u
            let vx = dirX * 60 * u + (rnd.nextFloat() - 0.5) * 40 * u
            let vy = dirY * 60 * u + (rnd.nextFloat() - 0.5) * 40 * u - 10 * u
            let life = 0.45 + rnd.nextFloat() * 0.3
            let size = (5 + rnd.nextFloat() * 5) * u
            spawn(.SMOKE, x, y, vx, vy, life, size, Particles.smokeColor)
        }
    }

    func sparks(_ at: Offset, _ count: Int = 10, _ color: Color = Particles.sparkColor) {
        for _ in 0..<count {
            let a = rnd.nextFloat() * 2 * Float.pi
            let s = (80 + rnd.nextFloat() * 160) * u
            let life = 0.25 + rnd.nextFloat() * 0.2
            let size = (1.6 + rnd.nextFloat() * 1.4) * u
            spawn(.SPARK, at.x, at.y, Kt.cos(a) * s, Kt.sin(a) * s, life, size, color)
        }
    }

    func ring(_ at: Offset, _ color: Color = .white, _ size: Float = 26) {
        spawn(.RING, at.x, at.y, 0, 0, 0.4, size * u, color)
    }

    func stars(_ at: Offset, _ count: Int, _ color: Color = Particles.starColor) {
        for _ in 0..<count {
            let a = rnd.nextFloat() * 2 * Float.pi
            let s = (30 + rnd.nextFloat() * 90) * u
            let life = 0.6 + rnd.nextFloat() * 0.4
            let size = (3 + rnd.nextFloat() * 4) * u
            spawn(.STAR, at.x, at.y, Kt.cos(a) * s, Kt.sin(a) * s - 30 * u, life, size, color, spin: 180)
        }
    }

    func confetti(_ width: Float, _ top: Float, _ count: Int) {
        let colors = Particles.confettiColors
        for _ in 0..<count {
            let x = rnd.nextFloat() * width
            let y = top - rnd.nextFloat() * 120 * u
            let vx = (rnd.nextFloat() - 0.5) * 120 * u
            let vy = (60 + rnd.nextFloat() * 120) * u
            let life = 2.2 + rnd.nextFloat() * 1.2
            let size = (4 + rnd.nextFloat() * 4) * u
            let color = colors[rnd.nextInt(colors.count)]
            let rot = rnd.nextFloat() * 360
            let spin = (rnd.nextFloat() - 0.5) * 720
            spawn(.CONFETTI, x, y, vx, vy, life, size, color, rot: rot, spin: spin, gravity: 120 * u)
        }
    }

    /// Draws every live particle. Coordinates are layout points.
    func draw(_ ctx: inout GraphicsContext) {
        let baseOpacity = ctx.opacity
        let baseTransform = ctx.transform
        let px = Double(1 / Art.scale)
        for p in list {
            let pp = p.p
            let a = 1 - pp
            let cx = CGFloat(p.x)
            let cy = CGFloat(p.y)
            switch p.kind {
            case .SMOKE:
                let r = CGFloat(p.size * (0.6 + pp * 1.2))
                ctx.opacity = baseOpacity * Double(0.75 * a)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), with: .color(p.color))
            case .SPARK:
                let r = CGFloat(p.size * (1 - pp * 0.5))
                ctx.opacity = baseOpacity * Double(a)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), with: .color(p.color))
            case .RING:
                let r = CGFloat(p.size * (0.3 + pp))
                ctx.opacity = baseOpacity * Double(0.8 * a)
                let lw = CGFloat(Double(3 * u * a) + 0.5 * px)
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), with: .color(p.color), lineWidth: lw)
            case .STAR:
                let r = CGFloat(p.size * (1 - pp * 0.4))
                ctx.opacity = baseOpacity * Double(a)
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: .degrees(Double(p.rot)))
                ctx.scaleBy(x: r, y: r)
                ctx.fill(Particles.unitStar, with: .color(p.color))
                ctx.transform = baseTransform
            case .CONFETTI:
                ctx.opacity = baseOpacity * Double(pp > 0.8 ? (1 - pp) * 5 : 1)
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: .degrees(Double(p.rot)))
                let s = CGFloat(p.size)
                ctx.fill(Path(CGRect(x: -s / 2, y: -s / 4, width: s, height: s / 2)), with: .color(p.color))
                ctx.transform = baseTransform
            }
        }
        ctx.opacity = baseOpacity
    }
}
