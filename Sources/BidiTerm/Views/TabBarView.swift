import AppKit

public final class FlippedView: NSView {
    override public var isFlipped: Bool { return true }
}

public struct TabItem: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var isCustomTitle: Bool
    public var customLabel: String?

    public init(id: UUID = UUID(), title: String = "zsh", isCustomTitle: Bool = false, customLabel: String? = nil) {
        self.id = id
        self.title = title
        self.isCustomTitle = isCustomTitle
        self.customLabel = customLabel
    }

    public static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
    }
}

public protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ tabBar: TabBarView, didSelectTabWithID id: UUID)
    func tabBar(_ tabBar: TabBarView, didCloseTabWithID id: UUID)
    func tabBar(_ tabBar: TabBarView, didCloseOtherTabsThanID id: UUID)
    func tabBar(_ tabBar: TabBarView, didRequestRenameTabWithID id: UUID)
    func tabBarDidRequestNewTab(_ tabBar: TabBarView)
    func tabBarDidRequestShortcutsHelp(_ tabBar: TabBarView)
    func tabBarDidRequestTogglePosition(_ tabBar: TabBarView)
}

public final class TabBarView: NSView {
    public weak var delegate: TabBarViewDelegate?

    public private(set) var tabs: [TabItem] = []
    public private(set) var selectedTabID: UUID?

    public var position: TabBarPosition = .top {
        didSet {
            if oldValue != position {
                updatePositionToggleButton()
                layoutTabs()
                needsDisplay = true
            }
        }
    }

    public static let height: CGFloat = 36.0
    public static let topHeight: CGFloat = 36.0
    public static let leftWidth: CGFloat = 210.0

    private var tabButtons: [UUID: TabButtonView] = [:]
    private var newTabButton: NSButton!
    private var shortcutsButton: NSButton!
    private var positionToggleButton: NSButton!

    private var sidebarHeaderView: NSView!
    private var sidebarTitleLabel: NSTextField!

