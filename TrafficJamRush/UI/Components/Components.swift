import SwiftUI
import UIKit
import CoreText
import GameKit

// Port of ui/components/Components.kt.

/// Kotlin `LocalAudio.current` (defaults to the app container's audio, like the Kotlin default).
enum LocalAudio {
    @MainActor static var current: AudioManager { App.container.audio }
}

/// One Android pixel in points (Kotlin px literals such as stroke widths).
@inline(__always) private var px: CGFloat { CGFloat(Art.px) }

// MARK: - OutlinedText

/// Game-style text: a thick dark stroke under a filled face (Compose draws the text twice, the
/// first pass with `Stroke(strokeWidth, join = Round)`). [strokeWidth] is in Android pixels.
struct OutlinedText: View {
    let text: String
    let style: TextStyle
    let color: Color
    let outline: Color
    let strokeWidth: CGFloat
    let fontSize: CGFloat?
    let textAlign: TextAlignment

    init(_ text: String, style: TextStyle = GameText.Title, color: Color = .white, outline: Color = Color(argb: 0xFF2B_1B0E),
         strokeWidth: CGFloat = 8, fontSize: CGFloat? = nil, textAlign: TextAlignment = .center) {
        self.text = text
        self.style = style
        self.color = color
        self.outline = outline
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
        self.textAlign = textAlign
    }

    var body: some View {
        OutlinedLabel(text: text,
                      font: style.copy(fontSize: fontSize ?? style.fontSize).uiFont,
                      fill: UIColor(color),
                      stroke: UIColor(outline),
                      strokeWidth: strokeWidth * px,
                      align: textAlign)
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}

private struct OutlinedLabel: UIViewRepresentable {
    let text: String
    let font: UIFont
    let fill: UIColor
    let stroke: UIColor
    let strokeWidth: CGFloat
    let align: TextAlignment

    func makeUIView(context: Context) -> OutlinedLabelView { OutlinedLabelView() }

    func updateUIView(_ v: OutlinedLabelView, context: Context) {
        v.configure(text: text, font: font, fill: fill, stroke: stroke, strokeWidth: strokeWidth, align: align)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: OutlinedLabelView, context: Context) -> CGSize? {
        uiView.configure(text: text, font: font, fill: fill, stroke: stroke, strokeWidth: strokeWidth, align: align)
        return uiView.measure(proposal.width)
    }
}

/// Lays the text out like a Compose `Text` (its bounds are the text's own size) and paints the stroke
/// and fill with Core Text into a slightly larger canvas so the outline is never clipped.
final class OutlinedLabelView: UIView {
    private let canvas = OutlinedTextCanvas()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        isUserInteractionEnabled = false
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, font: UIFont, fill: UIColor, stroke: UIColor, strokeWidth: CGFloat, align: TextAlignment) {
        canvas.configure(text: text, font: font, fill: fill, stroke: stroke, strokeWidth: strokeWidth, align: align)
        setNeedsLayout()
    }

    func measure(_ width: CGFloat?) -> CGSize { canvas.measure(width) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let p = canvas.pad
        canvas.frame = bounds.insetBy(dx: -p, dy: -p)
    }
}

private final class OutlinedTextCanvas: UIView {
    private var text = ""
    private var font = UIFont.systemFont(ofSize: 17)
    private var fill = UIColor.white
    private var stroke = UIColor.black
    private var strokeWidth: CGFloat = 0
    private var align: TextAlignment = .center
    private var cached: NSAttributedString?

    /// Room around the text for the outline and glyph overshoot.
    var pad: CGFloat { strokeWidth + font.pointSize * 0.2 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, font: UIFont, fill: UIColor, stroke: UIColor, strokeWidth: CGFloat, align: TextAlignment) {
        if text == self.text && font == self.font && fill == self.fill && stroke == self.stroke && strokeWidth == self.strokeWidth && align == self.align {
            return
        }
        self.text = text
        self.font = font
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.align = align
        cached = nil
        setNeedsDisplay()
    }

    private var attributed: NSAttributedString {
        if let c = cached { return c }
        let ps = NSMutableParagraphStyle()
        switch align {
        case .leading: ps.alignment = .natural
        case .center: ps.alignment = .center
        case .trailing: ps.alignment = .right
        }
        let s = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: ps,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        cached = s
        return s
    }

