# BidiTerm

A sleek, native macOS terminal emulator built in Swift with first-class support for **Hebrew and English bidirectional (BiDi) text** and **smart image handling**.

---

## Key Features

1. **Natural Hebrew & English (BiDi Layout):**
   - Built on Apple's CoreText layout engine.
   - Text is formatted using the Unicode Bidirectional Algorithm (UAX #9) per line.
   - Hebrew words, English words, file paths, numbers, and brackets appear in their proper visual order without scrambled letters or inverted parentheses.
   - Cursors align correctly alongside Hebrew and English text.

2. **Smart Clipboard Image Pasting (`⌘V`):**
   - Copy a screenshot or image to your clipboard and hit `⌘V` inside the terminal.
   - BidiTerm automatically saves the image to `~/Pictures/TerminalImages/` as a timestamped PNG and types the shell-escaped file path right into your prompt.
   - Perfect for working with modern AI CLI agents (Claude Code, Aider, etc.) and scripting.

3. **Interactive Screenshot Capture (`⌘⇧C` or `⌘⇧S`):**
   - Triggers the macOS crosshair screenshot tool, saves the selected area directly, and injects its path into your terminal.

4. **Drag & Drop:**
   - Drag any image or file directly from Finder into the terminal window to insert its path into the command line.

5. **Modern Terminal Controls:**
   - Full ANSI 16-color, 256-color, and 24-bit TrueColor support.
   - Font zoom with `⌘+`, `⌘-`, and `⌘0`.
   - Scrollback history buffer.
   - Standard keyboard shortcuts (`Ctrl+C`, `Ctrl+D`, `Ctrl+Z`, `Ctrl+L`, etc.).

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
