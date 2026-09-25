import AppKit

@MainActor
func runLogicTests() {
    mathTests()
    codeBlockTests()
    exporterTests()
    shortcutTests()
    storeTests()
    menuBarIconTests()
}

@MainActor
private func mathTests() {
    section("Inline maths")
    func math(_ line: String, _ expected: String?) {
        let got = MathEvaluator.result(forLineEndingIn: line)
        check(got == expected, "\"\(line)\" -> \(got ?? "nil") (expected \(expected ?? "nil"))")
    }
    math("12*3", "36")
    math("(4+5)/3", "3")
    math("2^10", "1024")
    math("sqrt(16)", "4")
    math("7/2", "3.5")
    math("10/3", "3.333333333")
    math("5", nil)
    math("1/0", nil)
    math("total: 12 * 3", "36")
    math("buy 3 + 4", "7")
    math("hello", nil)
    math("2 ^ 3 ^ 2", "512")
    math("-5 + 2", "-3")
    math("1.5*4", "6")
    math("12 × 3", "36")
    math("• 2+2", "4")
    math("2+", nil)
    math("(2+3", nil)
    math("0.1+0.2", "0.3")
    math("1000000*1000000", "1000000000000")
    math("", nil)
}

@MainActor
private func codeBlockTests() {
    section("Code blocks")
    let document = "intro\n```swift\nlet x = 1\n```\nafter" as NSString
    let blocks = CodeHighlighter.blocks(in: document)
    check(blocks.count == 1 && blocks[0].language == "swift", "one swift block is found")
    check(document.substring(with: blocks[0].code) == "let x = 1\n", "the code range is the body only")
    check(
        document.substring(with: blocks[0].range).hasPrefix("```swift") && document.substring(with: blocks[0].range).hasSuffix("```\n"),
        "the block range includes both fences"
    )
    let unclosed = "a\n```py\nx = 1" as NSString
    let unclosedBlocks = CodeHighlighter.blocks(in: unclosed)
    check(unclosedBlocks.count == 1 && NSMaxRange(unclosedBlocks[0].range) == unclosed.length, "an unclosed fence extends to the end")
    check(CodeHighlighter.blocks(in: "no code here" as NSString).isEmpty, "plain text has no blocks")
    check(
        CodeHighlighter.isInsideBlock(20, in: document) && !CodeHighlighter.isInsideBlock(2, in: document)
            && !CodeHighlighter.isInsideBlock(document.length - 1, in: document),
        "isInsideBlock distinguishes code from text"
    )
    check(
        CodeHighlighter.blocks(in: "```js\na\n```\ntext\n```py\nb\n```" as NSString).map(\.language) == ["js", "py"],
        "two blocks are found in order"
    )

    let storage = NSTextStorage(string: "intro\n```swift\nlet x = \"hi\" // note\nfoo(42)\n```\nafter")
    let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    let plain = NSFont.systemFont(ofSize: 13)
    var ranges = CodeHighlighter.apply(to: storage, previous: [], codeFont: mono, textFont: { _ in plain })
    func attr(_ needle: String, _ key: NSAttributedString.Key) -> Any? {
        storage.attribute(key, at: (storage.string as NSString).range(of: needle).location, effectiveRange: nil)
    }
    check((attr("let", .foregroundColor) as? NSColor) == .systemPink, "keywords are coloured")
    check((attr("\"hi\"", .foregroundColor) as? NSColor) == .systemRed, "strings are coloured")
    check((attr("// note", .foregroundColor) as? NSColor) == .systemGray, "comments are coloured")
    check((attr("42", .foregroundColor) as? NSColor) == .systemPurple, "numbers are coloured")
    check((attr("foo", .foregroundColor) as? NSColor) == .systemBlue, "function calls are coloured")
    check((attr("let", .font) as? NSFont)?.isFixedPitch == true, "code is monospaced")
    check(attr("let", .backgroundColor) != nil, "code sits on a background card")
    check(attr("intro", .backgroundColor) == nil && attr("after", .backgroundColor) == nil, "text outside the block is untouched")
    storage.replaceCharacters(in: (storage.string as NSString).range(of: "```\nafter"), with: "after")
    ranges = CodeHighlighter.apply(to: storage, previous: ranges, codeFont: mono, textFont: { _ in plain })
    check(attr("after", .backgroundColor) != nil, "an unclosed block now styles to the end")
    storage.replaceCharacters(in: (storage.string as NSString).range(of: "```swift\n"), with: "")
    ranges = CodeHighlighter.apply(to: storage, previous: ranges, codeFont: mono, textFont: { _ in plain })
    check(
        attr("let", .backgroundColor) == nil && (attr("let", .font) as? NSFont)?.isFixedPitch == false && ranges.isEmpty,
        "styling is removed when the fence is gone"
    )

    let json = NSTextStorage(string: "```json\n{\"name\": \"a\", \"n\": 1, \"ok\": true}\n```")
    _ = CodeHighlighter.apply(to: json, previous: [], codeFont: mono, textFont: { _ in plain })
    let jsonText = json.string as NSString
    func jsonColor(_ needle: String) -> NSColor? {
        json.attribute(.foregroundColor, at: jsonText.range(of: needle).location, effectiveRange: nil) as? NSColor
    }
    check(jsonColor("\"name\"") == .systemBlue && jsonColor("\"a\"") == .systemRed, "JSON keys differ from string values")
    check(jsonColor("true") == .systemPink && jsonColor("1,") == .systemPurple, "JSON literals and numbers are coloured")
}

