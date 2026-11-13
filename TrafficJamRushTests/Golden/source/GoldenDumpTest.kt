// How to regenerate Golden/*.json (scratch copy of /Volumes/Work/Raj/Android/Cartrafficjam only, never the original):
//  1. Copy this file to app/src/test/java/com/puzzel/lab/cartrafficjam/GoldenDumpTest.kt, and Path.java.txt /
//     PathMeasure.java.txt to app/src/test/java/android/graphics/{Path,PathMeasure}.java (they shadow the stub
//     android.jar classes and forward to real Skia through Skiko).
//  2. In app/build.gradle.kts add
//       testImplementation(files("/Applications/Android Studio.app/Contents/lib/intellij.libraries.skiko.jar"))
//     and inside android { }:
//       testOptions { unitTests.all {
//           it.systemProperty("skiko.library.path", "/Applications/Android Studio.app/Contents/lib/skiko-awt-runtime-all")
//           it.jvmArgs("--enable-native-access=ALL-UNNAMED", "-Xmx1g") } }
//  3. JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew --no-daemon \
//       :app:testDebugUnitTest --tests 'com.puzzel.lab.cartrafficjam.GoldenDumpTest'
//     Output: app/build/golden/{levels,pathmeasure,traces}.json → TrafficJamRushTests/Golden/.

package com.puzzel.lab.cartrafficjam

import androidx.compose.runtime.MutableState
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.ImageBitmapConfig
import androidx.compose.ui.graphics.colorspace.ColorSpace
import androidx.compose.ui.graphics.colorspace.ColorSpaces
import com.puzzel.lab.cartrafficjam.core.audio.Haptic
import com.puzzel.lab.cartrafficjam.core.audio.Sfx
import com.puzzel.lab.cartrafficjam.game.engine.GameEngine
import com.puzzel.lab.cartrafficjam.game.engine.GameEvent
import com.puzzel.lab.cartrafficjam.game.engine.GameFx
import com.puzzel.lab.cartrafficjam.game.engine.GameLayout
import com.puzzel.lab.cartrafficjam.game.engine.Particles
import com.puzzel.lab.cartrafficjam.game.engine.Phase
import com.puzzel.lab.cartrafficjam.game.engine.SLOT_COUNT
import com.puzzel.lab.cartrafficjam.game.engine.VIP_SLOT
import com.puzzel.lab.cartrafficjam.game.engine.VState
import com.puzzel.lab.cartrafficjam.game.gen.LevelGenerator
import com.puzzel.lab.cartrafficjam.game.gen.Solver
import com.puzzel.lab.cartrafficjam.game.model.Level
import com.puzzel.lab.cartrafficjam.game.render.Skin
import com.puzzel.lab.cartrafficjam.game.render.Themes
import com.puzzel.lab.cartrafficjam.game.render.VehicleArt
import org.junit.Test
import java.io.File
import kotlin.math.min
import kotlin.random.Random

/**
 * Golden dump for the iOS port (run on a scratch copy of the Android project only). Writes app/build/golden/:
 *  - levels.json: every LevelGenerator.generate(1..5000) output, one line per level (all Level fields, the full
 *    vehicle list, the queue run-length encoded, plus Solver.solvesIntended / solvesGreedy);
 *  - pathmeasure.json: real Skia (Skiko) PathMeasure lengths / positions / tangents for rounded polylines like the
 *    engine's exit roads;
 *  - traces.json: the real GameEngine driven by a deterministic bot. android.graphics.Path / PathMeasure are shadowed
 *    by test classes that forward to real Skia (Skiko), and setSize is replayed without the bitmap rendering
 *    (SceneArt / sprite pre-builds need a device), so everything else is the shipping engine code.
 * Float tokens are prefixed with '~' and compared with a tight tolerance on iOS; everything else must be equal.
 */
class GoldenDumpTest {

    private val dir = File("build/golden").apply { mkdirs() }

    // ------------------------------------------------------------------------------- levels

    @Test
    fun dumpLevels() {
        val lines = (1..5000).map { levelLine(LevelGenerator.generate(it)) }
        File(dir, "levels.json").writeText(jsonLines("levels", lines))
        println("golden: ${lines.size} levels, ${lines.sumOf { it.length }} chars")
    }

