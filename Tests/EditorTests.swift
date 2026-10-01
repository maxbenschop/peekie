import AppKit

@MainActor
func runEditorTests() {
    typingTests()
    listTests()
    checkboxTests()
    checkboxAlignmentTests()
    checkboxAccessibilityAndAppearanceTests()
    formattingTests()
    codeTypingTests()
    colourTests()
    imageTests()
}

@MainActor
private func typingTests() {
    section("Typing")
    var textView = makeTextView()
    type(textView, "12*3 =")
    check(textView.string == "12*3 = 36", "typing '12*3 =' appends the answer")
    textView = makeTextView()
    type(textView, "hello =")
    check(textView.string == "hello =", "lines that are not maths are left alone")
    textView = makeTextView()
    type(textView, "a = 5 + 5 =")
    check(textView.string == "a = 5 + 5 = 10", "maths works after an earlier '='")
    textView = makeTextView()
    type(textView, "```\n2+2 =")
    check(textView.string == "```\n2+2 =", "no maths inside a code block")
}

@MainActor
private func listTests() {
    section("Lists")
    var textView = makeTextView()
    type(textView, "- milk")
    check(textView.string == "• milk", "'- ' becomes a bullet")
    textView.insertNewline(nil)
    check(textView.string == "• milk\n• ", "Return continues the bullet list")
    textView.insertNewline(nil)
    check(textView.string == "• milk\n", "Return on an empty bullet ends the list")

    textView = makeTextView()
    type(textView, "[] task")
    check(checklistText(textView) == "☐ task", "'[] ' becomes a checkbox")
    textView.insertNewline(nil)
    check(checklistText(textView) == "☐ task\n☐ ", "Return continues the checklist")

    textView = makeTextView()
    type(textView, "```\n- item")
    check(textView.string == "```\n- item", "'- ' inside code stays literal")
    textView = makeTextView()
    type(textView, "```\nx\n```\n- item")
    check(textView.string == "```\nx\n```\n• item", "lists work again after the closing fence")
    textView = makeTextView()
    type(textView, "```\n    foo\nbar")
    check(textView.string == "```\n    foo\n    bar", "Return in code keeps the indentation")
}

@MainActor
private func checkboxTests() {
    section("Checkboxes")
    let textView = makeTextView()
    type(textView, "[] buy milk\neggs")
    check(checklistText(textView) == "☐ buy milk\n☐ eggs", "a checklist is set up")
    guard let layoutManager = textView.layoutManager, let container = textView.textContainer, let window = textView.window else { return }

    func click(characterAt index: Int) {
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        let point = NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y)
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: textView.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        textView.mouseDown(with: event)
    }
    click(characterAt: 0)
    check(checklistText(textView) == "☑ buy milk\n☐ eggs", "clicking a box checks it")
    check(((attribute(textView, "buy", .strikethroughStyle) as? Int) ?? 0) != 0, "a checked item is struck through")
    check((attribute(textView, "buy", .foregroundColor) as? NSColor) == .secondaryLabelColor, "a checked item's text is dimmed")
    check(attribute(textView, "eggs", .strikethroughStyle) == nil, "other items are untouched")
    click(characterAt: 0)
    check(checklistText(textView) == "☐ buy milk\n☐ eggs" && attribute(textView, "buy", .strikethroughStyle) == nil, "clicking again unchecks it")
    check((attribute(textView, "buy", .foregroundColor) as? NSColor) == NoteTextView.defaultColour, "unchecking restores the normal text colour")
    click(characterAt: 11)
    check(checklistText(textView) == "☐ buy milk\n☑ eggs", "each line's box toggles independently")
    textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    textView.insertNewline(nil)
    type(textView, "milk")
    let last = (textView.string as NSString).length - 1
    check(textView.textStorage?.attribute(.strikethroughStyle, at: last, effectiveRange: nil) == nil, "a new item after a checked one is not struck through")
    check((textView.textStorage?.attribute(.foregroundColor, at: last, effectiveRange: nil) as? NSColor) == NoteTextView.defaultColour, "a new item after a checked one is not dimmed")
}

