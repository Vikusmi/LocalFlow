import AppKit
import ApplicationServices

/// Light, rule-based cleanup of Whisper output.
enum TextCleaner {
    private static let fillers = ["um", "uh", "uhm", "umm", "erm", "hmm", "ehm", "eh"]

    static func clean(_ raw: String) -> String {
        var text = raw

        // Whisper artifacts like [BLANK_AUDIO], (music), <|en|>.
        text = text.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)|<\|[^|]*\|>"#, with: "", options: .regularExpression)

        // Filler words, with any trailing comma.
        let pattern = #"(?i)\b("# + fillers.joined(separator: "|") + #")\b,?\s*"#
        text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)

        // Collapse whitespace and fix spacing before punctuation.
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Whisper hallucinates these on silence.
        let hallucinations = ["thanks for watching!", "thank you for watching.", "you"]
        if hallucinations.contains(text.lowercased()) { return "" }

        // Capitalize the start of each sentence (removed fillers can leave "plan. can we…").
        var result = ""
        var capitalizeNext = true
        for char in text {
            if capitalizeNext, char.isLetter {
                result += char.uppercased()
                capitalizeNext = false
            } else {
                result.append(char)
                if ".!?".contains(char) { capitalizeNext = true }
                else if !char.isWhitespace { capitalizeNext = false }
            }
        }
        return result
    }
}

/// Puts text into whatever app is focused by pasting it, then restores the clipboard.
enum TextInserter {
    static func ensureAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Pastes `text` into the focused app. Returns false if Accessibility isn't granted:
    /// then the text is left on the clipboard so it isn't lost.
    @discardableResult
    static func insert(_ text: String) -> Bool {
        Log.write("insert \(text.count) chars, accessibility trusted: \(isTrusted)")
        guard isTrusted else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return false
        }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        pressCommandV()

        // Give the target app time to read the clipboard before restoring it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
        return true
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Appends lines to ~/Library/Logs/LocalFlow.log for troubleshooting.
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/LocalFlow.log")

    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
