import AppKit

public final class MainWindowController: NSWindowController, NSWindowDelegate, PTYSessionDelegate, TerminalBufferDelegate {
    private var terminalView: TerminalView!
    private var buffer: TerminalBuffer!
    private var parser: ANSIParser!
    private var ptySession: PTYSession!

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 850, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        window.delegate = self
        setupWindow()
        setupTerminal()
    }

    private func setupWindow() {
        guard let window = self.window else { return }

        window.title = "BidiTerm"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.backgroundColor = TerminalPalette.defaultBackground
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.center()
    }

    private func setupTerminal() {
        guard let window = self.window else { return }

        buffer = TerminalBuffer(cols: 80, rows: 24)
        buffer.delegate = self
        parser = ANSIParser(buffer: buffer)
        ptySession = PTYSession()
        ptySession.delegate = self

        terminalView = TerminalView(buffer: buffer)
        terminalView.ptySession = ptySession
        terminalView.frame = window.contentView?.bounds ?? .zero
        terminalView.autoresizingMask = [.width, .height]

        window.contentView?.addSubview(terminalView)
        window.makeFirstResponder(terminalView)

        // Start PTY Session
        do {
            try ptySession.start(cols: 80, rows: 24)
        } catch {
            NSLog("[MainWindowController] Error starting PTY: \(error)")
        }
    }

    // MARK: - PTYSessionDelegate

    public func ptySession(_ session: PTYSession, didReceiveData data: Data) {
        parser.feed(data: data)
        DispatchQueue.main.async { [weak self] in
            self?.terminalView.needsDisplay = true
        }
    }

    public func ptySessionDidTerminate(_ session: PTYSession, exitCode: Int32) {
        DispatchQueue.main.async { [weak self] in
            self?.window?.title = "BidiTerm (Completed - Exit Code: \(exitCode))"
        }
    }

    // MARK: - TerminalBufferDelegate

    public func terminalBufferDidChangeTitle(_ buffer: TerminalBuffer, title: String) {
        DispatchQueue.main.async { [weak self] in
            self?.window?.title = title.isEmpty ? "BidiTerm" : title
        }
    }

    public func terminalBufferDidTriggerBell(_ buffer: TerminalBuffer) {
        DispatchQueue.main.async {
            NSSound.beep()
        }
    }

    public func terminalBufferNeedsDisplay(_ buffer: TerminalBuffer) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalView.needsDisplay = true
        }
    }

    // MARK: - NSWindowDelegate

    public func windowDidResize(_ notification: Notification) {
        terminalView.notifyResize()
    }

    public func windowWillClose(_ notification: Notification) {
        ptySession.terminate()
    }

    // MARK: - Menu Actions

    @objc public func captureScreenshotAction(_ sender: Any?) {
        terminalView.handleScreenshotCapture()
    }

    @objc public func pasteAction(_ sender: Any?) {
        terminalView.handlePaste()
    }

    @objc public func copyAction(_ sender: Any?) {
        terminalView.handleCopy()
    }
}
