import SwiftUI
import UniformTypeIdentifiers

final class NoteTextView: NSTextView {
    struct Style {
        var bold = false
        var italic = false
    }

    static let palette: [(name: String, color: NSColor?)] = [
        ("Default", nil), ("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow),
        ("Green", .systemGreen), ("Blue", .systemBlue), ("Purple", .systemPurple), ("Pink", .systemPink),
    ]

    static let defaultColour = NSColor.labelColor

    private static let bullet = "•"
    private static let unchecked = "☐"
    private static let checked = "☑"

    var stateDidChange: (() -> Void)?

    private var codeRanges: [NSRange] = []
    private var highlightWork: DispatchWorkItem?

    private var settingsFontSize: CGFloat = PrefDefault.fontSize
    private var monospaced = false
    private(set) var zoomDelta: CGFloat = 0

    private var fontSize: CGFloat { min(max(settingsFontSize + zoomDelta, 8), 48) }

    func font(_ style: Style) -> NSFont {
        let weight: NSFont.Weight = style.bold ? .bold : .regular
        var font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
            : NSFont.systemFont(ofSize: fontSize, weight: weight)
        if style.italic {
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
            font = NSFont(descriptor: descriptor, size: fontSize) ?? font
        }
        return font
    }

    private static func style(of font: NSFont?) -> Style {
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        return Style(bold: traits.contains(.bold), italic: traits.contains(.italic))
    }

    private func rebuildFonts() {
        if let storage = textStorage, storage.length > 0 {
            var runs: [(NSRange, Style)] = []
            storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                runs.append((range, Self.style(of: value as? NSFont)))
            }
            storage.beginEditing()
            for (range, style) in runs {
                storage.addAttribute(.font, value: font(style), range: range)
            }
            storage.endEditing()
        }
        typingAttributes[.font] = font(Self.style(of: typingAttributes[.font] as? NSFont))
        rehighlight()
    }

