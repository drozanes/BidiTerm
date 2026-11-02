import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        windowController = MainWindowController()
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        // 1. Application Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About BidiTerm", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide BidiTerm", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit BidiTerm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 2. File Menu (Tabs & Sessions)
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(withTitle: "New Tab", action: #selector(MainWindowController.newTabAction(_:)), keyEquivalent: "t")

        let newTabInCwdItem = NSMenuItem(title: "New Tab in Current Directory", action: #selector(MainWindowController.newTabInCurrentDirectoryAction(_:)), keyEquivalent: "t")
        newTabInCwdItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(newTabInCwdItem)

        let reopenTabItem = NSMenuItem(title: "Reopen Closed Tab", action: #selector(MainWindowController.reopenClosedTabAction(_:)), keyEquivalent: "t")
        reopenTabItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(reopenTabItem)

        fileMenu.addItem(withTitle: "Close Tab", action: #selector(MainWindowController.closeTabAction(_:)), keyEquivalent: "w")
        fileMenu.addItem(NSMenuItem.separator())

        fileMenu.addItem(withTitle: "Restore Previous Session", action: #selector(MainWindowController.restorePreviousSessionAction(_:)), keyEquivalent: "")

        let restoreStartupItem = NSMenuItem(title: "Restore Tabs on Startup", action: #selector(MainWindowController.toggleRestoreOnStartupAction(_:)), keyEquivalent: "")
        restoreStartupItem.state = TabSessionManager.shared.restoreOnStartup ? .on : .off
        fileMenu.addItem(restoreStartupItem)

        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(MainWindowController.copyAction(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(MainWindowController.pasteAction(_:)), keyEquivalent: "v")
        let screenshotItem = NSMenuItem(title: "Capture Screenshot to Terminal", action: #selector(MainWindowController.captureScreenshotAction(_:)), keyEquivalent: "c")
        screenshotItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(screenshotItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Find in Terminal...", action: #selector(MainWindowController.toggleSearchAction(_:)), keyEquivalent: "f")

        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Bigger Font", action: #selector(zoomInAction(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Smaller Font", action: #selector(zoomOutAction(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Default Font Size", action: #selector(zoomResetAction(_:)), keyEquivalent: "0")

        // 5. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())

        let nextTabItem = NSMenuItem(title: "Select Next Tab", action: #selector(nextTabAction(_:)), keyEquivalent: "]")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: "Select Previous Tab", action: #selector(prevTabAction(_:)), keyEquivalent: "[")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(prevTabItem)

        // 6. Help Menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(withTitle: "Keyboard Shortcuts", action: #selector(MainWindowController.showShortcutsAction(_:)), keyEquivalent: "/")

        NSApp.mainMenu = mainMenu
    }

    @objc private func zoomInAction(_ sender: Any?) {
        if let view = windowController?.activeTab?.terminalView {
            view.fontSize = min(32.0, view.fontSize + 1.0)
        }
    }

    @objc private func zoomOutAction(_ sender: Any?) {
        if let view = windowController?.activeTab?.terminalView {
            view.fontSize = max(9.0, view.fontSize - 1.0)
        }
    }

    @objc private func zoomResetAction(_ sender: Any?) {
        if let view = windowController?.activeTab?.terminalView {
            view.fontSize = 14.0
        }
    }

    @objc private func nextTabAction(_ sender: Any?) {
        windowController?.selectNextTab()
    }

    @objc private func prevTabAction(_ sender: Any?) {
        windowController?.selectPreviousTab()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
