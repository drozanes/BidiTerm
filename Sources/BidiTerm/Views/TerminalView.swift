import AppKit
import CoreText

public final class TerminalView: NSView {
    public var ptySession: PTYSession?
    public let buffer: TerminalBuffer
    public weak var windowController: MainWindowController?

    public var fontSize: CGFloat = 14.0 {
        didSet {
            updateFontMetrics()
            buffer.invalidateAllLineCaches()
            notifyResize()
            needsDisplay = true
        }
    }

    private var font: NSFont = NSFont.monospacedSystemFont(ofSize: 14.0, weight: .medium)
    private var boldFont: NSFont = NSFont.monospacedSystemFont(ofSize: 14.0, weight: .bold)
    private var italicFont: NSFont = NSFont.monospacedSystemFont(ofSize: 14.0, weight: .medium)
    private var fontAscent: CGFloat = 10.0
    private var fontDescent: CGFloat = 3.0
    private var lineHeight: CGFloat = 18.0
    private var charWidth: CGFloat = 8.0

    private let paddingLeft: CGFloat = 10.0
    private let paddingRight: CGFloat = 10.0
    private let paddingTop: CGFloat = 10.0

    // Selection
    private var selectionStart: (row: Int, col: Int)?
    private var selectionEnd: (row: Int, col: Int)?
    private var isSelecting: Bool = false

    // Search highlights
    public var searchMatches: [SearchMatch] = [] {
        didSet {
            needsDisplay = true
        }
    }
    public var activeSearchMatchIndex: Int = 0 {
        didSet {
            needsDisplay = true
        }
    }

    // Path Hover & Cmd+Click
    private var hoveredPath: DetectedPath?
    private var hoveredLocation: (lineIdx: Int, range: Range<Int>)?
    private var trackingArea: NSTrackingArea?

    // Scroll offset (0 = viewing bottom of buffer)
    public var scrollOffset: Int = 0 {
        didSet {
            needsDisplay = true
        }
    }

    // Cursor blink
    private var cursorBlinkTimer: Timer?
    private var cursorBlinkState: Bool = true

