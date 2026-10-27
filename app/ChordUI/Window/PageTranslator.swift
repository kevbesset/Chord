import AppKit
import NaturalLanguage
import SwiftUI
import Translation

/// Translates pages with Apple's on-device translation, like Safari: into the Mac's
/// language, without sending the page anywhere, and without Google's service (which
/// Chromium's own translation needs, and which ungoogled-chromium leaves out).
///
/// The page's text is read and written back in a world of its own (the page's scripts
/// do not see it), node by node, so that links and styles stay. "Show Original" puts
/// the text back. A page in another language is offered a translation once it has
/// loaded, unless its language was set to "Never".
final class PageTranslator {
    /// Translation of a page needs macOS 26 (a translation session outside SwiftUI).
    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// The language pages are translated into: the Mac's first one.
    static var targetLanguage: Locale.Language {
        Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
    }

    /// The languages the user reads, from the Mac's list: their pages are not offered a
    /// translation.
    static var readLanguageCodes: Set<String> {
        Set(Locale.preferredLanguages.compactMap { Locale.Language(identifier: $0).languageCode?.identifier })
    }

    /// The address each page was translated at: a page that went elsewhere shows its
    /// own text again.
    private let translated = NSMapTable<AnyObject, NSURL>.weakToStrongObjects()
    /// The address each page was last looked at for an offer, to offer once per page.
    private let checked = NSMapTable<AnyObject, NSURL>.weakToStrongObjects()
    /// Each translated page's translation session, to cancel what it still has to do.
    private let sessions = NSMapTable<AnyObject, AnyObject>.weakToStrongObjects()

    func isTranslated(_ page: ChordWebPage) -> Bool {
        guard let url = page.url, let translatedURL = translated.object(forKey: page) else { return false }
        return translatedURL as URL == url
    }