/// Regression test for the checkbox/text baseline misalignment this app went through
/// several rounds of fixing by eyeballing screenshots. This renders the *real*
/// `NoteTextView` to an offscreen bitmap (same as `drawnImageWidth`/`drawnBrightness`
/// elsewhere in this file) and measures actual ink pixels, rather than trusting any
/// layout API's claimed position or a human comparing screenshots.
///
/// Swept across font sizes (not just the 13pt default) and label words, since a report
/// of misalignment at some zoom level the single-size test didn't cover is exactly the
/// kind of thing this is meant to catch before a human has to screenshot it again.
@MainActor
private func checkboxAlignmentTests() {
    section("Checkbox alignment")
    for fontSize: CGFloat in [8, 13, 17, 24, 32, 48] {
        for (checked, label, word) in [(false, "unchecked", "test"), (true, "checked", "done")] {
            assertCheckboxAligned(fontSize: fontSize, checked: checked, label: label, word: word)
        }
    }
}

@MainActor
private func assertCheckboxAligned(fontSize: CGFloat, checked: Bool, label: String, word: String) {
    let textView = makeTextView()
    textView.applyFont(size: fontSize, monospaced: false)
    type(textView, "[] \(word)")
    if checked {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer, let window = textView.window else {
            check(false, "checkbox alignment (\(label), \(fontSize)pt): could not set up test view")
            return
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: 1), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        let point = NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y)
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: textView.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        textView.mouseDown(with: event)
    }

    // Character 0 is the checkbox attachment; the word starts at character 2.
    let boxRect = glyphViewRect(of: textView, characterRange: NSRange(location: 0, length: 1))
    let textRect = glyphViewRect(of: textView, characterRange: NSRange(location: 2, length: (word as NSString).length))
    guard let boxInk = drawnInkRowRange(of: textView, xRange: boxRect.minX..<boxRect.maxX),
          let textInk = drawnInkRowRange(of: textView, xRange: textRect.minX..<textRect.maxX)
    else {
        check(false, "checkbox alignment (\(label), \(fontSize)pt): nothing was actually drawn to measure")
        return
    }
    // Row 0 is the top of the bitmap, so the *bottom* edge is the larger row number.
    // Tolerance is a flat 2px (antialiasing noise) regardless of font size — deliberately
    // NOT scaled with size, since a size-proportional gap is exactly the bug this test
    // caught once already (a scaling tolerance would have masked it as "passing").
    let tolerance = 2
    let bottomDelta = abs(boxInk.bottom - textInk.bottom)
    check(bottomDelta <= tolerance, "checkbox (\(label), \(fontSize)pt, \"\(word)\") bottom edge sits on the text baseline (off by \(bottomDelta)px, tolerance \(tolerance): box bottom row \(boxInk.bottom), text bottom row \(textInk.bottom))")
}

