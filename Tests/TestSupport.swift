import AppKit

var failures = 0

func check(_ condition: Bool, _ message: String) {
    FileHandle.standardError.write(((condition ? "PASS " : "FAIL ") + message + "\n").data(using: .utf8)!)
    if !condition { failures += 1 }
}

func section(_ title: String) {
    FileHandle.standardError.write(("\n" + title + "\n").data(using: .utf8)!)
}

func spin(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func temporaryDirectory(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("peekie-tests-\(name)-\(UUID().uuidString)")
}

func makeImage(width: Int, height: Int, scale: CGFloat = 2) -> NSImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    rep.size = NSSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

@MainActor
func makeTextView(width: CGFloat = 400, height: CGFloat = 300) -> NoteTextView {
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layoutManager.addTextContainer(container)

    let textView = NoteTextView(frame: NSRect(x: 0, y: 0, width: width, height: height), textContainer: container)
    textView.minSize = .zero
    textView.maxSize = NSSize(width: 10_000_000, height: 10_000_000)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.isRichText = true
    textView.allowsUndo = true
    textView.importsGraphics = true
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 8, height: 6)
    textView.applyFont(size: 13, monospaced: false)
    textView.typingAttributes = [
        .font: textView.font(NoteTextView.Style()),
        .foregroundColor: NoteTextView.defaultColour,
    ]

    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    scrollView.documentView = textView
    scrollView.drawsBackground = false
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = scrollView
    testWindows.append(window)
    return textView
}

@MainActor var testWindows: [NSWindow] = []

@MainActor
func type(_ textView: NoteTextView, _ text: String) {
    for character in text {
        if character == "\n" {
            textView.insertNewline(nil)
        } else {
            textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }
}

@MainActor
func attribute(_ textView: NoteTextView, _ needle: String, _ key: NSAttributedString.Key) -> Any? {
    let range = (textView.string as NSString).range(of: needle)
    return range.location == NSNotFound ? nil : textView.textStorage?.attribute(key, at: range.location, effectiveRange: nil)
}

@MainActor
func attachments(in textView: NoteTextView) -> [NSTextAttachment] {
    var found: [NSTextAttachment] = []
    guard let storage = textView.textStorage else { return found }
    storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
        if let attachment = value as? NSTextAttachment { found.append(attachment) }
    }
    return found
}

@MainActor
func drawnBrightness(of textView: NoteTextView) -> CGFloat {
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    textView.display()
    let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds)!
    textView.cacheDisplay(in: textView.bounds, to: rep)
    var sum: CGFloat = 0
    var count: CGFloat = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 else { continue }
            sum += (color.redComponent + color.greenComponent + color.blueComponent) / 3
            count += 1
        }
    }
    return count == 0 ? -1 : sum / count
}

@MainActor
func drawnImageWidth(of textView: NoteTextView) -> CGFloat {
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    textView.display()
    let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds)!
    textView.cacheDisplay(in: textView.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / textView.bounds.width
    var minX = Int.max
    var maxX = -1
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 else { continue }
            let saturation = max(color.redComponent, color.greenComponent, color.blueComponent)
                - min(color.redComponent, color.greenComponent, color.blueComponent)
            if saturation > 0.25 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
    }
    return maxX < 0 ? 0 : CGFloat(maxX - minX + 1) / scale
}