    func measure(_ width: CGFloat?) -> CGSize {
        let fs = CTFramesetterCreateWithAttributedString(attributed)
        let maxW = (width == nil || width! <= 0 || !width!.isFinite) ? CGFloat.greatestFiniteMagnitude : width!
        let sz = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(location: 0, length: 0), nil,
                                                              CGSize(width: maxW, height: .greatestFiniteMagnitude), nil)
        return CGSize(width: ceil(min(sz.width, maxW)), height: ceil(sz.height))
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), !text.isEmpty else { return }
        let p = pad
        let textRect = bounds.insetBy(dx: p, dy: p)
        let fs = CTFramesetterCreateWithAttributedString(attributed)
        // Core Text lays out in a y-up space.
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        let flipped = CGRect(x: textRect.minX, y: bounds.height - textRect.maxY, width: textRect.width + 0.5, height: textRect.height + 1)
        let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: flipped, transform: nil), nil)
        if strokeWidth > 0 {
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.setLineWidth(strokeWidth)
            ctx.setStrokeColor(stroke.cgColor)
            ctx.setTextDrawingMode(.stroke)
            CTFrameDraw(frame, ctx)
        }
        ctx.setTextDrawingMode(.fill)
        ctx.setFillColor(fill.cgColor)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
}

// MARK: - Buttons

enum ButtonColor: CaseIterable {
    case ORANGE, GREEN, BLUE, PURPLE, RED, YELLOW, GRAY

    var art: ArtColor {
        switch self {
        case .ORANGE: return ArtColor(0xFFFF_A000)
        case .GREEN: return ArtColor(0xFF5F_C12F)
        case .BLUE: return ArtColor(0xFF2F_8CF6)
        case .PURPLE: return ArtColor(0xFF8E_5CF0)
        case .RED: return ArtColor(0xFFF2_453D)
        case .YELLOW: return ArtColor(0xFFFF_C21A)
        case .GRAY: return ArtColor(0xFF9A_A3AE)
        }
    }

    var base: Color { art.color }
}

/// Precomputed colours of one button face.
private struct ButtonFaceColors {
    let lip: Color
    let gradient: [Color]
    let outline: Color

    private static var cache: [UInt32: ButtonFaceColors] = [:]

    @MainActor static func of(_ base: ArtColor) -> ButtonFaceColors {
        if let c = cache[base.argb] { return c }
        let c = ButtonFaceColors(lip: base.shade(0.62).color,
                                 gradient: [base.tint(0.35).color, base.color, base.shade(0.9).color],
                                 outline: base.shade(0.45).color)
        cache[base.argb] = c
        return c
    }
}

/// The glossy pill with its 3D lip; [press] squashes the lip (0 = up, 1 = pressed).
private struct GameButtonFace: View, Animatable {
    var press: CGFloat
    let colors: ButtonFaceColors

    var animatableData: CGFloat {
        get { press }
        set { press = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lip: CGFloat = 6
            let lipPx = lip * (1 - press * 0.7)
            let top = lip - lipPx
            let faceH = h - lip
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.black.opacity(0.25))
                    .frame(width: w, height: faceH).offset(y: lip + 2)
                Capsule().fill(colors.lip)
                    .frame(width: w, height: faceH).offset(y: top + lipPx)
                Capsule().stroke(Color(argb: 0xFF2B_1B0E).opacity(0.55), lineWidth: 2)
                    .frame(width: w, height: faceH).offset(y: top)
                Capsule().fill(LinearGradient(colors: colors.gradient, startPoint: .top, endPoint: .bottom))
                    .frame(width: w - 3, height: faceH - 3).offset(x: 1.5, y: top + 1.5)
                RoundedRectangle(cornerRadius: h / 4, style: .circular).fill(Color.white.opacity(0.38))
                    .frame(width: max(0, w - h * 0.56), height: faceH * 0.3).offset(x: h * 0.28, y: top + 4)
            }
        }
    }
}

private struct GameButtonStyle: ButtonStyle {
    let colors: ButtonFaceColors
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let press: CGFloat = configuration.isPressed ? 1 : 0
        let lip: CGFloat = 6
        configuration.label
            .offset(y: -lip / 2 + lip * press * 0.7)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(GameButtonFace(press: press, colors: colors))
            .scaleEffect(1 - press * 0.03)
            .contentShape(Rectangle())
            .animation(.compose(dampingRatio: 1, stiffness: 10_000), value: configuration.isPressed)
    }
}

