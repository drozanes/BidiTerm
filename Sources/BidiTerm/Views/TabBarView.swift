import AppKit

public struct TabItem: Identifiable, Equatable {
    public let id: UUID
    public var title: String

    public init(id: UUID = UUID(), title: String = "zsh") {
        self.id = id
        self.title = title
    }

    public static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        return lhs.id == rhs.id
    }
}

public protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ tabBar: TabBarView, didSelectTabWithID id: UUID)
    func tabBar(_ tabBar: TabBarView, didCloseTabWithID id: UUID)
    func tabBarDidRequestNewTab(_ tabBar: TabBarView)
    func tabBarDidRequestShortcutsHelp(_ tabBar: TabBarView)
}

public final class TabBarView: NSView {
    public weak var delegate: TabBarViewDelegate?

    public private(set) var tabs: [TabItem] = []
    public private(set) var selectedTabID: UUID?

    private var tabButtons: [UUID: TabButtonView] = [:]
    private var newTabButton: NSButton!
    private var shortcutsButton: NSButton!

    public static let height: CGFloat = 36.0

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: frameRect.width, height: Self.height))
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1.0).cgColor

        // Shortcuts Help Button
        shortcutsButton = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 26))
        shortcutsButton.bezelStyle = .inline
        shortcutsButton.isBordered = false
        shortcutsButton.title = "?"
        shortcutsButton.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        shortcutsButton.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        shortcutsButton.target = self
        shortcutsButton.action = #selector(shortcutsClicked)
        shortcutsButton.toolTip = "Keyboard Shortcuts (⌘/)"
        addSubview(shortcutsButton)

        // New Tab (+) Button
        newTabButton = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 26))
        newTabButton.bezelStyle = .inline
        newTabButton.isBordered = false
        newTabButton.title = "+"
        newTabButton.font = NSFont.systemFont(ofSize: 17, weight: .medium)
        newTabButton.contentTintColor = NSColor(white: 0.75, alpha: 1.0)
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        newTabButton.toolTip = "New Tab (⌘T)"
        addSubview(newTabButton)
    }

    public func setTabs(_ newTabs: [TabItem], selectedID: UUID?) {
        self.tabs = newTabs
        self.selectedTabID = selectedID
        layoutTabs()
    }

    public func updateTitle(for id: UUID, title: String) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].title = title
            tabButtons[id]?.setTitle(title)
        }
    }

    override public func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutTabs()
    }

    private func layoutTabs() {
        // Remove old buttons
        for (_, btn) in tabButtons {
            btn.removeFromSuperview()
        }
        tabButtons.removeAll()

        let totalWidth = bounds.width
        let paddingLeft: CGFloat = 80.0 // space for window traffic lights
        let rightButtonsWidth: CGFloat = 68.0
        let availableWidth = max(100.0, totalWidth - paddingLeft - rightButtonsWidth)

        let tabCount = max(1, tabs.count)
        let tabWidth = min(190.0, max(110.0, availableWidth / CGFloat(tabCount)))

        var currentX = paddingLeft
        for tab in tabs {
            let isSelected = (tab.id == selectedTabID)
            let btn = TabButtonView(tab: tab, isSelected: isSelected)
            btn.frame = NSRect(x: currentX, y: 3, width: tabWidth - 4, height: Self.height - 3)
            btn.onClick = { [weak self] in
                guard let self = self else { return }
                self.delegate?.tabBar(self, didSelectTabWithID: tab.id)
            }
            btn.onClose = { [weak self] in
                guard let self = self else { return }
                self.delegate?.tabBar(self, didCloseTabWithID: tab.id)
            }
            addSubview(btn)
            tabButtons[tab.id] = btn
            currentX += tabWidth
        }

        // Position (+) button
        newTabButton.frame = NSRect(x: currentX + 4, y: 5, width: 26, height: 26)

        // Position (?) button at top-right
        shortcutsButton.frame = NSRect(x: totalWidth - 36, y: 5, width: 26, height: 26)
    }

    @objc private func newTabClicked() {
        delegate?.tabBarDidRequestNewTab(self)
    }

    @objc private func shortcutsClicked() {
        delegate?.tabBarDidRequestShortcutsHelp(self)
    }
}

// MARK: - Individual Tab Button View

private final class TabButtonView: NSView {
    let tab: TabItem
    let isSelected: Bool
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?

    private var titleLabel: NSTextField!
    private var closeButton: NSButton!
    private var trackingArea: NSTrackingArea?

    init(tab: TabItem, isSelected: Bool) {
        self.tab = tab
        self.isSelected = isSelected
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        if isSelected {
            layer?.backgroundColor = TerminalPalette.defaultBackground.cgColor
        } else {
            layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.4).cgColor
        }

        // Title
        titleLabel = NSTextField(labelWithString: tab.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
        titleLabel.textColor = isSelected ? .white : NSColor(white: 0.65, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // Close Button (✕)
        closeButton = NSButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.title = "✕"
        closeButton.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        closeButton.contentTintColor = NSColor(white: 0.55, alpha: 1.0)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        addSubview(closeButton)
    }

    public func setTitle(_ title: String) {
        titleLabel.stringValue = title
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height

        closeButton.frame = NSRect(x: w - 22, y: (h - 16) / 2, width: 16, height: 16)
        titleLabel.frame = NSRect(x: 12, y: (h - 16) / 2, width: max(20, w - 38), height: 16)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.7).cgColor
        }
        closeButton.contentTintColor = NSColor(white: 0.9, alpha: 1.0)
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.4).cgColor
        }
        closeButton.contentTintColor = NSColor(white: 0.55, alpha: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    @objc private func closeClicked() {
        onClose?()
    }
}
