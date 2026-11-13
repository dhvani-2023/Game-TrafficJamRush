import SwiftUI
import GameKit
#if canImport(UIKit)
import UIKit
#endif

// Port of ui/theme/Theme.kt. Fonts: Lilita One (titles) and Fredoka (variable, body), bundled in
// Resources/Fonts and registered by `FontRegistry.registerAll()` (App.onCreate).

enum GameColors {
    static let SkyTop = Color(argb: 0xFF4F_C3F7)
    static let SkyBottom = Color(argb: 0xFF1E_88E5)
    static let SkyDeep = Color(argb: 0xFF15_65C0)
    static let Navy = Color(argb: 0xFF1A_3A6B)
    static let NavyDark = Color(argb: 0xFF0F_2547)
    static let Cream = Color(argb: 0xFFFF_F8E7)
    static let CreamDark = Color(argb: 0xFFF3_DFB8)
    static let Yellow = Color(argb: 0xFFFF_C107)
    static let YellowLight = Color(argb: 0xFFFF_E57F)
    static let Orange = Color(argb: 0xFFFF_9800)
    static let OrangeDark = Color(argb: 0xFFE6_5100)
    static let Green = Color(argb: 0xFF7C_B342)
    static let GreenLight = Color(argb: 0xFFAE_EA00)
    static let GreenDark = Color(argb: 0xFF33_691E)
    static let Red = Color(argb: 0xFFE5_3935)
    static let RedDark = Color(argb: 0xFF8E_1B1B)
    static let Pink = Color(argb: 0xFFEC_407A)
    static let Purple = Color(argb: 0xFF7E_57C2)
    static let PurpleDark = Color(argb: 0xFF45_27A0)
    static let Blue = Color(argb: 0xFF1E_88E5)
    static let BlueDark = Color(argb: 0xFF0D_47A1)
    static let Brown = Color(argb: 0xFF6D_4C41)
    static let TextDark = Color(argb: 0xFF3E_2723)
    static let Shade = Color(argb: 0x9900_0000)
}

enum Brushes {
    static let Sky = LinearGradient(colors: [GameColors.SkyTop, GameColors.SkyBottom], startPoint: .top, endPoint: .bottom)
    static let Panel = LinearGradient(colors: [Color(argb: 0xFFFF_FDF5), GameColors.Cream, Color(argb: 0xFFFF_EFC9)], startPoint: .top, endPoint: .bottom)
    static let Night = LinearGradient(colors: [Color(argb: 0xFF1A_237E), Color(argb: 0xFF0D_1B4A)], startPoint: .top, endPoint: .bottom)
}

// MARK: - Fonts

/// Compose `FontFamily`: `TitleFont` (Lilita One) or `BodyFont` (Fredoka 400–700).
enum FontFamily: Hashable {
    case title
    case body
}

let TitleFont = FontFamily.title
let BodyFont = FontFamily.body

/// Compose `FontWeight` (only the weight value matters for the fonts used here).
struct FontWeight: Hashable {
    let weight: Int
    init(_ weight: Int) { self.weight = weight }
    static let Normal = FontWeight(400)
    static let Medium = FontWeight(500)
    static let SemiBold = FontWeight(600)
    static let Bold = FontWeight(700)
}

enum GameFonts {
    static let titleName = "LilitaOne"
    /// Fredoka is a variable font (wght 300–700); every weight is an instance of this face.
    static let bodyName = "Fredoka-Regular"

    #if canImport(UIKit)
    private static var cache: [String: UIFont] = [:]
    private static let lock = NSLock()