@MainActor
private func exporterTests() {
    section("Export")
    let note = NSMutableAttributedString(string: "• bold item\n☑ done task\nplain *star* and a link\n```py\nx = 1\n```\n")
    let bold = NSFont.systemFont(ofSize: 13, weight: .bold)
    let italic = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
    let text = note.string as NSString
    note.addAttribute(.font, value: bold, range: text.range(of: "bold item"))
    note.addAttribute(.font, value: italic, range: text.range(of: "a link"))
    note.addAttribute(.link, value: URL(string: "https://example.com")!, range: text.range(of: "a link"))
    let markdown = NoteExporter.markdown(note)
    check(markdown.contains("- **bold item**"), "markdown: bullet with bold")
    check(markdown.contains("- [x] done task"), "markdown: checked task")
    check(
        markdown.contains("[*a link*](https://example.com)") || markdown.contains("*[a link](https://example.com)*"),
        "markdown: italic link"
    )
    check(markdown.contains("```py\nx = 1\n```"), "markdown: code fences are kept verbatim")

    let padded = NSMutableAttributedString(string: "say hello world")
    padded.addAttribute(.font, value: bold, range: NSRange(location: 3, length: 7))
    check(NoteExporter.markdown(padded) == "say **hello** world", "markdown: markers hug the word")
    check(NoteExporter.plainText(NSAttributedString(string: "a\u{FFFC}b")) == "ab", "plain text drops attachment placeholders")

    let directory = temporaryDirectory("export")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let coloured = NSAttributedString(string: "hello", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NoteTextView.defaultColour,
    ])
    for format in NoteExportFormat.allCases {
        let url = directory.appendingPathComponent("note." + format.fileExtension)
        do {
            try NoteExporter.write(coloured, to: url, as: format)
            check(FileManager.default.fileExists(atPath: url.path), "wrote .\(format.fileExtension)")
        } catch {
            check(false, "writing .\(format.fileExtension) failed: \(error)")
        }
    }
    let rtf = (try? Data(contentsOf: directory.appendingPathComponent("note.rtf"))).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
    check(rtf?.string == "hello" && rtf?.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil, "RTF export has no baked-in text colour")
    try? FileManager.default.removeItem(at: directory)

    let mixed = NSMutableAttributedString(string: "ab")
    mixed.addAttribute(.foregroundColor, value: NoteTextView.defaultColour, range: NSRange(location: 0, length: 1))
    mixed.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 1, length: 1))
    let stripped = NoteTextView.strippingDefaultColour(from: mixed)
    check(stripped.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil, "copying strips the default text colour")
    check((stripped.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor) == .systemRed, "copying keeps a chosen colour")
}

@MainActor
private func shortcutTests() {
    section("Shortcuts")
    check(MenuShortcut.keepOnTop.display == "⌥⌘T", "keep on top defaults to ⌥⌘T")
    check(MenuShortcut.reopenClosedNote.display == "⇧⌘T", "reopen closed note defaults to ⇧⌘T")
    check(MenuShortcut.copyAllAndClose.display == "⇧⌘C", "copy all and close defaults to ⇧⌘C")
    UserDefaults.standard.set("k", forKey: MenuShortcut.keepOnTop.keyPref)
    UserDefaults.standard.set(Int(NSEvent.ModifierFlags([.command, .control]).rawValue), forKey: MenuShortcut.keepOnTop.modifiersPref)
    check(MenuShortcut.keepOnTop.display == "⌃⌘K", "a custom binding round-trips")
    MenuShortcut.resetAll()
    check(MenuShortcut.keepOnTop.display == "⌥⌘T", "reset restores the default")

    let main = NSMenu()
    let fileItem = NSMenuItem()
    let file = NSMenu(title: "File")
    fileItem.submenu = file
    main.addItem(fileItem)
    let close = file.addItem(withTitle: "Close", action: nil, keyEquivalent: "w")
    let keep = file.addItem(withTitle: "Keep on Top", action: nil, keyEquivalent: "t")
    keep.keyEquivalentModifierMask = [.command, .option]
    keep.identifier = NSUserInterfaceItemIdentifier(MenuShortcut.keepOnTop.rawValue)
    NSApp.mainMenu = main
    check(MenuShortcut.conflict(key: "w", modifiers: [.command], excluding: .keepOnTop) === close, "⌘W is reported as taken by Close")
    check(MenuShortcut.conflict(key: "t", modifiers: [.command, .option], excluding: .keepOnTop) == nil, "a shortcut's own binding is not a conflict")
    check(MenuShortcut.conflict(key: "t", modifiers: [.command, .option], excluding: .reopenClosedNote) === keep, "another action's binding is a conflict")
    check(MenuShortcut.conflict(key: "j", modifiers: [.command], excluding: .keepOnTop) == nil, "a free combination is allowed")
    NSApp.mainMenu = nil
}

