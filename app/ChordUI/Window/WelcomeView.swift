import AppKit

/// The first launch, on one glass panel over the window: bring over another browser
/// (Arc first, as it is the one Chord follows), make Chord the default browser, and the
/// shortcuts to know. Shown once, on a Chord with nothing open yet.
final class WelcomeView: NSView {
    var onImportArc: (() -> Void)?
    var onImportBrowser: ((BrowserImport.Source) -> Void)?
    var onDone: (() -> Void)?

    private let scrim = ScrimView()
    private let host = ShadowHostView()
    private let panel = NSVisualEffectView()
    private let shortcuts = ShortcutSheetView()
    private let defaultButton = NSButton()
    private let defaultStatus = NSTextField(labelWithString: "")
    private var sources: [BrowserImport.Source] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    private func build() {
        scrim.dims = true
        host.cornerRadius = 20
        host.configureShadow(opacity: 0.2, radius: 10, offsetY: -4)
        host.configureAmbientShadow(opacity: 0.35, radius: 70, offsetY: -30)
        panel.material = .popover
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 20
        panel.layer?.masksToBounds = true
        panel.layer?.borderWidth = 0.5
        panel.layer?.borderColor = NSColor.separatorColor.cgColor

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        // Decorative: the title says it.
        icon.setAccessibilityRole(.unknown)
        let title = NSTextField(labelWithString: String(localized: "Welcome to Chord", bundle: .chordUI))
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: String(localized: "Arc's sidebar, Spaces and command bar, native on the Mac. Three things, and you're home.", bundle: .chordUI))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        let column = NSStackView(views: [icon, title, subtitle,
                                         section(String(localized: "Bring your browser", bundle: .chordUI), importRow()),
                                         section(String(localized: "Default browser", bundle: .chordUI), defaultRow()),
                                         section(String(localized: "Shortcuts", bundle: .chordUI), shortcuts),
                                         doneRow()])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 18
        column.setCustomSpacing(8, after: icon)
        column.setCustomSpacing(6, after: title)
        column.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 24, right: 32)
        column.translatesAutoresizingMaskIntoConstraints = false

        for view in [scrim, host] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        panel.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(panel)
        panel.addSubview(column)
        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.centerXAnchor.constraint(equalTo: centerXAnchor),
            host.centerYAnchor.constraint(equalTo: centerYAnchor),
            host.widthAnchor.constraint(equalToConstant: 520),
            host.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, constant: -40),
            panel.topAnchor.constraint(equalTo: host.topAnchor),
            panel.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            column.topAnchor.constraint(equalTo: panel.topAnchor),
            column.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
        ])
        shortcuts.refresh()
        refreshDefaultBrowser()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Welcome to Chord", bundle: .chordUI))
    }

    /// A small heading above its row.
    private func section(_ title: String, _ content: NSView) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, content])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        return stack
    }

    /// Arc first when it is on this Mac, then the other browsers found.
    private func importRow() -> NSView {
        var buttons: [NSView] = []
        if ArcImport.isAvailable {
            let arc = NSButton(title: String(localized: "Import from Arc", bundle: .chordUI), target: self, action: #selector(importArc))
            arc.bezelStyle = .push
            arc.keyEquivalent = "\r"
            buttons.append(arc)
        }
        sources = BrowserImport.installed
        if !sources.isEmpty {
            let other = NSPopUpButton(frame: .zero, pullsDown: true)
            other.addItem(withTitle: ArcImport.isAvailable ? String(localized: "Another browser", bundle: .chordUI) : String(localized: "Import from…", bundle: .chordUI))
            for (index, source) in sources.enumerated() {
                other.addItem(withTitle: source.name)
                other.lastItem?.tag = index
                other.lastItem?.target = self
                other.lastItem?.action = #selector(importOther(_:))
            }
            buttons.append(other)
        }
        if buttons.isEmpty {
            let none = NSTextField(labelWithString: String(localized: "No other browser found on this Mac.", bundle: .chordUI))
            none.font = .systemFont(ofSize: 12)
            none.textColor = .secondaryLabelColor
            buttons.append(none)
        }
        let row = NSStackView(views: buttons)
        row.spacing = 10
        return row
    }

    private func defaultRow() -> NSView {
        defaultButton.title = String(localized: "Make Chord the Default Browser", bundle: .chordUI)
        defaultButton.bezelStyle = .push
        defaultButton.target = self
        defaultButton.action = #selector(makeDefault)
        defaultStatus.font = .systemFont(ofSize: 12)
        defaultStatus.textColor = .secondaryLabelColor
        let row = NSStackView(views: [defaultButton, defaultStatus])
        row.spacing = 10
        return row
    }

    private func doneRow() -> NSView {
        let done = NSButton(title: String(localized: "Start Browsing", bundle: .chordUI), target: self, action: #selector(finish))
        done.bezelStyle = .push
        done.controlSize = .large
        if !ArcImport.isAvailable { done.keyEquivalent = "\r" }
        return done
    }

    /// esc closes the welcome, like "Start Browsing".
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            onDone?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func refreshDefaultBrowser() {
        let isDefault = DefaultBrowser.isChord
        defaultButton.isHidden = isDefault
        defaultStatus.stringValue = isDefault
            ? String(localized: "Chord is your default browser", bundle: .chordUI)
            : DefaultBrowser.currentName.map { String(localized: "Links from other apps open in \($0) for now.", bundle: .chordUI) } ?? ""
    }

    @objc private func importArc() {
        onImportArc?()
    }

    @objc private func importOther(_ sender: NSMenuItem) {
        guard sources.indices.contains(sender.tag) else { return }
        onImportBrowser?(sources[sender.tag])
    }

    @objc private func makeDefault() {
        defaultButton.isEnabled = false
        DefaultBrowser.makeChord { [weak self] _ in
            self?.defaultButton.isEnabled = true
            self?.refreshDefaultBrowser()
        }
    }

    @objc private func finish() {
        onDone?()
    }
}
