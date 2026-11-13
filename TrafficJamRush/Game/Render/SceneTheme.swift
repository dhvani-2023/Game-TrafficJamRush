import SwiftUI
import GameKit

// Port of game/render/SceneTheme.kt.

enum Backdrop: Int, CaseIterable { case STATION, ZOO, FAIR, PIER, DESERT, SNOW, NEON, FARM, JUNGLE, SPACE }

/// Colours and props for one world. Collections cycle through these ten in tiers I–V.
/// Colour properties are SwiftUI colours (UI code); `pal` holds the same values for the art code.
struct SceneTheme: Hashable {
    /// The theme colours as art colours (exact 8-bit channels).
    struct Palette: Hashable {
        let skyTop: ArtColor
        let skyBottom: ArtColor
        let platform: ArtColor
        let platformDark: ArtColor
        let slotBand: ArtColor
        let road: ArtColor
        let lot: ArtColor
        let lotEdge: ArtColor
        let outside: ArtColor
        let accent: ArtColor
    }

    let name: String
    let backdrop: Backdrop
    let pal: Palette
    let dark: Bool

    let skyTop: Color
    let skyBottom: Color
    let platform: Color
    let platformDark: Color
    let slotBand: Color
    let road: Color
    let lot: Color
    let lotEdge: Color
    let outside: Color
    let accent: Color

    init(_ name: String, _ backdrop: Backdrop,
         _ skyTop: UInt32, _ skyBottom: UInt32, _ platform: UInt32, _ platformDark: UInt32,
         _ slotBand: UInt32, _ road: UInt32, _ lot: UInt32, _ lotEdge: UInt32, _ outside: UInt32,
         _ accent: UInt32, dark: Bool = false) {
        self.name = name
        self.backdrop = backdrop
        self.dark = dark
        pal = Palette(skyTop: ArtColor(skyTop), skyBottom: ArtColor(skyBottom), platform: ArtColor(platform), platformDark: ArtColor(platformDark),
                      slotBand: ArtColor(slotBand), road: ArtColor(road), lot: ArtColor(lot), lotEdge: ArtColor(lotEdge),
                      outside: ArtColor(outside), accent: ArtColor(accent))
        self.skyTop = pal.skyTop.color
        self.skyBottom = pal.skyBottom.color
        self.platform = pal.platform.color
        self.platformDark = pal.platformDark.color
        self.slotBand = pal.slotBand.color
        self.road = pal.road.color
        self.lot = pal.lot.color
        self.lotEdge = pal.lotEdge.color
        self.outside = pal.outside.color
        self.accent = pal.accent.color
    }

    static func == (a: SceneTheme, b: SceneTheme) -> Bool { a.name == b.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

enum Themes {
    static let all: [SceneTheme] = [
        SceneTheme(
            "City Station", .STATION,
            0xFFBF_E6FF, 0xFFE3_F4FF, 0xFFED_EFF2, 0xFFC9_CED6,
            0xFF9E_A3AB, 0xFF6E_737B, 0xFFD4_D6CF, 0xFFB9_BBB2, 0xFF8F_C25A,
            0xFF2F_7CF6
        ),
        SceneTheme(
            "Sunny Zoo", .ZOO,
            0xFFA8_E4FF, 0xFFE8_F8D8, 0xFFE9_D9A6, 0xFFC9_B47A,
            0xFF8D_BE5A, 0xFF5E_7C46, 0xFFE5_E3B8, 0xFFC6_C28C, 0xFF8C_B55A,
            0xFF7C_B342
        ),
        SceneTheme(
            "Candy Fair", .FAIR,
            0xFFFF_D6EC, 0xFFFF_F0F7, 0xFFFF_E1EE, 0xFFF4_B7D0,
            0xFFE7_9AB8, 0xFFB0_688A, 0xFFF7_C9DA, 0xFFE6_A7BF, 0xFFD4_7DA0,
            0xFFEC_407A
        ),
        SceneTheme(
            "Ocean Pier", .PIER,
            0xFF7F_D3FF, 0xFFBF_EAFF, 0xFFD8_B98A, 0xFFB0_8F5E,
            0xFF6B_A3C7, 0xFF4A_6E8A, 0xFFCF_E6EE, 0xFFA9_CBD8, 0xFF3F_8FC0,
            0xFF00_ACC1
        ),
        SceneTheme(
            "Desert Dunes", .DESERT,
            0xFFFF_D59A, 0xFFFF_EFD2, 0xFFF1_D29B, 0xFFD8_B270,
            0xFFD6_A15E, 0xFF9E_7448, 0xFFF2_D7A8, 0xFFDD_B97F, 0xFFC9_955A,
            0xFFFF_8A1F
        ),
        SceneTheme(
            "Snowy Peak", .SNOW,
            0xFFB6_D8F2, 0xFFEA_F5FF, 0xFFF7_FBFF, 0xFFD5_E3F0,
            0xFFA9_BFD3, 0xFF6F_8399, 0xFFE9_F1F8, 0xFFC7_D6E5, 0xFF9D_B4CA,
            0xFF29_B6F6
        ),
        SceneTheme(
            "Neon Night", .NEON,
            0xFF1B_1446, 0xFF3A_2475, 0xFF3B_3366, 0xFF29_224F,
            0xFF2E_2859, 0xFF1C_1838, 0xFF3A_3468, 0xFF2A_2552, 0xFF22_1C46,
            0xFFE0_40FB, dark: true
        ),
        SceneTheme(
            "Autumn Farm", .FARM,
            0xFFFF_D8A8, 0xFFFF_F1DC, 0xFFE8_C48F, 0xFFC7_9A5E,
            0xFFC5_8A4E, 0xFF8A_5E35, 0xFFF0_DDB8, 0xFFD9_BE8E, 0xFFB9_8A4A,
            0xFFE6_5100
        ),
        SceneTheme(
            "Jungle Camp", .JUNGLE,
            0xFF9F_E3C2, 0xFFDD_F7E6, 0xFFCD_BB8A, 0xFFA8_955F,
            0xFF5E_9A5A, 0xFF3F_6B3D, 0xFFD5_E2B8, 0xFFB2_C48C, 0xFF5E_8F45,
            0xFF2E_7D32
        ),
        SceneTheme(
            "Space Port", .SPACE,
            0xFF0B_1030, 0xFF24_3063, 0xFF4A_5378, 0xFF35_3D5E,
            0xFF3A_4266, 0xFF23_2945, 0xFF3F_476B, 0xFF2F_3656, 0xFF1B_2140,
            0xFF00_E5FF, dark: true
        ),
    ]

    private static let roman = ["I", "II", "III", "IV", "V"]

    static func forCollection(_ c: Int) -> SceneTheme { all[(c - 1) % all.count] }
    static func forLevel(_ level: Int) -> SceneTheme { forCollection(collectionOf(level)) }
    static func collectionName(_ c: Int) -> String { "\(forCollection(c).name) \(roman[((c - 1) / all.count).coerceIn(0, 4)])" }

    /// Position of [th] in `all` (Kotlin `Themes.all.indexOf(th)`).
    static func indexOf(_ th: SceneTheme) -> Int { all.firstIndex(of: th) ?? -1 }
}
