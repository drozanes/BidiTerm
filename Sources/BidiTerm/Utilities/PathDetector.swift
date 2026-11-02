import Foundation
import AppKit

public struct DetectedPath {
    public enum PathType {
        case file(url: URL)
        case directory(url: URL)
        case webURL(url: URL)
    }

    public let rawText: String
    public let type: PathType
    public let lineNumber: Int?
    public let columnNumber: Int?

    public var targetURL: URL {
        switch type {
        case .file(let url), .directory(let url), .webURL(let url):
            return url
        }
    }
}

public enum PathDetector {
    /// Gets the current working directory of a process using Darwin libproc
    public static func getProcessCwd(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }

        // Use Darwin proc_pidinfo with PROC_PIDVNODEPATHINFO (flavor 9)
        var vpi = [UInt8](repeating: 0, count: 4096)
        let size = proc_pidinfo(pid, 9, 0, &vpi, 4096)
        guard size > 0 else { return nil }

        // vip_path in vnode_info_path is located at offset 152 in proc_vnodepathinfo
        let cdirOffset = 152
        guard cdirOffset < vpi.count else { return nil }

        let pathBytes = vpi[cdirOffset...].split(separator: 0).first
        guard let bytes = pathBytes, !bytes.isEmpty else { return nil }

        guard var rawPath = String(bytes: bytes, encoding: .utf8) else { return nil }
        if rawPath.hasPrefix("/private/tmp") {
            rawPath = String(rawPath.dropFirst(8))
        } else if rawPath.hasPrefix("/private/var") {
            rawPath = String(rawPath.dropFirst(8))
        }
        return rawPath
    }

    /// Formats an absolute path for display, substituting the user's home directory with '~'
    public static func formatDisplayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        var clean = path
        if clean.hasPrefix("/private/tmp") {
            clean = String(clean.dropFirst(8))
        } else if clean.hasPrefix("/private/var") {
            clean = String(clean.dropFirst(8))
        }

        if clean == home {
            return "~"
        } else if clean.hasPrefix(home + "/") {
            return "~" + clean.dropFirst(home.count)
        }
        return clean
    }

    /// Discovers the active Git branch name for a directory, or nil if not inside a git repository
    public static func getGitBranch(for directory: String) -> String? {
        var current = URL(fileURLWithPath: directory)
        let fm = FileManager.default

        for _ in 0..<12 {
            let gitDir = current.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitDir.path, isDirectory: &isDir) {
                let headFile: URL
                if isDir.boolValue {
                    headFile = gitDir.appendingPathComponent("HEAD")
                } else {
                    guard let content = try? String(contentsOf: gitDir, encoding: .utf8) else { break }
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("gitdir:") {
                        let relPath = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
                        let resolved = URL(fileURLWithPath: relPath, relativeTo: current).standardized
                        headFile = resolved.appendingPathComponent("HEAD")
                    } else {
                        break
                    }
                }

                if let head = try? String(contentsOf: headFile, encoding: .utf8) {
                    let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("ref: refs/heads/") {
                        return String(trimmed.dropFirst("ref: refs/heads/".count))
                    } else if trimmed.count >= 7 {
                        return String(trimmed.prefix(7))
                    }
                }
                break
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    /// Extracts the token or path under a given column index on a line of text
    public static func extractToken(on line: String, at col: Int) -> String? {
        guard !line.isEmpty, col >= 0, col < line.count else { return nil }

        let chars = Array(line)
        // Delimiters that separate file paths / tokens
        let delimiters: Set<Character> = [" ", "\t", "\"", "'", "`", "<", ">", "[", "]", "(", ")", "{", "}", "|", ";", ","]

        // If clicked directly on whitespace
        if chars[col].isWhitespace {
            return nil
        }

        var start = col
        while start > 0 && !delimiters.contains(chars[start - 1]) {
            start -= 1
        }

        var end = col
        while end < chars.count - 1 && !delimiters.contains(chars[end + 1]) {
            end += 1
        }

        var token = String(chars[start...end])

        // Strip trailing punctuation often found in text output (e.g. "path/to/file.txt:", "file.png.")
        while token.hasSuffix(":") || token.hasSuffix(".") || token.hasSuffix(",") || token.hasSuffix(";") {
            token.removeLast()
        }

        return token.isEmpty ? nil : token
    }

    /// Analyzes a candidate string to determine if it is a valid web URL or existing file path
    public static func detectPath(candidate: String, cwd: String? = nil) -> DetectedPath? {
        var clean = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        // Check for Web URL
        if clean.hasPrefix("http://") || clean.hasPrefix("https://") {
            if let url = URL(string: clean) {
                return DetectedPath(rawText: candidate, type: .webURL(url: url), lineNumber: nil, columnNumber: nil)
            }
        }

        // Parse optional line:column suffix (e.g. "Sources/BidiTerm/main.swift:42:10" or ":42")
        var lineNum: Int? = nil
        var colNum: Int? = nil
        let parts = clean.components(separatedBy: ":")
        if parts.count >= 2 {
            if let l = Int(parts[parts.count - 1]), parts.count == 2 {
                lineNum = l
                clean = parts[0]
            } else if let c = Int(parts[parts.count - 1]), let l = Int(parts[parts.count - 2]), parts.count >= 3 {
                lineNum = l
                colNum = c
                clean = parts[0..<(parts.count - 2)].joined(separator: ":")
            }
        }

        // Expand tilde
        let expanded = (clean as NSString).expandingTildeInPath
        let fm = FileManager.default

        // Absolute path check
        if expanded.hasPrefix("/") {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: expanded, isDirectory: &isDir) {
                let url = URL(fileURLWithPath: expanded)
                let type: DetectedPath.PathType = isDir.boolValue ? .directory(url: url) : .file(url: url)
                return DetectedPath(rawText: candidate, type: type, lineNumber: lineNum, columnNumber: colNum)
            }
        }

        // Relative path check against current working directory
        if let baseDir = cwd {
            let combined = (baseDir as NSString).appendingPathComponent(clean)
            let combinedExpanded = (combined as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: combinedExpanded, isDirectory: &isDir) {
                let url = URL(fileURLWithPath: combinedExpanded)
                let type: DetectedPath.PathType = isDir.boolValue ? .directory(url: url) : .file(url: url)
                return DetectedPath(rawText: candidate, type: type, lineNumber: lineNum, columnNumber: colNum)
            }
        }

        return nil
    }
}
