import AppKit
import Foundation

public final class ANSIParser {
    public let buffer: TerminalBuffer
    public var onResponse: ((String) -> Void)?

    private enum State {
        case ground
        case escape
        case csi
        case osc
        case oscEscape
        case charset
    }

    private var state: State = .ground
    private var csiParams: String = ""
    private var oscBuffer: String = ""
    private var pendingBytes: [UInt8] = []

    public init(buffer: TerminalBuffer) {
        self.buffer = buffer
    }

    public func feed(data: Data) {
        var bytes = pendingBytes
        bytes.append(contentsOf: data)
        pendingBytes.removeAll(keepingCapacity: true)

        var index = 0

        while index < bytes.count {
            let b = bytes[index]
            let charLen: Int
            if (b & 0x80) == 0 {
                charLen = 1
            } else if (b & 0xE0) == 0xC0 {
                charLen = 2
            } else if (b & 0xF0) == 0xE0 {
                charLen = 3
            } else if (b & 0xF8) == 0xF0 {
                charLen = 4
            } else {
                index += 1
                continue
            }

            if index + charLen > bytes.count {
                pendingBytes = Array(bytes[index...])
                break
            }

            let subData = Data(bytes[index..<(index + charLen)])
            if let decoded = String(data: subData, encoding: .utf8) {
                for char in decoded {
                    processCharacter(char)
                }
            }
            index += charLen
        }
    }

    private func processCharacter(_ char: Character) {
        switch state {
        case .ground:
            switch char {
            case "\u{1B}": // ESC
                state = .escape
            case "\r":
                buffer.carriageReturn()
            case "\n":
                buffer.newLine()
            case "\u{08}": // Backspace
                buffer.backspace()
            case "\t":
                buffer.tab()
            case "\u{07}": // Bell
                buffer.ringBell()
            default:
                if char >= " " {
                    buffer.writeCharacter(char)
                }
            }

        case .escape:
            switch char {
            case "[":
                csiParams = ""
                state = .csi
            case "]":
                oscBuffer = ""
                state = .osc
            case "(", ")":
                state = .charset
            case "7":
                buffer.saveCursor()
                state = .ground
            case "8":
                buffer.restoreCursor()
                state = .ground
            case "M": // Reverse index
                if buffer.cursorRow == 0 {
                    // scroll down
                } else {
                    buffer.moveCursor(deltaRow: -1, deltaCol: 0)
                }
                state = .ground
            case "c": // Reset
                buffer.reset()
                state = .ground
            case "\\": // String Terminator (ST) outside OSC
                state = .ground
            default:
                state = .ground
            }

        case .charset:
            state = .ground

        case .csi:
            // Standard CSI parameter bytes are 0x20 through 0x3F (0-9, :, ;, <, =, >, ?, spaces, etc.)
            if let ascii = char.asciiValue, ascii >= 0x20 && ascii <= 0x3F {
                csiParams.append(char)
            } else {
                handleCSI(command: char, params: csiParams)
                state = .ground
            }

        case .osc:
            if char == "\u{07}" { // BEL terminator
                handleOSC(command: oscBuffer)
                oscBuffer = ""
                state = .ground
            } else if char == "\u{1B}" { // ESC (possible start of ST: ESC \)
                state = .oscEscape
            } else {
                oscBuffer.append(char)
            }

        case .oscEscape:
            if char == "\\" { // ST terminator complete (ESC \)
                handleOSC(command: oscBuffer)
                oscBuffer = ""
                state = .ground
            } else if char == "\u{1B}" {
                handleOSC(command: oscBuffer)
                oscBuffer = ""
                state = .escape
            } else {
                handleOSC(command: oscBuffer)
                oscBuffer = ""
                state = .ground
                processCharacter(char)
            }
        }
    }

