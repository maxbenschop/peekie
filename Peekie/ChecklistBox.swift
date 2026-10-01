import AppKit

/// Renders and identifies the checklist boxes used in notes as `NSTextAttachment`s: an
/// almost-square box with a small rounded corner, filled with the user's macOS accent
/// colour when checked (matching how the rest of the app — e.g. the pin button in
/// `NoteWindow` — already uses `.controlAccentColor` rather than a hardcoded colour).
///
/// `NSTextAttachment.image` and `.fileWrapper` are mutually exclusive in practice: setting
/// either one clears the other. Live, in-memory attachments need `.image` set. But
/// `.fileWrapper` with a recognisable filename is the only thing that survives an RTFD
/// round-trip, and is needed to tell a checklist box apart from a pasted image after a
/// save/reload. So the two concerns are split: `checked`/`unchecked` is tagged on the live
/// image itself (via `accessibilityDescription`, which needs no serialisation) for
/// in-session use, and `preparedForEncoding` produces a save-time-only clone with
/// `.fileWrapper` set, so the embedded file is named — without ever touching the live
/// attachment's `.image`.
enum ChecklistBox {
    private static let uncheckedFilename = "peekie-checkbox-unchecked.png"
    private static let checkedFilename = "peekie-checkbox-checked.png"
    // Doubles as the live attachment's `accessibilityDescription`, so these are read
    // aloud by VoiceOver — they must stay human-readable, not internal identifiers.
    private static let uncheckedMarker = "Unchecked to-do item"
    private static let checkedMarker = "Checked to-do item"

    // Dynamic/semantic, like every other colour in this app (`.labelColor`,
    // `.controlAccentColor`, etc.), so the border adapts with Appearance mode instead
    // of staying a fixed grey that's wrong in one of light/dark.
    private static let borderColour = NSColor.secondaryLabelColor

    /// Builds a fresh, live attachment for inserting a new checklist item.
    static func attachment(checked: Bool, font: NSFont) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        apply(checked: checked, font: font, to: attachment)
        return attachment
    }

    /// True when this attachment is one of our checklist boxes (as opposed to a pasted image).
    static func checkedState(of attachment: NSTextAttachment) -> Bool? {
        switch attachment.image?.accessibilityDescription {
        case checkedMarker: return true
        case uncheckedMarker: return false
        default: break
        }
        switch attachment.fileWrapper?.preferredFilename {
        case checkedFilename: return true
        case uncheckedFilename: return false
        default: return nil
        }
    }

    /// Mutates an existing attachment in place to reflect the given checked state,
    /// refreshing its rendered image — live rendering always goes through `.image`.
    ///
    /// Without an explicit `bounds`, `NSTextAttachment` centers the image on the full
    /// line (ascent + descent) rather than on the text baseline, which visibly droops
    /// the box below the label, so its bottom edge is pinned explicitly to the baseline.
    static func apply(checked: Bool, font: NSFont, to attachment: NSTextAttachment) {
        let side = size(for: font)
        let image = render(checked: checked, side: side)
        image.accessibilityDescription = checked ? checkedMarker : uncheckedMarker
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: 0, width: side, height: side)
    }

    /// Returns a copy of `content` where every checklist attachment is replaced with a
    /// fileWrapper-only clone carrying a recognisable filename, so RTF/RTFD encoding embeds
    /// it identifiably instead of a generic auto-named file. Only this copy's attachments
    /// are touched — the live attachments (and their `.image`-based rendering) are untouched.
    static func preparedForEncoding(_ content: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: content)
        mutable.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let checked = checkedState(of: attachment),
                  let png = pngData(for: render(checked: checked, side: attachment.bounds.width))
            else { return }
            let clone = NSTextAttachment()
            clone.fileWrapper = FileWrapper(regularFileWithContents: png)
            clone.fileWrapper?.preferredFilename = checked ? checkedFilename : uncheckedFilename
            clone.bounds = attachment.bounds
            mutable.removeAttribute(.attachment, range: range)
            mutable.addAttribute(.attachment, value: clone, range: range)
        }
        return mutable
    }

    /// Sized to exactly match the font's cap height (1:1) — pixel-measured against a
    /// reference macOS checklist box (Notes-style), where the unchecked box and a
    /// capital letter in the label shared the identical top and bottom row. A prior
    /// version scaled this to 1.2x "to read a bit larger," which (combined with a
    /// too-thin stroke) was the "looks weird" complaint that led back to this ratio.
    private static func size(for font: NSFont) -> CGFloat {
        max(10, round(font.capHeight))
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // Draws synchronously via lockFocus/unlockFocus (rather than the lazy, closure-based
    // NSImage(size:flipped:drawingHandler:) API) so the image has a concrete cached
    // representation immediately.
    private static func render(checked: Bool, side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        defer { image.unlockFocus() }
        draw(checked: checked, side: side, in: NSRect(x: 0, y: 0, width: side, height: side))
        return image
    }

    /// Almost square, with just a small rounded corner. Stroke width (0.136) and corner
    /// radius (0.16) ratios are pixel-measured from a reference macOS checklist box
    /// (Notes-style), not eyeballed — see conversation history for the measurement.
    private static func draw(checked: Bool, side: CGFloat, in rect: NSRect) {
        let strokeWidth = max(1.2, side * 0.136)
        let cornerRadius = side * 0.16

        if checked {
            // Filled, so the path itself should span the full glyph canvas (`rect`) —
            // insetting it like the stroke below would pull the fill's edges inward by
            // strokeWidth/2 on every side, most visibly leaving a growing (with font
            // size) gap between the box's bottom and the text baseline it's pinned to.
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.controlAccentColor.setFill()
            path.fill()
            drawCheckmark(in: rect, strokeWidth: strokeWidth)
        } else {
            // Stroked, so inset by half the line width first — a centered stroke of
            // that width then lands exactly on `rect`'s edges, matching the filled
            // box's outer bounds above.
            let square = rect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
            let path = NSBezierPath(roundedRect: square, xRadius: cornerRadius, yRadius: cornerRadius)
            path.lineWidth = strokeWidth
            borderColour.setStroke()
            path.stroke()
        }
    }

    private static func drawCheckmark(in square: NSRect, strokeWidth: CGFloat) {
        let check = NSBezierPath()
        check.lineWidth = strokeWidth
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        // lockFocus draws y-up (origin bottom-left), so the points below trace the
        // checkmark from its left tip, down to the bottom vertex, up to the right tip.
        check.move(to: NSPoint(x: square.minX + square.width * 0.23, y: square.minY + square.height * 0.52))
        check.line(to: NSPoint(x: square.minX + square.width * 0.43, y: square.minY + square.height * 0.30))
        check.line(to: NSPoint(x: square.minX + square.width * 0.79, y: square.minY + square.height * 0.68))
        NSColor.white.setStroke()
        check.stroke()
    }
}