/// Glossy 3D pill button with a pressed-down squash, click sound and haptic.
/// It fills the width it is given (every caller sets one, like the Kotlin modifiers).
struct GameButton<Leading: View, Trailing: View>: View {
    let text: String
    let onClick: () -> Void
    var color: ButtonColor = .ORANGE
    var height: CGFloat = 60
    var fontSize: CGFloat = 24
    var enabled: Bool = true
    var sound: Bool = true
    let leading: Leading?
    let trailing: Trailing?

    init(_ text: String, onClick: @escaping () -> Void, color: ButtonColor = .ORANGE, height: CGFloat = 60, fontSize: CGFloat = 24,
         enabled: Bool = true, sound: Bool = true, leading: Leading?, trailing: Trailing?) {
        self.text = text
        self.onClick = onClick
        self.color = color
        self.height = height
        self.fontSize = fontSize
        self.enabled = enabled
        self.sound = sound
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        let base = (enabled ? color : .GRAY).art
        let colors = ButtonFaceColors.of(base)
        Button {
            let audio = LocalAudio.current
            if sound { audio.play(.Click) }
            audio.haptic(.Tap)
            onClick()
        } label: {
            HStack(spacing: 0) {
                if let leading {
                    leading
                    Spacer().frame(width: 8)
                }
                OutlinedText(text, style: GameText.Button, outline: colors.outline, strokeWidth: 6, fontSize: fontSize)
                    .fixedSize()
                if let trailing {
                    Spacer().frame(width: 8)
                    trailing
                }
            }
            .padding(.horizontal, 18)
        }
        .buttonStyle(GameButtonStyle(colors: colors, height: height))
        .disabled(!enabled)
    }
}

extension GameButton where Leading == EmptyView, Trailing == EmptyView {
    init(_ text: String, onClick: @escaping () -> Void, color: ButtonColor = .ORANGE, height: CGFloat = 60, fontSize: CGFloat = 24,
         enabled: Bool = true, sound: Bool = true) {
        self.init(text, onClick: onClick, color: color, height: height, fontSize: fontSize, enabled: enabled, sound: sound,
                  leading: nil, trailing: nil)
    }
}

extension GameButton where Trailing == EmptyView {
    init(_ text: String, onClick: @escaping () -> Void, color: ButtonColor = .ORANGE, height: CGFloat = 60, fontSize: CGFloat = 24,
         enabled: Bool = true, sound: Bool = true, leading: Leading) {
        self.init(text, onClick: onClick, color: color, height: height, fontSize: fontSize, enabled: enabled, sound: sound,
                  leading: leading, trailing: nil)
    }
}

extension GameButton where Leading == EmptyView {
    init(_ text: String, onClick: @escaping () -> Void, color: ButtonColor = .ORANGE, height: CGFloat = 60, fontSize: CGFloat = 24,
         enabled: Bool = true, sound: Bool = true, trailing: Trailing) {
        self.init(text, onClick: onClick, color: color, height: height, fontSize: fontSize, enabled: enabled, sound: sound,
                  leading: nil, trailing: trailing)
    }
}

private struct RoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.compose(dampingRatio: 1, stiffness: 10_000), value: configuration.isPressed)
    }
}

/// Round icon button (gear, close, back…) with a lip and gloss.
struct RoundButton<Content: View>: View {
    let onClick: () -> Void
    var size: CGFloat = 48
    var color: Color = Color(argb: 0xFF2F_8CF6)
    let content: Content

    init(onClick: @escaping () -> Void, size: CGFloat = 48, color: Color = Color(argb: 0xFF2F_8CF6), @ViewBuilder content: () -> Content) {
        self.onClick = onClick
        self.size = size
        self.color = color
        self.content = content()
    }

