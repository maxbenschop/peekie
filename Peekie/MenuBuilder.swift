import AppKit

@MainActor
enum MenuBuilder {
    static func formatMenu(includeZoom: Bool = false) -> NSMenu {
        let menu = NSMenu(title: "Format")
        menu.addItem(withTitle: "Bold", action: #selector(NoteTextView.toggleBold(_:)), keyEquivalent: "b")
        menu.addItem(withTitle: "Italic", action: #selector(NoteTextView.toggleItalic(_:)), keyEquivalent: "i")
        menu.addItem(withTitle: "Underline", action: #selector(NoteTextView.toggleUnderline(_:)), keyEquivalent: "u")
        menu.addItem(.separator())

        let colour = NSMenuItem(title: "Text Colour", action: nil, keyEquivalent: "")
        colour.submenu = textColourMenu()
        menu.addItem(colour)

        if includeZoom {
            menu.addItem(.separator())
            zoomItems().forEach { menu.addItem($0) }
        }
        return menu
    }

    static func textColourMenu() -> NSMenu {
        let menu = NSMenu(title: "Text Colour")
        for (index, entry) in NoteTextView.palette.enumerated() {
            let item = NSMenuItem(
                title: entry.name, action: #selector(NoteTextView.applyTextColour(_:)),
                keyEquivalent: String(index + 1)
            )
            item.keyEquivalentModifierMask = [.control, .command]
            item.tag = index
            item.image = swatch(entry.color)
            menu.addItem(item)
        }
        return menu
    }

    static func zoomItems() -> [NSMenuItem] {
        [
            NSMenuItem(title: "Bigger", action: #selector(NoteTextView.increaseFontSize(_:)), keyEquivalent: "+"),
            NSMenuItem(title: "Smaller", action: #selector(NoteTextView.decreaseFontSize(_:)), keyEquivalent: "-"),
            NSMenuItem(title: "Actual Size", action: #selector(NoteTextView.resetFontSize(_:)), keyEquivalent: "0"),
        ]
    }

    private static func swatch(_ color: NSColor?) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            if let color {
                color.setFill()
                dot.fill()
            } else {
                NSColor.secondaryLabelColor.setStroke()
                dot.lineWidth = 1.5
                dot.stroke()
            }
            return true
        }
    }
}