@MainActor
private func storeTests() {
    section("Saved notes")
    let directory = temporaryDirectory("store")
    let store = NoteStore(directory: directory)
    let id = UUID()
    let content = NSMutableAttributedString(string: "hello saved note", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NoteTextView.defaultColour,
    ])
    content.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .bold), range: NSRange(location: 0, length: 5))
    let frame = NSRect(x: 120, y: 140, width: 480, height: 300)
    store.save(id: id, content: content, frame: frame, zoom: 2, pinned: true, imageWidths: [200, 80])

    let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    check(files.count == 2 && files.contains { $0.hasSuffix(".note") } && files.contains { $0.hasSuffix(".json") }, "a note and its metadata are written")
    let permissions = (try? FileManager.default.attributesOfItem(atPath: directory.path))?[.posixPermissions] as? Int
    check(permissions == 0o700, "the folder is private")

    let loaded = store.loadAll()
    check(loaded.count == 1 && loaded[0].content.string == "hello saved note", "the text loads back")
    check(loaded.first?.meta.zoom == 2 && loaded.first?.meta.pinned == true, "zoom and pinned state are saved")
    check(loaded.first?.meta.rect == frame, "the window frame is saved")
    check(loaded.first?.meta.imageWidths == [200, 80], "image widths are saved")
    let font = loaded.first?.content.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    check(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "bold formatting is saved")
    check(loaded.first?.content.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil, "the default text colour is not written to disk")

    store.delete(id: id)
    check(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).isEmpty, "deleting removes both files")

    store.save(id: UUID(), content: NSAttributedString(string: "  \n "), frame: .zero, zoom: 0, pinned: false)
    check(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).isEmpty, "an empty note is not saved")
    check(!NoteStore.isEmpty(NSAttributedString(attachment: NSTextAttachment())), "an image-only note counts as content")

    store.save(id: UUID(), content: NSAttributedString(string: "keep me"), frame: frame, zoom: 0, pinned: false)
    store.deleteAll()
    check(!FileManager.default.fileExists(atPath: directory.path), "deleteAll removes the folder")
}

@MainActor
private func menuBarIconTests() {
    section("Menu bar icon")
    let icon = MenuBarIcon.image()
    check(icon.isTemplate, "the icon is a template image, so macOS tints it for light and dark menu bars")
    check(icon.size == NSSize(width: 18, height: 18), "the icon is 18 by 18 points")

    let scale = 4
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        check(false, "the icon can be rendered")
        return
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    icon.draw(in: NSRect(x: 0, y: 0, width: 18 * scale, height: 18 * scale))
    NSGraphicsContext.restoreGraphicsState()

    func alpha(atPointX x: CGFloat, y: CGFloat) -> CGFloat {
        rep.colorAt(x: Int(x * CGFloat(scale)), y: 18 * scale - 1 - Int(y * CGFloat(scale)))?.alphaComponent ?? -1
    }
    check(alpha(atPointX: 9, y: 3.5) > 0.95 && alpha(atPointX: 3.0, y: 9) > 0.95 && alpha(atPointX: 9, y: 15) > 0.95, "the tile is solid")
    check(alpha(atPointX: 5.4, y: 9.6) < 0.05 && alpha(atPointX: 10.4, y: 9.6) < 0.05, "the eyes are cut out of the tile")
    check(alpha(atPointX: 7.05, y: 9.3) > 0.95 && alpha(atPointX: 12.05, y: 9.3) > 0.95, "each eye has a solid pupil")
    check(alpha(atPointX: 9, y: 9.6) > 0.95, "a solid divider separates the eyes")
    check(alpha(atPointX: 0.3, y: 0.3) < 0.05 && alpha(atPointX: 17.7, y: 17.7) < 0.05, "the corners are transparent")
    check(alpha(atPointX: 2.3, y: 2.3) < 0.05, "the tile has rounded corners")
}
