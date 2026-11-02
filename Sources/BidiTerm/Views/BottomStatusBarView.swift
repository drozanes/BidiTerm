import AppKit

public protocol BottomStatusBarDelegate: AnyObject {
    func bottomStatusBarDidRequestShortcutsHelp(_ statusBar: BottomStatusBarView)
    func bottomStatusBarDidRequestNewTabAtDirectory(_ statusBar: BottomStatusBarView, directory: String)
}

public final class BottomStatusBarView: NSView, PathPillViewDelegate {
    public weak var delegate: BottomStatusBarDelegate?

    public static let height: CGFloat = 28.0

    public private(set) var pathPillView: PathPillView!
    private var gitPillView: NSView!
    private var gitLabel: NSTextField!
    private var shortcutsButton: NSButton!
    private var dividerLine: CALayer!

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: frameRect.width, height: Self.height))
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0).cgColor

        // Top subtle divider line
        dividerLine = CALayer()
        dividerLine.backgroundColor = NSColor(srgbRed: 0.18, green: 0.20, blue: 0.25, alpha: 0.8).cgColor
        layer?.addSublayer(dividerLine)

        // 1. Path Pill View (Warp-style [ 📁 ~/Dev ])
        pathPillView = PathPillView(frame: NSRect(x: 8, y: 3, width: 120, height: 22))
        pathPillView.delegate = self
        addSubview(pathPillView)

        // 2. Git Branch Badge (optional [ ⎇ main ])
        gitPillView = NSView(frame: NSRect(x: 136, y: 3, width: 80, height: 22))
        gitPillView.wantsLayer = true
        gitPillView.layer?.cornerRadius = 6.0
        gitPillView.layer?.borderWidth = 1.0
        gitPillView.layer?.backgroundColor = NSColor(srgbRed: 0.12, green: 0.14, blue: 0.18, alpha: 0.80).cgColor
        gitPillView.layer?.borderColor = NSColor(srgbRed: 0.22, green: 0.25, blue: 0.32, alpha: 0.60).cgColor
        gitPillView.isHidden = true

        gitLabel = NSTextField(labelWithString: "⎇ main")
        gitLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        gitLabel.textColor = NSColor(srgbRed: 0.60, green: 0.76, blue: 0.47, alpha: 1.0) // Soft Git branch green
        gitLabel.alignment = .center
        gitLabel.frame = NSRect(x: 6, y: 2, width: 68, height: 18)
        gitPillView.addSubview(gitLabel)
        addSubview(gitPillView)

        // 3. Shortcuts HUD Trigger Button on Right (? Shortcuts)
        shortcutsButton = NSButton(frame: NSRect(x: 0, y: 3, width: 110, height: 22))
        shortcutsButton.bezelStyle = .inline
        shortcutsButton.isBordered = false
        shortcutsButton.title = "? Shortcuts (⌘/)"
        shortcutsButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        shortcutsButton.contentTintColor = NSColor(white: 0.55, alpha: 1.0)
        shortcutsButton.target = self
        shortcutsButton.action = #selector(shortcutsButtonClicked)
        shortcutsButton.toolTip = "View all keyboard shortcuts and actions (⌘/)"
        addSubview(shortcutsButton)

        layoutElements()
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutElements()
    }

    private func layoutElements() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dividerLine.frame = CGRect(x: 0, y: bounds.height - 1.0, width: bounds.width, height: 1.0)
        CATransaction.commit()

        let pillSize = pathPillView.intrinsicContentSize
        pathPillView.frame = NSRect(x: 8.0, y: 3.0, width: pillSize.width, height: 22.0)

        if !gitPillView.isHidden {
            let labelSize = (gitLabel.stringValue as NSString).size(withAttributes: [.font: gitLabel.font!])
            let gitWidth = ceil(labelSize.width) + 16.0
            gitPillView.frame = NSRect(x: pathPillView.frame.maxX + 6.0, y: 3.0, width: gitWidth, height: 22.0)
            gitLabel.frame = NSRect(x: 8.0, y: 2.0, width: gitWidth - 16.0, height: 18.0)
        }

        let shortcutsW: CGFloat = 115.0
        shortcutsButton.frame = NSRect(x: bounds.width - shortcutsW - 8.0, y: 3.0, width: shortcutsW, height: 22.0)
    }

    public func update(path: String) {
        let branch = PathDetector.getGitBranch(for: path)
        pathPillView.update(path: path, gitBranch: branch)

        if let b = branch, !b.isEmpty {
            gitLabel.stringValue = "⎇ \(b)"
            gitPillView.toolTip = "Git branch: \(b)"
            gitPillView.isHidden = false
        } else {
            gitPillView.isHidden = true
        }

        layoutElements()
    }

    @objc private func shortcutsButtonClicked() {
        delegate?.bottomStatusBarDidRequestShortcutsHelp(self)
    }

    // MARK: - PathPillViewDelegate

    public func pathPillViewDidRequestNewTabAtDirectory(_ pathPillView: PathPillView, directory: String) {
        delegate?.bottomStatusBarDidRequestNewTabAtDirectory(self, directory: directory)
    }
}
