import AppKit

public final class ShortcutsWindowController: NSWindowController {
    public static let shared = ShortcutsWindowController()

    private var filterField: NSSearchField!
    private var scrollView: NSScrollView!
    private var containerView: NSView!
    private var currentFilter: String = ""

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        setupWindow()
    }

    private func setupWindow() {
        guard let window = self.window else { return }

        window.title = "Keyboard Shortcuts"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.center()

        let visualEffect = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        window.contentView = visualEffect

        // Header Title
        let titleLabel = NSTextField(labelWithString: "BidiTerm Keyboard Shortcuts")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 24, y: 448, width: 320, height: 26)
        visualEffect.addSubview(titleLabel)

        // Filter / Search Field
        filterField = NSSearchField(frame: NSRect(x: 350, y: 446, width: 200, height: 28))
        filterField.placeholderString = "Filter shortcuts..."
        filterField.target = self
        filterField.action = #selector(filterChanged(_:))
        visualEffect.addSubview(filterField)

        // Scroll View
        scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 540, height: 410))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        visualEffect.addSubview(scrollView)

        rebuildList()
    }

    @objc private func filterChanged(_ sender: Any?) {
        currentFilter = filterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        rebuildList()
    }

    private func rebuildList() {
        guard let scrollView = scrollView else { return }

        let categories = ShortcutCategory.allCases
        var filteredGroups: [(category: ShortcutCategory, items: [TerminalShortcut])] = []

        for cat in categories {
            let items = ShortcutRegistry.shortcuts(for: cat).filter { s in
                if currentFilter.isEmpty { return true }
                return s.title.lowercased().contains(currentFilter) ||
                       s.description.lowercased().contains(currentFilter) ||
                       s.keys.joined(separator: " ").lowercased().contains(currentFilter)
            }
            if !items.isEmpty {
                filteredGroups.append((category: cat, items: items))
            }
        }

        let width = scrollView.bounds.width - 20
        var totalHeight: CGFloat = 10

        // Calculate height
        for group in filteredGroups {
            totalHeight += 32 // Category header
            totalHeight += CGFloat(group.items.count) * 44 + 8 // Rows + spacing
        }
        totalHeight = max(totalHeight, scrollView.bounds.height)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        var currentY = totalHeight - 10

        for group in filteredGroups {
            // Category Header
            currentY -= 24
            let catLabel = NSTextField(labelWithString: group.category.rawValue.uppercased())
            catLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            catLabel.textColor = NSColor(srgbRed: 0.55, green: 0.70, blue: 0.95, alpha: 1.0)
            catLabel.frame = NSRect(x: 8, y: currentY, width: width - 16, height: 18)
            content.addSubview(catLabel)
            currentY -= 8

            for item in group.items {
                currentY -= 40
                let rowView = buildRowView(for: item, width: width)
                rowView.frame.origin = CGPoint(x: 0, y: currentY)
                content.addSubview(rowView)
                currentY -= 4
            }
            currentY -= 12
        }

        scrollView.documentView = content
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: totalHeight))
    }

    private func buildRowView(for shortcut: TerminalShortcut, width: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 38))
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor(white: 0.2, alpha: 0.25).cgColor
        row.layer?.cornerRadius = 6

        // Title & Description
        let titleLabel = NSTextField(labelWithString: shortcut.title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 12, y: 18, width: width - 180, height: 18)
        row.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: shortcut.description)
        descLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = NSColor(white: 0.75, alpha: 1.0)
        descLabel.frame = NSRect(x: 12, y: 3, width: width - 180, height: 16)
        row.addSubview(descLabel)

        // Key Badges
        var badgeX = width - 12
        for key in shortcut.keys.reversed() {
            let badge = makeBadge(text: key)
            badgeX -= badge.frame.width
            badge.frame.origin = CGPoint(x: badgeX, y: 8)
            row.addSubview(badge)
            badgeX -= 4
        }

        return row
    }

    private func makeBadge(text: String) -> NSView {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        let str = text as NSString
        let textWidth = max(18, ceil(str.size(withAttributes: [.font: font]).width) + 10)
        let badge = NSView(frame: NSRect(x: 0, y: 0, width: textWidth, height: 22))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(white: 0.35, alpha: 0.5).cgColor
        badge.layer?.borderColor = NSColor(white: 0.5, alpha: 0.4).cgColor
        badge.layer?.borderWidth = 1
        badge.layer?.cornerRadius = 4

        let lbl = NSTextField(labelWithString: text)
        lbl.font = font
        lbl.textColor = .white
        lbl.alignment = .center
        lbl.frame = NSRect(x: 0, y: 2, width: textWidth, height: 18)
        badge.addSubview(lbl)

        return badge
    }

    public func toggle() {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        }
    }
}
