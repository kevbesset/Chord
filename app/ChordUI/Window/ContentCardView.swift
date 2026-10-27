import AppKit

/// The rounded card that holds the page, with an optional bar on top of it (the page
/// toolbar, or a split pane's header). In edgeless mode it loses its corners and border.
final class ContentCardView: NSView {
    private(set) var hostedView: NSView?
    private(set) var accessory: NSView?
    private var edgeless = false
    private var hostedConstraints: [NSLayoutConstraint] = []
    private let loadingBar = LoadingBarView()
    private var loadingBarTop: NSLayoutConstraint?
    private let emptyLabel = NSTextField(labelWithString: String(localized: "⌘T to open a tab", bundle: .chordUI))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)
        loadingBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingBar)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            loadingBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            loadingBar.heightAnchor.constraint(equalToConstant: LoadingBarView.height),
        ])
        pinLoadingBar()
    }

    /// The loading line along the top of the page, under the bar above it if any.
    func setLoading(_ loading: Bool, accent: NSColor) {
        loadingBar.setLoading(loading, accent: accent)
    }

    private func pinLoadingBar() {
        loadingBarTop?.isActive = false
        loadingBarTop = loadingBar.topAnchor.constraint(equalTo: accessory?.bottomAnchor ?? topAnchor)
        loadingBarTop?.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The window is glass, which gives its views a vibrant appearance, and Chromium's
    /// page view allows vibrancy: the page would blend with the glass, washed out in
    /// light mode and dimmed in dark mode. What the card shows gets the same appearance
    /// without vibrancy.
    private var plainAppearance: NSAppearance? {
        NSAppearance(named: isDarkAppearance ? .darkAqua : .aqua)
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = edgeless ? 0 : Theme.cardRadius
        layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer.borderWidth = edgeless ? 0 : 0.5
        layer.borderColor = (isDarkAppearance ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.08)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hostedView?.appearance = plainAppearance
        needsDisplay = true
    }

    func setEdgeless(_ edgeless: Bool) {
        self.edgeless = edgeless
        needsDisplay = true
    }

    /// Puts a bar above the page, or removes it with nil.
    func setAccessory(_ view: NSView?) {
        guard accessory !== view else { return }
        accessory?.removeFromSuperview()
        accessory = view
        if let view {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        pinHostedView()
    }

    /// Shows a page's view, or the empty state when `view` is nil.
    func show(_ view: NSView?) {
        // The same view again changes nothing, unless another window's card took it.
        if hostedView === view, view == nil || view?.superview === self { return }
        if let old = hostedView, old !== view, old.superview === self { old.removeFromSuperview() }
        hostedView = view
        emptyLabel.isHidden = view != nil
        if let view {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.appearance = plainAppearance
            // Under the loading line, which must stay above the page.
            addSubview(view, positioned: .below, relativeTo: loadingBar)
        }
        pinHostedView()
    }

    private func pinHostedView() {
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints = []
        pinLoadingBar()
        guard let view = hostedView, view.superview === self else { return }
        hostedConstraints = [
            view.topAnchor.constraint(equalTo: accessory?.bottomAnchor ?? topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        NSLayoutConstraint.activate(hostedConstraints)
    }
}
