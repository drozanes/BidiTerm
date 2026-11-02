import AppKit

public final class TerminalLine {
    public var cells: [TerminalCell]
    public var cachedAttributedString: NSAttributedString?
    public var cachedColToAttrMap: [Int] = []

    public init(length: Int = 0) {
        self.cells = Array(repeating: TerminalCell(), count: length)
    }

    public func invalidateCache() {
        cachedAttributedString = nil
        cachedColToAttrMap.removeAll(keepingCapacity: true)
    }

    public func ensureCapacity(_ capacity: Int) {
        if cells.count < capacity {
            cells.append(contentsOf: Array(repeating: TerminalCell(), count: capacity - cells.count))
        }
    }

    public var text: String {
        return String(cells.map { $0.char })
    }

    public var trimmedText: String {
        var res = text
        while res.last == " " {
            res.removeLast()
        }
        return res
    }
}

public protocol TerminalBufferDelegate: AnyObject {
    func terminalBufferDidChangeTitle(_ buffer: TerminalBuffer, title: String)
    func terminalBufferDidTriggerBell(_ buffer: TerminalBuffer)
    func terminalBufferNeedsDisplay(_ buffer: TerminalBuffer)
}

public final class TerminalBuffer {
    public weak var delegate: TerminalBufferDelegate?

    public private(set) var cols: Int
    public private(set) var rows: Int
    public let maxScrollback: Int

    // Main screen buffer
    private var mainLines: [TerminalLine] = []
    private var mainCursorRow: Int = 0
    private var mainCursorCol: Int = 0
    private var mainSavedCursor: (row: Int, col: Int)?

    // Alternate screen buffer (for vim/htop)
    private var altLines: [TerminalLine] = []
    private var altCursorRow: Int = 0
    private var altCursorCol: Int = 0
    private var isUsingAltBuffer: Bool = false

    // State
    public var activeStyle: TerminalStyle = .default
    public var cursorVisible: Bool = true
    public var bracketedPasteMode: Bool = false
    public var windowTitle: String = "BidiTerm"

    public init(cols: Int = 80, rows: Int = 24, maxScrollback: Int = 5000) {
        self.cols = cols
        self.rows = rows
        self.maxScrollback = maxScrollback
        self.reset()
    }

    public func reset() {
        mainLines = (0..<rows).map { _ in TerminalLine(length: cols) }
        mainCursorRow = 0
        mainCursorCol = 0
        mainSavedCursor = nil

        altLines = (0..<rows).map { _ in TerminalLine(length: cols) }
        altCursorRow = 0
        altCursorCol = 0
        isUsingAltBuffer = false

        activeStyle = .default
        cursorVisible = true
        bracketedPasteMode = false
    }

    // MARK: - Current Buffer References

    public var isAltBufferActive: Bool {
        return isUsingAltBuffer
    }

    private var activeLines: [TerminalLine] {
        get { isUsingAltBuffer ? altLines : mainLines }
        set {
            if isUsingAltBuffer {
                altLines = newValue
            } else {
                mainLines = newValue
            }
        }
    }

    public var cursorRow: Int {
        get { isUsingAltBuffer ? altCursorRow : mainCursorRow }
        set {
            let clamped = max(0, min(rows - 1, newValue))
            if isUsingAltBuffer {
                altCursorRow = clamped
            } else {
                mainCursorRow = clamped
            }
        }
    }

    public var cursorCol: Int {
        get { isUsingAltBuffer ? altCursorCol : mainCursorCol }
        set {
            let clamped = max(0, min(cols - 1, newValue))
            if isUsingAltBuffer {
                altCursorCol = clamped
            } else {
                mainCursorCol = clamped
            }
        }
    }

    public var totalLineCount: Int {
        return isUsingAltBuffer ? rows : mainLines.count
    }

    /// Returns the line at the absolute index (including scrollback)
    public func line(at absoluteIndex: Int) -> TerminalLine? {
        if isUsingAltBuffer {
            guard absoluteIndex >= 0 && absoluteIndex < altLines.count else { return nil }
            return altLines[absoluteIndex]
        } else {
            guard absoluteIndex >= 0 && absoluteIndex < mainLines.count else { return nil }
            return mainLines[absoluteIndex]
        }
    }

    /// The index where visible rows begin (for scroll calculation)
    public var viewportStartIndex: Int {
        if isUsingAltBuffer {
            return 0
        }
        return max(0, mainLines.count - rows)
    }

    // MARK: - Writing & Newline

    public func writeCharacter(_ ch: Character) {
        let lineIdx = viewportStartIndex + cursorRow
        ensureLineExists(at: lineIdx)

        let line = activeLines[lineIdx]
        line.ensureCapacity(cols)
        if cursorCol < line.cells.count {
            line.cells[cursorCol] = TerminalCell(char: ch, style: activeStyle)
            line.invalidateCache()
        }

        cursorCol += 1
        if cursorCol >= cols {
            cursorCol = 0
            newLine()
        }
    }