    private fun levelLine(l: Level): String = buildString {
        append(l.number).append('|').append(l.cols).append('|').append(l.rows).append('|')
        append(java.lang.Float.floatToRawIntBits(l.rotation)).append('|').append(l.difficulty.name).append('|')
        append(l.colorCount).append('|').append(l.openSlots).append('|').append(l.lockedSlots).append('|')
        val n = l.cols * l.rows
        var i = 0
        while (i < n) {
            var nib = 0
            for (k in 0 until 4) if (i + k < n && l.mask[i + k]) nib = nib or (1 shl k)
            append("0123456789abcdef"[nib])
            i += 4
        }
        append('|')
        l.vehicles.forEachIndexed { idx, v ->
            if (idx > 0) append(';')
            append(v.id).append(',').append(v.type.name[0]).append(v.color).append(v.dir.name).append(v.x).append(',').append(v.y)
            if (v.mystery) append('m')
        }
        append('|')
        var j = 0
        val q = l.queue
        while (j < q.size) {
            var k = j
            while (k < q.size && q[k] == q[j]) k++
            if (j > 0) append(',')
            append(q[j]).append('x').append(k - j)
            j = k
        }
        append('|').append(if (Solver.solvesIntended(l)) 1 else 0).append(if (Solver.solvesGreedy(l)) 1 else 0)
    }

    // ------------------------------------------------------------------------- path measure

    @Test
    fun dumpPathMeasure() {
        val rnd = java.util.Random(20261108L)
        val cases = ArrayList<String>()
        repeat(300) { c ->
            // Random corner list in the spirit of exitPoints: mostly axis-aligned legs, sometimes diagonal.
            val pts = ArrayList<FloatArray>()
            var x = rnd.nextFloat() * 1000f
            var y = 600f + rnd.nextFloat() * 1600f
            pts += floatArrayOf(x, y)
            val legs = 1 + rnd.nextInt(5)
            repeat(legs) {
                when (rnd.nextInt(4)) {
                    0 -> y -= 20f + rnd.nextFloat() * 900f
                    1 -> x += (rnd.nextFloat() - 0.5f) * 1400f
                    2 -> { x += (rnd.nextFloat() - 0.5f) * 600f; y -= rnd.nextFloat() * 600f }
                    else -> y += 10f + rnd.nextFloat() * 400f
                }
                pts += floatArrayOf(x, y)
            }
            val radius = if (c % 7 == 0) 3f + rnd.nextFloat() * 4f else 16f * (1f + rnd.nextFloat() * 3f)
            val sk = org.jetbrains.skia.PathBuilder()
            val verbs = StringBuilder()
            sk.moveTo(pts[0][0], pts[0][1]); verbs.append("M~").append(pts[0][0]).append("~").append(pts[0][1])
            for (i in 1 until pts.size - 1) {
                val a = pts[i - 1]; val b = pts[i]; val cc = pts[i + 1]
                val inLen = Offset(b[0] - a[0], b[1] - a[1]).getDistance()
                val outLen = Offset(cc[0] - b[0], cc[1] - b[1]).getDistance()
                val r = min(radius, min(inLen, outLen) / 2)
                val p1 = Offset(b[0], b[1]) - (Offset(b[0], b[1]) - Offset(a[0], a[1])) / inLen * r
                val p2 = Offset(b[0], b[1]) + (Offset(cc[0], cc[1]) - Offset(b[0], b[1])) / outLen * r
                sk.lineTo(p1.x, p1.y); verbs.append(";L~").append(p1.x).append("~").append(p1.y)
                sk.quadTo(b[0], b[1], p2.x, p2.y); verbs.append(";Q~").append(b[0]).append("~").append(b[1]).append("~").append(p2.x).append("~").append(p2.y)
            }
            sk.lineTo(pts.last()[0], pts.last()[1]); verbs.append(";L~").append(pts.last()[0]).append("~").append(pts.last()[1])
            val m = org.jetbrains.skia.PathMeasure(sk.snapshot(), false, 1f)
            val len = m.length
            val samples = StringBuilder()
            for (k in 0..48) {
                val d = when {
                    k <= 40 -> len * k / 40f
                    k == 41 -> -5f
                    k == 42 -> len + 5f
                    else -> rnd.nextFloat() * len
                }
                val p = m.getPosition(d)!!
                val t = m.getTangent(d)!!
                if (k > 0) samples.append(';')
                samples.append('~').append(d).append(":~").append(p.x).append(":~").append(p.y).append(":~").append(t.x).append(":~").append(t.y)
            }
            cases += "$verbs|~$len|$samples"
        }
        File(dir, "pathmeasure.json").writeText(jsonLines("paths", cases))
        println("golden: ${cases.size} skia path measures")
    }

