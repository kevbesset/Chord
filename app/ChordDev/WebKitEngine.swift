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
        for scheme in InternalPageHandler.schemes {
            configuration.setURLSchemeHandler(InternalPageHandler.shared, forURLScheme: scheme)
        }
        return configuration
    }()

    func makePage() -> ChordWebPage {
        WebKitPage(configuration: configuration)
    }

    func cancelDownload(_ id: String) {
        WebKitDownloads.shared.cancel(id)
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
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard navigationAction.navigationType == .linkActivated,
              navigationAction.targetFrame?.isMainFrame == true,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let follow = page?.shouldFollowLink(to: url, modifiers: navigationAction.modifierFlags) ?? true
        decisionHandler(follow ? .allow : .cancel)
    }

    /// Files the page cannot show, or sent as attachments, are downloaded.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let attachment = disposition.lowercased().hasPrefix("attachment")
        decisionHandler(!navigationResponse.canShowMIMEType || attachment ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        if let page { WebKitDownloads.shared.adopt(download, from: page) }
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        if let page { WebKitDownloads.shared.adopt(download, from: page) }
    }
}

/// Saves downloads in ~/Downloads and reports them to the page's delegate, like
/// Chromium's download manager will in the real browser.
private final class WebKitDownloads: NSObject, WKDownloadDelegate {
    static let shared = WebKitDownloads()

    private struct Entry {
        let id: String
        weak var page: WebKitPage?
        var destination: URL?
        var observation: NSKeyValueObservation?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var downloads: [String: WKDownload] = [:]

    func adopt(_ download: WKDownload, from page: WebKitPage) {
        download.delegate = self
        let id = UUID().uuidString
        entries[ObjectIdentifier(download)] = Entry(id: id, page: page)
        downloads[id] = download
    }

    func cancel(_ id: String) {
        downloads[id]?.cancel { _ in }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor (URL?) -> Void) {
        guard var entry = entries[ObjectIdentifier(download)] else {
            completionHandler(nil)
            return
        }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let destination = Self.unusedURL(in: folder, for: suggestedFilename)
        entry.destination = destination
        let id = entry.id
        entry.observation = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            DispatchQueue.main.async { self?.report(id) { page in page.delegate?.page?(page, download: id, didProgress: fraction) } }
        }
        entries[ObjectIdentifier(download)] = entry
        completionHandler(destination)
        if let page = entry.page { page.delegate?.page?(page, didStartDownload: id, destination: destination) }
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(download, success: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(download, success: false)
    }

    private func finish(_ download: WKDownload, success: Bool) {
        guard let entry = entries.removeValue(forKey: ObjectIdentifier(download)) else { return }
        downloads[entry.id] = nil
        entry.observation?.invalidate()
        if let page = entry.page {
            page.delegate?.page?(page, download: entry.id, didFinishAt: success ? entry.destination : nil)
        }
    }

    private func report(_ id: String, _ body: (WebKitPage) -> Void) {
        guard let page = entries.values.first(where: { $0.id == id })?.page else { return }
        body(page)
    }

    /// "report.pdf", then "report (1).pdf", "report (2).pdf"… like Safari.
    private static func unusedURL(in folder: URL, for filename: String) -> URL {
        let name = filename.isEmpty ? "Téléchargement" : filename
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)")
            index += 1
        }
        return candidate
    }
}

/// Chromium's internal pages (`chrome://extensions`, `chrome://settings`…) do not exist in
/// WebKit: rather than an error, say that they come with the Chromium engine.
final class InternalPageHandler: NSObject, WKURLSchemeHandler {
    static let shared = InternalPageHandler()
    static let schemes = ["chrome", "chrome-extension", "chrome-untrusted", "devtools"]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let address = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let html = """
        <!doctype html>
        <html lang="fr"><head><meta charset="utf-8"><title>\(address)</title>
        <style>
          :root { color-scheme: light dark; }
          body { margin: 0; height: 100vh; display: flex; align-items: center; justify-content: center;
                 font: 14px -apple-system, system-ui; background: Canvas; color: CanvasText; }
          main { max-width: 440px; padding: 24px; text-align: center; }
          h1 { font-size: 20px; font-weight: 600; margin: 0 0 10px; }
          p { margin: 0 0 8px; line-height: 1.5; opacity: .7; }
          code { font: 13px ui-monospace, SFMono-Regular, monospace; }
        </style></head>
        <body><main>
          <h1>Page interne de Chromium</h1>
          <p><code>\(address)</code> sera disponible avec le moteur Chromium de Chord.</p>
          <p>Chord Dev utilise un moteur WebKit provisoire pour développer l'interface : il n'a pas ces pages.</p>
        </main></body></html>
        """
        let data = Data(html.utf8)
        task.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
