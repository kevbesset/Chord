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
        setAccessibilityLabel("Space \(space.name)")
        registerForDraggedTypes([.chordTab])

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = space.color.withAlphaComponent(isActive ? 1 : 0.45).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        var constraints = [
            heightAnchor.constraint(equalToConstant: 24),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]

        if isActive {
            let label = NSTextField(labelWithString: space.name)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            constraints += [
                dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
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
        menu.addItem(closureItem("Renommer…") { [weak self] in self?.delegate?.sidebarRename(space) })
        let colors = NSMenuItem(title: "Couleur", action: nil, keyEquivalent: "")
        let palette = NSMenu()
        for hex in Theme.spacePalette {
            let entry = closureItem(Theme.colorName(hex)) { [weak self] in self?.delegate?.sidebarSetColor(space, hex: hex) }
            entry.image = Theme.dot(color: NSColor(hex: hex), size: 12)
            entry.state = hex == space.colorHex ? .on : .off
            palette.addItem(entry)
        }
        colors.submenu = palette
        menu.addItem(colors)
        menu.addItem(.separator())
        let delete = closureItem("Supprimer le Space…") { [weak self] in self?.delegate?.sidebarDelete(space) }
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
