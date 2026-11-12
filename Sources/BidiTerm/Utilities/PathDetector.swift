import Foundation
import AppKit

public struct DetectedPath: Equatable {
    public enum PathType: Equatable {
        case file(url: URL)
        case directory(url: URL)
        case webURL(url: URL)
    }

    public let rawText: String
    public let type: PathType
    public let lineNumber: Int?
    public let columnNumber: Int?
    public let label: String?

    public init(rawText: String, type: PathType, lineNumber: Int? = nil, columnNumber: Int? = nil, label: String? = nil) {
        self.rawText = rawText
        self.type = type
        self.lineNumber = lineNumber
        self.columnNumber = columnNumber
        self.label = label
    }

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

    private static let markdownRegex = try? NSRegularExpression(pattern: #"\[(?<label>[^\]]+)\]\((?<url>[^\s\)]+)\)"#)
    private static let rawURLRegex = try? NSRegularExpression(pattern: #"(?i)\b(?:https?|file):\/\/[^\s<>"'`]+"#)

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

    /// Finds an interactive link (Markdown [label](url), raw URL, file:// URI, or filesystem path) under the given column
    public static func findLink(on line: String, at col: Int, cwd: String? = nil) -> (detected: DetectedPath, range: Range<Int>)? {
        guard !line.isEmpty, col >= 0 else { return nil }

        // A. Markdown Links: [label](destination)
        if let mdRegex = markdownRegex {
            let nsLine = line as NSString
            let matches = mdRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                guard let matchRange = Range(match.range, in: line) else { continue }
                let startCol = line.distance(from: line.startIndex, to: matchRange.lowerBound)
                let endCol = line.distance(from: line.startIndex, to: matchRange.upperBound)
                if col >= startCol && col < endCol {
                    let label = nsLine.substring(with: match.range(withName: "label"))
                    let urlStr = nsLine.substring(with: match.range(withName: "url"))
                    let detected = detectPath(candidate: urlStr, cwd: cwd)
                        ?? DetectedPath(rawText: urlStr, type: .webURL(url: URL(string: urlStr) ?? URL(fileURLWithPath: urlStr)), lineNumber: nil, columnNumber: nil, label: label)
                    let fullDetected = DetectedPath(
                        rawText: nsLine.substring(with: match.range),
                        type: detected.type,
                        lineNumber: detected.lineNumber,
                        columnNumber: detected.columnNumber,
                        label: label
                    )
                    return (detected: fullDetected, range: startCol..<endCol)
                }
            }
        }

        // B. Raw URLs: file://, http://, https://
        if let urlRegex = rawURLRegex {
            let nsLine = line as NSString
            let matches = urlRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                guard let matchRange = Range(match.range, in: line) else { continue }
                let rawMatched = String(line[matchRange])
                let originalLen = rawMatched.count
                let trimmedURL = trimTrailingPunctuation(rawMatched)
                let trimmedDiff = originalLen - trimmedURL.count

                let startCol = line.distance(from: line.startIndex, to: matchRange.lowerBound)
                let endCol = line.distance(from: line.startIndex, to: matchRange.upperBound) - trimmedDiff

                if col >= startCol && col < endCol {
                    if let detected = detectPath(candidate: trimmedURL, cwd: cwd) {
                        return (detected: detected, range: startCol..<endCol)
                    }
                }
            }
        }

        // C. Local or relative file paths via extractToken
        if let token = extractToken(on: line, at: col),
           let detected = detectPath(candidate: token, cwd: cwd) {
            let chars = Array(line)
            let delimiters: Set<Character> = [" ", "\t", "\"", "'", "`", "<", ">", "[", "]", "(", ")", "{", "}", "|", ";", ","]
            var start = min(col, chars.count - 1)
            while start > 0 && !delimiters.contains(chars[start - 1]) {
                start -= 1
            }
            var end = min(col, chars.count - 1)
            while end < chars.count - 1 && !delimiters.contains(chars[end + 1]) {
                end += 1
            }
            let rawSub = String(chars[start...end])
            let trailingPunctCount = rawSub.count - token.count
            let finalEnd = max(start + 1, end + 1 - max(0, trailingPunctCount))
            return (detected: detected, range: start..<finalEnd)
        }

        return nil
    }

