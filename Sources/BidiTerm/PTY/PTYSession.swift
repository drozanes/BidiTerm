import Foundation
import Darwin

public protocol PTYSessionDelegate: AnyObject {
    func ptySession(_ session: PTYSession, didReceiveData data: Data)
    func ptySessionDidTerminate(_ session: PTYSession, exitCode: Int32)
}

public final class PTYSession {
    public weak var delegate: PTYSessionDelegate?

    private var masterFd: Int32 = -1
    private var childPid: pid_t = -1
    public var pid: pid_t { return childPid }
    private var readSource: DispatchSourceRead?
    private let readQueue = DispatchQueue(label: "com.biditerm.pty.read", qos: .userInteractive)

    public private(set) var isRunning: Bool = false
    public private(set) var cols: UInt16 = 80
    public private(set) var rows: UInt16 = 24

    public init() {}

    deinit {
        terminate()
    }

    public func start(cols: UInt16 = 80, rows: UInt16 = 24, workingDirectory: String? = nil) throws {
        self.cols = cols
        self.rows = rows

        var master: Int32 = 0
        var win = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)

        // forkpty handles openpty, fork, and login_tty(slave) in the child process
        let pid = forkpty(&master, nil, nil, &win)
        guard pid >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to forkpty"])
        }

        if pid == 0 {
            // Child process: setup environment and execute shell
            setenv("TERM", "xterm-256color", 1)
            setenv("COLORTERM", "truecolor", 1)
            if getenv("LANG") == nil {
                setenv("LANG", "en_US.UTF-8", 1)
            }

            // Always start in the specified directory, defaulting to user's home directory
            let targetDir = (workingDirectory != nil && !workingDirectory!.isEmpty) ? workingDirectory! : NSHomeDirectory()
            chdir(targetDir)

            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            var cArgs: [UnsafeMutablePointer<CChar>?] = [
                strdup(shell),
                strdup("-l"),
                nil
            ]
            execv(shell, &cArgs)
            _exit(1)
        }

        // Parent process
        self.masterFd = master
        self.childPid = pid
        self.isRunning = true

        setupReadSource()
        setupTerminationWatcher()
    }

    private func setupReadSource() {
        guard masterFd >= 0 else { return }

        // Make masterFd non-blocking
        let flags = fcntl(masterFd, F_GETFL, 0)
        _ = fcntl(masterFd, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: masterFd, queue: readQueue)
        source.setEventHandler { [weak self] in
            guard let self = self, self.masterFd >= 0 else { return }

            var buffer = [UInt8](repeating: 0, count: 16384)
            let bytesRead = read(self.masterFd, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(bytes: buffer, count: bytesRead)
                self.delegate?.ptySession(self, didReceiveData: data)
            } else if bytesRead == 0 || (bytesRead < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                source.cancel()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.masterFd >= 0 {
                close(self.masterFd)
                self.masterFd = -1
            }
        }

        self.readSource = source
        source.resume()
    }

    private func setupTerminationWatcher() {
        guard childPid > 0 else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var status: Int32 = 0
            waitpid(self.childPid, &status, 0)

            let exitCode: Int32
            if WIFEXITED(status) {
                exitCode = WEXITSTATUS(status)
            } else if WIFSIGNALED(status) {
                exitCode = 128 + WTERMSIG(status)
            } else {
                exitCode = -1
            }

            DispatchQueue.main.async {
                self.isRunning = false
                self.delegate?.ptySessionDidTerminate(self, exitCode: exitCode)
            }
        }
    }

    public func write(data: Data) {
        guard masterFd >= 0 else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            _ = Darwin.write(masterFd, ptr, rawBuffer.count)
        }
    }

    public func write(string: String) {
        guard let data = string.data(using: .utf8) else { return }
        write(data: data)
    }

    public func resize(cols: UInt16, rows: UInt16) {
        guard masterFd >= 0 else { return }
        self.cols = cols
        self.rows = rows

        var win = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFd, TIOCSWINSZ, &win)

        if childPid > 0 {
            kill(childPid, SIGWINCH)
        }
    }

    public func terminate() {
        readSource?.cancel()
        readSource = nil

        if childPid > 0 {
            kill(childPid, SIGHUP)
            childPid = -1
        }

        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
        isRunning = false
    }
}

// Helpers for C macros
private func WIFEXITED(_ status: Int32) -> Bool {
    return (status & 0x7f) == 0
}

private func WEXITSTATUS(_ status: Int32) -> Int32 {
    return (status >> 8) & 0xff
}

private func WIFSIGNALED(_ status: Int32) -> Bool {
    return ((status & 0x7f) != 0) && ((status & 0x7f) != 0x7f)
}

private func WTERMSIG(_ status: Int32) -> Int32 {
    return status & 0x7f
}
