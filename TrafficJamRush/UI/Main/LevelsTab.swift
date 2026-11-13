import SwiftUI
import GameKit

private let ROW_DP: CGFloat = 92
private let HEADER_DP: CGFloat = 150
private let ITEMS_PER_COLLECTION = LEVELS_PER_COLLECTION + 1
/// Height of one collection block: its world header plus 100 level rows.
private let BLOCK_DP: CGFloat = HEADER_DP + CGFloat(LEVELS_PER_COLLECTION) * ROW_DP

private func nodeX(_ level: Int) -> Float { 0.5 + 0.27 * Kt.sin(Float(level) * 0.8) }

private func indexOfLevel(_ level: Int) -> Int {
    let c = collectionOf(level)
    return (c - 1) * ITEMS_PER_COLLECTION + 1 + (level - 1) % LEVELS_PER_COLLECTION
}

/// Top of LazyColumn item `k` (headers are 150 pt, level rows 92 pt).
private func itemTop(_ k: Int) -> CGFloat {
    let c0 = k / ITEMS_PER_COLLECTION
    let j = k % ITEMS_PER_COLLECTION
    return CGFloat(c0) * BLOCK_DP + (j == 0 ? 0 : HEADER_DP + CGFloat(j - 1) * ROW_DP)
}

private func itemHeight(_ k: Int) -> CGFloat { k % ITEMS_PER_COLLECTION == 0 ? HEADER_DP : ROW_DP }

/// LazyColumn item index at content offset `y`.
private func itemAt(_ y: CGFloat) -> Int {
    let maxIndex = TOTAL_COLLECTIONS * ITEMS_PER_COLLECTION - 1
    guard y > 0 else { return 0 }
    let c0 = Int(y / BLOCK_DP)
    let r = y - CGFloat(c0) * BLOCK_DP
    let j = r < HEADER_DP ? 0 : 1 + Int((r - HEADER_DP) / ROW_DP)
    return min(maxIndex, c0 * ITEMS_PER_COLLECTION + min(j, LEVELS_PER_COLLECTION))
}

private let TOTAL_MAP_HEIGHT = CGFloat(TOTAL_COLLECTIONS) * BLOCK_DP

struct LevelsTab: View {
    let player: PlayerState
    let scrollToCollection: Int
    let onScrolled: () -> Void
    let onLevel: (Int) -> Void

    var body: some View {
        let starsTotal = player.stars.reduce(0) { $0 + Int($1) }
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                OText("Level Map", .Title, size: 28, outline: Color(argb: 0xFF0D2C6B), strokeWidth: 7)
                HStack(spacing: 0) {
                    GameIcon(Icon.STAR, 18)
                    GText(" \(starsTotal) stars  ·  \(player.completedCount) / 5000 cleared", .Small, color: .white, size: 13)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [Color(argb: 0xFF1C5BD0), Color(argb: 0xFF2F7CF6)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            )
            LevelMap(player: player, scrollToCollection: scrollToCollection, onScrolled: onScrolled, onLevel: onLevel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }
}

/// The 5,050-item map (50 world headers + 5,000 level rows). Only the rows on screen exist as views:
/// row heights are fixed, so positions are computed directly and scrolling stays smooth at 120 Hz.
private struct LevelMap: View {
    let player: PlayerState
    let scrollToCollection: Int
    let onScrolled: () -> Void
    let onLevel: (Int) -> Void

    var body: some View {
        if #available(iOS 18.0, *) {
            LevelMapScroll(player: player, scrollToCollection: scrollToCollection, onScrolled: onScrolled, onLevel: onLevel)
        } else {
            LevelMapLegacy(player: player, scrollToCollection: scrollToCollection, onScrolled: onScrolled, onLevel: onLevel)
        }
    }
}

/// Window of item indices on screen (plus one item of overscan each side).
private func visibleWindow(_ top: CGFloat, _ height: CGFloat) -> ClosedRange<Int> {
    let f = max(0, itemAt(top) - 1)
    let l = min(TOTAL_COLLECTIONS * ITEMS_PER_COLLECTION - 1, max(f, itemAt(top + height) + 1))
    return f...l
}

/// First item shown when the map opens (`LazyColumn(initialFirstVisibleItemIndex = current - 3)`).
private func startIndexFor(_ player: PlayerState) -> Int { max(0, indexOfLevel(player.nextLevel) - 3) }

/// The rows of the window, each at its absolute content position (render offset; no layout cost).
private struct MapRows: View {
    let player: PlayerState
    let window: ClosedRange<Int>
    let width: CGFloat
    let onLevel: (Int) -> Void

