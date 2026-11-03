import AppKit

public final class FlippedView: NSView {
    override public var isFlipped: Bool { return true }
}

public struct TabItem: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var isCustomTitle: Bool

    public init(id: UUID = UUID(), title: String = "zsh", isCustomTitle: Bool = false) {
        self.id = id
        self.title = title
        self.isCustomTitle = isCustomTitle
    }

    public static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
    }
}

public protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ tabBar: TabBarView, didSelectTabWithID id: UUID)
    func tabBar(_ tabBar: TabBarView, didCloseTabWithID id: UUID)
    func tabBar(_ tabBar: TabBarView, didCloseOtherTabsThanID id: UUID)
    func tabBar(_ tabBar: TabBarView, didRenameTabWithID id: UUID, newTitle: String)
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

        // Scroll View for tab items
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
            tabButtons[id]?.setTitle(title)
        }
    }

    public func startEditingActiveTab() {
        guard let activeID = selectedTabID, let btn = tabButtons[activeID] else { return }
        btn.startEditing()
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
        // Remove old buttons from document view
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
        shortcutsButton.isHidden = false
        positionToggleButton.isHidden = false
        newTabButton.isHidden = false

        // Reparent buttons directly to TabBarView if previously inside sidebarHeaderView
        if shortcutsButton.superview != self {
            addSubview(shortcutsButton)
        }
        if positionToggleButton.superview != self {
            addSubview(positionToggleButton)
        }
        if newTabButton.superview != self {
            addSubview(newTabButton)
        }

        // Window traffic light reserved space
        let paddingLeft: CGFloat = 80.0
        let rightControlsWidth: CGFloat = 68.0
        let availableWidth = max(100.0, totalWidth - paddingLeft - rightControlsWidth - 36.0)

        let tabCount = max(1, tabs.count)
        let tabWidth = min(190.0, max(110.0, availableWidth / CGFloat(tabCount)))
        let tabsTotalW = CGFloat(tabs.count) * tabWidth

        tabsScrollView.frame = NSRect(x: paddingLeft, y: 0, width: tabsTotalW, height: Self.topHeight)
        tabsDocumentView.frame = NSRect(x: 0, y: 0, width: tabsTotalW, height: Self.topHeight)

        for (i, tab) in tabs.enumerated() {
            let isSelected = (tab.id == selectedTabID)
            let btn = TabButtonView(tab: tab, isSelected: isSelected, position: .top)
            btn.frame = NSRect(x: CGFloat(i) * tabWidth, y: 3, width: tabWidth - 4, height: Self.topHeight - 5)
            attachCallbacks(to: btn, for: tab)
            tabsDocumentView.addSubview(btn)
            tabButtons[tab.id] = btn
        }

        // Position (+) button immediately next to the last tab
        newTabButton.frame = NSRect(x: paddingLeft + tabsTotalW + 4, y: 5, width: 26, height: 26)

        // Position Toggle Button (Top/Left) and Shortcuts (?) Button at top-right
        positionToggleButton.frame = NSRect(x: totalWidth - 62, y: 5, width: 26, height: 26)
        shortcutsButton.frame = NSRect(x: totalWidth - 32, y: 5, width: 26, height: 26)
    }

    private func layoutLeftPane(totalWidth: CGFloat, totalHeight: CGFloat) {
        sidebarHeaderView.isHidden = false

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
        btn.onRename = { [weak self] newTitle in
            guard let self = self else { return }
            self.delegate?.tabBar(self, didRenameTabWithID: tab.id, newTitle: newTitle)
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

private final class TabButtonView: NSView, NSTextFieldDelegate {
    let tab: TabItem
    let isSelected: Bool
    let position: TabBarPosition

    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    var onCloseOthers: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onTogglePosition: (() -> Void)?

    private var titleLabel: NSTextField!
    private var closeButton: NSButton!
    private var accentIndicator: NSView?
    private var editTextField: NSTextField?
    public private(set) var isEditing: Bool = false
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

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        if position == .left {
            if isSelected {
                layer?.backgroundColor = NSColor(white: 0.17, alpha: 0.85).cgColor
                layer?.borderColor = NSColor(white: 0.28, alpha: 0.5).cgColor
                layer?.borderWidth = 1.0

                // Active accent bar on left
                let accent = NSView(frame: NSRect(x: 0, y: 5, width: 3, height: 22))
                accent.wantsLayer = true
                accent.layer?.backgroundColor = NSColor(srgbRed: 0.35, green: 0.65, blue: 0.95, alpha: 1.0).cgColor
                accent.layer?.cornerRadius = 1.5
                addSubview(accent)
                self.accentIndicator = accent
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
            }
        } else {
            if isSelected {
                layer?.backgroundColor = TerminalPalette.defaultBackground.cgColor
            } else {
                layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.4).cgColor
            }
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
        if isEditing {
            editTextField?.stringValue = title
        }
    }

    public func startEditing() {
        guard !isEditing else { return }
        isEditing = true
        titleLabel.isHidden = true
        closeButton.isHidden = true

        let tf = NSTextField(frame: NSRect(x: 8, y: (bounds.height - 22) / 2, width: max(40, bounds.width - 16), height: 22))
        tf.stringValue = tab.title
        tf.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        tf.textColor = .white
        tf.backgroundColor = NSColor(white: 0.12, alpha: 1.0)
        tf.isBordered = true
        tf.bezelStyle = .roundedBezel
        tf.focusRingType = .exterior
        tf.delegate = self
        addSubview(tf)
        self.editTextField = tf

        window?.makeFirstResponder(tf)
        tf.selectText(nil)
    }

    public func commitEditing() {
        guard isEditing else { return }
        isEditing = false
        let newTitle = editTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? tab.title
        editTextField?.removeFromSuperview()
        editTextField = nil
        titleLabel.isHidden = false
        closeButton.isHidden = false
        setTitle(newTitle)
        onRename?(newTitle)
    }

    public func cancelEditing() {
        guard isEditing else { return }
        isEditing = false
        editTextField?.removeFromSuperview()
        editTextField = nil
        titleLabel.isHidden = false
        closeButton.isHidden = false
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitEditing()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if isEditing {
            commitEditing()
        }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height

        let leftOffset: CGFloat = (position == .left && isSelected) ? 10.0 : 8.0
        closeButton.frame = NSRect(x: w - 22, y: (h - 16) / 2, width: 16, height: 16)
        titleLabel.frame = NSRect(x: leftOffset, y: (h - 16) / 2, width: max(20, w - leftOffset - 24), height: 16)

        if let tf = editTextField {
            tf.frame = NSRect(x: 6, y: (h - 22) / 2, width: max(30, w - 12), height: 22)
        }
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
                layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.7).cgColor
            }
        }
        closeButton.contentTintColor = NSColor(white: 0.9, alpha: 1.0)
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            if position == .left {
                layer?.backgroundColor = NSColor.clear.cgColor
            } else {
                layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.4).cgColor
            }
        }
        closeButton.contentTintColor = NSColor(white: 0.55, alpha: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            startEditing()
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
        startEditing()
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