    private func applyDefaultColour() {
        guard let storage = textStorage, storage.length > 0 else { return }
        var uncoloured: [NSRange] = []
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value == nil { uncoloured.append(range) }
        }
        storage.beginEditing()
        for range in uncoloured {
            storage.addAttribute(.foregroundColor, value: Self.defaultColour, range: range)
        }
        storage.endEditing()
    }

    func applyFont(size: CGFloat, monospaced: Bool) {
        guard size != settingsFontSize || monospaced != self.monospaced else { return }
        settingsFontSize = size
        self.monospaced = monospaced
        rebuildFonts()
    }

    func load(_ content: NSAttributedString, zoom: CGFloat, imageWidths: [Double]? = nil) {
        zoomDelta = zoom
        textStorage?.setAttributedString(content)
        applyDefaultColour()
        if let imageWidths { applyImageWidths(imageWidths) }
        normalizeAttachments()
        rebuildFonts()
        setSelectedRange(NSRange(location: content.length, length: 0))
    }

    private var monoFont: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }

    override func didChangeText() {
        super.didChangeText()
        scheduleRehighlight()
        stateDidChange?()
    }

    private func scheduleRehighlight() {
        highlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rehighlight() }
        highlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func rehighlight() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        normalizeAttachments()

        if codeRanges.isEmpty, (storage.string as NSString).range(of: "```").location == NSNotFound { return }
        codeRanges = CodeHighlighter.apply(
            to: storage, previous: codeRanges, codeFont: monoFont,
            textFont: { [unowned self] old in self.font(Self.style(of: old)) }
        )
    }

    private func isInsideCode(_ index: Int) -> Bool {
        CodeHighlighter.isInsideBlock(index, in: string as NSString)
    }

    @objc func toggleBold(_ sender: Any?) { toggle(\.bold) }
    @objc func toggleItalic(_ sender: Any?) { toggle(\.italic) }

    private func isOn(_ key: WritableKeyPath<Style, Bool>) -> Bool {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else {
            return Self.style(of: typingAttributes[.font] as? NSFont)[keyPath: key]
        }
        var all = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            if !Self.style(of: value as? NSFont)[keyPath: key] {
                all = false
                stop.pointee = true
            }
        }
        return all
    }

    private func toggle(_ key: WritableKeyPath<Style, Bool>) {
        let makeOn = !isOn(key)
        let range = selectedRange()

        guard range.length > 0, let storage = textStorage else {
            var style = Self.style(of: typingAttributes[.font] as? NSFont)
            style[keyPath: key] = makeOn
            typingAttributes[.font] = font(style)
            return
        }
        var runs: [(NSRange, Style)] = []
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            var style = Self.style(of: value as? NSFont)
            style[keyPath: key] = makeOn
            runs.append((run, style))
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        for (run, style) in runs {
            storage.addAttribute(.font, value: font(style), range: run)
        }
        storage.endEditing()
        didChangeText()
    }

    private var underlineActive: Bool {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else {
            return (typingAttributes[.underlineStyle] as? Int ?? 0) != 0
        }
        var all = true
        storage.enumerateAttribute(.underlineStyle, in: range) { value, _, stop in
            if (value as? Int ?? 0) == 0 {
                all = false
                stop.pointee = true
            }
        }
        return all
    }

    @objc func toggleUnderline(_ sender: Any?) {
        let makeOn = !underlineActive
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else {
            if makeOn {
                typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                typingAttributes.removeValue(forKey: .underlineStyle)
            }
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        if makeOn {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            storage.removeAttribute(.underlineStyle, range: range)
        }
        didChangeText()
    }

    @objc func applyTextColour(_ sender: NSMenuItem) {
        guard Self.palette.indices.contains(sender.tag) else { return }
        let color = Self.palette[sender.tag].color ?? Self.defaultColour
        let range = selectedRange()

        guard range.length > 0, let storage = textStorage else {
            typingAttributes[.foregroundColor] = color
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.addAttribute(.foregroundColor, value: color, range: range)
        didChangeText()
    }

    @objc func increaseFontSize(_ sender: Any?) { zoom(by: 1) }
    @objc func decreaseFontSize(_ sender: Any?) { zoom(by: -1) }

    @objc func resetFontSize(_ sender: Any?) {
        zoomDelta = 0
        rebuildFonts()
        stateDidChange?()
    }

    private func zoom(by step: CGFloat) {
        zoomDelta += step

        zoomDelta = min(max(zoomDelta, 8 - settingsFontSize), 48 - settingsFontSize)
        rebuildFonts()
        stateDidChange?()
    }

    @objc func copyAllAndClose(_ sender: Any?) {
        guard (textStorage?.length ?? 0) > 0 else {
            window?.close()
            return
        }
        setSelectedRange(NSRange(location: 0, length: textStorage?.length ?? 0))
        copy(sender)
        window?.close()
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleBold(_:)):
            item.state = isOn(\.bold) ? .on : .off
            return true
        case #selector(toggleItalic(_:)):
            item.state = isOn(\.italic) ? .on : .off
            return true
        case #selector(toggleUnderline(_:)):
            item.state = underlineActive ? .on : .off
            return true
        default:
            return super.validateMenuItem(item)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        if let index = characterIndex(at: point),
           textStorage?.attribute(.attachment, at: index, effectiveRange: nil) is NSTextAttachment {
            let sizes = NSMenu(title: "Image Size")
            for (title, tag) in [("Small", 1), ("Medium", 2), ("Large (fit note)", 3), ("Actual Size", 4)] {
                let item = NSMenuItem(title: title, action: #selector(setImageSize(_:)), keyEquivalent: "")
                item.tag = tag
                item.representedObject = index
                sizes.addItem(item)
            }
            let parent = NSMenuItem(title: "Image Size", action: nil, keyEquivalent: "")
            parent.submenu = sizes
            menu.insertItem(parent, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        menu.addItem(.separator())
        let format = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        format.submenu = MenuBuilder.formatMenu(includeZoom: true)
        menu.addItem(format)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save…", action: #selector(saveNote(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Share…", action: #selector(shareNote(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Print…", action: #selector(printNote(_:)), keyEquivalent: "")
        return menu
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.subtracting(.shift) == .command,
           let key = event.charactersIgnoringModifiers, key == "=" || key == "+" {
            increaseFontSize(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string
        if typed == " " {
            convertListPrefixIfNeeded()
        } else if typed == "=" {
            insertMathResultIfNeeded()
        }
    }

    private func insertMathResultIfNeeded() {
        let ns = string as NSString
        let caret = selectedRange()
        guard caret.length == 0, caret.location > 0, !isInsideCode(caret.location) else { return }
        let line = ns.lineRange(for: NSRange(location: caret.location, length: 0))
        var contentsEnd = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: line)

        guard caret.location == contentsEnd else { return }
        let before = ns.substring(with: NSRange(location: line.location, length: caret.location - 1 - line.location))
        guard let result = MathEvaluator.result(forLineEndingIn: before) else { return }
        super.insertText(" " + result, replacementRange: selectedRange())
    }

    private func convertListPrefixIfNeeded() {
        let ns = string as NSString
        let caret = selectedRange().location
        guard !isInsideCode(caret) else { return }
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        let prefixRange = NSRange(location: line.location, length: caret - line.location)
        guard prefixRange.length > 0 else { return }

        let replacement: String
        switch ns.substring(with: prefixRange) {
        case "- ", "* ": replacement = Self.bullet + " "
        case "[] ", "[ ] ": replacement = Self.unchecked + " "
        default: return
        }
        replace(prefixRange, with: replacement)
        setSelectedRange(NSRange(location: line.location + (replacement as NSString).length, length: 0))
    }

    private func replace(_ range: NSRange, with text: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
    }

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let caret = selectedRange()
        if isInsideCode(caret.location) {
            let line = ns.lineRange(for: NSRange(location: caret.location, length: 0))
            let text = ns.substring(with: line)
            let indent = String(text.prefix { $0 == " " || $0 == "\t" })
            super.insertNewline(sender)
            if !indent.isEmpty { super.insertText(indent, replacementRange: selectedRange()) }
            return
        }
        let line = ns.lineRange(for: NSRange(location: caret.location, length: 0))
        var contentsEnd = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: line)
        let text = ns.substring(with: NSRange(location: line.location, length: contentsEnd - line.location))

        let marker: String
        if text.hasPrefix(Self.bullet + " ") {
            marker = Self.bullet
        } else if text.hasPrefix(Self.unchecked + " ") || text.hasPrefix(Self.checked + " ") {
            marker = Self.unchecked
        } else {
            super.insertNewline(sender)
            return
        }

        guard caret.length == 0, caret.location >= line.location + 2 else {
            super.insertNewline(sender)
            return
        }
        if text.count <= 2 {
            replace(NSRange(location: line.location, length: contentsEnd - line.location), with: "")
            return
        }
        super.insertNewline(sender)
        typingAttributes.removeValue(forKey: .strikethroughStyle)
        super.insertText(marker + " ", replacementRange: selectedRange())
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = characterIndex(at: point) {
            if event.modifierFlags.contains(.command), openLink(at: index) { return }
            if toggleCheckbox(at: index) { return }
        }
        super.mouseDown(with: event)
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = layoutManager.characterIndex(
            for: local, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard index < (string as NSString).length else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).contains(local) ? index : nil
    }

    private func openLink(at index: Int) -> Bool {
        guard let value = textStorage?.attribute(.link, at: index, effectiveRange: nil) else { return false }
        let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
        guard let url else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    private func toggleCheckbox(at index: Int) -> Bool {
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: index, length: 0))
        guard index == line.location else { return false }
        let symbol = ns.substring(with: NSRange(location: index, length: 1))
        guard symbol == Self.unchecked || symbol == Self.checked, let storage = textStorage else { return false }

        var contentsEnd = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: line)
        let checking = symbol == Self.unchecked
        let lineRange = NSRange(location: index, length: contentsEnd - index)
        let rest = NSRange(location: index + 1, length: max(0, contentsEnd - index - 1))

        guard shouldChangeText(in: lineRange, replacementString: nil) else { return true }
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: index, length: 1), with: checking ? Self.checked : Self.unchecked)
        if checking {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: rest)
        } else {
            storage.removeAttribute(.strikethroughStyle, range: rest)
        }
        storage.endEditing()
        didChangeText()
        return true
    }

    static func strippingDefaultColour(from text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        result.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            if let colour = value as? NSColor, colour == defaultColour {
                result.removeAttribute(.foregroundColor, range: range)
            }
        }
        return result
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }
        let text = Self.strippingDefaultColour(from: storage.attributedSubstring(from: range))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([text])
    }

    override func cut(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        copy(sender)
        if shouldChangeText(in: range, replacementString: "") {
            textStorage?.replaceCharacters(in: range, with: "")
            didChangeText()
        }
    }

    private var maxImageWidth: CGFloat { max(60, bounds.width - textContainerInset.width * 2 - 12) }

    private var isLaidOut: Bool { bounds.width >= 100 }

    private func resolvedImage(for attachment: NSTextAttachment) -> NSImage? {
        if let image = attachment.image { return image }
        guard let data = attachment.fileWrapper?.regularFileContents, let image = NSImage(data: data) else { return nil }
        attachment.image = image
        return image
    }

    private func defaultImageBounds(for size: NSSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let boxWidth = maxImageWidth * 0.6
        let boxHeight = max(120, visibleRect.height) * 0.6
        let scale = min(1, boxWidth / size.width, boxHeight / size.height)
        return CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
    }

    private func imageBounds(width: CGFloat, for size: NSSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let clamped = min(max(24, width), maxImageWidth)
        return CGRect(x: 0, y: 0, width: clamped, height: clamped * size.height / size.width)
    }

    func insertImage(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }

        let stored = NSImage(data: png) ?? image
        let attachment = NSTextAttachment(data: png, ofType: UTType.png.identifier)
        attachment.image = stored
        attachment.bounds = defaultImageBounds(for: stored.size == .zero ? image.size : stored.size)

        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: "\u{FFFC}") else { return }
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
        setSelectedRange(NSRange(location: range.location + 1, length: 0))
        didChangeText()
    }

    func imageWidths() -> [Double] {
        guard let storage = textStorage, storage.length > 0 else { return [] }
        var widths: [Double] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { widths.append(Double(attachment.bounds.width)) }
        }
        return widths
    }

    private func applyImageWidths(_ widths: [Double]) {
        guard let storage = textStorage, storage.length > 0 else { return }
        var index = 0
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            defer { index += 1 }
            guard index < widths.count, widths[index] > 0, let image = resolvedImage(for: attachment),
                  image.size.width > 0 else { return }
            let width = CGFloat(widths[index])
            attachment.bounds = CGRect(x: 0, y: 0, width: width, height: width * image.size.height / image.size.width)
            layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }
    }

    func normalizeAttachments() {
        guard isLaidOut, let storage = textStorage, storage.length > 0 else { return }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, let image = resolvedImage(for: attachment) else { return }
            var target: CGRect?
            if attachment.bounds == .zero {
                target = defaultImageBounds(for: image.size)
            } else if attachment.bounds.width > maxImageWidth + 0.5 {
                target = imageBounds(width: maxImageWidth, for: image.size)
            }
            if let target {
                attachment.bounds = target
                layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager?.invalidateDisplay(forCharacterRange: range)
            }
        }
    }

    @objc func setImageSize(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, let storage = textStorage, index < storage.length,
              let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment,
              let image = resolvedImage(for: attachment) else { return }
        let width: CGFloat
        switch sender.tag {
        case 1: width = maxImageWidth * 0.25
        case 2: width = maxImageWidth * 0.5
        case 3: width = maxImageWidth
        default: width = image.size.width
        }
        attachment.bounds = imageBounds(width: width, for: image.size)
        let range = NSRange(location: index, length: 1)
        layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        layoutManager?.invalidateDisplay(forCharacterRange: range)
        needsDisplay = true
        stateDidChange?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        normalizeAttachments()
    }

    private func imageURLs(in pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        ) as? [URL] ?? []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let urls = imageURLs(in: pasteboard)
        let hasText = !(pasteboard.string(forType: .string) ?? "").isEmpty
        if !urls.isEmpty || !hasText, urls.isEmpty ? NSImage.canInit(with: pasteboard) : true {
            let point = convert(sender.draggingLocation, from: nil)
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            if !urls.isEmpty {
                urls.compactMap { NSImage(contentsOf: $0) }.forEach { insertImage($0) }
                return true
            }
            if let image = NSImage(pasteboard: pasteboard) {
                insertImage(image)
                return true
            }
        }
        return super.performDragOperation(sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let urls = imageURLs(in: pasteboard)
        if !urls.isEmpty {
            urls.compactMap { NSImage(contentsOf: $0) }.forEach { insertImage($0) }
            return
        }
        let hasText = !(pasteboard.string(forType: .string) ?? "").isEmpty
        if !hasText, let image = NSImage(pasteboard: pasteboard) {
            insertImage(image)
            return
        }
        pasteAsPlainText(sender)
    }

    private func suggestedFileName() -> String {
        let first = NoteExporter.plainText(attributedString()).split(separator: "\n").first.map(String.init) ?? ""
        let cleaned = first.filter { !"/:\\\u{0}".contains($0) }.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Peekie Note" : String(cleaned.prefix(40))
    }

    @objc func saveNote(_ sender: Any?) {
        guard let window else { return }
        let note = attributedString()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName()
        panel.canCreateDirectories = true

        let picker = SaveFormatPicker(panel: panel)
        panel.accessoryView = picker.view
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try NoteExporter.write(note, to: url, as: picker.format)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
            withExtendedLifetime(picker) {}
        }
    }

    @objc func shareNote(_ sender: Any?) {
        let note = attributedString()
        var items: [Any] = [NoteExporter.plainText(note)]
        note.enumerateAttribute(.attachment, in: NSRange(location: 0, length: note.length)) { value, _, _ in
            if let image = (value as? NSTextAttachment)?.image { items.append(image) }
        }
        let anchor = NSRect(x: visibleRect.maxX - 24, y: visibleRect.minY, width: 1, height: 1)
        NSSharingServicePicker(items: items).show(relativeTo: anchor, of: self, preferredEdge: .minY)
    }

    @objc func printNote(_ sender: Any?) {
        guard let window else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        let width = info.paperSize.width - info.leftMargin - info.rightMargin

        let printable = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        printable.appearance = NSAppearance(named: .aqua)
        printable.isVerticallyResizable = true
        printable.textContainer?.widthTracksTextView = true
        printable.textStorage?.setAttributedString(Self.strippingDefaultColour(from: attributedString()))
        if let layoutManager = printable.layoutManager, let container = printable.textContainer {
            layoutManager.ensureLayout(for: container)
            printable.setFrameSize(NSSize(width: width, height: ceil(layoutManager.usedRect(for: container).height) + 20))
        }
        NSPrintOperation(view: printable, printInfo: info)
            .runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

@MainActor
final class SaveFormatPicker: NSObject {
    let view = NSStackView()
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private unowned let panel: NSSavePanel

    init(panel: NSSavePanel) {
        self.panel = panel
        super.init()
        popup.addItems(withTitles: NoteExportFormat.allCases.map(\.title))
        popup.target = self
        popup.action = #selector(changed)
        let label = NSTextField(labelWithString: "Format:")
        view.orientation = .horizontal
        view.spacing = 8
        view.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.addArrangedSubview(label)
        view.addArrangedSubview(popup)
        changed()
    }

    var format: NoteExportFormat { NoteExportFormat.allCases[max(0, popup.indexOfSelectedItem)] }

    @objc private func changed() {
        panel.allowedContentTypes = [format.contentType]
    }
}

struct NoteTextEditor: NSViewRepresentable {
    let model: NoteModel
    var fontSize: Double
    var monospaced: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NoteTextView(frame: .zero, textContainer: container)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.applyFont(size: fontSize, monospaced: monospaced)
        textView.font = textView.font(NoteTextView.Style())
        textView.typingAttributes = [
            .font: textView.font(NoteTextView.Style()),
            .foregroundColor: NoteTextView.defaultColour,
        ]
        textView.insertionPointColor = NoteTextView.defaultColour

        model.textView = textView
        textView.stateDidChange = { [weak model] in model?.onChange?() }
        if let content = model.initialContent {
            textView.load(content, zoom: model.initialZoom, imageWidths: model.initialImageWidths)
            model.initialContent = nil
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        (scrollView.documentView as? NoteTextView)?.applyFont(size: fontSize, monospaced: monospaced)
    }
}
