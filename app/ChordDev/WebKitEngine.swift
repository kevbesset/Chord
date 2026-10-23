import AppKit
import WebKit
import ChordUI

/// Stand-in engine so the interface can be developed without building Chromium.
/// Never shipped: the real Chord runs on Chromium (see docs/decisions/0003).
final class WebKitEngine: NSObject, ChordWebEngine {
    private let configuration: WKWebViewConfiguration = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        return configuration
    }()

    func makePage() -> ChordWebPage {
        WebKitPage(configuration: configuration)
    }
}

final class WebKitPage: NSObject, ChordWebPage {
    weak var delegate: ChordWebPageDelegate?

    private let webView: WKWebView
    private let uiDelegate = WebKitUIDelegate()
    private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true // Safari's Web Inspector, until Chromium's DevTools
        uiDelegate.page = self
        webView.uiDelegate = uiDelegate
        webView.navigationDelegate = uiDelegate

        observations = [
            webView.observe(\.title) { [weak self] _, _ in self?.notify() },
            webView.observe(\.url) { [weak self] _, _ in self?.notify() },
            webView.observe(\.isLoading) { [weak self] _, _ in self?.notify() },
            webView.observe(\.canGoBack) { [weak self] _, _ in self?.notify() },
            webView.observe(\.canGoForward) { [weak self] _, _ in self?.notify() },
        ]
    }

    var view: NSView { webView }
    var url: URL? { webView.url }
    var title: String? { webView.title }
    var isLoading: Bool { webView.isLoading }
    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }
    private(set) var faviconURL: URL?

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func reloadIgnoringCache() { webView.reloadFromOrigin() }
    func stopLoading() { webView.stopLoading() }

    fileprivate func requestNewTab(_ url: URL) {
        delegate?.page(self, wantsNewTabWith: url)
    }

    fileprivate func shouldFollowLink(to url: URL, modifiers: NSEvent.ModifierFlags) -> Bool {
        delegate?.page?(self, shouldFollowLinkTo: url, modifiers: modifiers) ?? true
    }

    private func notify() {
        delegate?.pageDidUpdate(self)
    }

    /// Asks the loaded document for its icons and keeps the best one for the sidebar,
    /// ranked like ChordUI's FaviconStore: 32 px and up, then unsized, then touch icons.
    fileprivate func findFavicon() {
        let script = """
        (() => {
          const links = [...document.querySelectorAll('link[rel~="icon"], link[rel="shortcut icon"], link[rel^="apple-touch-icon"]')];
          const scored = links.filter(l => l.href && !/mask/i.test(l.rel)).map(l => {
            const size = Math.max(0, ...(l.getAttribute('sizes') || '').toLowerCase().split(' ').map(s => parseInt(s) || 0));
            const touch = /apple-touch/i.test(l.rel);
            const score = touch ? 2000 + (size || 180) : size ? (size >= 32 ? size : 3000 + size) : 1000;
            return { score, href: l.href };
          }).sort((a, b) => a.score - b.score);
          return scored.length ? scored[0].href : new URL('/favicon.ico', location.href).href;
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, let string = result as? String, let url = URL(string: string), url != self.faviconURL else { return }
            self.faviconURL = url
            self.notify()
        }
    }
}

/// Kept separate from WebKitPage: WebKit's delegate protocols are main-actor isolated,
/// ChordWebPage is not, and mixing both on one class trips Swift's concurrency checks.
private final class WebKitUIDelegate: NSObject, WKUIDelegate, WKNavigationDelegate {
    weak var page: WebKitPage?

    /// target=_blank and window.open become a new Chord tab.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            let modifiers = navigationAction.modifierFlags
            if navigationAction.navigationType != .linkActivated
                || page?.shouldFollowLink(to: url, modifiers: modifiers) ?? true {
                page?.requestNewTab(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        page?.findFavicon()
    }

    /// Link clicks go through ChordUI first: ⇧-click opens a Peek, ⌘-click a background tab.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated,
              navigationAction.targetFrame?.isMainFrame == true,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let follow = page?.shouldFollowLink(to: url, modifiers: navigationAction.modifierFlags) ?? true
        decisionHandler(follow ? .allow : .cancel)
    }
}