    // ------------------------------------------------------------------------------- traces

    private object FakeImage : ImageBitmap {
        override val width = 1
        override val height = 1
        override val colorSpace: ColorSpace = ColorSpaces.Srgb
        override val hasAlpha = true
        override val config = ImageBitmapConfig.Argb8888
        override fun prepareToDraw() {}
        override fun readPixels(buffer: IntArray, startX: Int, startY: Int, width: Int, height: Int, bufferOffset: Int, stride: Int) {}
    }

    private fun field(name: String) = GameEngine::class.java.getDeclaredField(name).apply { isAccessible = true }

    /** GameEngine.setSize without SceneArt.render and the sprite pre-builds (they need Android bitmaps). */
    @Suppress("UNCHECKED_CAST")
    private fun headlessSetSize(e: GameEngine, width: Float, height: Float, topInset: Float, bottomInset: Float) {
        val layout = GameLayout(width, height, topInset, bottomInset, e.level)
        field("layout").set(e, layout)
        field("art").set(e, VehicleArt(layout.unit, Skin.CLASSIC))
        field("particles").set(e, Particles(layout.u))
        (field("scene\$delegate").get(e) as MutableState<ImageBitmap?>).value = FakeImage
        field("qS").set(e, FloatArray(e.queue.size) { i -> i * layout.passengerSpacing + layout.width * 0.6f })
        val rnd = field("rnd").get(e) as Random
        val vehicles = e.vehicles
        vehicles.forEachIndexed { i, v ->
            v.home = layout.boardToScreen(v.spec.centerX, v.spec.centerY)
            if (v.state == VState.LOT) {
                v.pos = v.home
                v.heading = layout.rotationDeg + v.spec.dir.degrees
            }
            v.popDelay = 0.15f + i * min(0.018f, 0.7f / vehicles.size) + rnd.nextFloat() * 0.05f
        }
    }

    private class Run(val n: Int, val w: Float, val h: Float, val top: Float, val bottom: Float)

    @Test
    fun dumpTraces() {
        val runs = listOf(1, 2, 3, 5, 6, 10, 12, 26, 40, 77, 150, 333, 1000, 2500, 4999).map { Run(it, 1080f, 2400f, 98f, 0f) } +
            listOf(Run(1, 393f, 852f, 59f, 34f), Run(77, 393f, 852f, 59f, 34f), Run(203, 390f, 844f, 47f, 34f))
        val sb = StringBuilder("{\"traces\":[\n")
        var total = 0
        runs.forEachIndexed { ri, r ->
            val lines = trace(r)
            total += lines.size
            sb.append("{\"n\":").append(r.n).append(",\"w\":").append(r.w).append(",\"h\":").append(r.h)
                .append(",\"top\":").append(r.top).append(",\"bottom\":").append(r.bottom).append(",\"lines\":[\n")
            lines.forEachIndexed { j, l -> sb.append('"').append(l).append('"').append(if (j < lines.size - 1) ",\n" else "\n") }
            sb.append("]}").append(if (ri < runs.size - 1) ",\n" else "\n")
            println("trace ${r.n} ${r.w}x${r.h}: ${lines.size} lines, ${lines.last()}")
        }
        sb.append("]}\n")
        File(dir, "traces.json").writeText(sb.toString())
        println("golden: ${runs.size} traces, $total lines")
    }

