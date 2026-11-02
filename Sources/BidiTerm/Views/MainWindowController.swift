import AppKit

public final class MainWindowController: NSWindowController, NSWindowDelegate, TabBarViewDelegate, TerminalSearchBarDelegate {
    public private(set) var tabBarView: TabBarView!
    public private(set) var searchBarView: TerminalSearchBarView!
    public private(set) var contentContainerView: NSView!

    public private(set) var tabs: [TerminalTab] = []
    public private(set) var activeTab: TerminalTab?

    private var isSearchBarVisible: Bool = false

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 880, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        window.delegate = self
        setupWindow()
        setupUI()
        createNewTab()
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

        let bounds = contentView.bounds

        // 1. Tab Bar (at the top, with room for traffic light buttons)
        tabBarView = TabBarView(frame: NSRect(x: 0, y: bounds.height - TabBarView.height, width: bounds.width, height: TabBarView.height))
        tabBarView.autoresizingMask = [.width, .minYMargin]
        tabBarView.delegate = self
        contentView.addSubview(tabBarView)

        // 2. Search Bar (hidden by default under Tab Bar)
        searchBarView = TerminalSearchBarView(frame: NSRect(x: 0, y: bounds.height - TabBarView.height - TerminalSearchBarView.height, width: bounds.width, height: TerminalSearchBarView.height))
        searchBarView.autoresizingMask = [.width, .minYMargin]
        searchBarView.delegate = self
        searchBarView.isHidden = true
        contentView.addSubview(searchBarView)

        // 3. Content Container for active terminal
        contentContainerView = NSView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - TabBarView.height))
        contentContainerView.autoresizingMask = [.width, .height]
        contentContainerView.wantsLayer = true
        contentContainerView.layer?.backgroundColor = TerminalPalette.defaultBackground.cgColor
        contentView.addSubview(contentContainerView)

        layoutViews()
    }

    private func layoutViews() {
        guard let window = self.window, let contentView = window.contentView else { return }

        let bounds = contentView.bounds
        let tabH = TabBarView.height
        let searchH = isSearchBarVisible ? TerminalSearchBarView.height : 0.0

        tabBarView.frame = NSRect(x: 0, y: bounds.height - tabH, width: bounds.width, height: tabH)

        if isSearchBarVisible {
            searchBarView.frame = NSRect(x: 0, y: bounds.height - tabH - searchH, width: bounds.width, height: searchH)
            searchBarView.isHidden = false
        } else {
            searchBarView.isHidden = true
        }

        let contentH = max(10, bounds.height - tabH - searchH)
        contentContainerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: contentH)

        if let active = activeTab {
            active.terminalView.frame = contentContainerView.bounds
            active.terminalView.notifyResize()
        }
    }

    // MARK: - Tab Management

    @discardableResult
    public func createNewTab() -> TerminalTab {
        let tab = TerminalTab(windowController: self)
        tabs.append(tab)

        tab.start()
        selectTab(tab)
        updateTabBar()
        return tab
    }

    public func closeCurrentTab() {
        guard let active = activeTab else { return }
        closeTab(withID: active.id)
    }

    public func closeTab(withID id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }

        let tabToClose = tabs[idx]
        tabToClose.terminate()
        tabs.remove(at: idx)

        if tabs.isEmpty {
            window?.close()
            return
        }

        if activeTab?.id == id {
            let nextIndex = min(idx, tabs.count - 1)
            selectTab(tabs[nextIndex])
        }

        updateTabBar()
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

        // Update window title
        window?.title = tab.title

        // Update search query if active
        if isSearchBarVisible {
            performSearch(query: searchBarView.query)
        }

        updateTabBar()
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
    }

    private func updateTabBar() {
        let items = tabs.map { TabItem(id: $0.id, title: $0.title) }
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

    public func tabBarDidRequestNewTab(_ tabBar: TabBarView) {
        createNewTab()
    }

    public func tabBarDidRequestShortcutsHelp(_ tabBar: TabBarView) {
        ShortcutsWindowController.shared.toggle()
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

    @objc public func closeTabAction(_ sender: Any?) {
        closeCurrentTab()
    }

    @objc public func toggleSearchAction(_ sender: Any?) {
        toggleSearchBar()
    }

    @objc public func showShortcutsAction(_ sender: Any?) {
        ShortcutsWindowController.shared.toggle()
    }
}