    public init(buffer: TerminalBuffer) {
        self.buffer = buffer
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = TerminalPalette.defaultBackground.cgColor

        updateFontMetrics()
        registerForDraggedTypes([.fileURL])

        // Cursor blink timer
        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.cursorBlinkState.toggle()
            self.needsDisplay = true
        }
    }

    deinit {
        cursorBlinkTimer?.invalidate()
    }

    override public var isFlipped: Bool {
        return true
    }

    override public var acceptsFirstResponder: Bool {
        return true
    }

    private func updateFontMetrics() {
        let size = fontSize
        // Medium base font for crisp, solid monospaced Latin characters
        let baseFont = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
        let boldBase = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)

        // Cascade list: Arial Hebrew Bold gives clear, legible, robust Hebrew strokes
        let hebrewBoldDesc = CTFontDescriptorCreateWithNameAndSize("ArialHebrew-Bold" as CFString, size)
        let hebrewRegularDesc = CTFontDescriptorCreateWithNameAndSize("Arial Hebrew" as CFString, size)

        let desc = CTFontCopyFontDescriptor(baseFont as CTFont)
        let descWithCascade = CTFontDescriptorCreateCopyWithAttributes(
            desc,
            [kCTFontCascadeListAttribute: [hebrewBoldDesc, hebrewRegularDesc]] as CFDictionary
        )
        font = CTFontCreateWithFontDescriptor(descWithCascade, size, nil) as NSFont

        let boldDesc = CTFontCopyFontDescriptor(boldBase as CTFont)
        let boldDescWithCascade = CTFontDescriptorCreateCopyWithAttributes(
            boldDesc,
            [kCTFontCascadeListAttribute: [hebrewBoldDesc]] as CFDictionary
        )
        boldFont = CTFontCreateWithFontDescriptor(boldDescWithCascade, size, nil) as NSFont
        italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)

        let ctFont = font as CTFont
        fontAscent = ceil(CTFontGetAscent(ctFont))
        fontDescent = ceil(CTFontGetDescent(ctFont))
        let leading = CTFontGetLeading(ctFont)
        lineHeight = max(16.0, ceil(fontAscent + fontDescent + leading + 4.0))

        let mSize = ("M" as NSString).size(withAttributes: [.font: font])
        charWidth = max(7.0, ceil(mSize.width))
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        notifyResize()
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    public func notifyResize() {
        let availableWidth = bounds.width - (paddingLeft + paddingRight)
        let availableHeight = bounds.height - (paddingTop * 2)

        let cols = max(20, Int(availableWidth / charWidth))
        let rows = max(5, Int(availableHeight / lineHeight))

        if cols != buffer.cols || rows != buffer.rows {
            buffer.resize(cols: cols, rows: rows)
            ptySession?.resize(cols: UInt16(cols), rows: UInt16(rows))
            needsDisplay = true
        }
    }

    public func getCwd() -> String? {
        if let pty = ptySession, pty.pid > 0 {
            return PathDetector.getProcessCwd(pid: pty.pid)
        }
        return nil
    }

    public func scrollToLine(index: Int) {
        let total = buffer.totalLineCount
        let visible = buffer.rows
        let targetBottom = min(total - 1, max(visible - 1, index + visible / 2))
        scrollOffset = max(0, total - 1 - targetBottom)
        needsDisplay = true
    }

    // MARK: - Drawing

    override public func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Enable subpixel font smoothing, antialiasing, and subpixel positioning
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)
        context.setAllowsFontSubpixelQuantization(true)
        context.setShouldSubpixelQuantizeFonts(true)

        // Background
        context.setFillColor(TerminalPalette.defaultBackground.cgColor)
        context.fill(bounds)

        let totalLines = buffer.totalLineCount
        let visibleRows = buffer.rows

        // Calculate line range based on scrollOffset
        let bottomIndex = max(0, totalLines - 1 - scrollOffset)
        let startIndex = max(0, bottomIndex - visibleRows + 1)

        for row in 0..<visibleRows {
            let lineIdx = startIndex + row
            let y = paddingTop + CGFloat(row) * lineHeight

            var drawnCTLine: CTLine?
            var lineAttrLen = 0
            var lineX: CGFloat = paddingLeft
            var isLineRTL = false

            if let line = buffer.line(at: lineIdx) {
                let (attrString, isRTL) = buildAttributedString(for: line)
                lineAttrLen = attrString.length
                isLineRTL = isRTL

                if lineAttrLen > 0 {
                    let ctLine = CTLineCreateWithAttributedString(attrString)
                    drawnCTLine = ctLine
                    let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
                    lineX = isRTL ? max(paddingLeft, bounds.width - paddingRight - lineWidth) : paddingLeft

                    // 1. Draw Search Highlights behind text
                    if !searchMatches.isEmpty {
                        for (mIdx, match) in searchMatches.enumerated() {
                            if match.lineIndex == lineIdx {
                                let isActive = (mIdx == activeSearchMatchIndex)
                                var minX: CGFloat = lineX + CGFloat(match.range.lowerBound) * charWidth
                                var matchW: CGFloat = CGFloat(match.range.count) * charWidth

                                var sec: CGFloat = 0
                                let idx1 = min(lineAttrLen, match.range.lowerBound)
                                let idx2 = min(lineAttrLen, match.range.upperBound)
                                let off1 = CTLineGetOffsetForStringIndex(ctLine, idx1, &sec)
                                let off2 = CTLineGetOffsetForStringIndex(ctLine, idx2, &sec)
                                minX = lineX + min(off1, off2)
                                matchW = max(charWidth, abs(off2 - off1))

                                let matchRect = NSRect(x: minX, y: y + 2, width: matchW, height: lineHeight - 2)
                                context.setFillColor((isActive ? TerminalPalette.activeSearchHighlight : TerminalPalette.searchHighlight).cgColor)
                                let path = CGPath(roundedRect: matchRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                                context.addPath(path)
                                context.fillPath()
                            }
                        }
                    }

                    // 2. Draw Selection Highlight behind text
                    if let (start, end) = normalizedSelection(), lineIdx >= start.row && lineIdx <= end.row {
                        let startCol = (lineIdx == start.row) ? start.col : 0
                        let endCol = (lineIdx == end.row) ? end.col : buffer.cols
                        let selX = lineX + CGFloat(startCol) * charWidth
                        let selW = CGFloat(max(1, endCol - startCol)) * charWidth
                        context.setFillColor(TerminalPalette.selectionColor.cgColor)
                        context.fill(NSRect(x: selX, y: y + 1, width: selW, height: lineHeight - 2))
                    }

                    // 3. Draw Text
                    context.saveGState()
                    context.textMatrix = .identity
                    context.translateBy(x: lineX, y: y + fontAscent)
                    context.scaleBy(x: 1.0, y: -1.0)
                    CTLineDraw(ctLine, context)
                    context.restoreGState()

                    // 4. Draw Cmd+Hover Path Underline
                    if let (hoverLine, hoverRange) = hoveredLocation, hoverLine == lineIdx {
                        var minX: CGFloat = lineX + CGFloat(hoverRange.lowerBound) * charWidth
                        var matchW: CGFloat = CGFloat(hoverRange.count) * charWidth
                        var sec: CGFloat = 0
                        let idx1 = min(lineAttrLen, hoverRange.lowerBound)
                        let idx2 = min(lineAttrLen, hoverRange.upperBound)
                        let off1 = CTLineGetOffsetForStringIndex(ctLine, idx1, &sec)
                        let off2 = CTLineGetOffsetForStringIndex(ctLine, idx2, &sec)
                        minX = lineX + min(off1, off2)
                        matchW = max(charWidth, abs(off2 - off1))

                        context.setFillColor(NSColor(srgbRed: 0.45, green: 0.75, blue: 1.0, alpha: 0.90).cgColor)
                        context.fill(NSRect(x: minX, y: y + lineHeight - 2, width: matchW, height: 1.5))
                    }
                }
            }

            // Draw Cursor
            if scrollOffset == 0 && row == buffer.cursorRow && buffer.cursorVisible {
                drawCursor(context: context, ctLine: drawnCTLine, lineX: lineX, isRTL: isLineRTL, rowY: y, lineLen: lineAttrLen)
            }
        }
    }

    private func isRTLLine(_ line: TerminalLine) -> Bool {
        for cell in line.cells {
            for scalar in cell.char.unicodeScalars {
                let val = scalar.value
                if val <= 0x0040 || (val >= 0x005B && val <= 0x0060) || (val >= 0x007B && val <= 0x007E) || val == 0x2022 {
                    continue
                }
                if (val >= 0x0590 && val <= 0x05FF) || (val >= 0x0600 && val <= 0x06FF) || (val >= 0xFB1D && val <= 0xFB4F) {
                    return true
                }
                if (val >= 0x0041 && val <= 0x005A) || (val >= 0x0061 && val <= 0x007A) {
                    return false
                }
            }
        }
        return false
    }

    private func buildAttributedString(for line: TerminalLine) -> (attrString: NSAttributedString, isRTL: Bool) {
        if let cached = line.cachedAttributedString {
            return (cached, line.isCachedRTL)
        }

        let isRTL = isRTLLine(line)
        line.isCachedRTL = isRTL

        let pStyle = NSMutableParagraphStyle()
        pStyle.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight

        let result = NSMutableAttributedString()
        guard !line.cells.isEmpty else {
            line.cachedAttributedString = result
            return (result, isRTL)
        }

        var lastNonSpace = -1
        for i in stride(from: line.cells.count - 1, through: 0, by: -1) {
            let cell = line.cells[i]
            if cell.char != " " || cell.style.bgColor != nil || cell.style.isInverse {
                lastNonSpace = i
                break
            }
        }

        guard lastNonSpace >= 0 else {
            line.cachedAttributedString = result
            return (result, isRTL)
        }

        let relevantCells = line.cells[0...lastNonSpace]
        var currentChars = ""
        var currentStyle = relevantCells[0].style

        for cell in relevantCells {
            if cell.style == currentStyle {
                currentChars.append(cell.char)
            } else {
                appendRun(chars: currentChars, style: currentStyle, pStyle: pStyle, to: result)
                currentChars = String(cell.char)
                currentStyle = cell.style
            }
        }
        if !currentChars.isEmpty {
            appendRun(chars: currentChars, style: currentStyle, pStyle: pStyle, to: result)
        }

        line.cachedAttributedString = result
        return (result, isRTL)
    }

    private func appendRun(chars: String, style: TerminalStyle, pStyle: NSParagraphStyle, to result: NSMutableAttributedString) {
        var attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: pStyle,
            .foregroundColor: style.effectiveForeground(),
        ]

        if style.isBold {
            attrs[.font] = boldFont
        } else if style.isItalic {
            attrs[.font] = italicFont
        } else {
            attrs[.font] = font
        }

        if let bg = style.effectiveBackground() {
            attrs[.backgroundColor] = bg
        }

        if style.isUnderline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        result.append(NSAttributedString(string: chars, attributes: attrs))
    }

    private func drawCursor(context: CGContext, ctLine: CTLine?, lineX: CGFloat, isRTL: Bool, rowY: CGFloat, lineLen: Int) {
        guard cursorBlinkState else { return }

        let targetCol = buffer.cursorCol
        let rawCursorX = calculateCursorX(ctLine: ctLine, targetCol: targetCol, lineLen: lineLen, isRTL: isRTL, lineX: lineX)
        let cursorX = max(paddingLeft, min(bounds.width - paddingRight - charWidth, rawCursorX))

        let cursorRect = NSRect(x: cursorX, y: rowY + 2, width: charWidth, height: lineHeight - 2)
        context.setFillColor(TerminalPalette.cursorColor.cgColor)
        context.fill(cursorRect)
    }

    private func calculateCursorX(ctLine: CTLine?, targetCol: Int, lineLen: Int, isRTL: Bool, lineX: CGFloat) -> CGFloat {
        guard let ctLine = ctLine, lineLen > 0 else {
            if isRTL {
                return bounds.width - paddingRight - charWidth
            } else {
                return paddingLeft
            }
        }

        let runs = CTLineGetGlyphRuns(ctLine) as! [CTRun]

        // 1. If targetCol is on an existing glyph, find its exact visual position
        for r in runs {
            let count = CTRunGetGlyphCount(r)
            var indices = [CFIndex](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetStringIndices(r, CFRangeMake(0, count), &indices)
            CTRunGetPositions(r, CFRangeMake(0, count), &positions)

            for i in 0..<count {
                if indices[i] == targetCol {
                    return lineX + positions[i].x
                }
            }
        }

        // 2. If targetCol is at or past the end of the text (insertion point):
        if targetCol >= lineLen {
            let extra = CGFloat(targetCol - lineLen) * charWidth
            for r in runs {
                let count = CTRunGetGlyphCount(r)
                var indices = [CFIndex](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetStringIndices(r, CFRangeMake(0, count), &indices)
                CTRunGetPositions(r, CFRangeMake(0, count), &positions)
                let isLastRTL = CTRunGetStatus(r).contains(.rightToLeft)

                for i in 0..<count {
                    if indices[i] == lineLen - 1 {
                        let lastX = lineX + positions[i].x
                        if isLastRTL {
                            // In RTL, the next character will be placed to the LEFT of the last character
                            return lastX - charWidth - extra
                        } else {
                            // In LTR, the next character will be placed to the RIGHT of the last character
                            return lastX + charWidth + extra
                        }
                    }
                }
            }
        }

        return lineX + CGFloat(targetCol) * charWidth
    }

    // MARK: - Keyboard Handling

    override public func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Handle Command shortcuts (with hardware keyCode fallback for Hebrew keyboard layouts)
        if flags.contains(.command) && !flags.contains([.control]) {
            // Command + Shift shortcuts
            if flags.contains(.shift) {
                switch event.keyCode {
                case 8: // Cmd+Shift+C
                    handleScreenshotCapture()
                    return
                case 31: // Cmd+Shift+O
                    revealSelectedPathInFinder()
                    return
                case 17: // Cmd+Shift+T
                    windowController?.reopenLastClosedTab()
                    return
                default:
                    break
                }

                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c", "s":
                    handleScreenshotCapture()
                    return
                case "o":
                    revealSelectedPathInFinder()
                    return
                case "[":
                    windowController?.selectPreviousTab()
                    return
                case "]":
                    windowController?.selectNextTab()
                    return
                case "g":
                    windowController?.searchBarDidRequestPreviousMatch(windowController!.searchBarView)
                    return
                default:
                    break
                }
            }

            // Command shortcuts by hardware keyCode (works in any keyboard layout: Hebrew, English, etc.)
            switch event.keyCode {
            case 9: // Cmd+V (Paste)
                handlePaste()
                return
            case 8: // Cmd+C (Copy)
                handleCopy()
                return
            case 17: // Cmd+T (New Tab)
                windowController?.createNewTab()
                return
            case 13: // Cmd+W (Close Tab)
                windowController?.closeCurrentTab()
                return
            case 3: // Cmd+F (Find)
                windowController?.toggleSearchBar()
                return
            case 40: // Cmd+K (Clear buffer)
                buffer.eraseInDisplay(mode: 3)
                needsDisplay = true
                return
            case 24: // Cmd+= (+)
                fontSize = min(32.0, fontSize + 1.0)
                return
            case 27: // Cmd+-
                fontSize = max(9.0, fontSize - 1.0)
                return
            case 29: // Cmd+0
                fontSize = 14.0
                return
            case 44: // Cmd+/
                ShortcutsWindowController.shared.toggle()
                return
            default:
                break
            }

            switch event.charactersIgnoringModifiers {
            case "t":
                windowController?.createNewTab()
                return
            case "w":
                windowController?.closeCurrentTab()
                return
            case "f":
                windowController?.toggleSearchBar()
                return
            case "g":
                windowController?.searchBarDidRequestNextMatch(windowController!.searchBarView)
                return
            case "/":
                ShortcutsWindowController.shared.toggle()
                return
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                if let num = Int(event.charactersIgnoringModifiers ?? "") {
                    windowController?.selectTab(at: num - 1)
                    return
                }
            case "v":
                handlePaste()
                return
            case "c":
                handleCopy()
                return
            case "k":
                buffer.eraseInDisplay(mode: 3)
                needsDisplay = true
                return
            case "+", "=":
                fontSize = min(32.0, fontSize + 1.0)
                return
            case "-":
                fontSize = max(9.0, fontSize - 1.0)
                return
            case "0":
                fontSize = 14.0
                return
            default:
                break
            }

            super.keyDown(with: event)
            return
        }

        // Handle Control combinations (e.g. Ctrl+C, Ctrl+D, Ctrl+Z)
        if flags.contains(.control) {
            // First check hardware keyCode so Ctrl+C, Ctrl+D, etc. always work even in Hebrew keyboard layout
            if let byte = controlCode(for: event.keyCode) {
                ptySession?.write(data: Data([byte]))
                resetScroll()
                return
            }

            if let chars = event.charactersIgnoringModifiers, let firstChar = chars.first {
                let asciiVal = firstChar.asciiValue ?? 0
                if asciiVal >= 64 && asciiVal <= 95 { // '@' to '_'
                    let byte = asciiVal - 64
                    ptySession?.write(data: Data([byte]))
                    resetScroll()
                    return
                } else if asciiVal >= 97 && asciiVal <= 122 { // 'a' to 'z'
                    let byte = asciiVal - 96
                    ptySession?.write(data: Data([byte]))
                    resetScroll()
                    return
                }
            }
        }

        // Handle Special Keys
        if let specialCode = specialKeySequence(for: event.keyCode) {
            ptySession?.write(string: specialCode)
            resetScroll()
            return
        }

        // Standard Text (Hebrew, English, symbols, numbers)
        if let characters = event.characters {
            ptySession?.write(string: characters)
            resetScroll()
        }
    }

    private func controlCode(for keyCode: UInt16) -> UInt8? {
        switch keyCode {
        case 0: return 1   // Ctrl+A
        case 11: return 2  // Ctrl+B
        case 8: return 3   // Ctrl+C (SIGINT)
        case 2: return 4   // Ctrl+D (EOF)
        case 14: return 5  // Ctrl+E
        case 3: return 6   // Ctrl+F
        case 5: return 7   // Ctrl+G
        case 4: return 8   // Ctrl+H (Backspace)
        case 34: return 9  // Ctrl+I (Tab)
        case 38: return 10 // Ctrl+J (Linefeed)
        case 40: return 11 // Ctrl+K
        case 37: return 12 // Ctrl+L (Clear screen)
        case 46: return 13 // Ctrl+M (Return)
        case 45: return 14 // Ctrl+N
        case 31: return 15 // Ctrl+O
        case 35: return 16 // Ctrl+P
        case 12: return 17 // Ctrl+Q
        case 15: return 18 // Ctrl+R
        case 1: return 19  // Ctrl+S
        case 17: return 20 // Ctrl+T
        case 32: return 21 // Ctrl+U
        case 9: return 22  // Ctrl+V
        case 13: return 23 // Ctrl+W
        case 7: return 24  // Ctrl+X
        case 16: return 25 // Ctrl+Y
        case 6: return 26  // Ctrl+Z (SIGTSTP)
        case 33: return 27 // Ctrl+[ (Escape)
        case 42: return 28 // Ctrl+\ (SIGQUIT)
        case 30: return 29 // Ctrl+]
        default: return nil
        }
    }

    private func specialKeySequence(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "\r"          // Return
        case 48: return "\t"          // Tab
        case 51: return "\u{7F}"      // Backspace
        case 53: return "\u{1B}"      // Escape
        case 126: return "\u{1B}[A"   // Up Arrow
        case 125: return "\u{1B}[B"   // Down Arrow
        case 124: // Right Arrow
            // In RTL context, moving visually to the Right corresponds to moving backwards in memory (\e[D)
            return isCursorAtRTL() ? "\u{1B}[D" : "\u{1B}[C"
        case 123: // Left Arrow
            // In RTL context, moving visually to the Left corresponds to moving forwards in memory (\e[C)
            return isCursorAtRTL() ? "\u{1B}[C" : "\u{1B}[D"
        case 115: return "\u{1B}[H"   // Home
        case 119: return "\u{1B}[F"   // End
        case 116: return "\u{1B}[5~"  // Page Up
        case 121: return "\u{1B}[6~"  // Page Down
        case 117: return "\u{1B}[3~"  // Forward Delete
        default: return nil
        }
    }

    private func isCursorAtRTL() -> Bool {
        guard let line = buffer.line(at: buffer.cursorRow) else { return false }
        let col = buffer.cursorCol

        // 1. Check cell at current cursor position
        if col < line.cells.count {
            let ch = line.cells[col].char
            if isHebrewChar(ch) { return true }
        }

        // 2. Check cell immediately before cursor (insertion point after Hebrew word)
        if col > 0 && col - 1 < line.cells.count {
            let prevCh = line.cells[col - 1].char
            if isHebrewChar(prevCh) { return true }
        }

        // 3. Check if line as a whole is cached as RTL
        if line.isCachedRTL == true {
            return true
        }

        return false
    }

    private func isHebrewChar(_ ch: Character) -> Bool {
        for scalar in ch.unicodeScalars {
            let val = scalar.value
            if (val >= 0x0590 && val <= 0x05FF) || (val >= 0xFB1D && val <= 0xFB4F) {
                return true
            }
        }
        return false
    }

    private func resetScroll() {
        if scrollOffset != 0 {
            scrollOffset = 0
            needsDisplay = true
        }
    }

    // MARK: - Smart Paste & Clipboard

    public func handlePaste() {
        let pasteboard = NSPasteboard.general

        // 1. Text paste takes priority
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            // Normalize line endings:
            // In terminal raw PTY mode, CR (\r) is the canonical Enter/line-submission character.
            // Converting both \r\n and \n to \r ensures multi-line pastes never hang or drop newlines in CLI tools.
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")

            if buffer.bracketedPasteMode {
                ptySession?.write(string: "\u{1B}[200~" + normalized + "\u{1B}[201~")
            } else {
                ptySession?.write(string: normalized)
            }
            resetScroll()
            return
        }

        // 2. If no text, check for image data to save to file
        if ImageClipboardManager.shared.hasImage() {
            if let escapedPath = ImageClipboardManager.shared.saveClipboardImageToFile() {
                ptySession?.write(string: "\(escapedPath) ")
                resetScroll()
                return
            }
        }
    }

    public func handleCopy() {
        if let (start, end) = normalizedSelection() {
            var selectedText = ""
            for r in start.row...end.row {
                guard let line = buffer.line(at: r) else { continue }
                let lineChars = line.cells.map { $0.char }
                let cStart = (r == start.row) ? start.col : 0
                let cEnd = (r == end.row) ? min(end.col, lineChars.count - 1) : lineChars.count - 1

                if cStart <= cEnd && cStart < lineChars.count {
                    let slice = lineChars[cStart...cEnd]
                    selectedText += String(slice)
                }
                if r < end.row {
                    selectedText += "\n"
                }
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selectedText, forType: .string)
        }
    }

    public func handleScreenshotCapture() {
        ImageClipboardManager.shared.captureInteractiveScreenshot { [weak self] escapedPath in
            guard let self = self, let path = escapedPath else { return }
            self.ptySession?.write(string: "\(path) ")
            self.resetScroll()
        }
    }

    public func revealSelectedPathInFinder() {
        if let (start, end) = normalizedSelection() {
            var selectedText = ""
            for r in start.row...end.row {
                guard let line = buffer.line(at: r) else { continue }
                let lineChars = line.cells.map { $0.char }
                let cStart = (r == start.row) ? start.col : 0
                let cEnd = (r == end.row) ? min(end.col, lineChars.count - 1) : lineChars.count - 1
                if cStart <= cEnd && cStart < lineChars.count {
                    selectedText += String(lineChars[cStart...cEnd])
                }
            }
            let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = PathDetector.detectPath(candidate: trimmed, cwd: getCwd()) {
                NSWorkspace.shared.activateFileViewerSelecting([path.targetURL])
                return
            }
        }
        if let cwd = getCwd() {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
        }
    }

    // MARK: - Drag and Drop

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.fileURL.rawValue]) {
            return .copy
        }
        return []
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return false
        }

        let paths = urls.map { ImageClipboardManager.shared.shellEscape(path: $0.path) }
        let combined = paths.joined(separator: " ") + " "
        ptySession?.write(string: combined)
        resetScroll()
        return true
    }

    // MARK: - Mouse Events, Hover & Cmd+Click

    override public func mouseMoved(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let pt = convert(event.locationInWindow, from: nil)
            let row = Int((pt.y - paddingTop) / lineHeight)
            let col = max(0, Int((pt.x - paddingLeft) / charWidth))
            let totalLines = buffer.totalLineCount
            let bottomIndex = max(0, totalLines - 1 - scrollOffset)
            let startIndex = max(0, bottomIndex - buffer.rows + 1)
            let lineIdx = startIndex + row

            if let line = buffer.line(at: lineIdx),
               let token = PathDetector.extractToken(on: line.trimmedText, at: col),
               let detected = PathDetector.detectPath(candidate: token, cwd: getCwd()) {
                hoveredPath = detected
                if let range = line.trimmedText.range(of: token) {
                    let startCol = line.trimmedText.distance(from: line.trimmedText.startIndex, to: range.lowerBound)
                    let endCol = line.trimmedText.distance(from: line.trimmedText.startIndex, to: range.upperBound)
                    hoveredLocation = (lineIdx, startCol..<endCol)
                }
                NSCursor.pointingHand.set()
                needsDisplay = true
                return
            }
        }

        if hoveredPath != nil {
            hoveredPath = nil
            hoveredLocation = nil
            NSCursor.iBeam.set()
            needsDisplay = true
        }
    }

    override public func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if !event.modifierFlags.contains(.command) && hoveredPath != nil {
            hoveredPath = nil
            hoveredLocation = nil
            NSCursor.iBeam.set()
            needsDisplay = true
        }
    }

    override public func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let row = Int((pt.y - paddingTop) / lineHeight)
        let col = max(0, Int((pt.x - paddingLeft) / charWidth))
        let totalLines = buffer.totalLineCount
        let bottomIndex = max(0, totalLines - 1 - scrollOffset)
        let startIndex = max(0, bottomIndex - buffer.rows + 1)
        let lineIdx = startIndex + row

        // Check Cmd + Click to open file/URL or reveal in Finder
        if event.modifierFlags.contains(.command) {
            if let line = buffer.line(at: lineIdx),
               let token = PathDetector.extractToken(on: line.trimmedText, at: col),
               let detected = PathDetector.detectPath(candidate: token, cwd: getCwd()) {
                if event.modifierFlags.contains(.option) {
                    // Cmd + Option + Click -> Reveal in Finder
                    NSWorkspace.shared.activateFileViewerSelecting([detected.targetURL])
                } else {
                    // Cmd + Click -> Open in Default Application / Browser
                    NSWorkspace.shared.open(detected.targetURL)
                }
                return
            }
        }

        // Standard Selection
        selectionStart = (row: lineIdx, col: col)
        selectionEnd = selectionStart
        isSelecting = true
        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let row = Int((pt.y - paddingTop) / lineHeight)
        let col = max(0, Int((pt.x - paddingLeft) / charWidth))
        let totalLines = buffer.totalLineCount
        let bottomIndex = max(0, totalLines - 1 - scrollOffset)
        let startIndex = max(0, bottomIndex - buffer.rows + 1)
        let lineIdx = startIndex + row

        selectionEnd = (row: lineIdx, col: col)
        needsDisplay = true
    }

    override public func mouseUp(with event: NSEvent) {
        isSelecting = false
    }

    // Contextual Right-Click Menu
    override public func menu(for event: NSEvent) -> NSMenu? {
        let pt = convert(event.locationInWindow, from: nil)
        let row = Int((pt.y - paddingTop) / lineHeight)
        let col = max(0, Int((pt.x - paddingLeft) / charWidth))
        let totalLines = buffer.totalLineCount
        let bottomIndex = max(0, totalLines - 1 - scrollOffset)
        let startIndex = max(0, bottomIndex - buffer.rows + 1)
        let lineIdx = startIndex + row

        let contextMenu = NSMenu(title: "Terminal")

        if let line = buffer.line(at: lineIdx),
           let token = PathDetector.extractToken(on: line.trimmedText, at: col),
           let detected = PathDetector.detectPath(candidate: token, cwd: getCwd()) {
            let openItem = NSMenuItem(title: "Open \"\(token)\"", action: #selector(contextOpenPath(_:)), keyEquivalent: "")
            openItem.representedObject = detected.targetURL
            openItem.target = self
            contextMenu.addItem(openItem)

            let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(contextRevealPath(_:)), keyEquivalent: "")
            revealItem.representedObject = detected.targetURL
            revealItem.target = self
            contextMenu.addItem(revealItem)

            let copyPathItem = NSMenuItem(title: "Copy Path", action: #selector(contextCopyPath(_:)), keyEquivalent: "")
            copyPathItem.representedObject = detected.targetURL.path
            copyPathItem.target = self
            contextMenu.addItem(copyPathItem)

            contextMenu.addItem(NSMenuItem.separator())
        }

        contextMenu.addItem(withTitle: "Copy", action: #selector(MainWindowController.copyAction(_:)), keyEquivalent: "c")
        contextMenu.addItem(withTitle: "Paste", action: #selector(MainWindowController.pasteAction(_:)), keyEquivalent: "v")
        contextMenu.addItem(withTitle: "Find...", action: #selector(MainWindowController.toggleSearchAction(_:)), keyEquivalent: "f")
        contextMenu.addItem(NSMenuItem.separator())
        contextMenu.addItem(withTitle: "Keyboard Shortcuts...", action: #selector(MainWindowController.showShortcutsAction(_:)), keyEquivalent: "/")

        return contextMenu
    }

    @objc private func contextOpenPath(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func contextRevealPath(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func contextCopyPath(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(path, forType: .string)
        }
    }

    // MARK: - Scrolling

    override public func scrollWheel(with event: NSEvent) {
        if event.deltaY > 0 {
            let maxOffset = max(0, buffer.totalLineCount - buffer.rows)
            scrollOffset = min(maxOffset, scrollOffset + Int(ceil(event.deltaY)))
        } else if event.deltaY < 0 {
            scrollOffset = max(0, scrollOffset + Int(floor(event.deltaY)))
        }
    }

    // MARK: - Selection

    private func normalizedSelection() -> (start: (row: Int, col: Int), end: (row: Int, col: Int))? {
        guard let s = selectionStart, let e = selectionEnd else { return nil }
        if s.row < e.row || (s.row == e.row && s.col <= e.col) {
            return (s, e)
        } else {
            return (e, s)
        }
    }
}