/// Guards two Apple-rules violations found by auditing this app's UI: (1) VoiceOver
/// must read a meaningful label, never an internal implementation string; (2) a colour
/// used in both light and dark Appearance mode must be dynamic/semantic, not a fixed
/// RGB value that's only correct in one of the two.
@MainActor
private func checkboxAccessibilityAndAppearanceTests() {
    section("Checkbox accessibility & appearance")
    let unchecked = ChecklistBox.attachment(checked: false, font: .systemFont(ofSize: 13))
    let uncheckedLabel = unchecked.image?.accessibilityDescription ?? ""
    check(!uncheckedLabel.lowercased().contains("peekie"), "unchecked box's VoiceOver label is not an internal identifier (got \"\(uncheckedLabel)\")")
    check(uncheckedLabel.first?.isUppercase == true && uncheckedLabel.contains(" "), "unchecked box's VoiceOver label reads as an actual sentence (got \"\(uncheckedLabel)\")")

    let checked = ChecklistBox.attachment(checked: true, font: .systemFont(ofSize: 13))
    let checkedLabel = checked.image?.accessibilityDescription ?? ""
    check(!checkedLabel.lowercased().contains("peekie"), "checked box's VoiceOver label is not an internal identifier (got \"\(checkedLabel)\")")
    check(checkedLabel != uncheckedLabel, "checked and unchecked boxes have distinct VoiceOver labels")

    // NSColor.secondaryLabelColor only resolves to concrete pixels at *draw* time, and
    // ChecklistBox renders into a plain bitmap once (not a re-drawable dynamic image),
    // so each appearance needs its own render — reading the same already-rendered
    // bitmap back under a different appearance wrapper wouldn't change anything.
    func averagePixel(in appearanceName: NSAppearance.Name) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let appearance = NSAppearance(named: appearanceName) else { return nil }
        var result: (CGFloat, CGFloat, CGFloat)?
        appearance.performAsCurrentDrawingAppearance {
            let box = ChecklistBox.attachment(checked: false, font: .systemFont(ofSize: 13))
            guard let image = box.image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
            var sumR: CGFloat = 0, sumG: CGFloat = 0, sumB: CGFloat = 0, count: CGFloat = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.1 else { continue }
                    sumR += colour.redComponent; sumG += colour.greenComponent; sumB += colour.blueComponent
                    count += 1
                }
            }
            guard count > 0 else { return }
            result = (sumR / count, sumG / count, sumB / count)
        }
        return result
    }
    if let lightPixel = averagePixel(in: .aqua), let darkPixel = averagePixel(in: .darkAqua) {
        let changed = abs(lightPixel.r - darkPixel.r) > 0.05 || abs(lightPixel.g - darkPixel.g) > 0.05 || abs(lightPixel.b - darkPixel.b) > 0.05
        check(changed, "unchecked box's border colour actually differs between light and dark appearance (light=\(lightPixel), dark=\(darkPixel))")
    } else {
        check(false, "could not render the checkbox to compare light/dark appearance")
    }
}

