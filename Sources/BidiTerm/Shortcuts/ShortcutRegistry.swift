import Foundation
import AppKit

public enum ShortcutCategory: String, CaseIterable {
    case tabs = "Tabs & Windows"
    case search = "Search & Navigation"
    case files = "Files & Links"
    case clipboard = "Clipboard & Media"
    case terminal = "Terminal & Display"
}

public struct TerminalShortcut: Identifiable {
    public let id = UUID()
    public let keys: [String]
    public let title: String
    public let description: String
    public let category: ShortcutCategory

    public init(keys: [String], title: String, description: String, category: ShortcutCategory) {
        self.keys = keys
        self.title = title
        self.description = description
        self.category = category
    }
}

public enum ShortcutRegistry {
    /// Central registry of all available application shortcuts
    public static let allShortcuts: [TerminalShortcut] = [
        // Tabs
        TerminalShortcut(
            keys: ["⌘", "T"],
            title: "New Tab",
            description: "Opens a new terminal tab at the default home directory",
            category: .tabs
        ),
        TerminalShortcut(
            keys: ["⌘", "⌥", "T"],
            title: "New Tab in Current Directory",
            description: "Opens a new tab matching the current active tab's directory",
            category: .tabs
        ),
        TerminalShortcut(
            keys: ["⌘", "⇧", "T"],
            title: "Reopen Closed Tab",
            description: "Restores the most recently closed tab and its working directory",
            category: .tabs
        ),
        TerminalShortcut(
            keys: ["⌘", "W"],
            title: "Close Tab",
            description: "Closes the current terminal tab",
            category: .tabs
        ),
        TerminalShortcut(
            keys: ["⌘", "1...9"],
            title: "Jump to Tab",
            description: "Switches directly to tab number 1 through 9",
            category: .tabs
        ),
        TerminalShortcut(
            keys: ["⌘", "⇧", "["],
            title: "Previous Tab",
            description: "Switches to the tab on the left",
            category: .tabs
        ),
        TerminalShortcut(
            keys: ["⌘", "⇧", "]"],
            title: "Next Tab",
            description: "Switches to the tab on the right",
            category: .tabs
        ),
        TerminalShortcut(
            keys: ["⌘", "⇧", "R"],
            title: "Rename Tab",
            description: "Renames the current tab (also double-click any tab)",
            category: .tabs
        ),
        TerminalShortcut(
            keys: ["⌘", "⌥", "P"],
            title: "Toggle Tab Bar Position",
            description: "Toggles tabs between Upper Pane (Top) and Left Pane (Sidebar)",
            category: .tabs
        ),

        // Search & Find
        TerminalShortcut(
            keys: ["⌘", "F"],
            title: "Find in Terminal",
            description: "Opens the search bar to search visible and scrollback text",
            category: .search
        ),
        TerminalShortcut(
            keys: ["Return"],
            title: "Find Next",
            description: "Navigates to the next search match (also ⌘G)",
            category: .search
        ),
        TerminalShortcut(
            keys: ["⇧", "Return"],
            title: "Find Previous",
            description: "Navigates to the previous search match (also ⌘⇧G)",
            category: .search
        ),
        TerminalShortcut(
            keys: ["Esc"],
            title: "Dismiss Find",
            description: "Closes the search bar and clears highlights",
            category: .search
        ),

        // Files & Links
        TerminalShortcut(
            keys: ["⌘", "Click"],
            title: "Open File or Link",
            description: "Opens the clicked file in its default editor, or URL in browser",
            category: .files
        ),
        TerminalShortcut(
            keys: ["⌘", "⌥", "Click"],
            title: "Reveal in Finder",
            description: "Reveals the clicked file or folder in macOS Finder",
            category: .files
        ),
        TerminalShortcut(
            keys: ["⌘", "⇧", "O"],
            title: "Open Path in Finder",
            description: "Reveals selected file path in Finder",
            category: .files
        ),

        // Clipboard & Media
        TerminalShortcut(
            keys: ["⌘", "C"],
            title: "Copy",
            description: "Copies selected text to the macOS clipboard",
            category: .clipboard
        ),
        TerminalShortcut(
            keys: ["⌘", "V"],
            title: "Smart Paste",
            description: "Pastes text, or saves clipboard image to file and pastes its path",
            category: .clipboard
        ),
        TerminalShortcut(
            keys: ["⌘", "⇧", "C"],
            title: "Capture Screenshot",
            description: "Captures an interactive screenshot and pastes its path into prompt",
            category: .clipboard
        ),
        TerminalShortcut(
            keys: ["Drag & Drop"],
            title: "Drop File or Image",
            description: "Drag any file from Finder into terminal to insert escaped path",
            category: .clipboard
        ),

        // Terminal & Display
        TerminalShortcut(
            keys: ["⌘", "+"],
            title: "Increase Font Size",
            description: "Zooms in terminal font size",
            category: .terminal
        ),
        TerminalShortcut(
            keys: ["⌘", "-"],
            title: "Decrease Font Size",
            description: "Zooms out terminal font size",
            category: .terminal
        ),
        TerminalShortcut(
            keys: ["⌘", "0"],
            title: "Reset Font Size",
            description: "Resets font size to default (14pt)",
            category: .terminal
        ),
        TerminalShortcut(
            keys: ["⌘", "K"],
            title: "Clear Buffer",
            description: "Clears the active screen buffer",
            category: .terminal
        ),
        TerminalShortcut(
            keys: ["⌘", "/"],
            title: "Keyboard Shortcuts",
            description: "Opens this shortcuts reference cheat sheet (also ⌘?)",
            category: .terminal
        ),
        TerminalShortcut(
            keys: ["Ctrl", "C"],
            title: "Cancel / Interrupt",
            description: "Sends SIGINT to the running foreground process",
            category: .terminal
        ),
        TerminalShortcut(
            keys: ["Ctrl", "D"],
            title: "EOF / Exit",
            description: "Sends end-of-file signal or exits shell session",
            category: .terminal
        )
    ]

    /// Group shortcuts by category
    public static func shortcuts(for category: ShortcutCategory) -> [TerminalShortcut] {
        return allShortcuts.filter { $0.category == category }
    }
}
