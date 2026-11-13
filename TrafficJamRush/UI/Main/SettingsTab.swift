import SwiftUI
import GameKit

struct SettingsTab: View {
    let player: PlayerState
    let onOpenDoc: (String) -> Void

    @State private var confirmReset = false

    /// Set once the App Store listing exists; the share text then carries the link.
    static let appStoreURL: String? = nil

    private var progress: ProgressRepository { App.container.progress }
    private var audio: AudioManager { App.container.audio }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabHeader(title: "Settings")
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        SettingsCard {
                            ToggleItem(icon: "speaker.wave.2.fill", color: ArtColor(0xFF2F8CF6), label: "Sound Effects",
                                       value: player.sound, onChange: { progress.setSound($0) })
                            SettingsDivider()
                            ToggleItem(icon: "music.note", color: ArtColor(0xFF8E5CF0), label: "Music",
                                       value: player.music, onChange: { progress.setMusic($0) })
                            SettingsDivider()
                            ToggleItem(icon: "iphone.radiowaves.left.and.right", color: ArtColor(0xFFFF8A1F), label: "Vibration",
                                       value: player.vibration, onChange: { on in
                                           progress.setVibration(on)
                                           // Apply now so the confirmation buzz isn't dropped before the settings sync.
                                           audio.vibrationOn = on
                                           if on { audio.haptic(Haptic.Bump) }
                                       })
                            if ExtrasFeatures.colorBlindPatterns {
                                SettingsDivider()
                                ToggleItem(icon: "eye.fill", color: ArtColor(0xFFEC407A), label: "Colorblind Mode",
                                           value: App.container.extras.colorBlind, onChange: { App.container.extras.setColorBlind($0) })
                                ExtrasColorBlindPreview(on: App.container.extras.colorBlind)
                            }
                        }
                        Spacer().frame(height: 16)
                        SettingsCard {
                            MenuItem(icon: "star.fill", color: ArtColor(0xFFFFB300), label: "Rate Us") {
                                AppLinks.requestReview()
                            }
                            SettingsDivider()
                            ShareLink(item: SettingsTab.shareText) {
                                MenuRow(icon: "square.and.arrow.up.fill", color: ArtColor(0xFF5FC12F), label: "Share with Friends")
                            }
                            .buttonStyle(MenuPressStyle())
                            .simultaneousGesture(TapGesture().onEnded { audio.play(Sfx.Click) })
                            SettingsDivider()
                            MenuItem(icon: "shield.fill", color: ArtColor(0xFF26A69A), label: "Privacy Policy") { onOpenDoc("privacy") }
                            SettingsDivider()
                            MenuItem(icon: "doc.text.fill", color: ArtColor(0xFF5C6BC0), label: "Terms of Service") { onOpenDoc("terms") }
                        }
                        Spacer().frame(height: 16)
                        SettingsCard {
                            MenuItem(icon: "arrow.counterclockwise", color: ArtColor(0xFFF2453D), label: "Reset Progress") {
                                confirmReset = true
                            }
                        }
                        Spacer().frame(height: 22)
                        HStack(spacing: 0) {
                            Mascot(64)
                            Spacer().frame(width: 10)
                            VStack(alignment: .leading, spacing: 0) {
                                GText("Traffic Jam Rush", .Label, color: .white, size: 18, titleFont: true)
                                GText("Version \(SettingsTab.versionName)", .Small, color: .white.opacity(0.85))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(16)
                }
            }

            ConfirmDialog(
                visible: confirmReset,
                title: "Reset?",
                message: "This erases your levels, stars, coins and garage. It can't be undone.",
                confirm: "Reset",
                onConfirm: {
                    progress.resetProgress()
                    App.container.extras.resetProgress()
                    audio.play(Sfx.Whoosh)
                    confirmReset = false
                },
                onDismiss: { confirmReset = false }
            )
        }
    }

    static var versionName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var shareText: String {
        if let url = appStoreURL { return "Can you clear the jam? Play Traffic Jam Rush: \(url)" }
        return "Can you clear the jam? Play Traffic Jam Rush!"
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(
                LinearGradient(colors: [Color(argb: 0xFFFFFDF5), Color(argb: 0xFFFFEFCB)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .padding(4)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Color(argb: 0xFF0D2C6B)).offset(y: 5)
                    RoundedRectangle(cornerRadius: 24).fill(Color.white).padding(.bottom, 2)
                }
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
            )
            .frame(maxWidth: .infinity)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Color(argb: 0xFFEAD7B0)).frame(height: 1.5)
    }
}

private struct Badge: View {
    let icon: String
    let color: ArtColor

    var body: some View {
        ZStack {
            Circle().fill(color.shade(0.65).color).offset(y: 3)
            Circle().fill(LinearGradient(colors: [color.tint(0.3).color, color.color], startPoint: .top, endPoint: .bottom))
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 42, height: 42)
    }
}

private struct ToggleItem: View {
    let icon: String
    let color: ArtColor
    let label: String
    let value: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Badge(icon: icon, color: color)
            Spacer().frame(width: 14)
            GText(label, .Label, size: 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            GameToggle(value, onChange: onChange)
        }
        .padding(.vertical, 10)
    }
}

private struct MenuRow: View {
    let icon: String
    let color: ArtColor
    let label: String

    var body: some View {
        HStack(spacing: 0) {
            Badge(icon: icon, color: color)
            Spacer().frame(width: 14)
            GText(label, .Label, size: 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            GText("›", .Label, color: Color(argb: 0xFF8A4B14), size: 22)
                .frame(width: 30, height: 30)
                .background(Color(argb: 0xFFFFE0A3), in: Circle())
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// `scale(if (pressed) 0.97f else 1f)`.
private struct MenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct MenuItem: View {
    let icon: String
    let color: ArtColor
    let label: String
    let onClick: () -> Void

    var body: some View {
        Button {
            App.container.audio.play(Sfx.Click)
            onClick()
        } label: {
            MenuRow(icon: icon, color: color, label: label)
        }
        .buttonStyle(MenuPressStyle())
    }
}
