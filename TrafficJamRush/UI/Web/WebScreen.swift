import SwiftUI
import GameKit

/// Shows one of the bundled HTML documents (Resources/Legal), offline.
struct WebScreen: View {
    let doc: String
    let onBack: () -> Void

    var body: some View {
        let (title, file) = doc == "terms"
            ? ("Terms of Service", "terms_of_service")
            : ("Privacy Policy", "privacy_policy")
        VStack(spacing: 0) {
            ZStack {
                RoundButton(onClick: onBack, size: 44) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                OutlinedText(title, style: GameText.Title, outline: Color(argb: 0xFF0D2C6B), strokeWidth: 6, fontSize: 24)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                LinearGradient(colors: [Color(argb: 0xFF1C5BD0), Color(argb: 0xFF2F7CF6)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            )
            if let url = WebScreen.url(file) {
                LegalWebView(url: url, onClose: onBack)
            } else {
                Spacer()
            }
        }
        .background(Color(argb: 0xFF1E88E5).ignoresSafeArea())
    }

    static func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "html", subdirectory: "Legal")
            ?? Bundle.main.url(forResource: name, withExtension: "html")
    }
}
