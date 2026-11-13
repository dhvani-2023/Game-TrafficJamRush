import SwiftUI
import GameKit

/// Animated splash: the logo drops in, traffic drives past and a loading bar fills for ~2.3 s.
struct SplashScreen: View {
    let onDone: (_ onboardingDone: Bool) -> Void

    @State private var logoIn: CGFloat = 0
    @State private var clock = LoopClock()

    var body: some View {
        SkyBackground {
            SunRays()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -120)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                GameLogo(scale: 1.1)
                    // graphicsLayer { translationY = (1 - v) * -600px; rotationZ = (1 - v) * -12 }
                    .rotationEffect(.degrees(Double(1 - logoIn) * -12))
                    .offset(y: (1 - logoIn) * -300)
                Spacer(minLength: 0)
            }
            .padding(.top, 70)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Road with traffic
            SplashRoad(clock: clock)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)

            // Loading bar
            SplashLoading(clock: clock)
                .padding(.bottom, 22)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .task {
            // Build every menu sprite (splash, home, onboarding, garage cards) in the background while the splash
            // plays, so no screen pays for sprite rendering on its first frame.
            MenuArt.prewarm()
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            App.container.audio.play(Sfx.Whoosh)
            withAnimation(.compose(dampingRatio: 0.45, stiffness: 220)) { logoIn = 1 }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            let progress = App.container.progress
            while !Task.isCancelled && !progress.now.loaded {
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            onDone(progress.now.onboardingDone)
        }
    }
}

/// Grass, a two-lane road with a scrolling centre line, a bus and a car driving past, and Coney.
private struct SplashRoad: View {
    let clock: LoopClock

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            TimelineView(.animation) { tl in
                let t = clock.elapsed(tl.date)
                let dash = CGFloat(infiniteFloat(t, 0, 1, ms: 500, linear: true))
                let x1 = CGFloat(infiniteFloat(t, -0.3, 1.3, ms: 2600, linear: true))
                let x2 = CGFloat(infiniteFloat(t, 1.3, -0.3, ms: 3400, linear: true))
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        SplashRoad.drawRoad(&ctx, size, dash)
                    }
                    VehicleSprite(VehicleType.BUS, JamColor.YELLOW.ordinal, Skin.CLASSIC, 13, rotation: -90)
                        .offset(x: x2 * w, y: 38)
                    VehicleSprite(VehicleType.CAR, JamColor.RED.ordinal, Skin.CLASSIC, 13, rotation: 90)
                        .offset(x: x1 * w, y: 100)
                }
            }
            Mascot(110)
                .offset(x: w - 110 - 14, y: -86)
        }
    }

    static func drawRoad(_ ctx: inout GraphicsContext, _ size: CGSize, _ dash: CGFloat) {
        let w = size.width
        // Compose brushes without explicit bounds span the whole canvas.
        let grassTop = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color(argb: 0xFF8BC34A), Color(argb: 0xFF558B2F)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: 50)), with: grassTop)
        let top: CGFloat = 40
        ctx.fill(Path(CGRect(x: 0, y: top, width: w, height: 110)), with: .color(Color(argb: 0xFF5B6270)))
        ctx.fill(Path(CGRect(x: 0, y: top + 4, width: w, height: 3)), with: .color(.white))
        ctx.fill(Path(CGRect(x: 0, y: top + 103, width: w, height: 3)), with: .color(.white))
        let step: CGFloat = 46
        var line = Path()
        line.move(to: CGPoint(x: -step + dash * step, y: top + 55))
        line.addLine(to: CGPoint(x: w + step, y: top + 55))
        ctx.stroke(line, with: .color(Color(argb: 0xFFFFD54F)), style: StrokeStyle(lineWidth: 4, dash: [24, 22]))
        let grassBottom = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color(argb: 0xFF7CB342), Color(argb: 0xFF33691E)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        ctx.fill(Path(CGRect(x: 0, y: top + 110, width: w, height: size.height)), with: grassBottom)
    }
}

/// Loading bar, percentage and the "5000 Levels to Explore" tagline.
private struct SplashLoading: View {
    let clock: LoopClock

    var body: some View {
        TimelineView(.animation) { tl in
            // load.animateTo(1f, tween(2300, easing = FastOutSlowInEasing))
            let raw = min(1, clock.elapsed(tl.date) / 2.3)
            let load = TweenEasing.fastOutSlowIn(raw)
            VStack(spacing: 0) {
                Canvas { ctx, size in
                    SplashLoading.drawBar(&ctx, size, CGFloat(load))
                }
                .padding(4)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(Color(argb: 0xFF0D2C6B), in: RoundedRectangle(cornerRadius: 13))
                Spacer().frame(height: 8)
                GText("Loading \(Int(load * 100))%", .Label, color: .white, size: 15)
                Spacer().frame(height: 4)
                OText("5000 Levels to Explore", .Title, size: 18, color: Color(argb: 0xFFFFE082), strokeWidth: 5)
            }
        }
    }

    static func drawBar(_ ctx: inout GraphicsContext, _ size: CGSize, _ load: CGFloat) {
        let w = size.width * load
        let h = size.height
        ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: h / 2), with: .color(Color(argb: 0x33000000)))
        if w > h {
            let g = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(argb: 0xFFFFF176), Color(argb: 0xFFFFB300)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h))
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: h / 2), with: g)
            ctx.fill(Path(roundedRect: CGRect(x: 6, y: 2, width: w - 12, height: h * 0.3), cornerRadius: 4),
                     with: .color(.white.opacity(0.45)))
        }
    }
}
