import AppKit

public protocol TerminalSearchBarDelegate: AnyObject {
    func searchBar(_ searchBar: TerminalSearchBarView, didChangeQuery query: String)
    func searchBarDidRequestNextMatch(_ searchBar: TerminalSearchBarView)
    func searchBarDidRequestPreviousMatch(_ searchBar: TerminalSearchBarView)
    func searchBarDidClose(_ searchBar: TerminalSearchBarView)
}

public final class TerminalSearchBarView: NSView, NSSearchFieldDelegate {
    public weak var delegate: TerminalSearchBarDelegate?

    private var searchField: NSSearchField!
    private var matchCountLabel: NSTextField!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var closeButton: NSButton!

    public static let height: CGFloat = 38.0

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: frameRect.width, height: Self.height))
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 0.95).cgColor
        layer?.borderColor = NSColor(white: 0.25, alpha: 0.6).cgColor
        layer?.borderWidth = 1

        // Search Input Field
        searchField = NSSearchField(frame: NSRect(x: 14, y: 5, width: 220, height: 26))
        searchField.placeholderString = "Find in terminal..."
        searchField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction)
        addSubview(searchField)

        // Match Count Label
        matchCountLabel = NSTextField(labelWithString: "")
        matchCountLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        matchCountLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        matchCountLabel.frame = NSRect(x: 242, y: 9, width: 90, height: 18)
        addSubview(matchCountLabel)

        // Previous Button (▲)
        prevButton = NSButton(frame: NSRect(x: 338, y: 6, width: 26, height: 26))
        prevButton.bezelStyle = .inline
        prevButton.isBordered = false
        prevButton.title = "▲"
        prevButton.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        prevButton.contentTintColor = NSColor(white: 0.75, alpha: 1.0)
        prevButton.target = self
        prevButton.action = #selector(prevClicked)
        prevButton.toolTip = "Previous Match (⇧Return)"
        addSubview(prevButton)

        // Next Button (▼)
        nextButton = NSButton(frame: NSRect(x: 368, y: 6, width: 26, height: 26))
        nextButton.bezelStyle = .inline
        nextButton.isBordered = false
        nextButton.title = "▼"
        nextButton.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        nextButton.contentTintColor = NSColor(white: 0.75, alpha: 1.0)
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        nextButton.toolTip = "Next Match (Return)"
        addSubview(nextButton)

        // Close Button (✕)
        closeButton = NSButton(frame: NSRect(x: 404, y: 6, width: 26, height: 26))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.title = "✕"
        closeButton.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        closeButton.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Close Find (Esc)"
        addSubview(closeButton)
    }

    public func focus() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    public func updateMatchCount(current: Int, total: Int) {
        if total == 0 {
            if searchField.stringValue.isEmpty {
                matchCountLabel.stringValue = ""
            } else {
                matchCountLabel.stringValue = "No matches"
                matchCountLabel.textColor = NSColor(srgbRed: 0.95, green: 0.45, blue: 0.45, alpha: 1.0)
            }
        } else {
            matchCountLabel.stringValue = "\(current + 1) of \(total)"
            matchCountLabel.textColor = NSColor(white: 0.75, alpha: 1.0)
        }
    }

    public var query: String {
        return searchField.stringValue
    }

    public func controlTextDidChange(_ obj: Notification) {
        delegate?.searchBar(self, didChangeQuery: searchField.stringValue)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Check if Shift is pressed
            if NSEvent.modifierFlags.contains(.shift) {
                delegate?.searchBarDidRequestPreviousMatch(self)
            } else {
                delegate?.searchBarDidRequestNextMatch(self)
            }
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            closeClicked()
            return true
        }
        return false
    }

    @objc private func searchFieldAction() {
        delegate?.searchBarDidRequestNextMatch(self)
    }

    @objc private func prevClicked() {
        delegate?.searchBarDidRequestPreviousMatch(self)
    }

    @objc private func nextClicked() {
        delegate?.searchBarDidRequestNextMatch(self)
    }

    @objc private func closeClicked() {
        delegate?.searchBarDidClose(self)
    }
}
