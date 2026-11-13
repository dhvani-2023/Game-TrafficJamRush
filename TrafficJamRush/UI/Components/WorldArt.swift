import SwiftUI
import GameKit

// Port of ui/components/WorldArt.kt.

/// A small postcard of a world's scenery, painted with the same art as the game scene.
/// Postcards are cached; a new size is painted off the main thread (the sky colours show meanwhile).
struct WorldArt: View {
    let theme: SceneTheme

    init(_ theme: SceneTheme) { self.theme = theme }

    var body: some View {
        GeometryReader { geo in
            let k = CGFloat(Art.scale)
            let w = Int(geo.size.width * k).coerceIn(32, 1600)
            let h = Int(geo.size.height * k).coerceIn(32, 1600)
            Postcard(theme: theme, w: w, h: h)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct Postcard: View {
    let theme: SceneTheme
    let w: Int
    let h: Int
    @State private var painted: ImageBitmap?
    @State private var paintedKey = ""

    private var key: String { "\(theme.name)/\(w)x\(h)" }

    var body: some View {
        let img = (paintedKey == key ? painted : nil) ?? SceneArt.cachedPostcard(theme, w, h)
        ZStack {
            if let img {
                img.image.resizable()
            } else {
                LinearGradient(colors: [theme.skyTop, theme.skyBottom, theme.platform, theme.road, theme.outside],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .task(id: key) {
            if SceneArt.cachedPostcard(theme, w, h) != nil { return }
            let th = theme, ww = w, hh = h, k = key
            let result = await Task.detached(priority: .userInitiated) { SceneArt.postcard(th, ww, hh) }.value
            painted = result
            paintedKey = k
        }
    }
}