    private var tabsScrollView: NSScrollView!
    private var tabsDocumentView: FlippedView!

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: frameRect.width, height: Self.topHeight))
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var mouseDownCanMoveWindow: Bool {
        return true
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1.0).cgColor

        // Sidebar Header Container (used in Left Pane mode)
        sidebarHeaderView = NSView(frame: .zero)
        sidebarHeaderView.wantsLayer = true
        addSubview(sidebarHeaderView)

        sidebarTitleLabel = NSTextField(labelWithString: "TABS")
        sidebarTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        sidebarTitleLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        sidebarHeaderView.addSubview(sidebarTitleLabel)

        // Shortcuts Help Button
        shortcutsButton = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        shortcutsButton.bezelStyle = .inline
        shortcutsButton.isBordered = false
        shortcutsButton.title = "?"
        shortcutsButton.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        shortcutsButton.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        shortcutsButton.target = self
        shortcutsButton.action = #selector(shortcutsClicked)
        shortcutsButton.toolTip = "Keyboard Shortcuts (⌘/)"
        addSubview(shortcutsButton)

        // Position Toggle Button (Top / Left Pane)
        positionToggleButton = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        positionToggleButton.bezelStyle = .inline
        positionToggleButton.isBordered = false
        positionToggleButton.title = "◨"
        positionToggleButton.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        positionToggleButton.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        positionToggleButton.target = self
        positionToggleButton.action = #selector(togglePositionClicked)
        positionToggleButton.toolTip = "Move Tabs to Left Pane (⌘⌥P)"
        addSubview(positionToggleButton)

        // New Tab (+) Button
        newTabButton = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        newTabButton.bezelStyle = .inline
        newTabButton.isBordered = false
        newTabButton.title = "+"
        newTabButton.font = NSFont.systemFont(ofSize: 17, weight: .medium)
        newTabButton.contentTintColor = NSColor(white: 0.75, alpha: 1.0)
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        newTabButton.toolTip = "New Tab (⌘T)"
        addSubview(newTabButton)

        // Scroll View for tab items (used in Left Pane mode)
        tabsScrollView = NSScrollView(frame: .zero)
        tabsScrollView.drawsBackground = false
        tabsScrollView.hasHorizontalScroller = false
        tabsScrollView.hasVerticalScroller = false
        tabsScrollView.autohidesScrollers = true

        tabsDocumentView = FlippedView(frame: .zero)
        tabsScrollView.documentView = tabsDocumentView
        addSubview(tabsScrollView)
    }

    private func updatePositionToggleButton() {
        if position == .top {
            positionToggleButton.title = "◨"
            positionToggleButton.toolTip = "Move Tabs to Left Pane (⌘⌥P)"
        } else {
            positionToggleButton.title = "◫"
            positionToggleButton.toolTip = "Move Tabs to Upper Pane (⌘⌥P)"
        }
    }

    public func setTabs(_ newTabs: [TabItem], selectedID: UUID?) {
        self.tabs = newTabs
        self.selectedTabID = selectedID
        layoutTabs()
    }

    public func updateTitle(for id: UUID, title: String) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].title = title
            if let btn = tabButtons[id] {
                btn.setTitle(title)
                btn.updateLayout()
            }
        }
    }

    public func startEditingActiveTab() {
        guard let activeID = selectedTabID else { return }
        delegate?.tabBar(self, didRequestRenameTabWithID: activeID)
    }

    override public func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutTabs()
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if position == .left {
            // Draw 1px right border divider for sidebar
            NSColor(white: 0.20, alpha: 0.6).setFill()
            NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        } else {
            // Draw 1px bottom border divider for top bar
            NSColor(white: 0.20, alpha: 0.6).setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        }
    }

    private func layoutTabs() {
        // Remove old buttons
        for (_, btn) in tabButtons {
            btn.removeFromSuperview()
        }
        tabButtons.removeAll()

        let totalWidth = bounds.width
        let totalHeight = bounds.height

        if position == .left {
            layoutLeftPane(totalWidth: totalWidth, totalHeight: totalHeight)
        } else {
            layoutTopPane(totalWidth: totalWidth, totalHeight: totalHeight)
        }
    }

    private func layoutTopPane(totalWidth: CGFloat, totalHeight: CGFloat) {
        sidebarHeaderView.isHidden = true
        tabsScrollView.isHidden = true

        shortcutsButton.isHidden = false
        positionToggleButton.isHidden = false
        newTabButton.isHidden = false

        // Ensure buttons are direct subviews of TabBarView
        if shortcutsButton.superview != self {
            addSubview(shortcutsButton)
        }
        if positionToggleButton.superview != self {
            addSubview(positionToggleButton)
        }
        if newTabButton.superview != self {
            addSubview(newTabButton)
        }

        // Window traffic light reserved space on macOS
        let paddingLeft: CGFloat = 80.0
        let rightControlsWidth: CGFloat = 68.0
        let availableWidth = max(100.0, totalWidth - paddingLeft - rightControlsWidth - 36.0)

        let tabCount = max(1, tabs.count)
        let tabWidth = min(220.0, max(120.0, availableWidth / CGFloat(tabCount)))

        var currentX = paddingLeft
        for tab in tabs {
            let isSelected = (tab.id == selectedTabID)
            let btn = TabButtonView(tab: tab, isSelected: isSelected, position: .top)
            btn.frame = NSRect(x: currentX, y: 4, width: tabWidth - 4, height: Self.topHeight - 8)
            btn.updateLayout()
            attachCallbacks(to: btn, for: tab)
            addSubview(btn)
            tabButtons[tab.id] = btn
            currentX += tabWidth
        }

        // Position (+) button immediately next to the last tab
        newTabButton.frame = NSRect(x: currentX + 4, y: 5, width: 26, height: 26)

        // Position Toggle Button (Top/Left) and Shortcuts (?) Button at top-right
        positionToggleButton.frame = NSRect(x: totalWidth - 62, y: 5, width: 26, height: 26)
        shortcutsButton.frame = NSRect(x: totalWidth - 32, y: 5, width: 26, height: 26)
    }

    private func layoutLeftPane(totalWidth: CGFloat, totalHeight: CGFloat) {
        sidebarHeaderView.isHidden = false
        tabsScrollView.isHidden = false

        // Traffic lights reserved height at top
        let trafficLightsH: CGFloat = 38.0
        let headerH: CGFloat = 30.0

        sidebarHeaderView.frame = NSRect(x: 0, y: totalHeight - trafficLightsH - headerH, width: totalWidth, height: headerH)
        sidebarTitleLabel.stringValue = "TABS (\(tabs.count))"
        sidebarTitleLabel.frame = NSRect(x: 12, y: 6, width: 85, height: 18)

        // Add action buttons to the sidebar header
        if newTabButton.superview != sidebarHeaderView {
            sidebarHeaderView.addSubview(newTabButton)
        }
        if positionToggleButton.superview != sidebarHeaderView {
            sidebarHeaderView.addSubview(positionToggleButton)
        }
        if shortcutsButton.superview != sidebarHeaderView {
            sidebarHeaderView.addSubview(shortcutsButton)
        }

        newTabButton.frame = NSRect(x: totalWidth - 78, y: 3, width: 22, height: 22)
        positionToggleButton.frame = NSRect(x: totalWidth - 52, y: 3, width: 22, height: 22)
        shortcutsButton.frame = NSRect(x: totalWidth - 26, y: 3, width: 22, height: 22)

        // Vertical scroll view for tab items
        let scrollH = max(10, totalHeight - trafficLightsH - headerH - 8)
        tabsScrollView.frame = NSRect(x: 0, y: 4, width: totalWidth - 1, height: scrollH)

        let tabH: CGFloat = 32.0
        let tabSpacing: CGFloat = 3.0
        let totalContentH = max(scrollH, CGFloat(tabs.count) * (tabH + tabSpacing) + 12.0)

        tabsDocumentView.frame = NSRect(x: 0, y: 0, width: totalWidth - 1, height: totalContentH)

        for (i, tab) in tabs.enumerated() {
            let isSelected = (tab.id == selectedTabID)
            let btn = TabButtonView(tab: tab, isSelected: isSelected, position: .left)
            let y = 6.0 + CGFloat(i) * (tabH + tabSpacing)
            btn.frame = NSRect(x: 8, y: y, width: totalWidth - 17, height: tabH)
            btn.updateLayout()
            attachCallbacks(to: btn, for: tab)
            tabsDocumentView.addSubview(btn)
            tabButtons[tab.id] = btn
        }
    }

    private func attachCallbacks(to btn: TabButtonView, for tab: TabItem) {
        btn.onClick = { [weak self] in
            guard let self = self else { return }
            self.delegate?.tabBar(self, didSelectTabWithID: tab.id)
        }
        btn.onClose = { [weak self] in
            guard let self = self else { return }
            self.delegate?.tabBar(self, didCloseTabWithID: tab.id)
        }
        btn.onCloseOthers = { [weak self] in
            guard let self = self else { return }
            self.delegate?.tabBar(self, didCloseOtherTabsThanID: tab.id)
        }
        btn.onRenameClicked = { [weak self] in
            guard let self = self else { return }
            self.delegate?.tabBar(self, didRequestRenameTabWithID: tab.id)
        }
        btn.onTogglePosition = { [weak self] in
            guard let self = self else { return }
            self.delegate?.tabBarDidRequestTogglePosition(self)
        }
    }

    @objc private func newTabClicked() {
        delegate?.tabBarDidRequestNewTab(self)
    }

    @objc private func shortcutsClicked() {
        delegate?.tabBarDidRequestShortcutsHelp(self)
    }

    @objc private func togglePositionClicked() {
        delegate?.tabBarDidRequestTogglePosition(self)
    }
}

