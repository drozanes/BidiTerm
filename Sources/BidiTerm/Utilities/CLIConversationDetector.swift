import Foundation
import Darwin
import SQLite3

public struct ToolProcessInfo: Equatable {
    public let pid: pid_t
    public let name: String
    public let conversationTitle: String?

    public init(pid: pid_t, name: String, conversationTitle: String?) {
        self.pid = pid
        self.name = name
        self.conversationTitle = conversationTitle
    }
}

public enum CLIConversationDetector {
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Inspects child processes of the given shell PTY process to find active CLI tools
    /// (such as Antigravity / agy, vim, nano, python, etc.) and resolves their active conversation title.
    public static func detectToolInfo(ptyPid: pid_t, workingDirectory: String) -> ToolProcessInfo? {
        guard ptyPid > 0 else { return nil }

        var childPids = [pid_t](repeating: 0, count: 64)
        let numChildren = proc_listchildpids(ptyPid, &childPids, Int32(MemoryLayout<pid_t>.size * childPids.count))
        guard numChildren > 0 else { return nil }

        for i in 0..<Int(numChildren) {
            let childPid = childPids[i]
            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(childPid, &nameBuf, UInt32(nameBuf.count))
            let procName = String(cString: nameBuf)
            let lower = procName.lowercased()

            // Skip default shell processes
            if lower == "zsh" || lower == "bash" || lower == "sh" || lower == "login" || lower.isEmpty {
                continue
            }

            // Antigravity CLI detection
            if lower == "agy" || lower.contains("antigravity") {
                let title = resolveAntigravityConversationTitle(childPid: childPid, workingDirectory: workingDirectory)
                return ToolProcessInfo(pid: childPid, name: "Antigravity", conversationTitle: title ?? "Antigravity")
            }

            // Other interactive tools (e.g. claude, aider, chatgpt, vim, nano, python, git, ssh)
            return ToolProcessInfo(pid: childPid, name: procName, conversationTitle: procName)
        }
        return nil
    }

    /// Resolves the Antigravity conversation title from active presence lock files or the conversation summary database.
    public static func resolveAntigravityConversationTitle(childPid: pid_t, workingDirectory: String) -> String? {
        // 1. Check open file descriptors of the child process for active presence locks
        if let lockConvoId = findConversationIdFromPresenceLocks(pid: childPid) {
            if let title = queryConversationSummary(whereClause: "conversation_id = ?", param: lockConvoId) {
                return title
            }
        }

        // 2. Query the summary DB for the most recent conversation matching this working directory
        if !workingDirectory.isEmpty {
            if let title = queryConversationSummary(whereClause: "workspace_uris LIKE ? ORDER BY last_modified_time DESC LIMIT 1", param: "%\(workingDirectory)%") {
                return title
            }
        }

        // 3. Fallback to the globally most recently modified conversation
        if let title = queryConversationSummary(whereClause: "ORDER BY last_modified_time DESC LIMIT 1", param: nil) {
            return title
        }

        return nil
    }

    private static func findConversationIdFromPresenceLocks(pid: pid_t) -> String? {
        let bufSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufSize > 0 else { return nil }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufSize) / MemoryLayout<proc_fdinfo>.size)
        proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufSize)

        for fd in fds {
            if fd.proc_fdtype == PROX_FDTYPE_VNODE {
                var vnodeInfo = vnode_fdinfowithpath()
                let vnodeSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
                let res = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnodeInfo, vnodeSize)
                if res > 0 {
                    let path = withUnsafePointer(to: &vnodeInfo.pvip.vip_path) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                            String(cString: $0)
                        }
                    }
                    if path.contains("/presence/") && path.hasSuffix(".lock") {
                        let filename = (path as NSString).lastPathComponent
                        return filename.replacingOccurrences(of: ".lock", with: "")
                    }
                }
            }
        }
        return nil
    }

    private static func queryConversationSummary(whereClause: String, param: String?) -> String? {
        let dbPath = NSString("~/.gemini/antigravity-cli/conversation_summaries.db").expandingTildeInPath
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let sql: String
        if param != nil {
            sql = "SELECT title FROM conversation_summaries WHERE \(whereClause);"
        } else {
            sql = "SELECT title FROM conversation_summaries \(whereClause);"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        if let p = param {
            sqlite3_bind_text(stmt, 1, p, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                let str = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    return str
                }
            }
        }
        return nil
    }
}
