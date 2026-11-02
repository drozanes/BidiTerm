import AppKit
import Foundation

public final class ANSIParser {
    public let buffer: TerminalBuffer

    private enum State {
        case ground
        case escape
        case csi
        case osc
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
            // Check UTF-8 validity for the next character
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
                // Invalid byte, skip
                index += 1
                continue
            }

            if index + charLen > bytes.count {
                // Incomplete UTF-8 sequence, keep for next feed
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
            case "M": // Reverse index (cursor up or scroll down)
                if buffer.cursorRow == 0 {
                    // scroll down
                } else {
                    buffer.moveCursor(deltaRow: -1, deltaCol: 0)
                }
                state = .ground
            case "c": // Reset
                buffer.reset()
                state = .ground
            default:
                state = .ground
            }

        case .charset:
            // Skip the character set designation (e.g. `(B`)
            state = .ground

        case .csi:
            // CSI parameter bytes are 0x30–0x3F (0-9, :, ;, <, =, >, ?)
            if (char >= "0" && char <= "9") || char == ";" || char == "?" || char == ":" {
                csiParams.append(char)
            } else {
                // Final byte
                handleCSI(command: char, params: csiParams)
                state = .ground
            }

        case .osc:
            if char == "\u{07}" || char == "\u{1B}" { // BEL or start of ST
                handleOSC(command: oscBuffer)
                state = .ground
            } else {
                oscBuffer.append(char)
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

        case "K": // Erase in Line
            let mode = parts.first ?? 0
            buffer.eraseInLine(mode: mode)

        case "J": // Erase in Display
            let mode = parts.first ?? 0
            buffer.eraseInDisplay(mode: mode)

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
            // Standard FG
            case 30...37:
                buffer.activeStyle.fgColor = TerminalPalette.standardColors[p - 30]
            case 39:
                buffer.activeStyle.fgColor = TerminalPalette.defaultForeground
            // Standard BG
            case 40...47:
                buffer.activeStyle.bgColor = TerminalPalette.standardColors[p - 40]
            case 49:
                buffer.activeStyle.bgColor = nil
            // Bright FG
            case 90...97:
                buffer.activeStyle.fgColor = TerminalPalette.standardColors[8 + (p - 90)]
            // Bright BG
            case 100...107:
                buffer.activeStyle.bgColor = TerminalPalette.standardColors[8 + (p - 100)]
            // Extended 38 (FG)
            case 38:
                if i + 2 < parts.count && parts[i + 1] == 5 {
                    // 38;5;n
                    let colorIdx = parts[i + 2]
                    buffer.activeStyle.fgColor = TerminalPalette.colorFor256(index: colorIdx)
                    i += 2
                } else if i + 4 < parts.count && parts[i + 1] == 2 {
                    // 38;2;r;g;b
                    let r = Double(parts[i + 2]) / 255.0
                    let g = Double(parts[i + 3]) / 255.0
                    let b = Double(parts[i + 4]) / 255.0
                    buffer.activeStyle.fgColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
                    i += 4
                }
            // Extended 48 (BG)
            case 48:
                if i + 2 < parts.count && parts[i + 1] == 5 {
                    // 48;5;n
                    let colorIdx = parts[i + 2]
                    buffer.activeStyle.bgColor = TerminalPalette.colorFor256(index: colorIdx)
                    i += 2
                } else if i + 4 < parts.count && parts[i + 1] == 2 {
                    // 48;2;r;g;b
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
        // e.g. "0;New Title" or "2;New Title"
        let parts = command.split(separator: ";", maxSplits: 1)
        if parts.count == 2 {
            let code = parts[0]
            let value = String(parts[1])
            if code == "0" || code == "2" {
                buffer.setTitle(value)
            }
        }
    }
}
