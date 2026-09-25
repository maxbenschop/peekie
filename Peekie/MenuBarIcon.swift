import AppKit

enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func image() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Peekie"
        return image
    }

    static func draw() {
        guard let context = NSGraphicsContext.current else { return }

        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 1.8, y: 1.8, width: 14.4, height: 14.4), xRadius: 4.2, yRadius: 4.2).fill()

        let eyeCenters: [CGFloat] = [6.5, 11.5]

        context.compositingOperation = .clear
        for x in eyeCenters {
            NSBezierPath(ovalIn: NSRect(x: x - 2.0, y: 9.6 - 2.9, width: 4.0, height: 5.8)).fill()
        }
        context.compositingOperation = .sourceOver

        for x in eyeCenters {
            NSBezierPath(ovalIn: NSRect(x: x + 0.55 - 0.95, y: 9.3 - 0.95, width: 1.9, height: 1.9)).fill()
        }
    }
}