    private func handleCSI(command: Character, params: String) {
        let isPrivate = params.hasPrefix("?")
        let cleanParams = isPrivate ? String(params.dropFirst()) : params
        let parts = cleanParams.split(separator: ";").compactMap { Int($0) }

        switch command {
        case "m": // SGR - Colors and Styling
            handleSGR(parts: parts)

        case "@": // ICH - Insert Character
            let n = parts.first ?? 1
            buffer.insertCharacters(count: n)

        case "P": // DCH - Delete Character
            let n = parts.first ?? 1
            buffer.deleteCharacters(count: n)

        case "X": // ECH - Erase Character
            let n = parts.first ?? 1
            buffer.eraseCharacters(count: n)

        case "L": // IL - Insert Line
            let n = parts.first ?? 1
            buffer.insertLines(count: n)

        case "M": // DL - Delete Line
            let n = parts.first ?? 1
            buffer.deleteLines(count: n)

        case "A": // Cursor Up
            let n = parts.first ?? 1
            buffer.moveCursor(deltaRow: -max(1, n), deltaCol: 0)

        case "B": // Cursor Down
            let n = parts.first ?? 1
            buffer.moveCursor(deltaRow: max(1, n), deltaCol: 0)

        case "C": // Cursor Forward
            let n = parts.first ?? 1
            buffer.moveCursor(deltaRow: 0, deltaCol: max(1, n))

        case "D": // Cursor Back
            let n = parts.first ?? 1
            buffer.moveCursor(deltaRow: 0, deltaCol: -max(1, n))

        case "E": // CNL - Cursor Next Line
            let n = parts.first ?? 1
            buffer.moveCursor(deltaRow: max(1, n), deltaCol: 0)
            buffer.setCursor(row: buffer.cursorRow, col: 0)

        case "F": // CPL - Cursor Previous Line
            let n = parts.first ?? 1
            buffer.moveCursor(deltaRow: -max(1, n), deltaCol: 0)
            buffer.setCursor(row: buffer.cursorRow, col: 0)

        case "H", "f": // Cursor Position (1-based)
            let row = (parts.count > 0 ? parts[0] : 1) - 1
            let col = (parts.count > 1 ? parts[1] : 1) - 1
            buffer.setCursor(row: max(0, row), col: max(0, col))

        case "G": // Cursor Horizontal Absolute
            let col = (parts.first ?? 1) - 1
            buffer.setCursor(row: buffer.cursorRow, col: max(0, col))

        case "d": // Cursor Vertical Absolute
            let row = (parts.first ?? 1) - 1
            buffer.setCursor(row: max(0, row), col: buffer.cursorCol)

        case "I": // CHT - Cursor Forward Tabulation
            let n = parts.first ?? 1
            for _ in 0..<n { buffer.tab() }

        case "Z": // CBT - Cursor Backward Tabulation (Shift+Tab)
            let n = parts.first ?? 1
            let targetTab = max(0, ((buffer.cursorCol - 1) / 8 - (n - 1)) * 8)
            buffer.setCursor(row: buffer.cursorRow, col: targetTab)

        case "S": // SU - Scroll Up
            let n = parts.first ?? 1
            buffer.scrollUp(lines: n)

        case "T": // SD - Scroll Down
            let n = parts.first ?? 1
            buffer.scrollDown(lines: n)

        case "K": // Erase in Line
            let mode = parts.first ?? 0
            buffer.eraseInLine(mode: mode)

        case "J": // Erase in Display
            let mode = parts.first ?? 0
            buffer.eraseInDisplay(mode: mode)

        case "n": // Device Status Report
            if parts.first == 6 {
                // Reply with cursor position: \x1b[row;colR
                let r = buffer.cursorRow + 1
                let c = buffer.cursorCol + 1
                onResponse?("\u{1B}[\(r);\(c)R")
            }

        case "c": // Device Attributes
            if params.hasPrefix(">") {
                // Secondary DA
                onResponse?("\u{1B}[>0;10;0c")
            } else {
                // Primary DA (VT100 with AVO)
                onResponse?("\u{1B}[?1;2c")
            }

        case "h": // Set Mode
            if isPrivate {
                for p in parts {
                    switch p {
                    case 25: buffer.cursorVisible = true
                    case 1049: buffer.setAltBuffer(enabled: true)
                    case 2004: buffer.bracketedPasteMode = true
                    default: break
                    }
                }
            }

        case "l": // Reset Mode
            if isPrivate {
                for p in parts {
                    switch p {
                    case 25: buffer.cursorVisible = false
                    case 1049: buffer.setAltBuffer(enabled: false)
                    case 2004: buffer.bracketedPasteMode = false
                    default: break
                    }
                }
            }

        case "s": // Save cursor
            buffer.saveCursor()

        case "u": // Restore cursor
            buffer.restoreCursor()

        default:
            break
        }
    }

