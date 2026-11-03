import AppKit

public final class TerminalTab: NSObject, PTYSessionDelegate, TerminalBufferDelegate {
    public let id: UUID
    public var title: String
    public var isCustomTitle: Bool
    public var customLabel: String?
    public var conversationTitle: String?
    public var oscTitle: String?
    public let initialDirectory: String
    public var currentDirectory: String
    public let buffer: TerminalBuffer
    public let parser: ANSIParser
    public let ptySession: PTYSession
    public let terminalView: TerminalView
    public weak var windowController: MainWindowController?

    public init(id: UUID = UUID(),
                windowController: MainWindowController,
                initialDirectory: String? = nil,
                initialTitle: String? = nil,
                isCustomTitle: Bool = false,
                customLabel: String? = nil) {
        self.id = id
        self.windowController = windowController
        self.isCustomTitle = isCustomTitle
        self.customLabel = customLabel

        let dir = (initialDirectory != nil && !initialDirectory!.isEmpty) ? initialDirectory! : NSHomeDirectory()
        self.initialDirectory = dir
        self.currentDirectory = dir

        let folder = (dir == NSHomeDirectory()) ? "~" : (dir as NSString).lastPathComponent
        if let explicit = customLabel, !explicit.isEmpty {
            self.title = "📁 \(folder) • \(explicit)"
            self.isCustomTitle = true
        } else if let initial = initialTitle, !initial.isEmpty {
            self.title = initial
        } else {
            self.title = "📁 \(folder)"
        }

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

    public var folderDisplayName: String {
        if currentDirectory == NSHomeDirectory() {
            return "~"
        } else {
            return (currentDirectory as NSString).lastPathComponent
        }
    }

    public var formattedTitle: String {
        let folder = folderDisplayName
        if let custom = customLabel, !custom.isEmpty {
            return "📁 \(folder) • \(custom)"
        } else if let convo = conversationTitle, !convo.isEmpty {
            return "📁 \(folder) • \(convo)"
        } else if let osc = oscTitle, !osc.isEmpty, !isGenericShellTitle(osc) {
            return "📁 \(folder) • \(osc)"
        } else {
            return "📁 \(folder)"
        }
    }

    private func isGenericShellTitle(_ str: String) -> Bool {
        let lower = str.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower == "zsh" || lower == "bash" || lower == "sh" || lower.contains("@")
    }

    public func updateTitleIfNeeded() {
        let newTitle = formattedTitle
        if self.title != newTitle {
            self.title = newTitle
            windowController?.tabDidUpdateTitle(self)
        }
    }

    public func start() {
        do {
            try ptySession.start(cols: UInt16(buffer.cols), rows: UInt16(buffer.rows), workingDirectory: initialDirectory)
        } catch {
            NSLog("[TerminalTab] Error starting PTY: \(error)")
        }
    }

    public func checkProcessAndDirectory() {
        guard ptySession.pid > 0 else { return }

        // 1. Check directory
        if let liveCwd = PathDetector.getProcessCwd(pid: ptySession.pid), !liveCwd.isEmpty {
            if liveCwd != currentDirectory {
                currentDirectory = liveCwd
                windowController?.tabDidUpdateDirectory(self)
            }
        }

        // 2. Check active tool / conversation title
        let detected = CLIConversationDetector.detectToolInfo(ptyPid: ptySession.pid, workingDirectory: currentDirectory)
        let newConvoTitle = detected?.conversationTitle
        if newConvoTitle != self.conversationTitle {
            self.conversationTitle = newConvoTitle
        }

        updateTitleIfNeeded()
    }

    public func checkCurrentDirectory() {
        checkProcessAndDirectory()
    }

    public func setCustomLabel(_ newLabel: String?) {
        let trimmed = newLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = trimmed, !t.isEmpty {
            self.customLabel = t
            self.isCustomTitle = true
        } else {
            self.customLabel = nil
            self.isCustomTitle = false
        }
        updateTitleIfNeeded()
    }

    public func rename(to newLabel: String) {
        setCustomLabel(newLabel)
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
            self.checkProcessAndDirectory()
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
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !self.isGenericShellTitle(trimmed) {
                self.oscTitle = trimmed
            } else {
                self.oscTitle = nil
            }
            self.updateTitleIfNeeded()
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