    var body: some View {
        let current = player.nextLevel
        ForEach(window, id: \.self) { k in
            item(k, current)
                .frame(width: width, height: itemHeight(k))
                .offset(y: itemTop(k))
        }
    }

    @ViewBuilder
    private func item(_ k: Int, _ current: Int) -> some View {
        let c = k / ITEMS_PER_COLLECTION + 1
        let j = k % ITEMS_PER_COLLECTION
        if j == 0 {
            let unlocked = player.isCollectionUnlocked(c)
            WorldHeader(c: c, unlocked: unlocked,
                        completed: unlocked ? player.completedIn(c) : 0,
                        stars: unlocked ? player.starsIn(c) : 0)
                .equatable()
        } else {
            let level = (c - 1) * LEVELS_PER_COLLECTION + j
            LevelRow(level: level, width: width, unlocked: player.isLevelUnlocked(level), stars: player.starsOf(level),
                     isCurrent: level == current, onLevel: onLevel)
                .equatable()
        }
    }
}

private let mapGlide = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)

/// iOS 18+: `ScrollPosition` + `onScrollGeometryChange`.
@available(iOS 18.0, *)
private struct LevelMapScroll: View {
    let player: PlayerState
    let scrollToCollection: Int
    let onScrolled: () -> Void
    let onLevel: (Int) -> Void

    @State private var pos: ScrollPosition
    @State private var window: ClosedRange<Int>
    @State private var viewport: CGFloat = 700
    private let startY: CGFloat

    init(player: PlayerState, scrollToCollection: Int, onScrolled: @escaping () -> Void, onLevel: @escaping (Int) -> Void) {
        self.player = player
        self.scrollToCollection = scrollToCollection
        self.onScrolled = onScrolled
        self.onLevel = onLevel
        let start = startIndexFor(player)
        startY = itemTop(start)
        _pos = State(initialValue: ScrollPosition(y: itemTop(start)))
        _window = State(initialValue: visibleWindow(itemTop(start), 1000))
    }

    var body: some View {
        GeometryReader { outer in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    MapRows(player: player, window: window, width: outer.size.width, onLevel: onLevel)
                }
                .frame(width: outer.size.width, height: TOTAL_MAP_HEIGHT, alignment: .topLeading)
            }
            .scrollPosition($pos)
            .onScrollGeometryChange(for: CGRect.self, of: { $0.visibleRect }) { _, r in
                if viewport != r.height { viewport = r.height }
                let w = visibleWindow(r.minY, r.height)
                if w != window { window = w }
            }
            .onAppear {
                // LazyColumn(initialFirstVisibleItemIndex = current - 3).
                viewport = outer.size.height
                pos.scrollTo(y: startY)
                if scrollToCollection > 0 { scroll(to: scrollToCollection) }
            }
            .onChange(of: scrollToCollection) { _, c in
                if c > 0 { scroll(to: c) }
            }
        }
    }

    /// `animateScrollToItem(header of c)`: far targets first jump close (like Compose), then glide in.
    private func scroll(to c: Int) {
        let target = itemTop((c - 1) * ITEMS_PER_COLLECTION)
        let currentY = itemTop(window.lowerBound)
        let span = max(viewport, 400) * 2
        if abs(target - currentY) > span {
            pos.scrollTo(y: max(0, target + (target > currentY ? -span / 2 : span / 2)))
            DispatchQueue.main.async {
                withAnimation(mapGlide) { pos.scrollTo(y: target) }
                onScrolled()
            }
        } else {
            withAnimation(mapGlide) { pos.scrollTo(y: target) }
            onScrolled()
        }
    }
}

private struct MapOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// iOS 17 fallback: offset from a geometry preference and `ScrollViewReader` anchors laid out with padding.
private struct LevelMapLegacy: View {
    let player: PlayerState
    let scrollToCollection: Int
    let onScrolled: () -> Void
    let onLevel: (Int) -> Void