    public func newLine() {
        if cursorRow < rows - 1 {
            cursorRow += 1
        } else {
            // Scroll down: add new line at bottom
            if isUsingAltBuffer {
                altLines.removeFirst()
                altLines.append(TerminalLine(length: cols))
            } else {
                mainLines.append(TerminalLine(length: cols))
                if mainLines.count > maxScrollback + rows {
                    mainLines.removeFirst()
                }
            }
        }
    }

    public func carriageReturn() {
        cursorCol = 0
    }

    public func backspace() {
        cursorCol = max(0, cursorCol - 1)
    }

    public func tab() {
        let nextTab = (cursorCol / 8 + 1) * 8
        cursorCol = min(cols - 1, nextTab)
    }

    private func ensureLineExists(at index: Int) {
        if isUsingAltBuffer {
            while altLines.count <= index {
                altLines.append(TerminalLine(length: cols))
            }
        } else {
            while mainLines.count <= index {
                mainLines.append(TerminalLine(length: cols))
            }
        }
    }

    // MARK: - Cursor & Erase Operations

    public func setCursor(row: Int, col: Int) {
        cursorRow = row
        cursorCol = col
    }

    public func moveCursor(deltaRow: Int, deltaCol: Int) {
        cursorRow += deltaRow
        cursorCol += deltaCol
    }

    public func saveCursor() {
        if isUsingAltBuffer {
            // no-op or simple
        } else {
            mainSavedCursor = (mainCursorRow, mainCursorCol)
        }
    }

    public func restoreCursor() {
        if let saved = mainSavedCursor {
            mainCursorRow = saved.row
            mainCursorCol = saved.col
        }
    }

    public func eraseInLine(mode: Int) {
        let lineIdx = viewportStartIndex + cursorRow
        guard lineIdx < activeLines.count else { return }
        let line = activeLines[lineIdx]
        line.ensureCapacity(cols)

        let blank = TerminalCell(char: " ", style: activeStyle)

        switch mode {
        case 0: // Cursor to end of line
            for c in cursorCol..<line.cells.count {
                line.cells[c] = blank
            }
        case 1: // Start of line to cursor
            for c in 0...min(cursorCol, line.cells.count - 1) {
                line.cells[c] = blank
            }
        case 2: // Entire line
            for c in 0..<line.cells.count {
                line.cells[c] = blank
            }
        default:
            break
        }
        line.invalidateCache()
    }

    public func eraseInDisplay(mode: Int) {
        switch mode {
        case 0: // Cursor to end of screen
            eraseInLine(mode: 0)
            let startRow = cursorRow + 1
            if startRow < rows {
                for r in startRow..<rows {
                    let idx = viewportStartIndex + r
                    if idx < activeLines.count {
                        let l = activeLines[idx]
                        for c in 0..<l.cells.count { l.cells[c] = TerminalCell(char: " ", style: activeStyle) }
                        l.invalidateCache()
                    }
                }
            }
        case 1: // Start of screen to cursor
            eraseInLine(mode: 1)
            if cursorRow > 0 {
                for r in 0..<cursorRow {
                    let idx = viewportStartIndex + r
                    if idx < activeLines.count {
                        let l = activeLines[idx]
                        for c in 0..<l.cells.count { l.cells[c] = TerminalCell(char: " ", style: activeStyle) }
                        l.invalidateCache()
                    }
                }
            }
        case 2, 3: // Clear entire visible screen
            for r in 0..<rows {
                let idx = viewportStartIndex + r
                if idx < activeLines.count {
                    let l = activeLines[idx]
                    for c in 0..<l.cells.count { l.cells[c] = TerminalCell(char: " ", style: activeStyle) }
                    l.invalidateCache()
                }
            }
            if mode == 3 && !isUsingAltBuffer {
                // Clear scrollback history too
                let kept = Array(mainLines.suffix(rows))
                mainLines = kept.isEmpty ? (0..<rows).map { _ in TerminalLine(length: cols) } : kept
            }
        default:
            break
        }
    }

    // MARK: - Screen Buffer Switching

    public func setAltBuffer(enabled: Bool) {
        if enabled != isUsingAltBuffer {
            isUsingAltBuffer = enabled
            if enabled {
                altLines = (0..<rows).map { _ in TerminalLine(length: cols) }
                altCursorRow = 0
                altCursorCol = 0
            }
            delegate?.terminalBufferNeedsDisplay(self)
        }
    }

    // MARK: - Resize

    public func resize(cols: Int, rows: Int) {
        guard cols > 0 && rows > 0 else { return }
        self.cols = cols
        self.rows = rows

        for line in mainLines {
            line.ensureCapacity(cols)
            line.invalidateCache()
        }
        for line in altLines {
            line.ensureCapacity(cols)
            line.invalidateCache()
        }

        while mainLines.count < rows {
            mainLines.append(TerminalLine(length: cols))
        }
        while altLines.count < rows {
            altLines.append(TerminalLine(length: cols))
        }

        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
        delegate?.terminalBufferNeedsDisplay(self)
    }

    // MARK: - Notifications

    public func setTitle(_ title: String) {
        self.windowTitle = title
        delegate?.terminalBufferDidChangeTitle(self, title: title)
    }

    public func ringBell() {
        delegate?.terminalBufferDidTriggerBell(self)
    }
}
