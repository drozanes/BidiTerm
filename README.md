# BidiTerm

A sleek, native macOS terminal emulator built in Swift with first-class support for **Hebrew and English bidirectional (BiDi) text**, **tabs**, **smart link/file opening**, **search**, and **smart image handling**.

---

## Key Features

1. **Natural Hebrew & English (BiDi Layout):**
   - Built on Apple's CoreText layout engine using the Unicode Bidirectional Algorithm (UAX #9 Rule P2).
   - Dedicated font cascading using `Arial Hebrew Bold` and medium-weight monospaced Latin font for crisp legibility.
   - Hebrew words, English words, file paths, numbers, and brackets appear in their proper visual order.
   - Cursors align correctly alongside Hebrew and English text.

2. **Multiple Tabs (`⌘T` / `⌘W`):**
   - Modern dark tab bar integrated directly into the window titlebar area.
   - Shortcuts:
     - `⌘T`: Open New Tab
     - `⌘W`: Close Active Tab
     - `⌘1` ... `⌘9`: Jump directly to Tab 1–9
     - `⌘⇧[` / `⌘⇧]`: Switch to Previous / Next Tab
     - Click `+` or tab close `✕` buttons.

3. **Open Files & Links (`⌘ + Click` / `⌘⌥ + Click`):**
   - **`⌘ + Click`**: Hover over any file path or web URL; cursor becomes a pointing hand. Clicking opens the file in your default code editor (VS Code, Cursor, Xcode, etc.) or URL in your default browser.
   - **`⌘⌥ + Click` (Command + Option + Click)**: Directly reveals the target file or folder in **macOS Finder**.
   - **`⌘⇧O`**: Reveals the selected text or active working directory in Finder.
   - **Right-Click Context Menu**: Right-click on any detected path for "Open", "Reveal in Finder", and "Copy Path".

4. **Terminal Text Search (`⌘F`):**
   - Instant search across visible screen buffer and scrollback history.
   - Live query highlighting with active match focus.
   - `Return` / `⌘G`: Jump to Next match.
   - `⇧Return` / `⌘⇧G`: Jump to Previous match.
   - `Esc`: Dismiss find bar and clear highlights.

5. **Keyboard Shortcuts Cheat Sheet (`⌘/` or `⌘?`):**
   - Floating translucent reference sheet showing all available shortcuts grouped by category.
   - Centralized registry that automatically updates whenever shortcuts are added or modified.

6. **Smart Clipboard Image Pasting (`⌘V`):**
   - Copy a screenshot or image to your clipboard and hit `⌘V` inside the terminal.
   - BidiTerm automatically saves the image to `~/Pictures/TerminalImages/` as a timestamped PNG and types the shell-escaped file path right into your prompt.
   - Perfect for working with modern AI CLI agents (Claude Code, etc.) and scripting.

7. **Interactive Screenshot Capture (`⌘⇧C` or `⌘⇧S`):**
   - Triggers the macOS crosshair screenshot tool, saves the selected area directly, and injects its path into your terminal.

8. **Drag & Drop:**
   - Drag any image or file directly from Finder into the terminal window to insert its path into the command line.

9. **Modern Terminal Controls:**
   - Full ANSI 16-color, 256-color, and 24-bit TrueColor support.
   - Font zoom with `⌘+`, `⌘-`, and `⌘0`.
   - Scrollback history buffer.
   - Standard keyboard shortcuts (`Ctrl+C`, `Ctrl+D`, `Ctrl+Z`, `Ctrl+L`, etc.).

---

## Keyboard Shortcuts Summary

| Category | Shortcut | Action |
| :--- | :--- | :--- |
| **Tabs** | `⌘T` | New Tab |
| | `⌘W` | Close Tab |
| | `⌘1` ... `⌘9` | Switch to Tab 1–9 |
| | `⌘⇧[` / `⌘⇧]` | Previous / Next Tab |
| **Search** | `⌘F` | Find in Terminal |
| | `Return` / `⌘G` | Find Next Match |
| | `⇧Return` / `⌘⇧G` | Find Previous Match |
| | `Esc` | Close Find Bar |
| **Files & Links** | `⌘ + Click` | Open File / URL in Default App |
| | `⌘⌥ + Click` | Reveal File in Finder |
| | `⌘⇧O` | Open Path in Finder |
| **Clipboard & Media** | `⌘C` | Copy Selection |
| | `⌘V` | Smart Paste (Text or Image path) |
| | `⌘⇧C` / `⌘⇧S` | Capture Screenshot to Prompt |
| | *Drag & Drop* | Insert Escaped Path |
| **Terminal & View** | `⌘+` / `⌘=` | Increase Font Size |
| | `⌘-` | Decrease Font Size |
| | `⌘0` | Reset Font Size (14pt) |
| | `⌘K` | Clear Screen Buffer |
| | `⌘/` or `⌘?` | Open Shortcuts Reference |

---

## Building and Running

### Quick Build (Development)
```bash
swift run
```

### Create Standalone macOS App Bundle
```bash
./build_app.sh
open BidiTerm.app
```
