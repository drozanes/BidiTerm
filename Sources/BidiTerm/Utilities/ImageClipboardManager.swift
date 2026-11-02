import AppKit
import Foundation

public final class ImageClipboardManager {
    public static let shared = ImageClipboardManager()

    private let imagesDirectory: URL

    private init() {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.imagesDirectory = pictures.appendingPathComponent("TerminalImages", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    /// Checks if the general pasteboard has image data available.
    public func hasImage() -> Bool {
        let pasteboard = NSPasteboard.general
        let supportedTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        return pasteboard.canReadItem(withDataConformingToTypes: supportedTypes.map { $0.rawValue })
    }

    /// Saves the current image in the pasteboard to a file and returns its shell-escaped path.
    public func saveClipboardImageToFile() -> String? {
        let pasteboard = NSPasteboard.general
        guard let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let image = images.first else {
            return nil
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "screenshot_\(timestamp).png"
        let destinationURL = imagesDirectory.appendingPathComponent(filename)

        do {
            try pngData.write(to: destinationURL)
            return shellEscape(path: destinationURL.path)
        } catch {
            NSLog("[ImageClipboardManager] Failed to write image: \(error)")
            return nil
        }
    }

    /// Triggers an interactive screenshot capture (using macOS screencapture),
    /// saves it directly to a file, and returns the shell-escaped file path.
    public func captureInteractiveScreenshot(completion: @escaping (String?) -> Void) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "capture_\(formatter.string(from: Date())).png"
        let fileURL = imagesDirectory.appendingPathComponent(filename)

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-i", fileURL.path]

            do {
                try task.run()
                task.waitUntilExit()

                if task.terminationStatus == 0 && FileManager.default.fileExists(atPath: fileURL.path) {
                    let escaped = self.shellEscape(path: fileURL.path)
                    DispatchQueue.main.async {
                        completion(escaped)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            } catch {
                NSLog("[ImageClipboardManager] Failed to run screencapture: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    /// Escapes spaces and special characters for safe insertion into the shell.
    public func shellEscape(path: String) -> String {
        // Enclose in single quotes if it contains spaces or special characters
        if path.contains(" ") || path.contains("(") || path.contains(")") || path.contains("'") {
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }
        return path
    }
}
