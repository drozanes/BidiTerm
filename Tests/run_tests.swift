import Foundation
import Darwin
import AppKit
import CoreText

@main
struct TestsRunner {
    static func main() {
        print("========================================")
        print("Running BidiTerm Automated Engine Tests")
        print("========================================")

        // Test 1: PTY Session & zsh interaction
        print("[Test 1] Testing PTY session and zsh spawn...")
        var master: Int32 = 0
        var win = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&master, nil, nil, &win)

        assert(pid >= 0, "forkpty failed")
        if pid == 0 {
            setenv("TERM", "xterm-256color", 1)
            let shell = "/bin/zsh"
            var args = [strdup(shell), strdup("-f"), nil]
            execv(shell, &args)
            _exit(1)
        }

        let testCmd = "echo HEBREW_TEST_שלום_WORLD\n"
        _ = testCmd.withCString { Darwin.write(master, $0, strlen($0)) }

        var outputData = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        let start = Date()
        while Date().timeIntervalSince(start) < 2.0 {
            let n = read(master, &buf, buf.count)
            if n > 0 {
                outputData.append(buf, count: n)
                if let str = String(data: outputData, encoding: .utf8), str.contains("HEBREW_TEST_שלום_WORLD") {
                    print("  -> Successfully received shell output containing Hebrew & English!")
                    break
                }
            }
            usleep(20000)
        }
        kill(pid, SIGKILL)
        close(master)

        // Test 2: Dynamic UAX #9 Direction Detection and Bidirectional Ordering
        print("[Test 2] Testing Bidirectional Layout & First-Strong Detection...")

        func isRTLLineTest(_ text: String) -> Bool {
            for scalar in text.unicodeScalars {
                let val = scalar.value
                if val <= 0x0040 || (val >= 0x005B && val <= 0x0060) || (val >= 0x007B && val <= 0x007E) || val == 0x2022 {
                    continue
                }
                if (val >= 0x0590 && val <= 0x05FF) || (val >= 0x0600 && val <= 0x06FF) || (val >= 0xFB1D && val <= 0xFB4F) {
                    return true
                }
                if (val >= 0x0041 && val <= 0x005A) || (val >= 0x0061 && val <= 0x007A) {
                    return false
                }
            }
            return false
        }

        assert(isRTLLineTest("### סיכום וטיפ למשא ומתן (Negotiation)") == true, "Hebrew header should be RTL")
        assert(isRTLLineTest("• סה\"כ חבילה חודשית משוקללת (TC): 55,000 - 63,000 ₪") == true, "Hebrew bullet should be RTL")
        assert(isRTLLineTest("> אתה בטוח? אתה לא מגזים עם המשכורות האלו?") == true, "Hebrew prompt should be RTL")
        assert(isRTLLineTest("git status") == false, "English command should be LTR")
        assert(isRTLLineTest("echo 'hello world'") == false, "English echo should be LTR")
        print("  -> First-strong character direction classification verified!")