@MainActor
private func formattingTests() {
    section("Formatting")
    func traits(_ textView: NoteTextView, _ index: Int) -> (bold: Bool, italic: Bool) {
        let font = textView.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        return (traits.contains(.bold), traits.contains(.italic))
    }
    let textView = makeTextView()
    type(textView, "hello world")
    textView.setSelectedRange(NSRange(location: 0, length: 5))
    textView.toggleBold(nil)
    check(traits(textView, 0) == (true, false) && traits(textView, 6) == (false, false), "bold applies to the selection only")
    textView.toggleItalic(nil)
    check(traits(textView, 0) == (true, true), "italic stacks on bold")
    textView.toggleBold(nil)
    check(traits(textView, 0) == (false, true), "bold toggles off and italic stays")
    textView.toggleUnderline(nil)
    check((textView.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) != 0, "underline turns on")
    textView.toggleUnderline(nil)
    check((textView.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0, "underline turns off")

    textView.increaseFontSize(nil)
    textView.increaseFontSize(nil)
    let zoomed = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    check(zoomed?.pointSize == 15 && traits(textView, 0) == (false, true), "zoom changes the size and keeps the style")
    textView.resetFontSize(nil)
    check((textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 13, "zoom resets")
    textView.applyFont(size: 18, monospaced: true)
    let restyled = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    check(restyled?.pointSize == 18 && restyled?.fontName.contains("Monospaced") == true && traits(textView, 0) == (false, true), "a settings change re-fonts the note")

    let undoView = makeTextView()
    let undoManager = undoView.undoManager
    check(undoManager != nil, "an undo manager is available")
    undoManager?.groupsByEvent = false
    undoManager?.beginUndoGrouping()
    type(undoView, "undo me")
    undoManager?.endUndoGrouping()
    undoView.setSelectedRange(NSRange(location: 0, length: 4))
    undoManager?.beginUndoGrouping()
    undoView.toggleBold(nil)
    undoManager?.endUndoGrouping()
    check(traits(undoView, 0).bold, "bold is applied")
    undoManager?.undo()
    check(!traits(undoView, 0).bold && undoView.string == "undo me", "undo reverts bold and keeps the text")
    undoManager?.redo()
    check(traits(undoView, 0).bold, "redo restores bold")
}

@MainActor
private func codeTypingTests() {
    section("Code while typing")
    let textView = makeTextView()
    type(textView, "before\n```swift\nlet x = 1 // c\n```\nafter")
    spin(0.5)
    check((attribute(textView, "let", .foregroundColor) as? NSColor) == .systemPink, "keywords are highlighted after typing")
    check((attribute(textView, "let", .font) as? NSFont)?.isFixedPitch == true, "the block is monospaced")
    check(attribute(textView, "before", .backgroundColor) == nil && attribute(textView, "after", .backgroundColor) == nil, "text outside is untouched")
    textView.applyFont(size: 20, monospaced: false)
    spin(0.4)
    let font = attribute(textView, "let", .font) as? NSFont
    check(font?.isFixedPitch == true && font?.pointSize == 20, "code stays monospaced when the size changes")
    check((attribute(textView, "before", .font) as? NSFont)?.isFixedPitch == false, "normal text stays proportional")
}

@MainActor
private func colourTests() {
    section("Colour")
    let textView = makeTextView(width: 400, height: 100)
    textView.window?.appearance = NSAppearance(named: .darkAqua)
    textView.applyFont(size: 26, monospaced: false)
    type(textView, "HELLO")
    check(drawnBrightness(of: textView) > 0.9, "typed text is white in a dark note")

    let captured = makeTextView(width: 400, height: 100)
    captured.window?.appearance = NSAppearance(named: .darkAqua)
    captured.applyFont(size: 26, monospaced: false)
    captured.load(NSAttributedString(string: "HELLO"), zoom: 0)
    check(drawnBrightness(of: captured) > 0.9, "plain text loaded into a note is white")

    let sourceStyled = makeTextView(width: 400, height: 100)
    sourceStyled.applyFont(size: 26, monospaced: false)
    sourceStyled.load(NSAttributedString(string: "HELLO", attributes: [.font: NSFont(name: "Times New Roman", size: 9)!]), zoom: 0)
    let font = sourceStyled.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    check(font?.pointSize == 26 && font?.fontName.contains("Times") == false, "a source font is replaced by the note's font")

    textView.selectAll(nil)
    let red = NSMenuItem()
    red.tag = 1
    textView.applyTextColour(red)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    let redBrightness = drawnBrightness(of: textView)
    textView.selectAll(nil)
    let reset = NSMenuItem()
    reset.tag = 0
    textView.applyTextColour(reset)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    check(redBrightness < 0.9 && drawnBrightness(of: textView) > 0.9, "the Default colour restores white text")
}

@MainActor
private func imageTests() {
    section("Images in the editor")
    let textView = makeTextView()
    type(textView, "a")
    textView.insertImage(makeImage(width: 1600, height: 800))
    type(textView, "b")
    check(textView.string == "a\u{FFFC}b", "an image is inserted inline")
    let inserted = attachments(in: textView)
    check(inserted.count == 1, "one attachment is present")
    if let attachment = inserted.first {
        check(attachment.bounds.width <= 372.5 && abs(attachment.bounds.width / attachment.bounds.height - 2) < 0.01, "the image fits the note and keeps its aspect ratio")
        check(attachment.fileWrapper?.regularFileContents != nil, "the image carries its data")
    }
    textView.setSelectedRange(NSRange(location: 0, length: 1))
    textView.toggleBold(nil)
    textView.toggleItalic(nil)
    let portable = NoteTextView.strippingDefaultColour(from: NSAttributedString(attributedString: textView.textStorage!))
    let data = portable.rtfd(from: NSRange(location: 0, length: portable.length), documentAttributes: [:])
    check(data != nil && data!.count < 2_000_000, "a note with an image encodes compactly")
    let decoded = data.flatMap { NSAttributedString(rtfd: $0, documentAttributes: nil) }
    check(decoded?.string == "a\u{FFFC}b", "the encoded note decodes with the image placeholder")

    let restored = makeTextView()
    restored.load(decoded ?? NSAttributedString(), zoom: 3)
    spin(0.3)
    let font = restored.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let traits = font?.fontDescriptor.symbolicTraits ?? []
    check(traits.contains(.bold) && traits.contains(.italic) && font?.pointSize == 16, "bold, italic and zoom survive a save and load")
    let restoredImages = attachments(in: restored)
    check(restoredImages.count == 1 && restoredImages[0].bounds.width > 0 && restoredImages[0].bounds.width <= 372.5, "a restored image is sized to fit")
    check(restoredImages.first?.image != nil, "a restored image can be displayed")
    check((restored.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == NoteTextView.defaultColour, "the default text colour is restored")
}