    /// UIKit font for a family / weight / size (cached).
    static func uiFont(_ family: FontFamily, _ weight: FontWeight, _ size: CGFloat) -> UIFont {
        let key = "\(family)-\(weight.weight)-\(size)"
        lock.lock()
        defer { lock.unlock() }
        if let f = cache[key] { return f }
        let f: UIFont
        switch family {
        case .title:
            f = UIFont(name: titleName, size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        case .body:
            f = FontRegistry.variable(bodyName, size: size, weight: CGFloat(weight.weight))
        }
        cache[key] = f
        return f
    }
    #endif

    private static var swiftUICache: [String: Font] = [:]

    /// SwiftUI font for a family / weight / size (cached).
    static func font(_ family: FontFamily, _ weight: FontWeight, _ size: CGFloat) -> Font {
        let key = "\(family)-\(weight.weight)-\(size)"
        if let f = swiftUICache[key] { return f }
        let f: Font
        switch family {
        case .title: f = .custom(titleName, fixedSize: size)
        case .body:
            #if canImport(UIKit)
            f = Font(uiFont(.body, weight, size) as CTFont)
            #else
            f = .custom(bodyName, fixedSize: size)
            #endif
        }
        swiftUICache[key] = f
        return f
    }
}

// MARK: - Text styles

/// Compose `Shadow(color, offset, blurRadius)`; offset and blur are Android pixels.
struct TextShadow: Hashable {
    let color: Color
    let offsetX: CGFloat
    let offsetY: CGFloat
    let blurRadius: CGFloat
}

/// Compose `TextStyle` (the parts this game uses).
struct TextStyle {
    var fontFamily: FontFamily
    var fontWeight: FontWeight = .Normal
    var fontSize: CGFloat
    var color: Color = .black
    var shadow: TextShadow? = nil
    var textAlign: TextAlignment? = nil
    var lineHeight: CGFloat? = nil

    func copy(color: Color? = nil, fontSize: CGFloat? = nil, fontFamily: FontFamily? = nil, fontWeight: FontWeight? = nil,
              textAlign: TextAlignment? = nil, shadow: TextShadow?? = nil, lineHeight: CGFloat? = nil) -> TextStyle {
        var s = self
        if let color { s.color = color }
        if let fontSize { s.fontSize = fontSize }
        if let fontFamily { s.fontFamily = fontFamily }
        if let fontWeight { s.fontWeight = fontWeight }
        if let textAlign { s.textAlign = textAlign }
        if let shadow { s.shadow = shadow }
        if let lineHeight { s.lineHeight = lineHeight }
        return s
    }

    /// Lilita One ignores the weight; Fredoka uses it on the weight axis.
    var font: Font { GameFonts.font(fontFamily, fontFamily == .title ? .Normal : fontWeight, fontSize) }

    #if canImport(UIKit)
    var uiFont: UIFont { GameFonts.uiFont(fontFamily, fontFamily == .title ? .Normal : fontWeight, fontSize) }
    #endif
}

enum GameText {
    private static let outline = TextShadow(color: Color(argb: 0x6600_0000), offsetX: 0, offsetY: 4, blurRadius: 2)
    static let Display = TextStyle(fontFamily: TitleFont, fontSize: 44, color: .white, shadow: outline)
    static let Title = TextStyle(fontFamily: TitleFont, fontSize: 30, color: .white, shadow: outline)
    static let Button = TextStyle(fontFamily: TitleFont, fontSize: 22, color: .white,
                                  shadow: TextShadow(color: Color(argb: 0x5500_0000), offsetX: 0, offsetY: 3, blurRadius: 1))
    static let Label = TextStyle(fontFamily: BodyFont, fontWeight: .Bold, fontSize: 16, color: GameColors.TextDark)
    static let Body = TextStyle(fontFamily: BodyFont, fontWeight: .Medium, fontSize: 15, color: GameColors.TextDark)
    static let Small = TextStyle(fontFamily: BodyFont, fontWeight: .SemiBold, fontSize: 12, color: GameColors.TextDark)
}

extension View {
    /// Compose `Text(…, style = …)`: font, colour, shadow, alignment and line height of a `TextStyle`.
    func textStyle(_ style: TextStyle) -> some View {
        let px = CGFloat(Art.px)
        return self
            .font(style.font)
            .foregroundStyle(style.color)
            .multilineTextAlignment(style.textAlign ?? .leading)
            .lineSpacing(style.lineHeight.map { max(0, $0 - style.fontSize * 1.2) } ?? 0)
            .shadow(color: style.shadow?.color ?? .clear,
                    radius: (style.shadow?.blurRadius ?? 0) * px * 0.5,
                    x: (style.shadow?.offsetX ?? 0) * px,
                    y: (style.shadow?.offsetY ?? 0) * px)
    }
}

/// Compose `Text(text, style = …)`.
struct StyledText: View {
    let text: String
    let style: TextStyle

    init(_ text: String, style: TextStyle) {
        self.text = text
        self.style = style
    }

    var body: some View { Text(text).textStyle(style) }
}

/// Kotlin `CarTrafficJamTheme { … }`: the Material theme wrapper (colours only matter to Material
/// widgets, which this game doesn't use).
struct CarTrafficJamTheme<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .tint(GameColors.Orange)
    }
}
