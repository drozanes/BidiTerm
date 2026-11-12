import AppKit

public struct TerminalStyle: Equatable {
    public var fgColor: NSColor = TerminalPalette.defaultForeground
    public var bgColor: NSColor? = nil
    public var isBold: Bool = false
    public var isItalic: Bool = false
    public var isUnderline: Bool = false
    public var isInverse: Bool = false

    public static let `default` = TerminalStyle()

    public func effectiveForeground() -> NSColor {
        if isInverse {
            return bgColor ?? TerminalPalette.defaultBackground
        }
        return fgColor
    }

    public func effectiveBackground() -> NSColor? {
        if isInverse {
            return fgColor
        }
        return bgColor
    }
}

public struct TerminalCell: Equatable {
    public var char: Character
    public var style: TerminalStyle
    public var hyperlinkURL: String?
    public var hyperlinkId: String?

    public init(char: Character = " ", style: TerminalStyle = .default, hyperlinkURL: String? = nil, hyperlinkId: String? = nil) {
        self.char = char
        self.style = style
        self.hyperlinkURL = hyperlinkURL
        self.hyperlinkId = hyperlinkId
    }
}

public enum TerminalPalette {
    public static let defaultForeground = NSColor(srgbRed: 0.98, green: 0.98, blue: 1.00, alpha: 1.0) // Crisp bright white
    public static let defaultBackground = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0) // Rich dark slate
    public static let cursorColor = NSColor(srgbRed: 0.45, green: 0.75, blue: 1.0, alpha: 0.95)      // Crisp neon cyan/blue
    public static let selectionColor = NSColor(srgbRed: 0.25, green: 0.38, blue: 0.60, alpha: 0.50)
    public static let searchHighlight = NSColor(srgbRed: 0.95, green: 0.75, blue: 0.20, alpha: 0.45)
    public static let activeSearchHighlight = NSColor(srgbRed: 1.00, green: 0.60, blue: 0.10, alpha: 0.85)

    // Standard 16 ANSI colors
    public static let standardColors: [NSColor] = [
        NSColor(srgbRed: 0.15, green: 0.16, blue: 0.18, alpha: 1.0), // 0: Black
        NSColor(srgbRed: 0.98, green: 0.36, blue: 0.45, alpha: 1.0), // 1: Red
        NSColor(srgbRed: 0.42, green: 0.88, blue: 0.58, alpha: 1.0), // 2: Green
        NSColor(srgbRed: 1.00, green: 0.82, blue: 0.38, alpha: 1.0), // 3: Yellow
        NSColor(srgbRed: 0.42, green: 0.68, blue: 1.00, alpha: 1.0), // 4: Blue
        NSColor(srgbRed: 0.82, green: 0.52, blue: 0.98, alpha: 1.0), // 5: Magenta
        NSColor(srgbRed: 0.38, green: 0.85, blue: 0.92, alpha: 1.0), // 6: Cyan
        NSColor(srgbRed: 0.96, green: 0.96, blue: 0.98, alpha: 1.0), // 7: Bright White
        // Bright variants (8-15)
        NSColor(srgbRed: 0.45, green: 0.48, blue: 0.52, alpha: 1.0), // 8: Bright Black (Visible Gray)
        NSColor(srgbRed: 1.00, green: 0.48, blue: 0.55, alpha: 1.0), // 9: Bright Red
        NSColor(srgbRed: 0.55, green: 0.98, blue: 0.68, alpha: 1.0), // 10: Bright Green
        NSColor(srgbRed: 1.00, green: 0.90, blue: 0.48, alpha: 1.0), // 11: Bright Yellow
        NSColor(srgbRed: 0.58, green: 0.78, blue: 1.00, alpha: 1.0), // 12: Bright Blue
        NSColor(srgbRed: 0.92, green: 0.62, blue: 1.00, alpha: 1.0), // 13: Bright Magenta
        NSColor(srgbRed: 0.48, green: 0.95, blue: 1.00, alpha: 1.0), // 14: Bright Cyan
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1.0), // 15: Pure White
    ]

    public static func colorFor256(index: Int) -> NSColor {
        if index < 16 {
            return standardColors[index]
        }
        if index >= 16 && index <= 231 {
            // 6x6x6 color cube
            let i = index - 16
            let r = (i / 36) % 6
            let g = (i / 6) % 6
            let b = i % 6
            let conv = [0.0, 0.37, 0.53, 0.69, 0.85, 1.0]
            return NSColor(srgbRed: conv[r], green: conv[g], blue: conv[b], alpha: 1.0)
        }
        if index >= 232 && index <= 255 {
            // Grayscale ramp
            let gray = Double(index - 232) / 23.0 * 0.9 + 0.05
            return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1.0)
        }
        return defaultForeground
    }
}
