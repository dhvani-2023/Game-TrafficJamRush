import Foundation
import GameKit

// Port of game/engine/GameLayout.kt. Owned by the render module (layout + board transform helpers).

let SLOT_COUNT = 7
let VIP_SLOT = SLOT_COUNT

/// Geometry of the game screen, derived from the canvas size. Everything scales with [u], one
/// 360th of the screen width.
///
/// iOS: all values are in **points** (SwiftUI coordinates). Android used pixels, but every value is
/// a multiple of `u` (or derived from the size and insets), so the layout is identical up to scale.
/// Taps from SwiftUI can be passed straight to `screenToBoard`.
final class GameLayout {
    let width: Float
    let height: Float
    let topInset: Float
    let bottomInset: Float

    let u: Float

    // Scene (station + queue)
    let sceneBottom: Float
    let queueY: Float
    let queueColumnTop: Float
    let queueStartX: Float
    let queueEndX: Float
    let passengerSpacing: Float
    let passengerW: Float
    let passengerH: Float

    // Parking slots
    let slotsTop: Float
    let slotH: Float
    let slotsBottom: Float
    private let slotW: Float
    private let slotGap: Float
    private let slotsStart: Float

    /// Unit size vehicles are drawn at once parked.
    let slotUnit: Float

    // Road
    let roadTop: Float
    let roadBottom: Float
    let roadY: Float

    // Lot
    let boosterBarH: Float
    let lotRect: Rect

    /// The loop vehicles follow from the lot edge up to the road. Its top edge is the road.
    let track: Rect

    // Board transform
    let cols: Int
    let rows: Int
    let rotationDeg: Float
    private let rad: Double
    let cosR: Float
    let sinR: Float
    let unit: Float
    let boardCenter: Offset

    let queueVisibleLength: Float

    // HUD anchors
    let queueSign: Offset

    init(_ width: Float, _ height: Float, _ topInset: Float, _ bottomInset: Float, _ level: Level) {
        self.width = width
        self.height = height
        self.topInset = topInset
        self.bottomInset = bottomInset
        let u = width / 360
        self.u = u

        sceneBottom = topInset + 168 * u
        queueY = sceneBottom - 16 * u
        queueColumnTop = topInset + 70 * u
        queueStartX = 22 * u
        queueEndX = width - 20 * u
        passengerSpacing = 15.5 * u
        passengerW = 15 * u
        passengerH = 27 * u

        slotsTop = sceneBottom
        slotH = 68 * u
        slotsBottom = slotsTop + slotH + 8 * u
        slotW = 38 * u
        slotGap = 3.5 * u
        slotsStart = width - (Float(SLOT_COUNT) * slotW + Float(SLOT_COUNT - 1) * slotGap) - 8 * u
        slotUnit = Swift.min((slotH - 6 * u) / 5, slotW / 2.3)

        roadTop = slotsBottom
        roadBottom = roadTop + 36 * u
        roadY = (roadTop + roadBottom) / 2

        boosterBarH = 104 * u
        lotRect = Rect(10 * u, roadBottom + 8 * u, width - 10 * u, height - bottomInset - boosterBarH)
        track = Rect(lotRect.left + 16 * u, roadY, lotRect.right - 16 * u, lotRect.bottom - 14 * u)

        cols = level.cols
        rows = level.rows
        rotationDeg = level.rotation
        // Math.toRadians(d) = d * DEGREES_TO_RADIANS on the JVM.
        rad = Double(level.rotation) * 0.017453292519943295
        cosR = Float(Foundation.cos(rad))
        sinR = Float(Foundation.sin(rad))

        let bbW = Float(cols) * abs(cosR) + Float(rows) * abs(sinR)
        let bbH = Float(cols) * abs(sinR) + Float(rows) * abs(cosR)
        let availW = lotRect.width - 2 * 18 * u
        let availH = lotRect.height - 2 * 16 * u
        unit = Swift.min(Swift.min(availW / bbW, availH / bbH), 19 * u)
        boardCenter = Offset(lotRect.center.x, lotRect.center.y + 4 * u)

        queueVisibleLength = (queueEndX - queueStartX) + (queueY - queueColumnTop)
        queueSign = Offset(70 * u, topInset + 88 * u)
    }

    convenience init(width: Float, height: Float, topInset: Float, bottomInset: Float, level: Level) {
        self.init(width, height, topInset, bottomInset, level)
    }

    func slotRect(_ i: Int) -> Rect {
        if i == VIP_SLOT {
            return Rect(7 * u, slotsTop + 4 * u, slotsStart - 6 * u, slotsTop + 4 * u + slotH)
        }
        let x = slotsStart + Float(i) * (slotW + slotGap)
        return Rect(x, slotsTop + 4 * u, x + slotW, slotsTop + 4 * u + slotH)
    }

    func boardToScreen(_ gx: Float, _ gy: Float) -> Offset {
        let lx = (gx - Float(cols) / 2) * unit
        let ly = (gy - Float(rows) / 2) * unit
        return Offset(boardCenter.x + lx * cosR - ly * sinR, boardCenter.y + lx * sinR + ly * cosR)
    }

    /// Inverse of `boardToScreen`: a screen point (points) to fractional grid units.
    func screenToBoard(_ p: Offset) -> Offset {
        let dx = p.x - boardCenter.x
        let dy = p.y - boardCenter.y
        let lx = dx * cosR + dy * sinR
        let ly = -dx * sinR + dy * cosR
        return Offset(lx / unit + Float(cols) / 2, ly / unit + Float(rows) / 2)
    }

    /// Point along the queue snake, [s] points from the front.
    func queuePoint(_ s: Float) -> Offset {
        let row = queueEndX - queueStartX
        if s <= row {
            return Offset(queueStartX + s, queueY)
        }
        return Offset(queueEndX, queueY - (s - row))
    }
}
