import SwiftUI

// MARK: - Springs

public extension Animation {
    /// Compose `spring(dampingRatio, stiffness)` → SwiftUI interpolating spring with the same physics (mass 1).
    static func compose(dampingRatio: Double = 1, stiffness: Double = 1500) -> Animation {
        .interpolatingSpring(mass: 1, stiffness: stiffness, damping: 2 * dampingRatio * stiffness.squareRoot())
    }

    /// Default game UI spring: quick with a touch of overshoot.
    static var gamePop: Animation { .spring(response: 0.38, dampingFraction: 0.72) }
    static var gameSoft: Animation { .spring(response: 0.5, dampingFraction: 0.86) }
    static var gameSnappy: Animation { .spring(response: 0.26, dampingFraction: 0.8) }
}

// MARK: - Press feedback

/// Press-down scale with spring release, plus an optional tick/haptic hook.
public struct PressScaleStyle: ButtonStyle {
    let scale: CGFloat
    let onPress: (() -> Void)?

    public init(scale: CGFloat = 0.94, onPress: (() -> Void)? = nil) {
        self.scale = scale
        self.onPress = onPress
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.32, dampingFraction: 0.5),
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { onPress?() } }
    }
}

// MARK: - Outlined game text

/// Text with a solid outline and drop shadow (the chunky "game title" look used on Android via stroked TextStyle).
public struct OutlinedText: View {
    let text: String
    let font: Font
    let fill: AnyShapeStyle
    let stroke: Color
    let strokeWidth: CGFloat
    let shadow: Color
    let shadowY: CGFloat

    public init(_ text: String, font: Font, fill: some ShapeStyle = Color.white, stroke: Color = .black,
                strokeWidth: CGFloat = 3, shadow: Color = .black.opacity(0.25), shadowY: CGFloat = 2) {
        self.text = text
        self.font = font
        self.fill = AnyShapeStyle(fill)
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.shadow = shadow
        self.shadowY = shadowY
    }

    public var body: some View {
        let base = Text(text).font(font)
        ZStack {
            // outline: 16 offset copies give a round, even stroke
            ForEach(0..<16, id: \.self) { i in
                let a = Double(i) / 16 * 2 * .pi
                base.foregroundStyle(stroke)
                    .offset(x: CGFloat(cos(a)) * strokeWidth, y: CGFloat(sin(a)) * strokeWidth)
            }
            base.foregroundStyle(fill)
        }
        .compositingGroup()
        .shadow(color: shadow, radius: 0, x: 0, y: shadowY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Count-up number

/// Animates an integer change with easing (coins, score).
public struct CountingText: View, Animatable {
    var value: Double
    let format: (Int) -> String

    public init(value: Int, format: @escaping (Int) -> String = { "\($0)" }) {
        self.value = Double(value)
        self.format = format
    }

    public var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    public var body: some View { Text(format(Int(value.rounded()))) }
}

public extension Int {
    /// "2,000" grouping like Android's NumberFormat in English.
    var grouped: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// MARK: - Color helpers

public extension Color {
    /// 0xAARRGGBB like Android `Color(0xFF...)`.
    init(argb: UInt32) {
        self.init(.sRGB,
                  red: Double((argb >> 16) & 0xFF) / 255,
                  green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255,
                  opacity: Double((argb >> 24) & 0xFF) / 255)
    }

    /// 0xRRGGBB.
    init(rgb: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: alpha)
    }

    /// "#RRGGBB" or "#AARRGGBB".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0
        if s.count == 8 { self.init(argb: v) } else { self.init(rgb: v) }
    }
}
