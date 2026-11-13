import SwiftUI
import GameKit

struct CollectionsTab: View {
    let player: PlayerState
    let onOpen: (Int) -> Void

    var body: some View {
        let open = (1...TOTAL_COLLECTIONS).filter { player.isCollectionUnlocked($0) }.count
        VStack(spacing: 0) {
            TabHeader(title: "Worlds", subtitle: "\(open) of \(TOTAL_COLLECTIONS) open")
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(1...TOTAL_COLLECTIONS, id: \.self) { c in
                        let unlocked = player.isCollectionUnlocked(c)
                        WorldCard(c: c, unlocked: unlocked, done: player.completedIn(c), stars: player.starsIn(c), onOpen: onOpen)
                            .equatable()
                    }
                }
                .padding(14)
            }
        }
    }
}

struct TabHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            OText(title, .Title, size: 28, outline: Color(argb: 0xFF0D2C6B), strokeWidth: 7)
            if let subtitle {
                GText(subtitle, .Small, color: .white, size: 13)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Color(argb: 0xFF1C5BD0), Color(argb: 0xFF2F7CF6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }
}

/// Card art (navy lip under a white frame) shared by the world and paint-pack cards.
struct CardBack: View {
    var radius: CGFloat = 20
    var face: Color = .white
    var lip: CGFloat = 5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(Color(argb: 0xFF0D2C6B)).offset(y: lip)
            RoundedRectangle(cornerRadius: radius).fill(face)
        }
    }
}

private struct WorldCard: View, Equatable {
    let c: Int
    let unlocked: Bool
    let done: Int
    let stars: Int
    let onOpen: (Int) -> Void

    static func == (a: WorldCard, b: WorldCard) -> Bool {
        a.c == b.c && a.unlocked == b.unlocked && a.done == b.done && a.stars == b.stars
    }

    var body: some View {
        let theme = Themes.forCollection(c)
        Button { onOpen(c) } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    WorldArt(theme)
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)
                    GText("\(c)", .Label, color: .white, size: 15, titleFont: true)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 1)
                        .background(Color(argb: 0xAA0D2C6B), in: Capsule())
                        .padding(6)
                    if !unlocked {
                        VStack(spacing: 0) {
                            GameIcon(Icon.LOCK, 44)
                            HStack(spacing: 0) {
                                GameIcon(Icon.AD, 18)
                                GText(" Unlock", .Small, color: .white, titleFont: true)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(argb: 0xFF5FC12F), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(argb: 0x99101828))
                    }
                }
                .frame(height: 112)
                VStack(alignment: .leading, spacing: 0) {
                    GText(Themes.collectionName(c), .Label, color: Color(argb: 0xFF3E2723), size: 16, titleFont: true, lineLimit: 1)
                    Spacer().frame(height: 4)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(argb: 0xFFE6D3AE))
                            Capsule()
                                .fill(LinearGradient(colors: [Color(argb: 0xFF9CCC65), Color(argb: 0xFF43A047)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * CGFloat(done) / CGFloat(LEVELS_PER_COLLECTION))
                        }
                    }
                    .frame(height: 10)
                    Spacer().frame(height: 4)
                    HStack(spacing: 0) {
                        GText("\(done)/\(LEVELS_PER_COLLECTION)", .Small, color: Color(argb: 0xFF6D4C41))
                        Spacer(minLength: 0)
                        GameIcon(Icon.STAR, 14)
                        GText(" \(stars)", .Small, color: Color(argb: 0xFF6D4C41))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(argb: 0xFFFFF8E7))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(4)
            .background(CardBack(radius: 20))
        }
        .buttonStyle(.plain)
    }
}