    var body: some View {
        let c = ArtColor(color)
        let r = size / 2
        Button {
            let audio = LocalAudio.current
            audio.play(.Click)
            audio.haptic(.Tap)
            onClick()
        } label: {
            ZStack {
                Circle().fill(Color.black.opacity(0.25)).offset(y: 3)
                Circle().fill(Color.white)
                Circle().fill(LinearGradient(colors: [c.tint(0.35).color, c.color, c.shade(0.8).color], startPoint: .top, endPoint: .bottom))
                    .padding(3)
                Ellipse().fill(Color.white.opacity(0.4))
                    .frame(width: r * 1.1, height: r * 0.5)
                    .position(x: r * 0.45 + r * 0.55, y: r * 0.25 + r * 0.25)
                content
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(RoundButtonStyle())
    }
}

/// Red round button with a white cross.
struct CloseButton: View {
    let onClick: () -> Void

    init(_ onClick: @escaping () -> Void) { self.onClick = onClick }
    init(onClick: @escaping () -> Void) { self.onClick = onClick }

    var body: some View {
        RoundButton(onClick: onClick, size: 44, color: Color(argb: 0xFFF2_453D)) {
            Canvas { ctx, size in
                var p = Path()
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.move(to: CGPoint(x: size.width, y: 0))
                p.addLine(to: CGPoint(x: 0, y: size.height))
                ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            .frame(width: 18, height: 18)
        }
    }
}

// MARK: - Panels and dialogs

/// Cream card with a thick blue frame and a ribbon title; the house style for every dialog.
struct GamePanel<Content: View>: View {
    let title: String
    var frame: Color = Color(argb: 0xFF2F_7CF6)
    var onClose: (() -> Void)?
    let content: Content

    init(_ title: String, frame: Color = Color(argb: 0xFF2F_7CF6), onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.frame = frame
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        let f = ArtColor(frame)
        ZStack(alignment: .top) {
            VStack(spacing: 0) { content }
                .padding(EdgeInsets(top: 40, leading: 18, bottom: 20, trailing: 18))
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [Color(argb: 0xFFFF_FDF5), GameColors.Cream, Color(argb: 0xFFFF_EDC2)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 22, style: .circular)
                )
                .padding(9)
                .background(LinearGradient(colors: [f.tint(0.25).color, frame], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 30, style: .circular))
                .padding(.bottom, 6)
                .background(f.shade(0.7).color, in: RoundedRectangle(cornerRadius: 30, style: .circular))
                .compositingGroup()
                .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 8)
                .padding(.top, 26)

            // Ribbon title
            OutlinedText(title, style: GameText.Title, outline: f.shade(0.4).color, strokeWidth: 7, fontSize: 28)
                .fixedSize()
                .padding(.horizontal, 28)
                .frame(minWidth: 200, minHeight: 56, maxHeight: 56)
                .background(alignment: .top) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 22, style: .circular).fill(f.shade(0.55).color).offset(y: 5)
                        RoundedRectangle(cornerRadius: 22, style: .circular)
                            .fill(LinearGradient(colors: [f.tint(0.45).color, f.tint(0.1).color], startPoint: .top, endPoint: .bottom))
                            .padding(.bottom, 2)
                        RoundedRectangle(cornerRadius: 6, style: .circular).fill(Color.white.opacity(0.3))
                            .frame(height: 12).padding(.horizontal, 14).offset(y: 5)
                    }
                }

            if let onClose {
                CloseButton(onClose)
                    .offset(x: 6, y: 14)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: 380)
    }
}

/// Full-screen modal overlay with a dimmed, blurred scrim and a springy entrance.
struct GameDialog<Content: View>: View {
    let visible: Bool
    var onDismiss: (() -> Void)?
    let content: Content

    init(visible: Bool, onDismiss: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.visible = visible
        self.onDismiss = onDismiss
        self.content = content()
    }

    init(_ visible: Bool, _ onDismiss: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.init(visible: visible, onDismiss: onDismiss, content: content)
    }

    var body: some View {
        ZStack {
            if visible {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color(argb: 0xB300_0814).opacity(0.8)
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.16)),
                                        removal: .opacity.animation(.easeIn(duration: 0.14))))
                .zIndex(0)

                content
                    .padding(22)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6).combined(with: .opacity).animation(.compose(dampingRatio: 0.55, stiffness: 420)),
                        removal: .scale(scale: 0.8).combined(with: .opacity).animation(.easeIn(duration: 0.14))
                    ))
                    .zIndex(1)
            }
        }
        .zIndex(10)
        .onChange(of: visible) { _, v in if v { LocalAudio.current.play(.Open) } }
        .onAppear { if visible { LocalAudio.current.play(.Open) } }
    }
}

// MARK: - Pills, toggles, stars, banners

struct CoinPill: View {
    let coins: Int
    var onPlus: (() -> Void)?

