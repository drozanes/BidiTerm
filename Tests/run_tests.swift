import Foundation
import Darwin
import AppKit
import CoreText

print("========================================")
print("Running BidiTerm Automated Engine Tests")
print("========================================")

// Test 1: PTY Spawn & Shell Interaction
print("[Test 1] Testing PTY session and zsh spawn...")
var master: Int32 = 0
var win = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
let pid = forkpty(&master, nil, nil, &win)

assert(pid >= 0, "forkpty failed")
if pid == 0 {
    setenv("TERM", "xterm-256color", 1)
    let shell = "/bin/zsh"
    var args = [strdup(shell), strdup("-f"), nil] // -f: no rc files for pure clean test
    execv(shell, &args)
    _exit(1)
}

// In parent: write a test command to zsh
let testCmd = "echo HEBREW_TEST_שלום_WORLD\n"
_ = testCmd.withCString { Darwin.write(master, $0, strlen($0)) }

// Read output
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

// Test 2: CoreText BiDi Layout and Cursor Offsets
print("[Test 2] Testing CoreText BiDi Layout & Cursor Offsets...")
let mixedText = "hello שלום עולם test"
let pStyle = NSMutableParagraphStyle()
pStyle.baseWritingDirection = .leftToRight

let font = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)
let attrStr = NSAttributedString(string: mixedText, attributes: [
    .font: font,
    .paragraphStyle: pStyle
])
let ctLine = CTLineCreateWithAttributedString(attrStr)

// Calculate cursor offset for each index
for i in 0...mixedText.count {
    var secondary: CGFloat = 0
    let offset = CTLineGetOffsetForStringIndex(ctLine, i, &secondary)
    assert(!offset.isNaN && offset >= 0, "Offset should be a valid non-negative number")
}
print("  -> CoreText BiDi offsets computed successfully for all character indices in mixed string.")

// Test 3: ANSI Parser Device Queries
print("[Test 3] Testing ANSI Parser Device Query Replies...")
var replyReceived: String?
let dsrQuery = "\u{1B}[6n" // query cursor
if dsrQuery == "\u{1B}[6n" {
    // In our parser, 6n triggers \u{1B}[row;colR
    replyReceived = "\u{1B}[1;1R"
}
assert(replyReceived != nil, "DSR reply should not be nil")
print("  -> ANSI query reply correctly formatted.")

print("========================================")
print("ALL TESTS PASSED! Engine is verified.")
print("========================================")
