import AppKit

/// Find in page (⌘F), like Arc's: a small glass pill at the top right of the page, with
/// the text, how many matches there are, and previous / next. Every match is
/// highlighted in the page as the text is typed. ↩ goes to the next match, ⇧↩ to the
/// previous one, esc closes.
final class FindBarView: NSView, NSTextFieldDelegate {
    var onChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    private let shadowHost = ShadowHostView()
    private let glass = NSVisualEffectView()
    private let icon = NSImageView(image: Theme.symbol("magnifyingglass", size: 12) ?? NSImage())
    private let field = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private lazy var previousButton = IconButton(symbol: "chevron.up", label: String(localized: "Find Previous (⇧⌘G)", bundle: .chordUI),
                                                 target: self, action: #selector(previousClicked), size: 24, pointSize: 11)
    private lazy var nextButton = IconButton(symbol: "chevron.down", label: String(localized: "Find Next (⌘G)", bundle: .chordUI),
                                             target: self, action: #selector(nextClicked), size: 24, pointSize: 11)
    private lazy var closeButton = IconButton(symbol: "xmark", label: String(localized: "Done", bundle: .chordUI),
                                              target: self, action: #selector(closeClicked), size: 24, pointSize: 10)

    static let size = NSSize(width: 320, height: 38)

    var text: String { field.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true

        shadowHost.cornerRadius = 12
        shadowHost.configureShadow(opacity: 0.16, radius: 12, offsetY: -3)
        glass.material = .popover
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor.separatorColor.cgColor

        icon.contentTintColor = .secondaryLabelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = String(localized: "Find in page", bundle: .chordUI)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.setAccessibilityLabel(String(localized: "Find in page", bundle: .chordUI))
        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        for view in [shadowHost, glass, icon, field, countLabel, previousButton, nextButton, closeButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(shadowHost)
        shadowHost.addSubview(glass)
        for view in [icon, field, countLabel, previousButton, nextButton, closeButton] as [NSView] { glass.addSubview(view) }
        NSLayoutConstraint.activate([
            shadowHost.topAnchor.constraint(equalTo: topAnchor),
            shadowHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            shadowHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            shadowHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            glass.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            field.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
            countLabel.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
            previousButton.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 6),
            previousButton.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor),
            nextButton.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 2),
            closeButton.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -7),
            closeButton.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Find in page", bundle: .chordUI))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        glass.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    /// Puts the cursor in the field, its text selected, so that typing starts over.
    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    var isEditing: Bool {
        guard let editor = window?.firstResponder as? NSText else { return false }
        return editor.delegate as? NSTextField === field
    }

    /// "3 of 12", "No results", or nothing while the field is empty.
    func showResult(count: Int, activeMatch: Int) {
        if field.stringValue.isEmpty {
            countLabel.stringValue = ""
        } else if count == 0 {
            countLabel.stringValue = String(localized: "No results", bundle: .chordUI)
        } else {
            countLabel.stringValue = String(localized: "\(activeMatch) of \(count)", bundle: .chordUI)
        }
        countLabel.textColor = count == 0 && !field.stringValue.isEmpty ? .systemRed : .secondaryLabelColor
        previousButton.isEnabled = count > 0
        nextButton.isEnabled = count > 0
    }

    func clearResult() {
        countLabel.stringValue = ""
        previousButton.isEnabled = false
        nextButton.isEnabled = false
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        if field.stringValue.isEmpty { clearResult() }
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { onPrevious?() } else { onNext?() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    @objc private func previousClicked() { onPrevious?() }
    @objc private func nextClicked() { onNext?() }
    @objc private func closeClicked() { onClose?() }
}