    init(_ coins: Int, onPlus: (() -> Void)? = nil) {
        self.coins = coins
        self.onPlus = onPlus
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CountingText(value: coins)
                .font(GameFonts.font(TitleFont, .Bold, 18))
                .foregroundStyle(Color(argb: 0xFF4A_2E12))
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.65), value: coins)
                .padding(.leading, 26)
                .padding(.trailing, onPlus != nil ? 30 : 12)
                .frame(minWidth: 92 - 4, minHeight: 32 - 4, maxHeight: 32 - 4)
                .background(LinearGradient(colors: [Color(argb: 0xFFFF_FBEF), Color(argb: 0xFFF6_E7C4)], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14, style: .circular))
                .padding(2)
                .background(Color(argb: 0x5500_0000), in: RoundedRectangle(cornerRadius: 16, style: .circular))
                .padding(.leading, 18)
            GameIcon(Icon.COIN, 40)
        }
        .overlay(alignment: .trailing) {
            if let onPlus {
                Button {
                    onPlus()
                } label: {
                    Text("+").textStyle(GameText.Button.copy(fontSize: 18))
                        .frame(width: 26, height: 26)
                        .background(Color(argb: 0xFF5F_C12F), in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .frame(height: 40)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Big ON/OFF switch with a sliding knob.
struct GameToggle: View {
    let checked: Bool
    let onChange: (Bool) -> Void

    init(_ checked: Bool, onChange: @escaping (Bool) -> Void) {
        self.checked = checked
        self.onChange = onChange
    }

    init(checked: Bool, onChange: @escaping (Bool) -> Void) {
        self.init(checked, onChange: onChange)
    }

    private static let off = ArtColor(0xFFB0_B7C3)
    private static let on = ArtColor(0xFF5F_C12F)

    var body: some View {
        let x: CGFloat = checked ? 1 : 0
        ToggleFace(x: x)
            .frame(width: 76, height: 38)
            .contentShape(Rectangle())
            .onTapGesture {
                let audio = LocalAudio.current
                audio.play(.Click)
                audio.haptic(.Tap)
                onChange(!checked)
            }
            .animation(.compose(dampingRatio: 0.6, stiffness: 500), value: checked)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(checked ? "On" : "Off")
    }

    private struct ToggleFace: View, Animatable {
        var x: CGFloat
        var animatableData: CGFloat {
            get { x }
            set { x = newValue }
        }

        var body: some View {
            let track = lerp(GameToggle.off, GameToggle.on, Float(x.coerceIn(0, 1)))
            ZStack(alignment: .topLeading) {
                Capsule().fill(track.shade(0.65).color).offset(y: 3)
                Capsule().fill(track.color).frame(height: 36)
                Capsule().fill(Color.black.opacity(0.12)).frame(width: 70, height: 38 * 0.4).offset(x: 3, y: 3)
                Text(x >= 0.5 ? "ON" : "OFF")
                    .textStyle(GameText.Small.copy(color: .white, fontSize: 13, fontFamily: TitleFont))
                    .padding(.horizontal, 10)
                    .frame(width: 76, height: 38, alignment: x >= 0.5 ? .leading : .trailing)
                Circle()
                    .fill(LinearGradient(colors: [.white, Color(argb: 0xFFE6_EAF0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: 3 + 38 * x, y: 2)
            }
            .frame(width: 76, height: 38, alignment: .topLeading)
        }
    }
}

/// Row of stars that pop in one after another.
struct StarRow: View {
    let stars: Int
    let size: CGFloat
    var animate: Bool = false
    var onStar: (Int) -> Void = { _ in }

    init(_ stars: Int, _ size: CGFloat, animate: Bool = false, onStar: @escaping (Int) -> Void = { _ in }) {
        self.stars = stars
        self.size = size
        self.animate = animate
        self.onStar = onStar
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: size * -0.08) {
            ForEach(0..<3, id: \.self) { i in
                StarCell(index: i, earned: i < stars, size: size, animate: animate, onStar: onStar)
            }
        }
    }

    private struct StarCell: View {
        let index: Int
        let earned: Bool
        let size: CGFloat
        let animate: Bool
        let onStar: (Int) -> Void
        @State private var anim: CGFloat?

        var body: some View {
            let a = anim ?? (animate ? 0 : 1)
            let s = index == 1 ? size * 1.15 : size
            GameIcon(earned ? Icon.STAR : Icon.STAR_EMPTY, s)
                .scaleEffect(a)
                .rotationEffect(.degrees(Double((1 - a) * 90)))
                .offset(y: index == 1 ? -size * 0.18 : 0)
                .task(id: animate) {
                    guard animate else { return }
                    anim = 0
                    try? await Task.sleep(nanoseconds: UInt64(350 + index * 380) * 1_000_000)
                    if Task.isCancelled { return }
                    if earned { onStar(index) }
                    withAnimation(.compose(dampingRatio: 0.42, stiffness: 300)) { anim = 1 }
                }
        }
    }
}

/// A horizontal ribbon banner with folded tails (used for "Level Complete!" and friends).
struct RibbonBanner: View {
    let text: String
    let color: Color
    var fontSize: CGFloat = 30

    init(_ text: String, _ color: Color, fontSize: CGFloat = 30) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
    }

    var body: some View {
        let c = ArtColor(color)
        OutlinedText(text, style: GameText.Title, outline: c.shade(0.4).color, strokeWidth: 7, fontSize: fontSize)
            .fixedSize()
            .padding(.top, 6)
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .top)
            .background {
                Canvas { ctx, size in
                    let w = size.width
                    let h = size.height
                    let tail: CGFloat = 28
                    let dark = c.shade(0.6).color
                    var lt = Path()
                    lt.move(to: CGPoint(x: 0, y: h * 0.25)); lt.addLine(to: CGPoint(x: tail * 1.6, y: h * 0.25))
                    lt.addLine(to: CGPoint(x: tail * 1.6, y: h)); lt.addLine(to: CGPoint(x: 0, y: h))
                    lt.addLine(to: CGPoint(x: tail * 0.6, y: h * 0.62)); lt.closeSubpath()
                    var rt = Path()
                    rt.move(to: CGPoint(x: w, y: h * 0.25)); rt.addLine(to: CGPoint(x: w - tail * 1.6, y: h * 0.25))
                    rt.addLine(to: CGPoint(x: w - tail * 1.6, y: h)); rt.addLine(to: CGPoint(x: w, y: h))
                    rt.addLine(to: CGPoint(x: w - tail * 0.6, y: h * 0.62)); rt.closeSubpath()
                    ctx.fill(lt, with: .color(dark))
                    ctx.fill(rt, with: .color(dark))
                    ctx.fill(Path(roundedRect: CGRect(x: tail, y: 4, width: w - 2 * tail, height: h * 0.8), cornerRadius: 10), with: .color(c.shade(0.5).color))
                    ctx.fill(Path(roundedRect: CGRect(x: tail, y: 0, width: w - 2 * tail, height: h * 0.78), cornerRadius: 10),
                             with: .linearGradient(Gradient(colors: [c.tint(0.35).color, c.color]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                    ctx.fill(Path(roundedRect: CGRect(x: tail + 10, y: 5, width: w - 2 * tail - 20, height: 10), cornerRadius: 5),
                             with: .color(.white.opacity(0.3)))
                }
            }
    }
}

// MARK: - Ready-made dialogs

/// "Watch an ad to unlock" dialog used for levels, collections, slots and skins. Without a real ad
/// network the button says "Free" (the reward is granted straight away), keeping the button art.
struct WatchAdDialog: View {
    let visible: Bool
    let title: String
    let message: String
    let onWatch: () -> Void
    let onDismiss: () -> Void
    var icon: Icon = Icon.LOCK

    init(visible: Bool, title: String, message: String, onWatch: @escaping () -> Void, onDismiss: @escaping () -> Void, icon: Icon = Icon.LOCK) {
        self.visible = visible
        self.title = title
        self.message = message
        self.onWatch = onWatch
        self.onDismiss = onDismiss
        self.icon = icon
    }

    var body: some View {
        GameDialog(visible: visible, onDismiss: onDismiss) {
            GamePanel(title, onClose: onDismiss) {
                PulsingIcon(icon: icon)
                    .frame(width: 120, height: 120)
                    .background(RadialGradient(colors: [Color(argb: 0xFFFF_F3C4), Color(argb: 0x00FF_F3C4)], center: .center, startRadius: 0, endRadius: 60),
                                in: Circle())
                Spacer().frame(height: 8)
                Text(message)
                    .textStyle(GameText.Body.copy(fontSize: 17, textAlign: .center))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 20)
                GameButton(Ads.usesRealAds ? "Watch Ad" : "Free", onClick: onWatch, color: .GREEN, leading: GameIcon(Icon.AD, 34))
            }
        }
    }

    private struct PulsingIcon: View {
        let icon: Icon
        @State private var big = false

        var body: some View {
            GameIcon(icon, 86)
                .scaleEffect(big ? 1.06 : 0.94)
                .onAppear {
                    withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.7).repeatForever(autoreverses: true)) { big = true }
                }
        }
    }
}

struct ConfirmDialog: View {
    let visible: Bool
    let title: String
    let message: String
    let confirm: String
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    var cancel: String = "Cancel"

    init(visible: Bool, title: String, message: String, confirm: String, onConfirm: @escaping () -> Void, onDismiss: @escaping () -> Void,
         cancel: String = "Cancel") {
        self.visible = visible
        self.title = title
        self.message = message
        self.confirm = confirm
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        self.cancel = cancel
    }

    var body: some View {
        GameDialog(visible: visible, onDismiss: onDismiss) {
            GamePanel(title, onClose: onDismiss) {
                Text(message)
                    .textStyle(GameText.Body.copy(fontSize: 17, textAlign: .center))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 22)
                HStack(spacing: 12) {
                    GameButton(cancel, onClick: onDismiss, color: .BLUE, fontSize: 20)
                    GameButton(confirm, onClick: onConfirm, color: .RED, fontSize: 20)
                }
            }
        }
    }
}

/// Android showed a placeholder full-screen "Rewarded Ad" here. iOS never shows a fake ad: rewarded
/// requests go through GameKit `Ads.rewarded`, so this overlay draws nothing.
struct AdOverlay: View {
    init() {}
    init<T>(_ ads: T) {}
    var body: some View { EmptyView() }
}

/// Short message that slides in near the top and fades away.
struct GameToast: View {
    let message: String?
    @State private var shown: String = ""

    init(_ message: String?) { self.message = message }

    var body: some View {
        ZStack {
            if let message {
                Text(message)
                    .textStyle(GameText.Label.copy(color: .white, fontSize: 16, fontFamily: BodyFont))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(argb: 0xE61A_3A6B), in: RoundedRectangle(cornerRadius: 20, style: .circular))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .circular).stroke(Color.white.opacity(0.6), lineWidth: 2))
                    .transition(.asymmetric(insertion: .scale(scale: 0.7).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.gameSnappy, value: message)
    }
}

/// Soft sky backdrop with drifting clouds shared by menu screens.
struct SkyBackground<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(argb: 0xFF5C_C8FF), Color(argb: 0xFF2D_8EF0), Color(argb: 0xFF1E_6FD9)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            SkyClouds().ignoresSafeArea().allowsHitTesting(false)
            content
        }
    }
}