    private fun f(x: Float) = "~$x"

    private fun trace(r: Run): List<String> {
        val level = LevelGenerator.generate(r.n)
        val out = ArrayList<String>()
        var frame = 0
        val fx = object : GameFx {
            override fun sfx(s: Sfx, rate: Float) { out += "S|$frame|${s.name}|${f(rate)}" }
            override fun haptic(h: Haptic) { out += "H|$frame|${h.name}" }
        }
        val e = GameEngine(level, Themes.forLevel(r.n), Skin.CLASSIC, fx)
        e.onEvent = { ev ->
            out += "E|$frame|" + when (ev) {
                is GameEvent.Won -> "Won:${ev.stars}"
                GameEvent.Stuck -> "Stuck"
                is GameEvent.LockedSlot -> "LockedSlot:${ev.index}"
                GameEvent.NoSpace -> "NoSpace"
                GameEvent.VipBusy -> "VipBusy"
            }
        }
        headlessSetSize(e, r.w, r.h, r.top, r.bottom)
        val lay = e.layout
        out += buildString {
            append("L|").append(f(lay.u)).append('|').append(f(lay.unit)).append('|').append(f(lay.slotUnit)).append('|')
            append(f(lay.cosR)).append('|').append(f(lay.sinR)).append('|').append(f(lay.boardCenter.x)).append('|').append(f(lay.boardCenter.y)).append('|')
            append(f(lay.track.left)).append('|').append(f(lay.track.top)).append('|').append(f(lay.track.right)).append('|').append(f(lay.track.bottom)).append('|')
            append(f(lay.roadY)).append('|').append(f(lay.queueVisibleLength)).append('|').append(f(lay.queueSign.x)).append('|').append(f(lay.queueSign.y))
            for (i in 0..SLOT_COUNT) {
                val s = lay.slotRect(i)
                append('|').append(f(s.left)).append(':').append(f(s.top)).append(':').append(f(s.right)).append(':').append(f(s.bottom))
            }
            for (v in e.vehicles) append('|').append(f(v.home.x)).append(':').append(f(v.home.y)).append(':').append(f(v.heading)).append(':').append(f(v.popDelay))
        }

        val dts = floatArrayOf(1 / 60f, 1 / 60f, 1 / 120f, 1 / 60f, 0.05f, 1 / 60f, 1 / 90f)
        var actions = 0
        var stuckCount = 0

        fun tapAt(p: Offset) {
            out += "T|$frame|${f(p.x)}|${f(p.y)}"
            e.onTap(p)
        }

        fun act() {
            actions++
            when (actions) {
                3 -> { tapAt(e.slotCenter(5)); if (!e.slots[5].open) e.unlockSlot(5); return }
                7 -> if (level.number % 3 == 0) { out += "B|$frame|shuffle"; e.shuffle(); return }
                9 -> if (level.number % 2 == 0) {
                    val ok = e.armCrane()
                    out += "B|$frame|crane:$ok"
                    if (ok) {
                        val lotNow = e.vehicles.filter { it.state == VState.LOT }
                        val target = lotNow.firstOrNull { !e.grid.isFree(it.spec) } ?: lotNow.firstOrNull()
                        if (target != null) tapAt(target.home)
                    }
                    return
                }
                12 -> if (level.number % 4 == 1) { out += "B|$frame|sort"; e.useSort(); return }
            }
            val lot = e.vehicles.filter { it.state == VState.LOT }
            if (lot.isEmpty() || actions % 13 == 6) { tapAt(Offset(lay.width * 0.5f, lay.height - 2f)); return }
            val front = if (e.qHead < e.queue.size) e.queue[e.qHead] else -1
            val free = lot.filter { e.grid.isFree(it.spec) }
            val blocked = lot.filter { !e.grid.isFree(it.spec) && it.bumpT < 0f }
            if (actions % 5 == 2 && blocked.isNotEmpty()) { tapAt(blocked[actions % blocked.size].home); return }
            val pick = free.firstOrNull { it.color == front } ?: free.minByOrNull { v ->
                var i = e.qHead
                while (i < e.queue.size && e.queue[i] != v.color) i++
                i
            }
            if (pick != null) tapAt(pick.home)
        }

        while (frame < 20000) {
            e.update(dts[frame % dts.size])
            frame++
            if (frame % 8 == 0) out += snapshot(e, frame)
            if (e.phase == Phase.WON) break
            if (e.phase == Phase.STUCK) {
                stuckCount++
                out += "B|$frame|stuck:$stuckCount"
                when (stuckCount) {
                    1, 3, 4 -> e.revive()
                    2 -> e.useSort()
                    else -> break
                }
                continue
            }
            if (e.phase != Phase.PLAYING || frame % 10 != 5) continue
            act()
        }
        out += snapshot(e, frame)
        out += "END|$frame|${e.phase}|${e.boostersUsed}|${e.revivesUsed}|${e.remaining}|${e.qHead}"
        return out
    }