    private func handleSGR(parts: [Int]) {
        if parts.isEmpty {
            buffer.activeStyle = .default
            return
        }

        var i = 0
        while i < parts.count {
            let p = parts[i]
            switch p {
            case 0:
                buffer.activeStyle = .default
            case 1:
                buffer.activeStyle.isBold = true
            case 3:
                buffer.activeStyle.isItalic = true
            case 4:
                buffer.activeStyle.isUnderline = true
            case 7:
                buffer.activeStyle.isInverse = true
            case 22:
                buffer.activeStyle.isBold = false
            case 23:
                buffer.activeStyle.isItalic = false
            case 24:
                buffer.activeStyle.isUnderline = false
            case 27:
                buffer.activeStyle.isInverse = false
            case 30...37:
                buffer.activeStyle.fgColor = TerminalPalette.standardColors[p - 30]
            case 39:
                buffer.activeStyle.fgColor = TerminalPalette.defaultForeground
            case 40...47:
                buffer.activeStyle.bgColor = TerminalPalette.standardColors[p - 40]
            case 49:
                buffer.activeStyle.bgColor = nil
            case 90...97:
                buffer.activeStyle.fgColor = TerminalPalette.standardColors[8 + (p - 90)]
            case 100...107:
                buffer.activeStyle.bgColor = TerminalPalette.standardColors[8 + (p - 100)]
            case 38:
                if i + 2 < parts.count && parts[i + 1] == 5 {
                    let colorIdx = parts[i + 2]
                    buffer.activeStyle.fgColor = TerminalPalette.colorFor256(index: colorIdx)
                    i += 2
                } else if i + 4 < parts.count && parts[i + 1] == 2 {
                    let r = Double(parts[i + 2]) / 255.0
                    let g = Double(parts[i + 3]) / 255.0
                    let b = Double(parts[i + 4]) / 255.0
                    buffer.activeStyle.fgColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
                    i += 4
                }
            case 48:
                if i + 2 < parts.count && parts[i + 1] == 5 {
                    let colorIdx = parts[i + 2]
                    buffer.activeStyle.bgColor = TerminalPalette.colorFor256(index: colorIdx)
                    i += 2
                } else if i + 4 < parts.count && parts[i + 1] == 2 {
                    let r = Double(parts[i + 2]) / 255.0
                    let g = Double(parts[i + 3]) / 255.0
                    let b = Double(parts[i + 4]) / 255.0
                    buffer.activeStyle.bgColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
                    i += 4
                }
            default:
                break
            }
            i += 1
        }
    }

    private func handleOSC(command: String) {
        if command.hasPrefix("8;") {
            let rest = command.dropFirst(2)
            let linkParts = rest.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            if linkParts.count >= 2 {
                let params = String(linkParts[0])
                let uri = String(linkParts[1])
                let linkId = parseOSC8Id(params: params)
                if uri.isEmpty {
                    buffer.setActiveHyperlink(url: nil, id: nil)
                } else {
                    buffer.setActiveHyperlink(url: uri, id: linkId)
                }
            } else if linkParts.count == 1 && linkParts[0].isEmpty {
                buffer.setActiveHyperlink(url: nil, id: nil)
            }
            return
        }

        let parts = command.split(separator: ";", maxSplits: 1)
        if parts.count == 2 {
            let code = parts[0]
            let value = String(parts[1])
            if code == "0" || code == "2" {
                buffer.setTitle(value)
            }
        }
    }

    private func parseOSC8Id(params: String) -> String? {
        guard !params.isEmpty else { return nil }
        for pair in params.split(separator: ":") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 && kv[0] == "id" {
                return String(kv[1])
            }
        }
        return nil
    }
}