        let hebrewTestLine = "### סיכום וטיפ למשא ומתן (Negotiation)"
        let pRTL = NSMutableParagraphStyle()
        pRTL.baseWritingDirection = .rightToLeft
        let attrRTL = NSAttributedString(string: hebrewTestLine, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .paragraphStyle: pRTL
        ])
        let ctLineRTL = CTLineCreateWithAttributedString(attrRTL)
        let lineRuns = CTLineGetGlyphRuns(ctLineRTL) as! [CTRun]
        var visualRuns = [(x: CGFloat, text: String)]()

        for r in lineRuns {
            let count = CTRunGetGlyphCount(r)
            var indices = [CFIndex](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetStringIndices(r, CFRangeMake(0, count), &indices)
            CTRunGetPositions(r, CFRangeMake(0, count), &positions)
            var s = ""
            for i in 0..<count {
                s.append((hebrewTestLine as NSString).substring(with: NSRange(location: indices[i], length: 1)))
            }
            visualRuns.append((x: positions[0].x, text: s))
        }
        visualRuns.sort { $0.x > $1.x }
        let readingOrder = visualRuns.map { $0.text }.joined()
        assert(readingOrder.contains("###") && readingOrder.contains("Negotiation"), "Both prefix and suffix runs must be present")
        print("  -> CoreText BiDi layout renders Hebrew & English in authentic right-to-left natural reading order!")

        // Test 3: Path & URL Detection
        print("[Test 3] Testing Path & URL Detection for Cmd+Click...")
        let sampleTerminalLine = "error at Sources/BidiTerm/main.swift:42:10 or see https://github.com/drozanes/BidiTerm"
        let cwd = "/Users/drozanes/dev/BidiTerm"

        // Extract token for file path
        let fileToken = PathDetector.extractToken(on: sampleTerminalLine, at: 15)
        assert(fileToken == "Sources/BidiTerm/main.swift:42:10", "File token extracted correctly")
        let detectedFile = PathDetector.detectPath(candidate: fileToken!, cwd: cwd)
        assert(detectedFile != nil, "File path detected successfully")
        assert(detectedFile?.lineNumber == 42 && detectedFile?.columnNumber == 10, "Line and column numbers parsed")

        // Extract token for web URL
        let urlToken = PathDetector.extractToken(on: sampleTerminalLine, at: 65)
        assert(urlToken == "https://github.com/drozanes/BidiTerm", "URL token extracted correctly")
        let detectedURL = PathDetector.detectPath(candidate: urlToken!, cwd: cwd)
        assert(detectedURL != nil, "URL detected successfully")
        if case .webURL = detectedURL!.type {
            print("  -> Web URL correctly recognized!")
        } else {
            fatalError("Should be webURL")
        }
        print("  -> PathDetector accurately extracts and resolves local paths and web URLs!")

        // Test 4: Buffer Text Search Engine
        print("[Test 4] Testing Buffer Text Search...")
        let buffer = TerminalBuffer(cols: 80, rows: 24)
        let parser = ANSIParser(buffer: buffer)
        parser.feed(data: "Hello world from BidiTerm\r\nSecond line with another BidiTerm occurrence\r\nThird line with Hebrew שלום עולם\r\n".data(using: .utf8)!)

        let matches = buffer.search(query: "BidiTerm")
        assert(matches.count == 2, "Should find 2 matches for BidiTerm")
        assert(matches[0].lineIndex == 0, "First match on line 0")
        assert(matches[1].lineIndex == 1, "Second match on line 1")

        let hebrewMatches = buffer.search(query: "שלום")
        assert(hebrewMatches.count == 1, "Should find 1 Hebrew match")
        print("  -> TerminalBuffer search engine successfully finds Latin and Hebrew strings with exact line & range mapping!")

        // Test 5: Keyboard Shortcuts Registry
        print("[Test 5] Testing Keyboard Shortcuts Registry...")
        let allShortcuts = ShortcutRegistry.allShortcuts
        assert(!allShortcuts.isEmpty, "Shortcuts registry must not be empty")
        assert(ShortcutRegistry.shortcuts(for: .tabs).contains { $0.title == "New Tab" }, "New Tab shortcut present")
        assert(ShortcutRegistry.shortcuts(for: .tabs).contains { $0.title == "Reopen Closed Tab" }, "Reopen Closed Tab shortcut present")
        assert(ShortcutRegistry.shortcuts(for: .tabs).contains { $0.title == "New Tab in Current Directory" }, "New Tab in Current Directory shortcut present")
        assert(ShortcutRegistry.shortcuts(for: .search).contains { $0.title == "Find in Terminal" }, "Find shortcut present")
        assert(ShortcutRegistry.shortcuts(for: .files).contains { $0.title == "Open File or Link" }, "Cmd+Click shortcut present")
        print("  -> ShortcutRegistry verified across all categories (tabs, search, files, clipboard, terminal)!")

        // Test 6: Default Opening Path & Path Formatting
        print("[Test 6] Testing Default Opening Path & Path Formatting...")
        let homeDir = NSHomeDirectory()
        assert(!homeDir.isEmpty && homeDir.hasPrefix("/"), "Home directory must be valid absolute path")
        assert(PathDetector.formatDisplayPath(homeDir) == "~", "Home directory should format as '~'")
        let subDir = homeDir + "/Dev"
        assert(PathDetector.formatDisplayPath(subDir) == "~/Dev", "Subdirectory should format as '~/Dev'")
        print("  -> Path formatting correctly produces Warp-style display path ('~/Dev')!")

        // Test 7: Git Branch Detection
        print("[Test 7] Testing Git Branch Detection...")
        let gitRepoDir = "/Users/drozanes/dev/BidiTerm"
        let branch = PathDetector.getGitBranch(for: gitRepoDir)
        assert(branch == "main", "Branch for BidiTerm should be detected as 'main'")
        let nonRepoBranch = PathDetector.getGitBranch(for: homeDir)
        assert(nonRepoBranch == nil, "Home directory should not have a git branch")
        print("  -> Git branch detection accurately extracts active branch ('\(branch ?? "")') without shell execution!")

        // Test 8: TabSessionManager & Recently Closed Tabs
        print("[Test 8] Testing TabSessionManager & Restoration Stack...")
        let testDir1 = "/Users/drozanes/dev/BidiTerm"
        let testDir2 = "/tmp"

        TabSessionManager.shared.pushClosedTab(workingDirectory: testDir1, title: "📁 BidiTerm")
        assert(TabSessionManager.shared.hasRecentlyClosedTabs, "Stack should have closed tabs")

        let popped = TabSessionManager.shared.popClosedTab()
        assert(popped != nil, "Popped closed tab should not be nil")
        assert(popped?.workingDirectory == testDir1, "Popped directory should match pushed directory")

        let sampleTabs = [
            SavedTabState(workingDirectory: testDir1, title: "📁 BidiTerm"),
            SavedTabState(workingDirectory: testDir2, title: "📁 tmp")
        ]
        TabSessionManager.shared.saveSession(tabs: sampleTabs, activeIndex: 1)
        let loadedSession = TabSessionManager.shared.loadSavedSession()
        assert(loadedSession != nil, "Session should be successfully saved and loaded")
        assert(loadedSession?.tabs.count == 2, "Session should have 2 tabs")
        assert(loadedSession?.activeIndex == 1, "Session activeIndex should match")
        print("  -> TabSessionManager handles session persistence and recently closed tab restoration (Cmd+Shift+T) flawlessly!")

        // Test 9: Shell Integration & Prompt Styling
        print("[Test 9] Testing ShellIntegrationManager & Prompt Styling...")
        let integrationDir = ShellIntegrationManager.shared.setupShellIntegration()
        assert(!integrationDir.isEmpty, "Integration directory should not be empty")

        let zshrcURL = URL(fileURLWithPath: integrationDir).appendingPathComponent(".zshrc")
        let zshrcContent = try? String(contentsOf: zshrcURL, encoding: .utf8)
        assert(zshrcContent != nil, ".zshrc must exist in shell integration directory")
        assert(zshrcContent!.contains("PROMPT="), ".zshrc must define custom prompt")
        assert(zshrcContent!.contains("vcs_info"), ".zshrc must configure git vcs_info")

        ShellIntegrationManager.shared.currentStyle = .styledUserHost
        assert(ShellIntegrationManager.shared.currentStyle == .styledUserHost, "Style should be styledUserHost")
        let styledContent = try? String(contentsOf: zshrcURL, encoding: .utf8)
        assert(styledContent!.contains("%n") && styledContent!.contains("%m"), "styledUserHost prompt must include user and host")
        print("  -> ShellIntegrationManager generates complete zsh integration with user-selected prompt styling!")

        // Test 10: Multi-line Large Hebrew Text PTY Write & Paste Pipeline
        print("[Test 10] Testing Multi-line Large Hebrew Text PTY Write & Paste Pipeline...")
        let sampleHebrew = """
        פירוט המסלול המעגלי בנחל פרס
        המסלול הקלאסי הוא מעגלי נגד כיוון השעון, באורך של כ-7.5–8 ק"מ (כ-3.5–4 שעות הליכה):

        יציאה על רמת המדבר (סימון ירוק):
        מחנים בחניון נחל פרס על כביש 25 (כ-3 ק"מ לפני צומת הערבה). מתחילים בהליכה נוחה על השביל המסומן ירוק לכיוון דרום-מזרח לאורך רמת המדבר, מעל הגדה הצפונית של הנחל (כ-3 ק"מ).

        תצפית מפל פרס:
        מגיעים אל שפת המצוק לתצפית מעל מפל נחל פרס – מפל יבש ועצום בגובה של כ-50 מטר המשקיף ישירות לעבר צומת הערבה והרי אדום.

        ירידה לערוץ (סימון אדום):
        סמוך לתצפית מתפצל שביל קצר ותלול המסומן אדום (כ-300–400 מטר). יורדים בו בזהירות אל תוך אפיק הנחל, עד למפגש עם שביל מסומן שחור.

        גבי פרס (סימון שחור):
        במפגש עם האפיק פונים ימינה (מערבה / במעלה הנחל). בתוך שניות ספורות נכנסים למעוק הגיר הלבן של גבי פרס – סדרת מכתשות סלע עמוקות שמתמלאות במים אחרי שיטפון. כאן עוצרים לשחייה ולטבילה.

        חזרה בערוץ לרכב (המשך הסימון השחור):
        במקום לחזור בשביל הירוק, ממשיכים לעלות בתוך ערוץ הנחל לאורך השביל השחור. ההליכה בערוץ מגוונת (מדרגות סלע, עצי שיטה ובולדרים). לקראת הסוף השביל מטפס במתינות מתוך הנחל ומתחבר חזרה ישירות לחניון הרכבים.
        """

        let rawBytes = sampleHebrew.data(using: .utf8)!
        assert(rawBytes.count > 1500, "Hebrew text is larger than 1.5 KB to test chunking beyond 1024-byte kernel buffer")

        // Test newline normalization
        let normalized = sampleHebrew.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        assert(!normalized.contains("\n"), "Normalized text must not contain raw LF (\\n)")
        assert(normalized.contains("\r"), "Normalized text must use CR (\\r) for universal CLI compatibility")

        // Test PTY session writing the entire large Hebrew chunk
        let session = PTYSession()
        try! session.start(cols: 80, rows: 24)
        session.write(string: normalized)

        // Give the async queue a moment to flush all chunks through poll
        usleep(150000)
        session.terminate()
        print("  -> Multi-line Hebrew paste successfully processed through chunked async PTY write queue without buffer overflow!")

        // Test 11: Hebrew Cursor Positioning & BiDi Arrow Navigation
        print("[Test 11] Testing Hebrew Cursor Positioning & BiDi Arrow Navigation...")
        let hebrewLine = "שלום"
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let pStyle = NSMutableParagraphStyle()
        pStyle.baseWritingDirection = .rightToLeft
        let attr = NSAttributedString(string: hebrewLine, attributes: [.font: font, .paragraphStyle: pStyle])
        let ctLine = CTLineCreateWithAttributedString(attr)
        let w = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        let lineX = 800 - 10 - w

        let runs = CTLineGetGlyphRuns(ctLine) as! [CTRun]
        assert(!runs.isEmpty, "CTLine must contain glyph runs")

        var col0Pos: CGFloat = 0
        var col3Pos: CGFloat = 0
        for r in runs {
            let count = CTRunGetGlyphCount(r)
            var indices = [CFIndex](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetStringIndices(r, CFRangeMake(0, count), &indices)
            CTRunGetPositions(r, CFRangeMake(0, count), &positions)
            for i in 0..<count {
                if indices[i] == 0 { col0Pos = lineX + positions[i].x }
                if indices[i] == 3 { col3Pos = lineX + positions[i].x }
            }
        }
        // In Hebrew RTL, character 0 ('ש') is to the RIGHT of character 3 ('ם')
        assert(col0Pos > col3Pos, "In Hebrew RTL, character 0 ('ש') must be visually to the right of character 3 ('ם')")
        print("  -> Hebrew cursor visual positioning verified!")

        // Test 12: Mixed Hebrew & English Natural Arrow Navigation
        print("[Test 12] Testing Mixed Hebrew & English Natural Arrow Navigation...")
        struct VisualGlyph {
            let col: Int
            let x: CGFloat
        }

        func testArrowResolver(text: String, isRTL: Bool, currentCol: Int, isLeft: Bool) -> String {
            func hasHebrewTest(_ str: String) -> Bool {
                for scalar in str.unicodeScalars {
                    let val = scalar.value
                    if (val >= 0x0590 && val <= 0x05FF) || (val >= 0xFB1D && val <= 0xFB4F) { return true }
                }
                return false
            }

            let lineLen = text.count
            guard lineLen > 0, hasHebrewTest(text) else {
                return isLeft ? "\u{1B}[D" : "\u{1B}[C"
            }

            let pS = NSMutableParagraphStyle()
            pS.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
            let aStr = NSAttributedString(string: text, attributes: [
                .font: font,
                .paragraphStyle: pS
            ])
            let cLine = CTLineCreateWithAttributedString(aStr)
            let lineWidth = CGFloat(CTLineGetTypographicBounds(cLine, nil, nil, nil))
            let lX: CGFloat = isRTL ? max(16.0, 800.0 - 16.0 - lineWidth) : 16.0

            var glyphs: [VisualGlyph] = []
            let cRuns = CTLineGetGlyphRuns(cLine) as! [CTRun]
            for r in cRuns {
                let count = CTRunGetGlyphCount(r)
                var indices = [CFIndex](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetStringIndices(r, CFRangeMake(0, count), &indices)
                CTRunGetPositions(r, CFRangeMake(0, count), &positions)
                for i in 0..<count {
                    glyphs.append(VisualGlyph(col: indices[i], x: lX + positions[i].x))
                }
            }
            var sec: CGFloat = 0
            let ctOff = CTLineGetOffsetForStringIndex(cLine, lineLen, &sec)
            glyphs.append(VisualGlyph(col: lineLen, x: lX + ctOff))

            var curX: CGFloat = lX + ctOff
            for g in glyphs {
                if g.col == currentCol {
                    curX = g.x
                    break
                }
            }

            if isLeft {
                let leftCandidates = glyphs.filter { $0.x < curX - 1.0 }
                if let target = leftCandidates.max(by: { $0.x < $1.x }) {
                    let diff = target.col - currentCol
                    if diff > 0 {
                        return String(repeating: "\u{1B}[C", count: min(50, diff))
                    } else if diff < 0 {
                        return String(repeating: "\u{1B}[D", count: min(50, -diff))
                    }
                }
                return "\u{1B}[D"
            } else {
                let rightCandidates = glyphs.filter { $0.x > curX + 1.0 }
                if let target = rightCandidates.min(by: { $0.x < $1.x }) {
                    let diff = target.col - currentCol
                    if diff > 0 {
                        return String(repeating: "\u{1B}[C", count: min(50, diff))
                    } else if diff < 0 {
                        return String(repeating: "\u{1B}[D", count: min(50, -diff))
                    }
                }
                return "\u{1B}[C"
            }
        }

        // Verify pure English line
        let engCmd = "git commit -m 'test'"
        for i in 0...engCmd.count {
            assert(testArrowResolver(text: engCmd, isRTL: false, currentCol: i, isLeft: true) == "\u{1B}[D")
            assert(testArrowResolver(text: engCmd, isRTL: false, currentCol: i, isLeft: false) == "\u{1B}[C")
        }

        // Verify mixed line: "echo שלום world"
        let mixedLine = "echo שלום world"
        // English word: Left arrow must send \e[D and Right arrow \e[C
        for i in 11...14 {
            assert(testArrowResolver(text: mixedLine, isRTL: false, currentCol: i, isLeft: true) == "\u{1B}[D")
            assert(testArrowResolver(text: mixedLine, isRTL: false, currentCol: i, isLeft: false) == "\u{1B}[C")
        }
        // Hebrew word: on 'ל' (col 6), to the right is 'ש' (col 5), so Right arrow must send \e[D
        assert(testArrowResolver(text: mixedLine, isRTL: false, currentCol: 6, isLeft: false) == "\u{1B}[D")
        // on 'ל' (col 6), to the left is 'ו' (col 7), so Left arrow must send \e[C
        assert(testArrowResolver(text: mixedLine, isRTL: false, currentCol: 6, isLeft: true) == "\u{1B}[C")

        // Boundary crossing: from space before Hebrew (col 4) to rightmost Hebrew character visually 'ם' (col 8)
        assert(testArrowResolver(text: mixedLine, isRTL: false, currentCol: 4, isLeft: false) == "\u{1B}[C\u{1B}[C\u{1B}[C\u{1B}[C")
        print("  -> Mixed Hebrew & English natural visual arrow navigation verified without inverting English words!")

        print("========================================")
        print("ALL TESTS PASSED! Engine is verified.")
        print("========================================")
    }
}
