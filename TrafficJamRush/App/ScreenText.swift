import SwiftUI
import GameKit

// Short-hands the screens use for Compose `Text(style = GameText.X.copy(...))` and `OutlinedText(...)`
// calls. They resolve to the shared theme (UI/Theme) and components (UI/Components).

/// The `GameText` styles of ui/theme/Theme.kt.
enum GameTextKind {
    case Display, Title, Button, Label, Body, Small

    var textStyle: TextStyle {
        switch self {
        case .Display: return GameText.Display
        case .Title: return GameText.Title
        case .Button: return GameText.Button
        case .Label: return GameText.Label
        case .Body: return GameText.Body
        case .Small: return GameText.Small
        }
    }
}

/// Compose `Text(text, style = GameText.<kind>.copy(color, fontSize, fontFamily = TitleFont, textAlign, lineHeight))`.
struct GText: View {
    let text: String
    let style: TextStyle
    let lineLimit: Int?

    init(_ text: String, _ kind: GameTextKind, color: Color? = nil, size: CGFloat? = nil, titleFont: Bool = false,
         align: TextAlignment = .leading, lineHeight: CGFloat? = nil, lineLimit: Int? = nil) {
        self.text = text
        self.style = kind.textStyle.copy(color: color, fontSize: size, fontFamily: titleFont ? TitleFont : nil,
                                         textAlign: align, lineHeight: lineHeight)
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(text)
            .textStyle(style)
            .lineLimit(lineLimit)
    }
}

/// Compose `OutlinedText(text, style = GameText.<kind>, fontSize, color, outline, strokeWidth, textAlign)`.
/// `strokeWidth` is the Kotlin value (Android pixels of a centred stroke).
struct OText: View {
    let text: String
    let kind: GameTextKind
    let size: CGFloat?
    let color: Color
    let outline: Color
    let strokeWidth: CGFloat
    let align: TextAlignment

    init(_ text: String, _ kind: GameTextKind = .Title, size: CGFloat? = nil, color: Color = .white,
         outline: Color = Color(argb: 0xFF2B1B0E), strokeWidth: CGFloat = 8, align: TextAlignment = .center) {
        self.text = text
        self.kind = kind
        self.size = size
        self.color = color
        self.outline = outline
        self.strokeWidth = strokeWidth
        self.align = align
    }

    var body: some View {
        OutlinedText(text, style: kind.textStyle, color: color, outline: outline, strokeWidth: strokeWidth,
                     fontSize: size, textAlign: align)
    }
}

/// `leading = { GameIcon(Icon.AD, n.dp) }` on rewarded buttons. The art stays even without real ads
/// (the brief: "FREE" replaces ad *labels*, the button art is kept).
enum AdBadge {
    static func icon(_ size: CGFloat) -> GameIcon { GameIcon(Icon.AD, size) }
}

/// `leading = { GameIcon(Icon.COIN, n.dp) }` on coin-price buttons.
enum CoinBadge {
    static func icon(_ size: CGFloat) -> GameIcon { GameIcon(Icon.COIN, size) }
}