    /// Translates `page`. `done` gets a message to show when it could not, nil when it
    /// worked or the user cancelled.
    func translate(_ page: ChordWebPage, in window: NSWindow?, done: @escaping (String?) -> Void) {
        guard #available(macOS 26, *) else {
            done(String(localized: "Translating pages needs macOS 26 or later.", bundle: .chordUI))
            return
        }
        Task { @MainActor in
            do {
                try await self.run(page, in: window)
                done(nil)
            } catch let error as TranslationFailure {
                done(error.message)
            } catch {
                done(String(localized: "The page could not be translated.", bundle: .chordUI))
            }
        }
    }

    /// Puts the page's own text back.
    func showOriginal(_ page: ChordWebPage) {
        translated.removeObject(forKey: page)
        // What is still waiting to be translated for the page is dropped.
        if #available(macOS 26, *), let session = sessions.object(forKey: page) as? TranslationSession { session.cancel() }
        sessions.removeObject(forKey: page)
        page.evaluateJavaScript?("window.__chordTranslation && window.__chordTranslation.restore()") { _ in }
    }

    /// Once a page has loaded: when it is in another language than the Mac's, one that
    /// can be translated and was not set to "Never", `ask` gets the question. `failed`
    /// gets what to say when the translation, once accepted, could not be done.
    func offerIfForeign(_ page: ChordWebPage, settings: ChordSettings, ask: @escaping (ChordPermissionRequest) -> Void,
                        failed: @escaping (String) -> Void) {
        guard #available(macOS 26, *), let url = page.url, ["http", "https"].contains(url.scheme ?? ""),
              !page.isLoading, page.evaluateJavaScript != nil else { return }
        if let last = checked.object(forKey: page), last as URL == url { return }
        checked.setObject(url as NSURL, forKey: page)
        Task { @MainActor [weak self, weak page] in
            guard let self, let page, let source = await self.language(of: page), page.url == url,
                  !self.isTranslated(page) else { return }
            let target = Self.targetLanguage
            guard let code = source.languageCode?.identifier, !Self.readLanguageCodes.contains(code),
                  !settings.neverTranslate.contains(code) else { return }
            guard await LanguageAvailability().status(from: source, to: target) != .unsupported else { return }
            let name = Self.name(of: source)
            let offer = TranslationOffer(url: url, languageName: name, targetName: Self.name(of: target))
            offer.onAllow = { [weak self, weak page] in
                guard let self, let page else { return }
                self.translate(page, in: page.view.window) { message in
                    if let message { failed(message) }
                }
            }
            offer.onBlock = { settings.neverTranslate.insert(code) }
            ask(offer)
        }
    }

    // MARK: - Translating

    private struct TranslationFailure: Error {
        let message: String?
    }

    @available(macOS 26, *)
    @MainActor
    private func run(_ page: ChordWebPage, in window: NSWindow?) async throws {
        guard let source = await language(of: page) else {
            throw TranslationFailure(message: String(localized: "The page's language could not be recognised.", bundle: .chordUI))
        }
        let target = Self.targetLanguage
        guard source.languageCode != target.languageCode else {
            throw TranslationFailure(message: String(localized: "The page is already in \(Self.name(of: target)).", bundle: .chordUI))
        }
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            // The languages are not on this Mac yet: macOS asks to download them.
            guard let window else { throw TranslationFailure(message: nil) }
            try await downloadLanguages(from: source, to: target, in: window)
        default:
            throw TranslationFailure(message: String(localized: "This page cannot be translated into \(Self.name(of: target)) on this Mac.", bundle: .chordUI))
        }
        let session = TranslationSession(installedSource: source, target: target)
        guard let collected = await evaluate(page, Self.collectScript) as? [Any] else {
            throw TranslationFailure(message: String(localized: "The page could not be translated.", bundle: .chordUI))
        }
        let texts = Self.blocks(collected)
        let url = page.url
        if let url { translated.setObject(url as NSURL, forKey: page) }
        sessions.setObject(session, forKey: page)
        let done: Int
        do {
            done = try await translate(texts, with: session, in: page, at: url)
        } catch {
            showOriginal(page)
            throw error
        }
        if done == 0, !texts.isEmpty {
            translated.removeObject(forKey: page)
            throw TranslationFailure(message: String(localized: "The page could not be translated.", bundle: .chordUI))
        }
        followChanges(of: page, at: url, with: session)
    }

    /// Texts of the page that read together (a paragraph, a list item, a title), as
    /// (index, text): a link or a word in bold is a text of its own.
    typealias Block = [(Int, String)]

    /// The blocks as the script gives them: lists of [index, text] pairs.
    private static func blocks(_ value: [Any]) -> [Block] {
        value.compactMap { block in
            (block as? [[Any]])?.compactMap { pair in
                guard pair.count == 2, let index = (pair[0] as? NSNumber)?.intValue, let text = pair[1] as? String else { return nil }
                return (index, text)
            }
        }.filter { !$0.isEmpty }
    }

    /// Translates the page's blocks, what is on screen first, written back a few at a
    /// time. A block goes as one text, its pieces tagged (<t1>…</t1>), so that a link
    /// is translated within its sentence and keeps its place. A request that gets no
    /// answer stops the translation (macOS's translation service is stuck), with a
    /// message. Returns how many texts were translated.
    @available(macOS 26, *)
    @MainActor
    private func translate(_ blocks: [Block], with session: TranslationSession, in page: ChordWebPage, at url: URL?) async throws -> Int {
        // Very long blocks (a menu in a single element) go in parts.
        let parts = blocks.flatMap { block in
            stride(from: 0, to: block.count, by: 24).map { Array(block[$0..<min($0 + 24, block.count)]) }
        }
        var done = 0
        let perRequest = 2
        for start in stride(from: 0, to: parts.count, by: perRequest) {
            guard isTranslated(page) else { break }
            let group = Array(parts[start..<min(start + perRequest, parts.count)])
            guard let pairs = await withTimeout(seconds: 60, { await self.translations(of: group, with: session) }) else {
                session.cancel()
                throw TranslationFailure(message: String(localized: "macOS's translation is not answering. Try again later, or after restarting the Mac.", bundle: .chordUI))
            }
            done += pairs.count
            guard !pairs.isEmpty, let data = try? JSONSerialization.data(withJSONObject: pairs.map { [$0.0, $0.1] }),
                  let json = String(data: data, encoding: .utf8) else { continue }
            _ = await evaluate(page, "window.__chordTranslation && window.__chordTranslation.apply(\(json))")
        }
        return done
    }

    /// The blocks' translations, by text. A request fails as a whole when one of its texts
    /// cannot be translated (a word in another language, a symbol): it is split until
    /// those are found, and they stay as they are.
    @available(macOS 26, *)
    @MainActor
    private func translations(of blocks: [Block], with session: TranslationSession) async -> [(Int, String)] {
        guard !blocks.isEmpty else { return [] }
        let requests = blocks.enumerated().map {
            TranslationSession.Request(sourceText: Self.tagged($0.element), clientIdentifier: String($0.offset))
        }
        do {
            var pairs: [(Int, String)] = []
            for response in try await session.translations(from: requests) {
                guard let position = response.clientIdentifier.flatMap(Int.init), blocks.indices.contains(position) else { continue }
                pairs += Self.untagged(response.targetText, for: blocks[position])
            }
            return pairs
        } catch {
            // Halves of the request, or the texts of a single block one by one.
            let smaller = blocks.count > 1 ? [Array(blocks[..<(blocks.count / 2)]), Array(blocks[(blocks.count / 2)...])]
                : blocks[0].count > 1 ? [blocks[0].map { [$0] }] : []
            var pairs: [(Int, String)] = []
            for part in smaller { pairs += await translations(of: part, with: session) }
            return pairs
        }
    }

    /// A block as one text: its pieces in numbered tags, or the piece alone.
    static func tagged(_ block: Block) -> String {
        guard block.count > 1 else { return block.first?.1 ?? "" }
        return block.enumerated().map { "<t\($0.offset + 1)>\($0.element.1)</t\($0.offset + 1)>" }.joined(separator: " ")
    }

    /// The translation of a tagged block, piece by piece. Words the translation moved
    /// out of the tags join the piece before; a piece whose tag got lost (merged with
    /// its neighbour) is left empty, and with no tag at all the whole translation goes
    /// to the longest piece (plain text rather than a word in bold): translating the pieces alone would lose their sentence
    /// ("Windows" into "Fenêtres").
    static func untagged(_ text: String, for block: Block) -> [(Int, String)] {
        let clean = { (words: String) in
            words.replacingOccurrences(of: "</?t\\d+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard block.count > 1 else { return block.first.map { [($0.0, clean(text))] } ?? [] }
        guard let expression = try? NSRegularExpression(pattern: "<t(\\d+)>([\\s\\S]*?)</t\\d+>") else { return [] }
        let source = text as NSString
        var pieces = [String](repeating: "", count: block.count)
        var last: Int?
        var leading = ""
        var cursor = 0
        func add(_ words: String, to index: Int) {
            guard !words.isEmpty else { return }
            pieces[index] = pieces[index].isEmpty ? words : pieces[index] + " " + words
        }
        func outside(_ range: NSRange) {
            let words = clean(source.substring(with: range))
            if let last { add(words, to: last) } else if !words.isEmpty { leading += words + " " }
        }
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            outside(NSRange(location: cursor, length: match.range.location - cursor))
            let number = Int(source.substring(with: match.range(at: 1))) ?? 0
            let index = (1...block.count).contains(number) ? number - 1 : (last ?? 0)
            add(clean(source.substring(with: match.range(at: 2))), to: index)
            last = index
            cursor = match.range.location + match.range.length
        }
        if last == nil {
            let longest = block.indices.max { block[$0].1.count < block[$1].1.count } ?? 0
            pieces[longest] = clean(text)
            return zip(block, pieces).map { ($0.0, $1) }
        }
        outside(NSRange(location: cursor, length: source.length - cursor))
        if !leading.isEmpty { pieces[0] = clean(leading + pieces[0]) }
        return zip(block, pieces).map { ($0.0, $1) }
    }

    /// The work's result, or nil when it takes longer than `seconds` (it is then left
    /// to finish on its own).
    @MainActor
    private func withTimeout<T>(seconds: Double, _ work: @escaping @MainActor () async -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            var finished = false
            Task { @MainActor in
                let result = await work()
                if !finished { finished = true; continuation.resume(returning: result) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                if !finished { finished = true; continuation.resume(returning: nil) }
            }
        }
    }

    /// A batch fails as a whole when one of its texts cannot be translated (a word in
    /// another language, a symbol): it is split in two until those are found, and they
    /// stay as they are.
    @available(macOS 26, *)
    @MainActor
    private func translations(of items: ArraySlice<(Int, String)>, with session: TranslationSession) async -> [(Int, String)] {
        guard !items.isEmpty else { return [] }
        let requests = items.map { TranslationSession.Request(sourceText: $0.1, clientIdentifier: String($0.0)) }
        do {
            let responses = try await session.translations(from: requests)
            return responses.compactMap { response in
                response.clientIdentifier.flatMap(Int.init).map { ($0, response.targetText) }
            }
        } catch {
            guard items.count > 1 else { return [] }
            let middle = items.startIndex + items.count / 2
            let first = await translations(of: items[..<middle], with: session)
            let second = await translations(of: items[middle...], with: session)
            return first + second
        }
    }

    /// Text the page adds or changes once translated (a single-page app, a list that
    /// loads more) is translated too, every second, until the page shows its original
    /// text or goes elsewhere.
    @available(macOS 26, *)
    @MainActor
    private func followChanges(of page: ChordWebPage, at url: URL?, with session: TranslationSession) {
        Task { @MainActor [weak self, weak page] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let page, page.url == url, self.isTranslated(page),
                      let pending = await self.evaluate(page, "window.__chordTranslation ? window.__chordTranslation.take() : null") as? [Any]
                else { return }
                let blocks = Self.blocks(pending)
                if !blocks.isEmpty { _ = try? await self.translate(blocks, with: session, in: page, at: url) }
            }
        }
    }

    /// Asks macOS to download the languages, through SwiftUI's translation task (the
    /// only way to ask): a tiny view in the window hosts it while macOS shows its sheet.
    @MainActor
    private func downloadLanguages(from source: Locale.Language, to target: Locale.Language, in window: NSWindow) async throws {
        guard #available(macOS 15, *), let contentView = window.contentView else { throw TranslationFailure(message: nil) }
        let configuration = TranslationSession.Configuration(source: source, target: target)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var host: NSView?
            let view = TranslationDownloadView(configuration: configuration) { error in
                host?.removeFromSuperview()
                host = nil
                if error != nil {
                    // Cancelled, or the download failed: nothing more to say than macOS did.
                    continuation.resume(throwing: TranslationFailure(message: nil))
                } else {
                    continuation.resume()
                }
            }
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
            contentView.addSubview(hosting)
            host = hosting
        }
    }

    // MARK: - Reading the page

    /// The page's language: recognised from its text, else what the page declares.
    @MainActor
    private func language(of page: ChordWebPage) async -> Locale.Language? {
        let script = "[document.documentElement.lang || '', (document.body ? document.body.innerText : '').slice(0, 4000)]"
        guard let result = await evaluate(page, script) as? [Any], result.count == 2 else { return nil }
        let declared = (result[0] as? String) ?? ""
        let text = (result[1] as? String) ?? ""
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let best = recognizer.languageHypotheses(withMaximum: 1).first, best.value > 0.6 {
            return Locale.Language(identifier: best.key.rawValue)
        }
        return declared.isEmpty ? nil : Locale.Language(identifier: declared)
    }

    @MainActor
    private func evaluate(_ page: ChordWebPage, _ script: String) async -> Any? {
        guard let evaluate = page.evaluateJavaScript else { return nil }
        return await withCheckedContinuation { continuation in
            evaluate(script) { result in continuation.resume(returning: result) }
        }
    }

    /// Whether `page` can be offered a translation at all: a web page, on a Mac that
    /// translates.
    static func canTranslate(_ page: ChordWebPage) -> Bool {
        guard isAvailable, page.evaluateJavaScript != nil, let scheme = page.url?.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// The Mac's language, named in the interface's language ("français").
    static var targetName: String { name(of: targetLanguage) }

    static func name(of language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        return Locale.chordUI.localizedString(forLanguageCode: code) ?? code
    }

    /// Collects the page's text nodes worth translating (not code, not fields, not
    /// what the page marks translate="no"), keeps them and their spacing, and returns
    /// them in blocks, what is on screen first. `apply` writes translations back by index, `restore` the originals,
    /// `take` gives the text the page has added or changed since (with new indexes),
    /// in blocks too.
    private static let collectScript = #"""
    (() => {
      const previous = window.__chordTranslation;
      if (previous) previous.restore();
      const skipped = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'CODE', 'PRE', 'KBD', 'SAMP', 'VAR',
                               'TEXTAREA', 'INPUT', 'SELECT', 'OPTION', 'SVG', 'MATH', 'IFRAME']);
      const filter = {
        acceptNode(node) {
          if (!/\p{L}/u.test(node.nodeValue)) return NodeFilter.FILTER_REJECT;
          const parent = node.parentElement;
          if (!parent || parent.closest('[translate="no"], .notranslate, [contenteditable=""], [contenteditable="true"]')) return NodeFilter.FILTER_REJECT;
          for (let element = parent; element; element = element.parentElement) {
            if (skipped.has(element.tagName.toUpperCase())) return NodeFilter.FILTER_REJECT;
          }
          return NodeFilter.FILTER_ACCEPT;
        }
      };
      const nodes = [], leads = [], trails = [], originals = [];
      const indexes = new Map(), written = new WeakMap(), queue = new Set();
      // Keeps a node and its spacing; returns its index and its text on one line.
      const keep = node => {
        const value = node.nodeValue;
        let index = indexes.get(node);
        if (index === undefined) { index = nodes.length; nodes.push(node); indexes.set(node, index); }
        originals[index] = value;
        leads[index] = value.slice(0, value.length - value.trimStart().length);
        trails[index] = value.slice(value.trimEnd().length);
        return [index, value.trim().replace(/\s+/g, ' ')];
      };
      // The element a text reads in: its nearest ancestor that is not inline (a
      // paragraph, a list item, a title, a button).
      const blockElements = new Map();
      const blockOf = node => {
        let element = node.parentElement;
        while (element && element !== document.body) {
          let inline = blockElements.get(element);
          if (inline === undefined) {
            const display = getComputedStyle(element).display;
            inline = display.startsWith('inline') || display === 'contents';
            blockElements.set(element, inline);
          }
          if (!inline) return element;
          element = element.parentElement;
        }
        return element || document.documentElement;
      };
      // The texts in blocks, in the order of the page.
      const group = list => {
        const blocks = new Map();
        for (const node of list) {
          const block = blockOf(node);
          if (!blocks.has(block)) blocks.set(block, []);
          blocks.get(block).push(node);
        }
        return [...blocks.entries()];
      };
      const found = [];
      const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, filter);
      let characters = 0;
      while (walker.nextNode() && found.length < 4000 && characters < 300000) {
        found.push(walker.currentNode);
        characters += walker.currentNode.nodeValue.length;
      }
      // What is on screen first, then what follows below, then what is hidden (menus).
      const range = document.createRange();
      const rank = node => {
        range.selectNodeContents(node);
        const box = range.getBoundingClientRect();
        if (!box.width && !box.height) return 2;
        return box.bottom > 0 && box.top < innerHeight ? 0 : 1;
      };
      // On-device translation takes seconds per paragraph: what is on screen goes
      // first, the rest as it comes into view (scrolled to, a menu opened).
      const waiting = new Map();
      const watcher = new IntersectionObserver(entries => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          for (const node of waiting.get(entry.target) || []) queue.add(node);
          waiting.delete(entry.target);
          watcher.unobserve(entry.target);
        }
      }, { rootMargin: '50% 0px' });
      // The page's own content (its main part, an article) before its menus, and
      // what is read (titles, paragraphs, lists) before the controls around it.
      const main = document.querySelector('main, [role="main"], article');
      const reading = new Set(['P', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'LI', 'BLOCKQUOTE', 'FIGCAPTION', 'DD', 'DT', 'TD', 'TH']);
      const near = [];
      for (const [element, block] of group(found)) {
        const box = element.getBoundingClientRect();
        if (Math.min(...block.map(rank)) < 2 && box.top < innerHeight * 1.5 && box.bottom > -innerHeight / 2) {
          const onScreen = box.top < innerHeight && box.bottom > 0;
          near.push([(main && main.contains(element) ? 0 : 2) + (reading.has(element.tagName) ? 0 : 1), onScreen ? 0 : 1, near.length, block]);
        } else {
          waiting.set(element, block);
          watcher.observe(element);
        }
      }
      const ordered = near.sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2]).map(entry => entry[3].map(keep));
      // What the page writes afterwards: new text, or text it changed (not ours).
      const consider = node => {
        if (written.get(node) === node.nodeValue || nodes.length + queue.size >= 8000) return;
        if (filter.acceptNode(node) === NodeFilter.FILTER_ACCEPT) queue.add(node);
      };
      const observer = new MutationObserver(records => {
        for (const record of records) {
          if (record.type === 'characterData') { consider(record.target); continue; }
          for (const added of record.addedNodes) {
            if (added.nodeType === Node.TEXT_NODE) consider(added);
            else if (added.nodeType === Node.ELEMENT_NODE) {
              const inner = document.createTreeWalker(added, NodeFilter.SHOW_TEXT, filter);
              while (inner.nextNode()) consider(inner.currentNode);
            }
          }
        }
      });
      observer.observe(document.body || document.documentElement, { childList: true, subtree: true, characterData: true });
      window.__chordTranslation = {
        apply(pairs) {
          for (const [index, text] of pairs) {
            const node = nodes[index];
            if (!node || !node.isConnected) continue;
            const value = leads[index] + text + trails[index];
            node.nodeValue = value;
            written.set(node, value);
          }
        },
        take() {
          const pending = group([...queue].filter(node => node.isConnected)).map(([, block]) => block.map(keep));
          queue.clear();
          return pending;
        },
        restore() {
          observer.disconnect();
          watcher.disconnect();
          nodes.forEach((node, index) => { if (node.isConnected && written.get(node) === node.nodeValue) node.nodeValue = originals[index]; });
          window.__chordTranslation = null;
        },
      };
      return ordered;
    })()
    """#
}

/// Hosts SwiftUI's translation task, whose session asks macOS to download languages.
@available(macOS 15, *)
private struct TranslationDownloadView: View {
    let configuration: TranslationSession.Configuration
    let done: (Error?) -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(configuration) { session in
                do {
                    try await session.prepareTranslation()
                    done(nil)
                } catch {
                    done(error)
                }
            }
    }
}

/// "Translate this page into French?" (a page in Japanese), asked like a site's
/// permission, from the site controls: "Translate", "Never" (for this language) and
/// "Not Now".
final class TranslationOffer: NSObject, ChordPermissionRequest {
    /// The address of the page it was asked for.
    let url: URL
    let site: String
    let asks: [String] = []
    let symbol = "translate"
    var onCancel: (() -> Void)?
    var onAllow: (() -> Void)?
    var onBlock: (() -> Void)?
    let question: String?
    let detail: String?
    let allowTitle: String?
    let blockTitle: String?

    init(url: URL, languageName: String, targetName: String) {
        self.url = url
        site = url.host ?? ""
        question = String(localized: "Translate this page into \(targetName)?", bundle: .chordUI)
        detail = String(localized: "Page in \(languageName)", bundle: .chordUI)
        allowTitle = String(localized: "Translate", bundle: .chordUI)
        blockTitle = String(localized: "Never", bundle: .chordUI)
    }

    func allow() { onAllow?() }
    func block() { onBlock?() }
    func dismiss() {}

    /// The question no longer stands (another tab, the page translated from the menu):
    /// the prompt takes it down, unanswered.
    func withdraw() { onCancel?() }
}
