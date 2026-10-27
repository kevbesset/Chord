import AppKit

/// The sidebar's media controls, like Arc's mini player: the tab playing sound or video
/// out of sight, with play / pause and mute. A click on its title goes back to it.
final class MediaControlsView: NSView {
    var onSelect: ((Tab) -> Void)?
    var onTogglePlayback: ((Tab) -> Void)?
    var onToggleMute: ((Tab) -> Void)?

    private var tab: Tab?
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let site = NSTextField(labelWithString: "")
    private lazy var playButton = IconButton(symbol: "pause.fill", label: String(localized: "Pause", bundle: .chordUI), target: self, action: #selector(playClicked), size: 26, pointSize: 12)
    private lazy var muteButton = IconButton(symbol: "speaker.wave.2.fill", label: String(localized: "Mute Tab", bundle: .chordUI), target: self, action: #selector(muteClicked), size: 26, pointSize: 11)

    static let height: CGFloat = 44

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        site.font = .systemFont(ofSize: 11)
        site.textColor = .secondaryLabelColor
        site.lineBreakMode = .byTruncatingTail
        site.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let texts = NSStackView(views: [title, site])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 0
        for view in [icon, texts, playButton, muteButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            texts.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: playButton.leadingAnchor, constant: -4),
            playButton.trailingAnchor.constraint(equalTo: muteButton.leadingAnchor, constant: -2),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            muteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            muteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.cornerRadius = 10
        layer?.backgroundColor = (isDarkAppearance ? NSColor.white.withAlphaComponent(0.08) : NSColor.white.withAlphaComponent(0.55)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Shows `tab`'s media, or nothing.
    func update(tab: Tab?) {
        self.tab = tab
        guard let tab, let page = tab.page else { return }
        icon.image = FaviconStore.shared.icon(for: tab.url) { [weak icon] image in icon?.image = image }
            ?? Theme.symbol("music.note", size: 13)
        title.stringValue = tab.displayTitle
        site.stringValue = tab.url?.displayHost ?? ""
        let playing = page.isPlayingMedia ?? false
        playButton.image = Theme.symbol(playing ? "pause.fill" : "play.fill", size: 12)
        playButton.toolTip = playing ? String(localized: "Pause", bundle: .chordUI) : String(localized: "Play", bundle: .chordUI)
        playButton.setAccessibilityLabel(playButton.toolTip)
        let muted = page.isMuted ?? false
        muteButton.image = Theme.symbol(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 11)
        muteButton.toolTip = muted ? String(localized: "Unmute Tab", bundle: .chordUI) : String(localized: "Mute Tab", bundle: .chordUI)
        muteButton.setAccessibilityLabel(muteButton.toolTip)
        muteButton.isHidden = page.setMuted == nil
        setAccessibilityLabel(String(localized: "Playing in \(tab.displayTitle)", bundle: .chordUI))
    }

    override func mouseUp(with event: NSEvent) {
        if let tab { onSelect?(tab) }
    }

    @objc private func playClicked() {
        if let tab { onTogglePlayback?(tab) }
    }

    @objc private func muteClicked() {
        if let tab { onToggleMute?(tab) }
    }
}