    @State private var window: ClosedRange<Int>
    @State private var positioned = false
    @State private var jumpY: CGFloat = 0
    @State private var viewport: CGFloat = 700
    private let startIndex: Int

    init(player: PlayerState, scrollToCollection: Int, onScrolled: @escaping () -> Void, onLevel: @escaping (Int) -> Void) {
        self.player = player
        self.scrollToCollection = scrollToCollection
        self.onScrolled = onScrolled
        self.onLevel = onLevel
        let start = startIndexFor(player)
        startIndex = start
        _window = State(initialValue: visibleWindow(itemTop(start), 1000))
    }

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        GeometryReader { g in
                            Color.clear.preference(key: MapOffsetKey.self, value: -g.frame(in: .named("levelMap")).minY)
                        }
                        // Scroll anchors (laid out, never drawn).
                        anchor("start", itemTop(startIndex))
                        anchor("jump", jumpY)
                        ForEach(1...TOTAL_COLLECTIONS, id: \.self) { c in
                            anchor("h\(c)", itemTop((c - 1) * ITEMS_PER_COLLECTION))
                        }
                        MapRows(player: player, window: window, width: outer.size.width, onLevel: onLevel)
                    }
                    .frame(width: outer.size.width, height: TOTAL_MAP_HEIGHT, alignment: .topLeading)
                }
                .coordinateSpace(name: "levelMap")
                .onPreferenceChange(MapOffsetKey.self) { y in
                    let w = visibleWindow(y, outer.size.height)
                    if w != window { window = w }
                }
                .opacity(positioned ? 1 : 0)
                .onAppear {
                    // LazyColumn(initialFirstVisibleItemIndex = current - 3): start there without a visible jump.
                    viewport = outer.size.height
                    proxy.scrollTo("start", anchor: .top)
                    DispatchQueue.main.async {
                        proxy.scrollTo("start", anchor: .top)
                        positioned = true
                        if scrollToCollection > 0 { scroll(proxy, to: scrollToCollection) }
                    }
                }
                .onChange(of: scrollToCollection) { _, c in
                    if c > 0 { scroll(proxy, to: c) }
                }
            }
        }
    }

    private func anchor(_ id: String, _ y: CGFloat) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .id(id)
            .padding(.top, y)
            .allowsHitTesting(false)
    }

    private func scroll(_ proxy: ScrollViewProxy, to c: Int) {
        let target = itemTop((c - 1) * ITEMS_PER_COLLECTION)
        let currentY = itemTop(window.lowerBound)
        let span = max(viewport, 400) * 2
        if abs(target - currentY) > span {
            jumpY = max(0, target + (target > currentY ? -span / 2 : span / 2))
            DispatchQueue.main.async {
                proxy.scrollTo("jump", anchor: .top)
                DispatchQueue.main.async {
                    withAnimation(mapGlide) { proxy.scrollTo("h\(c)", anchor: .top) }
                    onScrolled()
                }
            }
        } else {
            withAnimation(mapGlide) { proxy.scrollTo("h\(c)", anchor: .top) }
            onScrolled()
        }
    }
}

private struct WorldHeader: View, Equatable {
    let c: Int
    let unlocked: Bool
    let completed: Int
    let stars: Int

