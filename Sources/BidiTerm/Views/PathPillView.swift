import AppKit

public protocol PathPillViewDelegate: AnyObject {
    func pathPillViewDidRequestNewTabAtDirectory(_ pathPillView: PathPillView, directory: String)
}

public final class PathPillView: NSView {
    public weak var delegate: PathPillViewDelegate?

    public private(set) var rawPath: String = ""
    public private(set) var displayPath: String = "~"
    public private(set) var gitBranch: String? = nil

    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false

    // Visual attributes
    private let cornerRadius: CGFloat = 6.0
    private let pillHeight: CGFloat = 22.0
    private let iconImage: NSImage? = {
        if #available(macOS 11.0, *) {
            let img = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
            return img?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        }
        return nil
    }()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1.0
        updateColors()
        toolTip = "Click to reveal in Finder • Right-click for options"
    }

    private func updateColors() {
        if isHovered {
            layer?.backgroundColor = NSColor(srgbRed: 0.17, green: 0.20, blue: 0.26, alpha: 0.95).cgColor
            layer?.borderColor = NSColor(srgbRed: 0.36, green: 0.42, blue: 0.54, alpha: 0.85).cgColor
        } else {
            layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.13, blue: 0.17, alpha: 0.90).cgColor
            layer?.borderColor = NSColor(srgbRed: 0.24, green: 0.27, blue: 0.35, alpha: 0.70).cgColor
        }
    }

    public func update(path: String, gitBranch: String? = nil) {
        self.rawPath = path
        self.displayPath = PathDetector.formatDisplayPath(path)
        self.gitBranch = gitBranch

        let branchText = (gitBranch != nil && !gitBranch!.isEmpty) ? " • ⎇ \(gitBranch!)" : ""
        toolTip = "\(rawPath)\(branchText)\nClick to reveal in Finder • Right-click for options"

        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    public override var intrinsicContentSize: NSSize {
        let textFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: textFont]
        let textSize = (displayPath as NSString).size(withAttributes: textAttrs)

        var totalWidth: CGFloat = 8.0 // left padding
        totalWidth += 14.0 // folder icon
        totalWidth += 6.0 // space
        totalWidth += ceil(textSize.width)
        totalWidth += 10.0 // right padding

        return NSSize(width: max(48.0, totalWidth), height: pillHeight)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateColors()
    }

    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateColors()
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds

        // 1. Draw Folder Icon
        let iconSize: CGFloat = 13.0
        let iconY = floor((bounds.height - iconSize) / 2.0)
        let iconRect = NSRect(x: 8.0, y: iconY, width: iconSize, height: iconSize)

        if let icon = iconImage {
            // Tint icon to a clean folder blue
            let tinted = icon.copy() as! NSImage
            tinted.lockFocus()
            NSColor(srgbRed: 0.40, green: 0.65, blue: 0.95, alpha: 1.0).set()
            let rect = NSRect(origin: .zero, size: tinted.size)
            rect.fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: iconRect)
        } else {
            let emoji = "📁"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11)
            ]
            (emoji as NSString).draw(at: NSPoint(x: 7.0, y: iconY - 1.0), withAttributes: attrs)
        }

        // 2. Draw Path Text
        let textX: CGFloat = 8.0 + iconSize + 6.0
        let textFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        let textColor = isHovered ? NSColor(white: 0.98, alpha: 1.0) : NSColor(white: 0.88, alpha: 1.0)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor
        ]

        let textY = floor((bounds.height - textFont.capHeight) / 2.0) - 1.0
        (displayPath as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttrs)
    }

    // MARK: - Mouse Click Handling

    public override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }

        // Left click reveals in Finder
        let target = rawPath.isEmpty ? NSHomeDirectory() : rawPath
        let url = URL(fileURLWithPath: target)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Path Options")

        let revealItem = NSMenuItem(title: "Reveal \"\(displayPath)\" in Finder", action: #selector(revealInFinderAction(_:)), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(NSMenuItem.separator())

        let copyDisplayItem = NSMenuItem(title: "Copy Path (\"\(displayPath)\")", action: #selector(copyDisplayPathAction(_:)), keyEquivalent: "")
        copyDisplayItem.target = self
        menu.addItem(copyDisplayItem)

        let copyFullItem = NSMenuItem(title: "Copy Full Absolute Path", action: #selector(copyFullPathAction(_:)), keyEquivalent: "")
        copyFullItem.target = self
        menu.addItem(copyFullItem)

        menu.addItem(NSMenuItem.separator())

        let newTabItem = NSMenuItem(title: "Open New Tab Here", action: #selector(openNewTabHereAction(_:)), keyEquivalent: "")
        newTabItem.target = self
        menu.addItem(newTabItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func revealInFinderAction(_ sender: Any?) {
        let target = rawPath.isEmpty ? NSHomeDirectory() : rawPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
    }

    @objc private func copyDisplayPathAction(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayPath, forType: .string)
    }

    @objc private func copyFullPathAction(_ sender: Any?) {
        let target = rawPath.isEmpty ? NSHomeDirectory() : rawPath
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(target, forType: .string)
    }

    @objc private func openNewTabHereAction(_ sender: Any?) {
        let target = rawPath.isEmpty ? NSHomeDirectory() : rawPath
        delegate?.pathPillViewDidRequestNewTabAtDirectory(self, directory: target)
    }
}
