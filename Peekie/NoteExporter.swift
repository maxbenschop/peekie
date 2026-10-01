import AppKit
import UniformTypeIdentifiers

enum NoteExportFormat: CaseIterable {
    case text, markdown, rtf, rtfd

    var title: String {
        switch self {
        case .text: return "Plain Text (.txt)"
        case .markdown: return "Markdown (.md)"
        case .rtf: return "Rich Text (.rtf)"
        case .rtfd: return "Rich Text with Images (.rtfd)"
        }
    }

    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .markdown: return "md"
        case .rtf: return "rtf"
        case .rtfd: return "rtfd"
        }
    }

    var contentType: UTType {
        switch self {
        case .text: return .plainText
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .rtf: return .rtf
        case .rtfd: return .rtfd
        }
    }
}

enum NoteExporter {
    static func write(_ note: NSAttributedString, to url: URL, as format: NoteExportFormat) throws {
        switch format {
        case .text:
            try plainText(note).write(to: url, atomically: true, encoding: .utf8)
        case .markdown:
            try markdown(note).write(to: url, atomically: true, encoding: .utf8)
        case .rtf, .rtfd:
            let portable = ChecklistBox.preparedForEncoding(NoteTextView.strippingDefaultColour(from: note))
            let range = NSRange(location: 0, length: portable.length)
            let type: NSAttributedString.DocumentType = format == .rtf ? .rtf : .rtfd
            let wrapper = try portable.fileWrapper(from: range, documentAttributes: [.documentType: type])
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        }
    }

    static func plainText(_ note: NSAttributedString) -> String {
        var result = ""
        let ns = note.string as NSString
        note.enumerateAttribute(.attachment, in: NSRange(location: 0, length: note.length)) { value, range, _ in
            if let attachment = value as? NSTextAttachment {
                if let checked = ChecklistBox.checkedState(of: attachment) {
                    result += checked ? "☑" : "☐"
                }
            } else {
                result += ns.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            }
        }
        return result
    }

    private static let listMarkers: [(marker: String, markdown: String)] = [
        ("• ", "- "),
    ]

    static func markdown(_ note: NSAttributedString) -> String {
        let text = note.string as NSString
        let codeRanges = CodeHighlighter.blocks(in: text).map(\.range)
        var output = ""

        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, lineRange, enclosing, _ in
            var content = lineRange
            var prefix = ""
            let insideCode = codeRanges.contains { NSLocationInRange(lineRange.location, $0) }

            if !insideCode {
                let line = text.substring(with: lineRange)
                if let match = listMarkers.first(where: { line.hasPrefix($0.marker) }) {
                    prefix = match.markdown
                    content = NSRange(location: lineRange.location + (match.marker as NSString).length,
                                      length: lineRange.length - (match.marker as NSString).length)
                } else if lineRange.length >= 2,
                          let attachment = note.attribute(.attachment, at: lineRange.location, effectiveRange: nil) as? NSTextAttachment,
                          let checked = ChecklistBox.checkedState(of: attachment) {
                    prefix = checked ? "- [x] " : "- [ ] "
                    content = NSRange(location: lineRange.location + 2, length: lineRange.length - 2)
                }
            }
            output += prefix + (insideCode ? text.substring(with: content) : inline(note, range: content))

            output += text.substring(with: NSRange(location: NSMaxRange(lineRange), length: NSMaxRange(enclosing) - NSMaxRange(lineRange)))
        }
        return output.replacingOccurrences(of: "\u{FFFC}", with: "![image]")
    }

    private static func inline(_ note: NSAttributedString, range: NSRange) -> String {
        var result = ""
        note.enumerateAttributes(in: range) { attributes, run, _ in
            let text = (note.string as NSString).substring(with: run)
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            var markers = ""
            if traits.contains(.bold) { markers += "**" }
            if traits.contains(.italic) { markers += "*" }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { markers = "~~" + markers }
            let link = (attributes[.link] as? URL)?.absoluteString ?? (attributes[.link] as? String)

            let leading = text.prefix { $0 == " " || $0 == "\t" }
            let trailing = text.dropFirst(leading.count).reversed().prefix { $0 == " " || $0 == "\t" }
            var core = String(text.dropFirst(leading.count).dropLast(trailing.count))
            if !core.isEmpty {
                if let link { core = "[\(core)](\(link))" }
                if !markers.isEmpty { core = markers + core + String(markers.reversed()) }
            }
            result += leading + core + String(trailing.reversed())
        }
        return result
    }
}