/// The four drifting clouds (one 40 s linear loop). Frozen when Reduce Motion is on.
private struct SkyClouds: View {
    @State private var start = Date()

    var body: some View {
        let reduce = Motion.reduce
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { tl in
            let drift = reduce ? 0 : (tl.date.timeIntervalSince(start) / 40).truncatingRemainder(dividingBy: 1)
            Canvas { ctx, size in
                let w = size.width
                let p = px
                func cloud(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ a: Double) {
                    let c = Color.white.opacity(a)
                    let r1 = 28 * s * p, r2 = 22 * s * p, r3 = 24 * s * p
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r1, y: y - r1, width: 2 * r1, height: 2 * r1)), with: .color(c))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 30 * s * p - r2, y: y + 8 * s * p - r2, width: 2 * r2, height: 2 * r2)), with: .color(c))
                    ctx.fill(Path(ellipseIn: CGRect(x: x + 30 * s * p - r3, y: y + 6 * s * p - r3, width: 2 * r3, height: 2 * r3)), with: .color(c))
                    ctx.fill(Path(roundedRect: CGRect(x: x - 52 * s * p, y: y + 4 * s * p, width: 104 * s * p, height: 24 * s * p), cornerRadius: 12 * s * p),
                             with: .color(c))
                }
                let span = w + 300 * p
                let d = CGFloat(drift)
                func wrap(_ v: CGFloat) -> CGFloat { v.truncatingRemainder(dividingBy: span) - 150 * p }
                cloud(wrap(d * span + 0.1 * span), size.height * 0.1, 1.4, 0.35)
                cloud(wrap(d * span * 0.7 + 0.6 * span), size.height * 0.22, 1.0, 0.25)
                cloud(wrap(d * span * 1.3 + 0.35 * span), size.height * 0.42, 1.2, 0.18)
                cloud(wrap(d * span * 0.5 + 0.85 * span), size.height * 0.63, 0.9, 0.15)
            }
        }
    }
}
