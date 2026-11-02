import AppKit
import CoreText

public final class TerminalView: NSView {
    public var ptySession: PTYSession?
    public let buffer: TerminalBuffer

    public var fontSize: CGFloat = 13.0 {
        didSet {
            updateFontMetrics()
            notifyResize()
            needsDisplay = true
        }
    }

    private var font: NSFont = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)
    private var boldFont: NSFont = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .bold)
    private var italicFont: NSFont = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)
    private var fontAscent: CGFloat = 10.0
    private var fontDescent: CGFloat = 3.0
    private var lineHeight: CGFloat = 18.0
    private var charWidth: CGFloat = 8.0

    private let paddingLeft: CGFloat = 10.0
    private let paddingTop: CGFloat = 10.0

    // Selection
    private var selectionStart: (row: Int, col: Int)?
    private var selectionEnd: (row: Int, col: Int)?
    private var isSelecting: Bool = false

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
        font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)

        let ctFont = font as CTFont
        fontAscent = ceil(CTFontGetAscent(ctFont))
        fontDescent = ceil(CTFontGetDescent(ctFont))
        let leading = CTFontGetLeading(ctFont)
        lineHeight = max(14.0, ceil(fontAscent + fontDescent + leading + 4.0))

        let mSize = ("M" as NSString).size(withAttributes: [.font: font])
        charWidth = max(6.0, ceil(mSize.width))
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        notifyResize()
    }

    public func notifyResize() {
        let availableWidth = bounds.width - (paddingLeft * 2)
        let availableHeight = bounds.height - (paddingTop * 2)

        let cols = max(20, Int(availableWidth / charWidth))
        let rows = max(5, Int(availableHeight / lineHeight))

        if cols != buffer.cols || rows != buffer.rows {
            buffer.resize(cols: cols, rows: rows)
            ptySession?.resize(cols: UInt16(cols), rows: UInt16(rows))
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    override public func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Background
        context.setFillColor(TerminalPalette.defaultBackground.cgColor)
        context.fill(bounds)

        let totalLines = buffer.totalLineCount
        let visibleRows = buffer.rows

        // Calculate line range based on scrollOffset
        let bottomIndex = max(0, totalLines - 1 - scrollOffset)
        let startIndex = max(0, bottomIndex - visibleRows + 1)

        let styleParagraph = NSMutableParagraphStyle()
        styleParagraph.baseWritingDirection = .leftToRight

        for row in 0..<visibleRows {
            let lineIdx = startIndex + row
            let y = paddingTop + CGFloat(row) * lineHeight

            var drawnCTLine: CTLine?
            var drawnLine: TerminalLine?
            var lineAttrLen = 0

            if let line = buffer.line(at: lineIdx) {
                drawnLine = line
                let attrString = buildAttributedString(for: line, pStyle: styleParagraph)
                lineAttrLen = attrString.length

                if lineAttrLen > 0 {
                    let ctLine = CTLineCreateWithAttributedString(attrString)
                    drawnCTLine = ctLine

                    context.saveGState()
                    context.textMatrix = .identity
                    context.translateBy(x: paddingLeft, y: y + fontAscent)
                    context.scaleBy(x: 1.0, y: -1.0)
                    CTLineDraw(ctLine, context)
                    context.restoreGState()
                }
            }

            // Draw Cursor
            if scrollOffset == 0 && row == buffer.cursorRow && buffer.cursorVisible {
                drawCursor(context: context, ctLine: drawnCTLine, line: drawnLine, rowY: y, lineLen: lineAttrLen)
            }
        }
    }

    private func buildAttributedString(for line: TerminalLine, pStyle: NSParagraphStyle) -> NSAttributedString {
        if let cached = line.cachedAttributedString {
            return cached
        }

        let result = NSMutableAttributedString()
        guard !line.cells.isEmpty else {
            return result
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
            line.cachedColToAttrMap = []
            return result
        }

        let relevantCells = Array(line.cells[0...lastNonSpace])

        // Fix Hebrew abbreviations punctuation (" -> ״, ' -> ׳)
        var preprocessedCells = relevantCells
        for i in 0..<relevantCells.count {
            let ch = relevantCells[i].char
            if ch == "\"" {
                let prevHeb = i > 0 && isHebrew(relevantCells[i-1].char)
                let nextHeb = i + 1 < relevantCells.count && isHebrew(relevantCells[i+1].char)
                if prevHeb && nextHeb {
                    preprocessedCells[i] = TerminalCell(char: "\u{05F4}", style: relevantCells[i].style)
                }
            } else if ch == "'" {
                let prevHeb = i > 0 && isHebrew(relevantCells[i-1].char)
                if prevHeb {
                    preprocessedCells[i] = TerminalCell(char: "\u{05F3}", style: relevantCells[i].style)
                }
            }
        }

        // Segment Hebrew tokens with Right-to-Left Isolate (\u{2067}) so they read naturally in sentence order
        var formattedTokens: [(text: String, style: TerminalStyle, origCol: Int?)] = []
        var inHebrew = false

        for col in 0..<preprocessedCells.count {
            let cell = preprocessedCells[col]
            let ch = cell.char
            let isHeb = isHebrew(ch)
            let isHebPunct = (ch == "\u{05F4}" || ch == "\u{05F3}" || ch == "-") && inHebrew

            if isHeb || isHebPunct {
                if !inHebrew {
                    formattedTokens.append((text: "\u{2067}", style: cell.style, origCol: nil))
                    inHebrew = true
                }
                formattedTokens.append((text: String(ch), style: cell.style, origCol: col))
            } else {
                if inHebrew {
                    formattedTokens.append((text: "\u{2069}", style: cell.style, origCol: nil))
                    inHebrew = false
                }
                formattedTokens.append((text: String(ch), style: cell.style, origCol: col))
            }
        }
        if inHebrew {
            let lastStyle = preprocessedCells.last?.style ?? .default
            formattedTokens.append((text: "\u{2069}", style: lastStyle, origCol: nil))
        }

        // Assemble AttributedString and build colToAttr map
        var colToAttr = Array(repeating: 0, count: relevantCells.count)
        var currentAttrLen = 0

        for token in formattedTokens {
            if let col = token.origCol, col < colToAttr.count {
                colToAttr[col] = currentAttrLen
            }
            appendRun(chars: token.text, style: token.style, pStyle: pStyle, to: result)
            currentAttrLen = result.length
        }

        line.cachedColToAttrMap = colToAttr
        line.cachedAttributedString = result
        return result
    }

    private func isHebrew(_ ch: Character) -> Bool {
        return ch.unicodeScalars.contains { $0.value >= 0x0590 && $0.value <= 0x05FF }
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

    private func drawCursor(context: CGContext, ctLine: CTLine?, line: TerminalLine?, rowY: CGFloat, lineLen: Int) {
        guard cursorBlinkState else { return }

        var cursorX: CGFloat = paddingLeft
        let targetCol = buffer.cursorCol

        if let ctLine = ctLine, let line = line, lineLen > 0 {
            if targetCol < line.cachedColToAttrMap.count {
                let attrIdx = line.cachedColToAttrMap[targetCol]
                var secondary: CGFloat = 0
                let offset = CTLineGetOffsetForStringIndex(ctLine, attrIdx, &secondary)
                cursorX += offset
            } else {
                var secondary: CGFloat = 0
                let endOffset = CTLineGetOffsetForStringIndex(ctLine, lineLen, &secondary)
                let extraCols = targetCol - line.cachedColToAttrMap.count
                cursorX += endOffset + CGFloat(extraCols) * charWidth
            }
        } else {
            cursorX += CGFloat(targetCol) * charWidth
        }

        let cursorRect = NSRect(x: cursorX, y: rowY + 2, width: charWidth, height: lineHeight - 2)
        context.setFillColor(TerminalPalette.cursorColor.cgColor)
        context.fill(cursorRect)
    }

    // MARK: - Keyboard Handling

    override public func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Handle Command shortcuts
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers {
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
                fontSize = 13.0
                return
            default:
                break
            }

            // Command + Shift shortcuts
            if flags.contains([.command, .shift]) {
                if event.charactersIgnoringModifiers == "C" || event.charactersIgnoringModifiers == "c" ||
                   event.charactersIgnoringModifiers == "S" || event.charactersIgnoringModifiers == "s" {
                    handleScreenshotCapture()
                    return
                }
            }
            super.keyDown(with: event)
            return
        }

        // Handle Control combinations (e.g. Ctrl+C, Ctrl+D, Ctrl+Z)
        if flags.contains(.control) {
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

    private func specialKeySequence(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "\r"          // Return
        case 48: return "\t"          // Tab
        case 51: return "\u{7F}"      // Backspace
        case 53: return "\u{1B}"      // Escape
        case 126: return "\u{1B}[A"   // Up Arrow
        case 125: return "\u{1B}[B"   // Down Arrow
        case 124: return "\u{1B}[C"   // Right Arrow
        case 123: return "\u{1B}[D"   // Left Arrow
        case 115: return "\u{1B}[H"   // Home
        case 119: return "\u{1B}[F"   // End
        case 116: return "\u{1B}[5~"  // Page Up
        case 121: return "\u{1B}[6~"  // Page Down
        case 117: return "\u{1B}[3~"  // Forward Delete
        default: return nil
        }
    }

    private func resetScroll() {
        if scrollOffset != 0 {
            scrollOffset = 0
            needsDisplay = true
        }
    }

    // MARK: - Smart Paste & Clipboard

    public func handlePaste() {
        if ImageClipboardManager.shared.hasImage() {
            if let escapedPath = ImageClipboardManager.shared.saveClipboardImageToFile() {
                ptySession?.write(string: "\(escapedPath) ")
                resetScroll()
                return
            }
        }

        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            if buffer.bracketedPasteMode {
                ptySession?.write(string: "\u{1B}[200~" + text + "\u{1B}[201~")
            } else {
                ptySession?.write(string: text)
            }
            resetScroll()
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