// MARK: - Individual Tab Button View

private final class TabButtonView: NSView {
    let tab: TabItem
    let isSelected: Bool
    let position: TabBarPosition

    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    var onCloseOthers: (() -> Void)?
    var onRenameClicked: (() -> Void)?
    var onTogglePosition: (() -> Void)?

    private var titleLabel: NSTextField!
    private var closeButton: NSButton!
    private var accentIndicator: NSView?
    private var trackingArea: NSTrackingArea?

    init(tab: TabItem, isSelected: Bool, position: TabBarPosition) {
        self.tab = tab
        self.isSelected = isSelected
        self.position = position
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var frame: NSRect {
        didSet {
            updateLayout()
        }
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        if position == .left {
            if isSelected {
                layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.90).cgColor
                layer?.borderColor = NSColor(white: 0.32, alpha: 0.6).cgColor
                layer?.borderWidth = 1.0

                // Active accent bar on left
                let accent = NSView(frame: .zero)
                accent.wantsLayer = true
                accent.layer?.backgroundColor = NSColor(srgbRed: 0.35, green: 0.65, blue: 0.95, alpha: 1.0).cgColor
                accent.layer?.cornerRadius = 1.5
                addSubview(accent)
                self.accentIndicator = accent
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 0.0
            }
        } else {
            if isSelected {
                // High contrast selected tab pill in top pane
                layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.95).cgColor
                layer?.borderColor = NSColor(white: 0.38, alpha: 0.8).cgColor
                layer?.borderWidth = 1.0

                // Subtle bottom accent indicator
                let accent = NSView(frame: .zero)
                accent.wantsLayer = true
                accent.layer?.backgroundColor = NSColor(srgbRed: 0.35, green: 0.65, blue: 0.95, alpha: 1.0).cgColor
                accent.layer?.cornerRadius = 1.0
                addSubview(accent)
                self.accentIndicator = accent
            } else {
                // Clearly visible unselected tab pill
                layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.65).cgColor
                layer?.borderColor = NSColor(white: 0.22, alpha: 0.4).cgColor
                layer?.borderWidth = 1.0
            }
        }

        // Title Label
        titleLabel = NSTextField(labelWithString: tab.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
        titleLabel.textColor = isSelected ? .white : NSColor(white: 0.72, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
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

        self.toolTip = tab.title
        updateLayout()
    }

    public func setTitle(_ title: String) {
        titleLabel.stringValue = title
        self.toolTip = title
        updateLayout()
    }

    public func updateLayout() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0 && h > 0 else { return }

        let closeSize: CGFloat = 16.0
        let closePaddingRight: CGFloat = 6.0
        let leftOffset: CGFloat = (position == .left && isSelected) ? 12.0 : 8.0

        closeButton.frame = NSRect(x: max(8, w - closeSize - closePaddingRight), y: (h - closeSize) / 2, width: closeSize, height: closeSize)
        let labelW = max(10, w - leftOffset - closeSize - closePaddingRight - 4)
        titleLabel.frame = NSRect(x: leftOffset, y: (h - 16) / 2, width: labelW, height: 16)

        if let accent = accentIndicator {
            if position == .top {
                accent.frame = NSRect(x: 4, y: 1, width: max(10, w - 8), height: 2)
            } else {
                accent.frame = NSRect(x: 0, y: 5, width: 3, height: max(10, h - 10))
            }
        }
    }

    override func layout() {
        super.layout()
        updateLayout()
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
            if position == .left {
                layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.45).cgColor
            } else {
                layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.85).cgColor
                layer?.borderColor = NSColor(white: 0.30, alpha: 0.6).cgColor
            }
        }
        closeButton.contentTintColor = NSColor(white: 0.9, alpha: 1.0)
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            if position == .left {
                layer?.backgroundColor = NSColor.clear.cgColor
            } else {
                layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.65).cgColor
                layer?.borderColor = NSColor(white: 0.22, alpha: 0.4).cgColor
            }
        }
        closeButton.contentTintColor = NSColor(white: 0.55, alpha: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onRenameClicked?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Tab Actions")

        let renameItem = NSMenuItem(title: "Rename Tab...", action: #selector(contextRenameClicked), keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)

        menu.addItem(NSMenuItem.separator())

        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(closeClicked), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        let closeOthersItem = NSMenuItem(title: "Close Other Tabs", action: #selector(contextCloseOthersClicked), keyEquivalent: "")
        closeOthersItem.target = self
        menu.addItem(closeOthersItem)

        menu.addItem(NSMenuItem.separator())

        let toggleTitle = (position == .top) ? "Move Tabs to Left Pane" : "Move Tabs to Upper Pane"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(contextTogglePositionClicked), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextRenameClicked() {
        onRenameClicked?()
    }

    @objc private func contextCloseOthersClicked() {
        onCloseOthers?()
    }

    @objc private func contextTogglePositionClicked() {
        onTogglePosition?()
    }

    @objc private func closeClicked() {
        onClose?()
    }
}