    private fun snapshot(e: GameEngine, frame: Int): String = buildString {
        append("F|").append(frame).append('|').append(e.phase).append('|').append(e.remaining).append('|').append(e.qHead)
        append('|').append(e.walkers.size).append('|').append(e.particles.list.size).append('|').append(e.craneArmed)
        append('|').append(f(e.screenShake.x)).append('|').append(f(e.screenShake.y))
        append('|').append(f(if (e.qHead < e.queue.size) e.qS[e.qHead] else -1f))
        append('|').append(e.queue.size).append(':').append(e.queue.sum()).append(':').append(e.queue.drop(e.qHead).take(12).joinToString(""))
        append('|').append(e.slots.joinToString(",") { s -> if (!s.open) "x" else s.vehicle?.id?.toString() ?: "." })
        for (w in e.walkers) {
            val p = e.walkerPos(w)
            append("|w:").append(w.color).append(':').append(w.vehicle.id).append(':').append(f(w.t)).append(':').append(f(p.x)).append(':').append(f(p.y))
        }
        for (v in e.vehicles) {
            val moving = v.state != VState.LOT && v.state != VState.GONE
            val interesting = moving || v.bumpT >= 0f || v.shakeT >= 0f || v.flipT >= 0f || (v.popT < 1f && frame == 32)
            if (!interesting) continue
            if (v.state == VState.PARKED && v.bounceT < 0f && v.shakeT < 0f && v.flipT < 0f) {
                append("|p").append(v.id).append(':').append(v.slot).append(':').append(v.filled).append(':').append(v.reserved).append(':')
                    .append(v.color).append(':').append(v.parkedOrder).append(':').append(f(v.departDelay))
                continue
            }
            append("|v").append(v.id).append(':').append(v.state).append(':').append(v.slot).append(':').append(v.filled).append(':')
                .append(v.reserved).append(':').append(v.color).append(':').append(v.mystery).append(':').append(v.parkedOrder).append(':').append(v.departPhase)
            append(':').append(f(v.pos.x)).append(':').append(f(v.pos.y)).append(':').append(f(v.heading)).append(':').append(f(v.scale)).append(':').append(f(v.lift))
            append(':').append(f(v.bumpT)).append(':').append(f(v.shakeT)).append(':').append(f(v.flipT)).append(':').append(f(v.popT)).append(':').append(f(v.bounceT))
            append(':').append(f(v.departDelay)).append(':').append(f(v.t))
            if (v.state == VState.EXITING) append(':').append(f(v.pathLen)).append(':').append(f(v.duration))
        }
        if (e.level.number == 1) {
            append("|tut:").append(e.tutorialText ?: "-").append(':').append(f(e.tutorialPoint?.x ?: -1f)).append(':').append(f(e.tutorialPoint?.y ?: -1f))
        }
        if (e.slots[VIP_SLOT].vehicle != null) append("|vip:").append(e.slots[VIP_SLOT].vehicle!!.id)
    }

    private fun jsonLines(key: String, lines: List<String>) = buildString {
        append("{\"").append(key).append("\":[\n")
        lines.forEachIndexed { i, l -> append('"').append(l).append('"').append(if (i < lines.size - 1) ",\n" else "\n") }
        append("]}\n")
    }
}
