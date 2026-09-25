import ApplicationServices
import AppKit
import Carbon.HIToolbox

@MainActor
enum QuickCapture {
    static func run() {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            NoteWindowController.shared.newNote()
            return
        }
        Task { @MainActor in
            let text = await selectedText()
            NoteWindowController.shared.newNote(text: text)
        }
    }

    private static func selectedText() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let before = pasteboard.changeCount

        try? await Task.sleep(for: .milliseconds(80))
        postCopy()

        var waited = 0
        while pasteboard.changeCount == before, waited < 300 {
            try? await Task.sleep(for: .milliseconds(15))
            waited += 15
        }

        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        restore(saved, to: pasteboard)
        return text
    }

    private static func postCopy() {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let value = item.data(forType: type) { data[type] = value }
            }
            return data
        }
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
