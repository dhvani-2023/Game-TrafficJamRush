#if canImport(UIKit)
import UIKit
import SwiftUI
import CoreText
import StoreKit
import WebKit

// MARK: - Fonts

public enum FontRegistry {
    /// Registers every .ttf/.otf in the bundle (no Info.plist `UIAppFonts` list needed).
    public static func registerAll(in bundle: Bundle = .main) {
        for ext in ["ttf", "otf"] {
            for url in bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [] {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            for url in bundle.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? [] {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// A variable font at a given weight axis value (e.g. Fredoka 400–700, Nunito 200–1000).
    public static func variable(_ postScriptName: String, size: CGFloat, weight: CGFloat) -> UIFont {
        let wghtTag: Int = 0x77676874 // 'wght'
        let desc = UIFontDescriptor(name: postScriptName, size: size)
            .addingAttributes([kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [wghtTag: weight]])
        return UIFont(descriptor: desc, size: size)
    }
}

public extension Font {
    /// SwiftUI font from a variable font at a weight-axis value.
    static func variable(_ postScriptName: String, size: CGFloat, weight: CGFloat) -> Font {
        Font(FontRegistry.variable(postScriptName, size: size, weight: weight) as CTFont)
    }
}

// MARK: - Orientation

/// Per-screen orientation control. Apps set `GameAppDelegate` as their app delegate adaptor.
@MainActor
public final class OrientationLock {
    public static let shared = OrientationLock()
    public var mask: UIInterfaceOrientationMask = .portrait

    public func set(_ mask: UIInterfaceOrientationMask, rotateTo preferred: UIInterfaceOrientationMask? = nil) {
        self.mask = mask
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            ws.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            ws.requestGeometryUpdate(.iOS(interfaceOrientations: preferred ?? mask)) { _ in }
        }
    }
}

open class GameAppDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication,
                            supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.shared.mask }
    }
}

// MARK: - Review / links

public enum AppLinks {
    @MainActor
    public static func requestReview() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    @MainActor
    public static func open(_ url: URL) { UIApplication.shared.open(url) }

    @MainActor
    public static func mail(_ address: String, subject: String) {
        let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(address)?subject=\(s)") { UIApplication.shared.open(url) }
    }
}

// MARK: - Legal pages

/// Shows bundled HTML (privacy / terms) offline. Links with the `close` scheme dismiss the page.
public struct LegalWebView: UIViewRepresentable {
    let url: URL
    let onClose: (() -> Void)?

    public init(url: URL, onClose: (() -> Void)? = nil) {
        self.url = url
        self.onClose = onClose
    }

    public func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    public func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.backgroundColor = .clear
        v.navigationDelegate = context.coordinator
        if url.isFileURL {
            v.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            v.load(URLRequest(url: url))
        }
        return v
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}

    public final class Coordinator: NSObject, WKNavigationDelegate {
        let onClose: (() -> Void)?
        init(onClose: (() -> Void)?) { self.onClose = onClose }

        public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.allow); return }
            if url.scheme?.hasSuffix("close") == true || url.host == "close" {
                onClose?()
                decisionHandler(.cancel)
            } else if url.isFileURL || url.scheme == "about" {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }
    }
}

// MARK: - System chrome

public extension View {
    /// Full-screen game chrome: hides the status bar and home indicator, defers edge swipes.
    func gameChrome(deferEdges: Edge.Set = []) -> some View {
        self.statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .defersSystemGestures(on: deferEdges)
    }
}

/// Honours iOS Reduce Motion together with an app's own toggle.
@MainActor
public enum Motion {
    public static var appReduceMotion = false
    public static var reduce: Bool { appReduceMotion || UIAccessibility.isReduceMotionEnabled }
}
#endif
