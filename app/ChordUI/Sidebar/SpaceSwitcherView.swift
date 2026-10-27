import AppKit

/// The Spaces at the bottom of the sidebar: the active one as a named pill, the others
/// as coloured dots. The sidebar puts "+" for a new Space at the far right, like Arc.
final class SpaceSwitcherView: NSStackView {
    weak var sidebarDelegate: SidebarDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        spacing = 2
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(spaces: [Space], active: Space) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, space) in spaces.enumerated() {
            let chip = SpaceChipView(space: space, isActive: space.id == active.id, number: index + 1, canDelete: spaces.count > 1)
            chip.delegate = sidebarDelegate
            addArrangedSubview(chip)
        }
    }
}

final class SpaceChipView: NSView {
    weak var delegate: SidebarDelegate?
    private let space: Space
    private let isActive: Bool
    private let canDelete: Bool
    private var isDropTarget = false

    init(space: Space, isActive: Bool, number: Int, canDelete: Bool) {
        self.space = space
        self.isActive = isActive
        self.canDelete = canDelete
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = number <= 9 ? "\(space.name) (⌃\(number))" : space.name
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Space \(space.name)", bundle: .chordUI))
        // VoiceOver says which Space is shown, and how to reach each one.
        setAccessibilityValue(isActive ? String(localized: "Current Space", bundle: .chordUI) : nil)
        if number <= 9 { setAccessibilityHelp("⌃\(number)") }
        registerForDraggedTypes([.chordTab])

        // The Space's emoji when it has one, else its coloured dot.
        let dot: NSView
        var constraints = [heightAnchor.constraint(equalToConstant: 24)]
        if let icon = space.icon {
            let emoji = NSTextField(labelWithString: icon)
            emoji.font = .systemFont(ofSize: 13)
            emoji.alphaValue = isActive ? 1 : 0.6
            dot = emoji
        } else {
            dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            dot.layer?.backgroundColor = space.color.withAlphaComponent(isActive ? 1 : 0.45).cgColor
            constraints += [
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8),
            ]
        }
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        constraints.append(dot.centerYAnchor.constraint(equalTo: centerYAnchor))

        if isActive {
            let label = NSTextField(labelWithString: space.name)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            constraints += [
                dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: space.icon == nil ? 10 : 8),
                label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                widthAnchor.constraint(lessThanOrEqualToConstant: 140),
            ]
        } else {
            constraints += [
                widthAnchor.constraint(equalToConstant: 24),
                dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.cornerRadius = 12
        let dark = isDarkAppearance
        if isActive || isDropTarget {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(dark ? 0.12 : 0.85).cgColor
            layer?.borderWidth = isDropTarget ? 1.5 : 0
            layer?.borderColor = space.color.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, isActive {
            delegate?.sidebarRename(space)
        } else {
            delegate?.sidebarSelectSpace(space)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        delegate?.sidebarSelectSpace(space)
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let space = space
        let menu = NSMenu()
        menu.addItem(closureItem(String(localized: "Rename…", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarRename(space) })
        let colors = NSMenuItem(title: String(localized: "Color", bundle: .chordUI), action: nil, keyEquivalent: "")
        let palette = NSMenu()
        for hex in Theme.spacePalette {
            let entry = closureItem(Theme.colorName(hex)) { [weak self] in self?.delegate?.sidebarSetColor(space, hex: hex) }
            entry.image = Theme.dot(color: NSColor(hex: hex), size: 12)
            entry.state = hex == space.colorHex ? .on : .off
            palette.addItem(entry)
        }
        colors.submenu = palette
        menu.addItem(colors)
        let icons = NSMenuItem(title: String(localized: "Icon", bundle: .chordUI), action: nil, keyEquivalent: "")
        let choices = NSMenu()
        for icon in Space.suggestedIcons {
            let entry = closureItem(icon) { [weak self] in self?.delegate?.sidebarSetIcon(space, icon: icon) }
            entry.state = icon == space.icon ? .on : .off
            choices.addItem(entry)
        }
        choices.addItem(.separator())
        choices.addItem(closureItem(String(localized: "Other Emoji…", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarChooseIcon(space) })
        let none = closureItem(String(localized: "No Icon", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarSetIcon(space, icon: nil) }
        none.state = space.icon == nil ? .on : .off
        choices.addItem(none)
        icons.submenu = choices
        menu.addItem(icons)
        menu.addItem(.separator())
        let delete = closureItem(String(localized: "Delete Space…", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarDelete(space) }
        delete.isEnabled = canDelete
        menu.addItem(delete)
        menu.autoenablesItems = false
        return menu
    }

    // MARK: - Drop a tab to move it here

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isActive else { return [] }
        isDropTarget = true
        needsDisplay = true
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        needsDisplay = true
        guard let id = sender.draggingPasteboard.string(forType: .chordTab).flatMap(UUID.init(uuidString:)),
              let tab = delegate?.sidebarTab(withID: id) else { return false }
        delegate?.sidebarMove(tab, toSpace: space)
        return true
    }
}