    var body: some View {
        let theme = Themes.forCollection(c)
        ZStack {
            WorldArt(theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    GText("WORLD \(c)", .Small, color: Color(argb: 0xFFFFE082), size: 13, titleFont: true)
                    OText(Themes.collectionName(c), .Title, size: 22, strokeWidth: 6)
                    if unlocked {
                        GText("\(completed) / \(LEVELS_PER_COLLECTION)  ·  ★ \(stars)", .Small, color: .white, size: 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(Color(argb: 0xCC0D2C6B), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.7), lineWidth: 2))
                if !unlocked {
                    HStack(spacing: 0) {
                        GameIcon(Icon.LOCK, 18)
                        GText(" Locked", .Small, color: .white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color(argb: 0xCC000000), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: HEADER_DP)
        .background(theme.pal.platform.shade(0.9).color)
    }
}

private struct LevelRow: View, Equatable {
    let level: Int
    let width: CGFloat
    let unlocked: Bool
    let stars: Int
    let isCurrent: Bool
    let onLevel: (Int) -> Void

    static func == (a: LevelRow, b: LevelRow) -> Bool {
        a.level == b.level && a.width == b.width && a.unlocked == b.unlocked && a.stars == b.stars && a.isCurrent == b.isCurrent
    }

    var body: some View {
        let theme = Themes.forLevel(level)
        let idxInWorld = (level - 1) % LEVELS_PER_COLLECTION
        let prevX: Float = idxInWorld == 0 ? 0.5 : nodeX(level - 1)
        let x = nodeX(level)
        let nextX: Float = idxInWorld == LEVELS_PER_COLLECTION - 1 ? 0.5 : nodeX(level + 1)
        let w = width
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                LevelRow.drawRow(&ctx, size, level: level, theme: theme, prevX: prevX, x: x, nextX: nextX)
            }
            .frame(width: w, height: ROW_DP)
            LevelNode(level: level, unlocked: unlocked, stars: stars, isCurrent: isCurrent, onLevel: onLevel)
                .offset(x: w * CGFloat(x) - 39, y: 7)
            if isCurrent {
                Mascot(56)
                    .offset(x: min(w * CGFloat(x) + 30, w - 58), y: 18)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: ROW_DP, alignment: .topLeading)
    }

    static func drawRow(_ ctx: inout GraphicsContext, _ size: CGSize, level: Int, theme: SceneTheme,
                        prevX: Float, x: Float, nextX: Float) {
        let ground = theme.pal.outside
        let w = size.width
        let h = size.height
        let edge = ground.shade(0.9).color
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [edge, ground.color, edge]),
            startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
        let rnd = KotlinRandom(intSeed: level * 7919)
        let light = ground.tint(0.12).color
        let dark = ground.shade(0.88).color
        for _ in 0..<14 {
            let c = rnd.nextBoolean() ? light : dark
            let px = CGFloat(rnd.nextFloat()) * w
            let py = CGFloat(rnd.nextFloat()) * h
            var blade = Path()
            blade.move(to: CGPoint(x: px, y: py))
            blade.addLine(to: CGPoint(x: px + 0.75, y: py - 4))
            ctx.stroke(blade, with: .color(c), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        // Scenery on the side away from the road
        let side: Float = x > 0.5 ? 0.16 : 0.84
        let jitter = (rnd.nextFloat() - 0.5) * 0.12
        mapProp(&ctx, theme, CGPoint(x: w * CGFloat(side + jitter), y: h * 0.62), level)
        if rnd.nextFloat() < 0.5 {
            let fx = w * CGFloat(side < 0.5 ? 0.04 + rnd.nextFloat() * 0.06 : 0.9 + rnd.nextFloat() * 0.06)
            let flower = [Color.white, Color(argb: 0xFFFFEB3B), Color(argb: 0xFFFF80AB)][level % 3]
            ctx.fill(circle(CGPoint(x: fx, y: h * 0.3), 2.5), with: .color(flower))
        }
        let top = CGPoint(x: CGFloat((prevX + x) / 2) * w, y: 0)
        let mid = CGPoint(x: CGFloat(x) * w, y: h / 2)
        let bot = CGPoint(x: CGFloat((x + nextX) / 2) * w, y: h)
        let k = h * 0.28
        var road = Path()
        road.move(to: top)
        road.addCurve(to: mid, control1: CGPoint(x: top.x, y: top.y + k), control2: CGPoint(x: mid.x, y: mid.y - k))
        road.addCurve(to: bot, control1: CGPoint(x: mid.x, y: mid.y + k), control2: CGPoint(x: bot.x, y: bot.y - k))
        ctx.stroke(road, with: .color(Color.black.opacity(0.15)), style: StrokeStyle(lineWidth: 44, lineCap: .butt))
        ctx.stroke(road, with: .color(Color(argb: 0xFFE6E9EC)), style: StrokeStyle(lineWidth: 40, lineCap: .butt))
        ctx.stroke(road, with: .color(theme.road), style: StrokeStyle(lineWidth: 33, lineCap: .butt))
        ctx.stroke(road, with: .color(Color.white.opacity(0.75)), style: StrokeStyle(lineWidth: 3, dash: [10, 9]))
    }
}

/// Press-down scale without spring (Compose `scale(if (pressed) s else 1f)`).
struct InstantPressStyle: ButtonStyle {
    var scale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? scale : 1)
    }
}

private struct LevelNode: View {
    let level: Int
    let unlocked: Bool
    let stars: Int
    let isCurrent: Bool
    let onLevel: (Int) -> Void

    var body: some View {
        let base = ArtColor(isCurrent ? 0xFFFF9800 : stars > 0 ? 0xFF5FC12F : unlocked ? 0xFF2F8CF6 : 0xFF9AA3AE)
        Button {
            App.container.audio.play(Sfx.Click)
            onLevel(level)
        } label: {
            ZStack {
                Canvas { ctx, size in
                    LevelNode.drawDisc(&ctx, size, base: base, isCurrent: isCurrent)
                }
                .frame(width: 78, height: 78)
                if unlocked {
                    OText("\(level)", .Title, size: level >= 1000 ? 17 : 22, outline: base.shade(0.4).color, strokeWidth: 6)
                } else {
                    VStack(spacing: 0) {
                        GameIcon(Icon.LOCK, 26)
                        GText("\(level)", .Small, color: .white, size: 11, titleFont: true)
                    }
                }
                if stars > 0 {
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { i in GameIcon(i < stars ? Icon.STAR : Icon.STAR_EMPTY, 18) }
                    }
                    .offset(y: 6)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                if unlocked && stars == 0 && !isCurrent {
                    GameIcon(Icon.PLAY, 12)
                        .frame(width: 22, height: 22)
                        .background(Color(argb: 0xFFFFC107), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: 78, height: 78)
            .contentShape(Circle())
        }
        .buttonStyle(InstantPressStyle(scale: 0.9))
        .repeatingScale(1, 1.1, ms: 600, active: isCurrent)
    }

    static func drawDisc(_ ctx: inout GraphicsContext, _ size: CGSize, base: ArtColor, isCurrent: Bool) {
        // The 62 pt disc centred in the 78 pt node.
        let o = (size.width - 62) / 2
        let r: CGFloat = 31
        let c = CGPoint(x: o + r, y: o + r)
        ctx.fill(circle(CGPoint(x: c.x, y: c.y + 5), r), with: .color(Color.black.opacity(0.3)))
        ctx.fill(circle(c, r), with: .color(.white))
        ctx.fill(circle(c, r - 4), with: .linearGradient(
            Gradient(colors: [base.tint(0.35).color, base.color, base.shade(0.8).color]),
            startPoint: CGPoint(x: 0, y: o), endPoint: CGPoint(x: 0, y: o + 62)))
        ctx.fill(Path(ellipseIn: CGRect(x: o + r * 0.45, y: o + r * 0.2, width: r * 1.1, height: r * 0.5)),
                 with: .color(Color.white.opacity(0.4)))
        if isCurrent {
            ctx.stroke(circle(c, r + 4), with: .color(Color(argb: 0xFFFFF59D)), lineWidth: 3)
        }
    }
}

@inline(__always) private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

/// A small piece of world-appropriate scenery beside the map road.
private func mapProp(_ ctx: inout GraphicsContext, _ theme: SceneTheme, _ c: CGPoint, _ seed: Int) {
    let u: CGFloat = 1
    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 14 * u, y: c.y + 8 * u, width: 28 * u, height: 7 * u)), with: .color(Color.black.opacity(0.15)))
    func tri(_ a: CGPoint, _ b: CGPoint, _ d: CGPoint) -> Path {
        var p = Path()
        p.move(to: a); p.addLine(to: b); p.addLine(to: d); p.closeSubpath()
        return p
    }
    func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }
    switch theme.backdrop {
    case .SNOW:
        for k in 0..<3 {
            let y0 = c.y + 6 * u - CGFloat(k) * 10 * u
            let wdt = CGFloat(26 - k * 6) * u
            ctx.fill(tri(CGPoint(x: c.x, y: y0 - 16 * u), CGPoint(x: c.x + wdt / 2, y: y0), CGPoint(x: c.x - wdt / 2, y: y0)),
                     with: .color(Color(argb: 0xFF2E7D32)))
            ctx.fill(tri(CGPoint(x: c.x, y: y0 - 16 * u), CGPoint(x: c.x + wdt / 4, y: y0 - 8 * u), CGPoint(x: c.x - wdt / 4, y: y0 - 8 * u)),
                     with: .color(.white))
        }
    case .DESERT:
        let g = Color(argb: 0xFF558B2F)
        ctx.fill(rrect(c.x - 5 * u, c.y - 26 * u, 10 * u, 34 * u, 5 * u), with: .color(g))
        ctx.fill(rrect(c.x - 15 * u, c.y - 16 * u, 8 * u, 14 * u, 4 * u), with: .color(g))
        ctx.fill(rrect(c.x + 7 * u, c.y - 20 * u, 8 * u, 14 * u, 4 * u), with: .color(g))
    case .SPACE:
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 16 * u, y: c.y - 4 * u, width: 32 * u, height: 12 * u)), with: .color(Color(argb: 0xFF2F3656)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 12 * u, y: c.y - 2 * u, width: 24 * u, height: 7 * u)), with: .color(Color(argb: 0xFF1B2140)))
        ctx.fill(circle(CGPoint(x: c.x + 10 * u, y: c.y - 18 * u), 2 * u), with: .color(Color(argb: 0xFF00E5FF).opacity(0.7)))
    case .NEON:
        ctx.fill(Path(CGRect(x: c.x - 1.5 * u, y: c.y - 30 * u, width: 3 * u, height: 36 * u)), with: .color(Color(argb: 0xFF37474F)))
        let lamp = CGPoint(x: c.x, y: c.y - 32 * u)
        ctx.fill(circle(lamp, 18 * u), with: .radialGradient(
            Gradient(colors: [Color(argb: 0x88E040FB), .clear]), center: lamp, startRadius: 0, endRadius: 18 * u))
        ctx.fill(circle(lamp, 4 * u), with: .color(Color(argb: 0xFFF8BBFF)))
    case .FAIR:
        let cols = [Color(argb: 0xFFFF4081), Color(argb: 0xFFFFEB3B), Color(argb: 0xFF29B6F6)]
        for k in 0..<3 {
            let b = CGPoint(x: c.x + CGFloat(k - 1) * 9 * u, y: c.y - CGFloat(24 + (k % 2) * 6) * u)
            var string = Path()
            string.move(to: b)
            string.addLine(to: CGPoint(x: c.x, y: c.y + 4 * u))
            ctx.stroke(string, with: .color(Color.white.opacity(0.7)), lineWidth: 0.8 * u)
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - 6 * u, y: b.y - 8 * u, width: 12 * u, height: 15 * u)), with: .color(cols[(seed + k) % 3]))
        }
    case .PIER:
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 18 * u, y: c.y - 6 * u, width: 36 * u, height: 14 * u)), with: .color(Color(argb: 0xFF29B6F6)))
        var hull = Path()
        hull.move(to: CGPoint(x: c.x - 8 * u, y: c.y - 4 * u))
        hull.addLine(to: CGPoint(x: c.x + 8 * u, y: c.y - 4 * u))
        hull.addLine(to: CGPoint(x: c.x + 5 * u, y: c.y + 1 * u))
        hull.addLine(to: CGPoint(x: c.x - 5 * u, y: c.y + 1 * u))
        hull.closeSubpath()
        ctx.fill(hull, with: .color(Color(argb: 0xFFFF7043)))
        ctx.fill(tri(CGPoint(x: c.x, y: c.y - 20 * u), CGPoint(x: c.x + 7 * u, y: c.y - 5 * u), CGPoint(x: c.x, y: c.y - 5 * u)), with: .color(.white))
    default:
        let leaf: ArtColor
        switch theme.backdrop {
        case .FARM: leaf = ArtColor(0xFFFF8F00)
        case .JUNGLE: leaf = ArtColor(0xFF2E7D32)
        default: leaf = ArtColor(0xFF43A047)
        }
        ctx.fill(rrect(c.x - 3 * u, c.y - 8 * u, 6 * u, 16 * u, 2 * u), with: .color(Color(argb: 0xFF6D4C41)))
        ctx.fill(circle(CGPoint(x: c.x + 2 * u, y: c.y - 16 * u), 15 * u), with: .color(leaf.shade(0.78).color))
        ctx.fill(circle(CGPoint(x: c.x - 3 * u, y: c.y - 20 * u), 12 * u), with: .color(leaf.color))
        ctx.fill(circle(CGPoint(x: c.x - 7 * u, y: c.y - 25 * u), 4 * u), with: .color(leaf.tint(0.3).color))
    }
}
