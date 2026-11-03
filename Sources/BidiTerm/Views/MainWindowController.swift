import AppKit

public final class MainWindowController: NSWindowController, NSWindowDelegate, TabBarViewDelegate, TerminalSearchBarDelegate, BottomStatusBarDelegate {
    public private(set) var tabBarView: TabBarView!
    public private(set) var searchBarView: TerminalSearchBarView!
    public private(set) var contentContainerView: NSView!
    public private(set) var bottomStatusBarView: BottomStatusBarView!

    public private(set) var tabs: [TerminalTab] = []
    public private(set) var activeTab: TerminalTab?
    public private(set) var tabBarPosition: TabBarPosition = .top

    private var isSearchBarVisible: Bool = false
    private var cwdPollingTimer: Timer?

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 920, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.tabBarPosition = TabSessionManager.shared.tabBarPosition
        super.init(window: window)
        window.delegate = self
        setupWindow()
        setupUI()
        setupCwdPolling()
        restoreOrInitializeTabs()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cwdPollingTimer?.invalidate()
    }

    private func setupWindow() {
        guard let window = self.window else { return }

        window.title = "BidiTerm"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = TerminalPalette.defaultBackground
        window.minSize = NSSize(width: 500, height: 350)
        window.isReleasedWhenClosed = false
        window.center()
    }

    private func setupUI() {
        guard let window = self.window, let contentView = window.contentView else { return }

        // 1. Tab Bar View (supports both Top pane and Left pane)
        tabBarView = TabBarView(frame: .zero)
        tabBarView.position = tabBarPosition
        tabBarView.delegate = self
        contentView.addSubview(tabBarView)

        // 2. Search Bar View
        searchBarView = TerminalSearchBarView(frame: .zero)
        searchBarView.delegate = self
        searchBarView.isHidden = true
        contentView.addSubview(searchBarView)

        // 3. Bottom Status Bar (with Warp-style [ 📁 ~/Dev ] pill and shortcuts trigger)
        bottomStatusBarView = BottomStatusBarView(frame: .zero)
        bottomStatusBarView.delegate = self
        contentView.addSubview(bottomStatusBarView)

        // 4. Content Container for active terminal
        contentContainerView = NSView(frame: .zero)
        contentContainerView.wantsLayer = true
        contentContainerView.layer?.backgroundColor = TerminalPalette.defaultBackground.cgColor
        contentView.addSubview(contentContainerView)

        layoutViews()
    }

    private func layoutViews() {
        guard let window = self.window, let contentView = window.contentView else { return }

        let bounds = contentView.bounds
        let statusH = BottomStatusBarView.height
        let searchH = isSearchBarVisible ? TerminalSearchBarView.height : 0.0

        if tabBarPosition == .left {
            let tabW = TabBarView.leftWidth

            // 1. Tab Bar on Left (Sidebar)
            tabBarView.frame = NSRect(x: 0, y: 0, width: tabW, height: bounds.height)

            // 2. Search Bar at Top of Content Area
            if isSearchBarVisible {
                searchBarView.frame = NSRect(x: tabW, y: bounds.height - searchH, width: bounds.width - tabW, height: searchH)
                searchBarView.isHidden = false
            } else {
                searchBarView.isHidden = true
            }

            // 3. Bottom Status Bar
            bottomStatusBarView.frame = NSRect(x: tabW, y: 0, width: bounds.width - tabW, height: statusH)

            // 4. Terminal Content Container
            let contentY = statusH
            let contentH = max(10, bounds.height - searchH - statusH)
            contentContainerView.frame = NSRect(x: tabW, y: contentY, width: max(10, bounds.width - tabW), height: contentH)
        } else {
            let tabH = TabBarView.topHeight

            // 1. Tab Bar on Top
            tabBarView.frame = NSRect(x: 0, y: bounds.height - tabH, width: bounds.width, height: tabH)

            // 2. Search Bar below Tab Bar
            if isSearchBarVisible {
                searchBarView.frame = NSRect(x: 0, y: bounds.height - tabH - searchH, width: bounds.width, height: searchH)
                searchBarView.isHidden = false
            } else {
                searchBarView.isHidden = true
            }

            // 3. Bottom Status Bar
            bottomStatusBarView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: statusH)

            // 4. Terminal Content Container
            let contentY = statusH
            let contentH = max(10, bounds.height - tabH - searchH - statusH)
            contentContainerView.frame = NSRect(x: 0, y: contentY, width: bounds.width, height: contentH)
        }

        if let active = activeTab {
            active.terminalView.frame = contentContainerView.bounds
            active.terminalView.notifyResize()
        }
    }

    private func setupCwdPolling() {
        cwdPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkCurrentTabCwd()
        }
    }

    private func checkCurrentTabCwd() {
        guard let active = activeTab else { return }
        active.checkProcessAndDirectory()
    }

    // MARK: - Tab Session Restoration

    private func restoreOrInitializeTabs() {
        if TabSessionManager.shared.restoreOnStartup,
           let saved = TabSessionManager.shared.loadSavedSession(),
           !saved.tabs.isEmpty {
            for tabState in saved.tabs {
                let dir = FileManager.default.fileExists(atPath: tabState.workingDirectory) ? tabState.workingDirectory : NSHomeDirectory()
                createNewTab(directory: dir, title: tabState.title, isCustomTitle: tabState.isCustomTitle, customLabel: tabState.customLabel, autoSelect: false)
            }
            let targetIndex = min(saved.activeIndex, tabs.count - 1)
            if targetIndex >= 0 {
                selectTab(tabs[targetIndex])
            }
        } else {
            // Default opening path: user's home directory (/Users/...)
            createNewTab(directory: NSHomeDirectory())
        }
    }

    private func persistCurrentSession() {
        let savedTabs = tabs.map { SavedTabState(workingDirectory: $0.currentDirectory, title: $0.title, isCustomTitle: $0.isCustomTitle, customLabel: $0.customLabel) }
        let activeIdx = activeTab != nil ? (tabs.firstIndex(where: { $0.id == activeTab!.id }) ?? 0) : 0
        TabSessionManager.shared.saveSession(tabs: savedTabs, activeIndex: activeIdx)
    }

    // MARK: - Tab Management

    @discardableResult
    public func createNewTab(directory: String? = nil, title: String? = nil, isCustomTitle: Bool = false, customLabel: String? = nil, autoSelect: Bool = true) -> TerminalTab {
        // Default opening path is the user path (NSHomeDirectory())
        let targetDir = (directory != nil && !directory!.isEmpty) ? directory! : NSHomeDirectory()
        let tab = TerminalTab(windowController: self, initialDirectory: targetDir, initialTitle: title, isCustomTitle: isCustomTitle, customLabel: customLabel)
        tabs.append(tab)

        tab.start()
        if autoSelect {
            selectTab(tab)
        }
        updateTabBar()
        persistCurrentSession()
        return tab
    }

    public func closeCurrentTab() {
        guard let active = activeTab else { return }
        closeTab(withID: active.id)
    }

    public func closeOtherTabs(than id: UUID) {
        let others = tabs.filter { $0.id != id }
        for t in others {
            closeTab(withID: t.id)
        }
    }

    public func closeTab(withID id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }

        let tabToClose = tabs[idx]
        // Save to recently closed tabs stack for Cmd+Shift+T restoration
        TabSessionManager.shared.pushClosedTab(workingDirectory: tabToClose.currentDirectory, title: tabToClose.title, isCustomTitle: tabToClose.isCustomTitle, customLabel: tabToClose.customLabel)

        tabToClose.terminate()
        tabs.remove(at: idx)

        if tabs.isEmpty {
            persistCurrentSession()
            window?.close()
            return
        }

        if activeTab?.id == id {
            let nextIndex = min(idx, tabs.count - 1)
            selectTab(tabs[nextIndex])
        }

        updateTabBar()
        persistCurrentSession()
    }

    public func reopenLastClosedTab() {
        if let closed = TabSessionManager.shared.popClosedTab() {
            let dir = FileManager.default.fileExists(atPath: closed.workingDirectory) ? closed.workingDirectory : NSHomeDirectory()
            createNewTab(directory: dir, title: closed.title, isCustomTitle: closed.isCustomTitle, customLabel: closed.customLabel)
        }
    }

    public func restorePreviousSession() {
        guard let saved = TabSessionManager.shared.loadSavedSession(), !saved.tabs.isEmpty else { return }

        // Close existing tabs
        for tab in tabs {
            tab.terminate()
        }
        tabs.removeAll()

        for tabState in saved.tabs {
            let dir = FileManager.default.fileExists(atPath: tabState.workingDirectory) ? tabState.workingDirectory : NSHomeDirectory()
            createNewTab(directory: dir, title: tabState.title, isCustomTitle: tabState.isCustomTitle, customLabel: tabState.customLabel, autoSelect: false)
        }
        let targetIndex = min(saved.activeIndex, tabs.count - 1)
        if targetIndex >= 0 {
            selectTab(tabs[targetIndex])
        }
    }

    public func selectTab(_ tab: TerminalTab) {
        activeTab = tab

        // Swap terminal view into container
        for subview in contentContainerView.subviews {
            subview.removeFromSuperview()
        }

        tab.terminalView.frame = contentContainerView.bounds
        tab.terminalView.autoresizingMask = [.width, .height]
        contentContainerView.addSubview(tab.terminalView)
        window?.makeFirstResponder(tab.terminalView)
        tab.terminalView.notifyResize()

        // Update window title and bottom path pill
        window?.title = tab.title
        bottomStatusBarView.update(path: tab.currentDirectory)

        // Update search query if active
        if isSearchBarVisible {
            performSearch(query: searchBarView.query)
        }

        updateTabBar()
        persistCurrentSession()
    }

    public func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        selectTab(tabs[index])
    }

    public func selectNextTab() {
        guard !tabs.isEmpty, let active = activeTab, let idx = tabs.firstIndex(where: { $0.id == active.id }) else { return }
        let next = (idx + 1) % tabs.count
        selectTab(tabs[next])
    }

    public func selectPreviousTab() {
        guard !tabs.isEmpty, let active = activeTab, let idx = tabs.firstIndex(where: { $0.id == active.id }) else { return }
        let prev = (idx - 1 + tabs.count) % tabs.count
        selectTab(tabs[prev])
    }

    public func tabDidUpdateTitle(_ tab: TerminalTab) {
        tabBarView.updateTitle(for: tab.id, title: tab.title)
        if activeTab?.id == tab.id {
            window?.title = tab.title
        }
        persistCurrentSession()
    }

    public func tabDidUpdateDirectory(_ tab: TerminalTab) {
        if activeTab?.id == tab.id {
            bottomStatusBarView.update(path: tab.currentDirectory)
        }
        persistCurrentSession()
    }

    private func updateTabBar() {
        let items = tabs.map { TabItem(id: $0.id, title: $0.title, isCustomTitle: $0.isCustomTitle, customLabel: $0.customLabel) }
        tabBarView.setTabs(items, selectedID: activeTab?.id)
    }

    // MARK: - Search Bar & Find

    public func toggleSearchBar() {
        isSearchBarVisible.toggle()
        layoutViews()

        if isSearchBarVisible {
            searchBarView.focus()
            if !searchBarView.query.isEmpty {
                performSearch(query: searchBarView.query)
            }
        } else {
            // Clear search highlights
            activeTab?.terminalView.searchMatches = []
            if let active = activeTab {
                window?.makeFirstResponder(active.terminalView)
            }
        }
    }

    private func performSearch(query: String) {
        guard let active = activeTab else { return }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            active.terminalView.searchMatches = []
            searchBarView.updateMatchCount(current: 0, total: 0)
            return
        }

        let matches = active.buffer.search(query: trimmed, caseSensitive: false)
        active.terminalView.searchMatches = matches
        active.terminalView.activeSearchMatchIndex = 0

        searchBarView.updateMatchCount(current: 0, total: matches.count)

        if let first = matches.first {
            active.terminalView.scrollToLine(index: first.lineIndex)
        }
    }

    // MARK: - TabBarViewDelegate

    public func tabBar(_ tabBar: TabBarView, didSelectTabWithID id: UUID) {
        if let tab = tabs.first(where: { $0.id == id }) {
            selectTab(tab)
        }
    }

    public func tabBar(_ tabBar: TabBarView, didCloseTabWithID id: UUID) {
        closeTab(withID: id)
    }

    public func tabBar(_ tabBar: TabBarView, didCloseOtherTabsThanID id: UUID) {
        closeOtherTabs(than: id)
    }

    public func tabBar(_ tabBar: TabBarView, didRequestRenameTabWithID id: UUID) {
        if let tab = tabs.first(where: { $0.id == id }) {
            promptRenameTab(tab)
        }
    }

    public func promptRenameTab(_ tab: TerminalTab) {
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "Enter a custom label for this tab.\nThis label will appear alongside the directory path:\n📁 \(tab.folderDisplayName) • <Label>"
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = tab.customLabel ?? ""
        input.placeholderString = "e.g. Frontend, DB, or blank to reset"
        alert.accessoryView = input

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset")

        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self, weak tab] response in
            guard let self = self, let tab = tab else { return }
            if response == .alertFirstButtonReturn {
                let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                tab.setCustomLabel(text.isEmpty ? nil : text)
                self.persistCurrentSession()
            } else if response == .alertThirdButtonReturn {
                tab.setCustomLabel(nil)
                self.persistCurrentSession()
            }
        }
    }

    public func tabBarDidRequestNewTab(_ tabBar: TabBarView) {
        createNewTab()
    }

    public func tabBarDidRequestShortcutsHelp(_ tabBar: TabBarView) {
        ShortcutsWindowController.shared.toggle()
    }

    public func tabBarDidRequestTogglePosition(_ tabBar: TabBarView) {
        toggleTabBarPositionAction(nil)
    }

    // MARK: - BottomStatusBarDelegate

    public func bottomStatusBarDidRequestShortcutsHelp(_ statusBar: BottomStatusBarView) {
        ShortcutsWindowController.shared.toggle()
    }

    public func bottomStatusBarDidRequestNewTabAtDirectory(_ statusBar: BottomStatusBarView, directory: String) {
        createNewTab(directory: directory)
    }

    // MARK: - TerminalSearchBarDelegate

    public func searchBar(_ searchBar: TerminalSearchBarView, didChangeQuery query: String) {
        performSearch(query: query)
    }

    public func searchBarDidRequestNextMatch(_ searchBar: TerminalSearchBarView) {
        guard let active = activeTab, !active.terminalView.searchMatches.isEmpty else { return }

        let total = active.terminalView.searchMatches.count
        let next = (active.terminalView.activeSearchMatchIndex + 1) % total
        active.terminalView.activeSearchMatchIndex = next
        searchBarView.updateMatchCount(current: next, total: total)

        let match = active.terminalView.searchMatches[next]
        active.terminalView.scrollToLine(index: match.lineIndex)
    }

    public func searchBarDidRequestPreviousMatch(_ searchBar: TerminalSearchBarView) {
        guard let active = activeTab, !active.terminalView.searchMatches.isEmpty else { return }

        let total = active.terminalView.searchMatches.count
        let prev = (active.terminalView.activeSearchMatchIndex - 1 + total) % total
        active.terminalView.activeSearchMatchIndex = prev
        searchBarView.updateMatchCount(current: prev, total: total)

        let match = active.terminalView.searchMatches[prev]
        active.terminalView.scrollToLine(index: match.lineIndex)
    }

    public func searchBarDidClose(_ searchBar: TerminalSearchBarView) {
        if isSearchBarVisible {
            toggleSearchBar()
        }
    }

    // MARK: - NSWindowDelegate

    public func windowDidResize(_ notification: Notification) {
        layoutViews()
    }

    public func windowWillClose(_ notification: Notification) {
        cwdPollingTimer?.invalidate()
        persistCurrentSession()
        for tab in tabs {
            tab.terminate()
        }
    }

    // MARK: - Menu Actions

    @objc public func captureScreenshotAction(_ sender: Any?) {
        activeTab?.terminalView.handleScreenshotCapture()
    }

    @objc public func pasteAction(_ sender: Any?) {
        activeTab?.terminalView.handlePaste()
    }

    @objc public func copyAction(_ sender: Any?) {
        activeTab?.terminalView.handleCopy()
    }

    @objc public func newTabAction(_ sender: Any?) {
        createNewTab()
    }

    @objc public func newTabInCurrentDirectoryAction(_ sender: Any?) {
        let dir = activeTab?.currentDirectory ?? NSHomeDirectory()
        createNewTab(directory: dir)
    }

    @objc public func reopenClosedTabAction(_ sender: Any?) {
        reopenLastClosedTab()
    }

    @objc public func restorePreviousSessionAction(_ sender: Any?) {
        restorePreviousSession()
    }

    @objc public func toggleRestoreOnStartupAction(_ sender: Any?) {
        TabSessionManager.shared.restoreOnStartup.toggle()
        if let menuItem = sender as? NSMenuItem {
            menuItem.state = TabSessionManager.shared.restoreOnStartup ? .on : .off
        }
    }

    @objc public func closeTabAction(_ sender: Any?) {
        closeCurrentTab()
    }

    @objc public func toggleSearchAction(_ sender: Any?) {
        toggleSearchBar()
    }

    @objc public func showShortcutsAction(_ sender: Any?) {
        ShortcutsWindowController.shared.toggle()
    }

    @objc public func renameActiveTabAction(_ sender: Any?) {
        guard let active = activeTab else { return }
        promptRenameTab(active)
    }

    @objc public func closeOtherTabsAction(_ sender: Any?) {
        guard let active = activeTab else { return }
        closeOtherTabs(than: active.id)
    }

    public func setTabBarPosition(_ newPosition: TabBarPosition) {
        guard tabBarPosition != newPosition else { return }
        tabBarPosition = newPosition
        TabSessionManager.shared.tabBarPosition = newPosition
        tabBarView.position = newPosition
        layoutViews()
    }

    @objc public func toggleTabBarPositionAction(_ sender: Any?) {
        let next: TabBarPosition = (tabBarPosition == .top) ? .left : .top
        setTabBarPosition(next)
    }

    @objc public func setTabBarPositionAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pos = TabBarPosition(rawValue: raw) else { return }
        setTabBarPosition(pos)
        if let menu = sender.menu {
            for item in menu.items {
                item.state = (item == sender) ? .on : .off
            }
        }
    }

    @objc public func changePromptStyleAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = PromptStyle(rawValue: raw) else { return }
        ShellIntegrationManager.shared.currentStyle = style
        if let menu = sender.menu {
            for item in menu.items {
                item.state = (item == sender) ? .on : .off
            }
        }
    }
}
