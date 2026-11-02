import AppKit

public final class TerminalTab: NSObject, PTYSessionDelegate, TerminalBufferDelegate {
    public let id: UUID
    public var title: String
    public let buffer: TerminalBuffer
    public let parser: ANSIParser
    public let ptySession: PTYSession
    public let terminalView: TerminalView
    public weak var windowController: MainWindowController?

    public init(id: UUID = UUID(), windowController: MainWindowController) {
        self.id = id
        self.windowController = windowController
        self.title = "zsh"
        self.buffer = TerminalBuffer(cols: 80, rows: 24)
        self.parser = ANSIParser(buffer: buffer)
        self.ptySession = PTYSession()
        self.terminalView = TerminalView(buffer: buffer)

        super.init()

        self.buffer.delegate = self
        self.ptySession.delegate = self
        self.terminalView.ptySession = ptySession
        self.terminalView.windowController = windowController

        // Forward ANSI query replies to PTY
        self.parser.onResponse = { [weak self] reply in
            self?.ptySession.write(string: reply)
        }
    }

    public func start() {
        do {
            try ptySession.start(cols: UInt16(buffer.cols), rows: UInt16(buffer.rows))
        } catch {
            NSLog("[TerminalTab] Error starting PTY: \(error)")
        }
    }

    public func terminate() {
        ptySession.terminate()
    }

    // MARK: - PTYSessionDelegate

    public func ptySession(_ session: PTYSession, didReceiveData data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.parser.feed(data: data)
            self.terminalView.needsDisplay = true
        }
    }

    public func ptySessionDidTerminate(_ session: PTYSession, exitCode: Int32) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.title = "\(self.title) (Exit: \(exitCode))"
            self.windowController?.tabDidUpdateTitle(self)
        }
    }

    // MARK: - TerminalBufferDelegate

    public func terminalBufferDidChangeTitle(_ buffer: TerminalBuffer, title: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let newTitle = title.isEmpty ? "zsh" : title
            self.title = newTitle
            self.windowController?.tabDidUpdateTitle(self)
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
}