    /// Analyzes a candidate string to determine if it is a valid web URL, file URI, or existing file path
    public static func detectPath(candidate: String, cwd: String? = nil) -> DetectedPath? {
        var clean = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        // 1. Check for markdown link syntax [label](destination)
        if clean.hasPrefix("[") && clean.contains("](") && clean.hasSuffix(")") {
            if let closeBracket = clean.firstIndex(of: "]"),
               clean[clean.index(after: closeBracket)] == "(" {
                let label = String(clean[clean.index(after: clean.startIndex)..<closeBracket])
                let destStart = clean.index(closeBracket, offsetBy: 2)
                let dest = String(clean[destStart..<clean.index(before: clean.endIndex)])
                if let detectedDest = detectPath(candidate: dest, cwd: cwd) {
                    return DetectedPath(rawText: candidate, type: detectedDest.type, lineNumber: detectedDest.lineNumber, columnNumber: detectedDest.columnNumber, label: label)
                } else if let url = URL(string: dest) {
                    let type: DetectedPath.PathType = (url.scheme == "file") ? .file(url: url) : .webURL(url: url)
                    return DetectedPath(rawText: candidate, type: type, lineNumber: nil, columnNumber: nil, label: label)
                }
            }
        }

        // 2. Check for file:// URI
        if clean.lowercased().hasPrefix("file://") {
            var lineNum: Int? = nil
            var colNum: Int? = nil
            var urlString = clean

            // Parse optional fragment e.g. #L42 or #L42-L50 or #42
            if let hashIdx = urlString.firstIndex(of: "#") {
                let frag = String(urlString[urlString.index(after: hashIdx)...])
                urlString = String(urlString[..<hashIdx])
                let cleanedFrag = frag.lowercased().hasPrefix("l") ? String(frag.dropFirst()) : frag
                let linePart = cleanedFrag.split(separator: "-").first ?? ""
                if let l = Int(linePart) {
                    lineNum = l
                }
            }

            // Parse optional :line:col suffix (e.g. file:///path/to/file.swift:42:10 or :42)
            if let colonIdx = urlString.lastIndex(of: ":") {
                let afterColon = String(urlString[urlString.index(after: colonIdx)...])
                if let l = Int(afterColon) {
                    let beforeColon = String(urlString[..<colonIdx])
                    if let secondColon = beforeColon.lastIndex(of: ":") {
                        let potentialLine = String(beforeColon[beforeColon.index(after: secondColon)...])
                        if let pl = Int(potentialLine) {
                            lineNum = pl
                            colNum = l
                            urlString = String(beforeColon[..<secondColon])
                        } else {
                            lineNum = l
                            urlString = beforeColon
                        }
                    } else {
                        lineNum = l
                        urlString = beforeColon
                    }
                }
            }

            if let url = URL(string: urlString) {
                let filePath = url.path.removingPercentEncoding ?? url.path
                let fm = FileManager.default
                var isDir: ObjCBool = false
                let fileURL = URL(fileURLWithPath: filePath)
                if fm.fileExists(atPath: filePath, isDirectory: &isDir) {
                    let type: DetectedPath.PathType = isDir.boolValue ? .directory(url: fileURL) : .file(url: fileURL)
                    return DetectedPath(rawText: candidate, type: type, lineNumber: lineNum, columnNumber: colNum)
                } else {
                    return DetectedPath(rawText: candidate, type: .file(url: fileURL), lineNumber: lineNum, columnNumber: colNum)
                }
            }
        }

        // 3. Check for Web URL
        if clean.lowercased().hasPrefix("http://") || clean.lowercased().hasPrefix("https://") {
            let trimmedURL = trimTrailingPunctuation(clean)
            if let url = URL(string: trimmedURL) {
                return DetectedPath(rawText: candidate, type: .webURL(url: url), lineNumber: nil, columnNumber: nil)
            }
        }

        // 4. Check other standard URL schemes (mailto, ssh, vnc)
        if let url = URL(string: clean), let scheme = url.scheme, !scheme.isEmpty,
           scheme != "http" && scheme != "https" && scheme != "file" && !clean.contains(" ") {
            return DetectedPath(rawText: candidate, type: .webURL(url: url), lineNumber: nil, columnNumber: nil)
        }

        // 5. Parse optional line:column suffix for local paths (e.g. "Sources/BidiTerm/main.swift:42:10" or ":42")
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

    private static func trimTrailingPunctuation(_ raw: String) -> String {
        var str = raw
        while str.hasSuffix(")") {
            let openCount = str.filter { $0 == "(" }.count
            let closeCount = str.filter { $0 == ")" }.count
            if closeCount > openCount {
                str.removeLast()
            } else {
                break
            }
        }
        while str.hasSuffix(".") || str.hasSuffix(",") || str.hasSuffix(";") || str.hasSuffix(":") ||
              str.hasSuffix("?") || str.hasSuffix("!") || str.hasSuffix(">") || str.hasSuffix("\"") ||
              str.hasSuffix("'") {
            str.removeLast()
        }
        return str
    }
}
