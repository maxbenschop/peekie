import AppKit

enum CodeHighlighter {
    struct Block {
        let range: NSRange

        let code: NSRange
        let language: String
    }

    static func blocks(in text: NSString) -> [Block] {
        var blocks: [Block] = []
        var openStart: Int?
        var openLanguage = ""
        var codeStart = 0

        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, lineRange, enclosing, _ in
            let line = text.substring(with: lineRange)
            if openStart == nil {
                guard line.hasPrefix("```") else { return }
                openStart = enclosing.location
                openLanguage = line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                codeStart = NSMaxRange(enclosing)
            } else if line.trimmingCharacters(in: .whitespaces) == "```" {
                let code = NSRange(location: codeStart, length: max(0, enclosing.location - codeStart))
                blocks.append(Block(
                    range: NSRange(location: openStart!, length: NSMaxRange(enclosing) - openStart!),
                    code: code, language: openLanguage
                ))
                openStart = nil
            }
        }
        if let openStart {
            let end = text.length
            blocks.append(Block(
                range: NSRange(location: openStart, length: end - openStart),
                code: NSRange(location: min(codeStart, end), length: max(0, end - codeStart)),
                language: openLanguage
            ))
        }
        return blocks
    }

    static func isInsideBlock(_ index: Int, in text: NSString) -> Bool {
        blocks(in: text).contains { block in
            let end = NSMaxRange(block.range)
            let endsWithNewline = end > 0 && end <= text.length && text.character(at: end - 1) == 10
            return index > block.range.location && (index < end || (index == end && !endsWithNewline))
        }
    }

    static func apply(
        to storage: NSTextStorage, previous: [NSRange], codeFont: NSFont, textFont: (NSFont?) -> NSFont
    ) -> [NSRange] {
        let text = storage.string as NSString
        let blocks = blocks(in: text)
        let length = storage.length

        storage.beginEditing()
        for range in previous {
            let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
            guard clamped.length > 0 else { continue }
            storage.removeAttribute(.backgroundColor, range: clamped)
            storage.addAttribute(.foregroundColor, value: NoteTextView.defaultColour, range: clamped)
            storage.enumerateAttribute(.font, in: clamped) { value, run, _ in
                storage.addAttribute(.font, value: textFont(value as? NSFont), range: run)
            }
        }

        for block in blocks where block.range.length > 0 {
            storage.addAttribute(.font, value: codeFont, range: block.range)
            storage.addAttribute(.backgroundColor, value: NSColor.labelColor.withAlphaComponent(0.09), range: block.range)
            storage.addAttribute(.foregroundColor, value: NoteTextView.defaultColour, range: block.range)

            let fenceEnd = block.code.location
            if fenceEnd > block.range.location {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                     range: NSRange(location: block.range.location, length: fenceEnd - block.range.location))
            }
            let closeStart = NSMaxRange(block.code)
            if closeStart < NSMaxRange(block.range) {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                     range: NSRange(location: closeStart, length: NSMaxRange(block.range) - closeStart))
            }

            guard block.code.length > 0 else { continue }
            let code = text.substring(with: block.code)
            for token in Tokenizer(spec: Language.spec(for: block.language)).tokens(in: code) {
                let range = NSRange(location: block.code.location + token.range.location, length: token.range.length)
                storage.addAttribute(.foregroundColor, value: token.kind.color, range: range)
            }
        }
        storage.endEditing()
        return blocks.map(\.range)
    }

    enum TokenKind {
        case keyword, string, comment, number, type, function, key

        var color: NSColor {
            switch self {
            case .keyword: return .systemPink
            case .string: return .systemRed
            case .comment: return .systemGray
            case .number: return .systemPurple
            case .type: return .systemTeal
            case .function: return .systemBlue
            case .key: return .systemBlue
            }
        }
    }

    struct Token {
        let range: NSRange
        let kind: TokenKind
    }

    struct Spec {
        var keywords: Set<String> = []
        var lineComments: [String] = []
        var blockComment: (open: String, close: String)?
        var stringDelimiters: [Character] = ["\"", "'"]
        var caseInsensitive = false
        var highlightTypes = true
        var highlightFunctions = true

        var keysBeforeColon = false
        var isMarkup = false
    }

    enum Language {
        private static let cLike: Set<String> = [
            "if", "else", "for", "while", "do", "return", "class", "struct", "enum", "union", "switch", "case",
            "default", "break", "continue", "static", "const", "final", "void", "int", "long", "short", "double",
            "float", "char", "bool", "boolean", "string", "new", "delete", "null", "nullptr", "true", "false", "this",
            "import", "package", "include", "using", "namespace", "public", "private", "protected", "internal",
            "try", "catch", "throw", "throws", "finally", "extends", "implements", "interface", "abstract", "override",
            "virtual", "typedef", "sizeof", "fun", "val", "var", "when", "in", "is", "as", "object", "sealed",
            "async", "await", "let", "func", "where", "get", "set", "readonly", "unsigned", "signed", "template",
        ]

        static func spec(for name: String) -> Spec {
            switch name {
            case "swift":
                return Spec(keywords: [
                    "let", "var", "func", "class", "struct", "enum", "protocol", "extension", "import", "return", "if",
                    "else", "guard", "switch", "case", "default", "for", "while", "in", "do", "try", "catch", "throw",
                    "throws", "async", "await", "self", "super", "init", "deinit", "static", "private", "public",
                    "internal", "fileprivate", "final", "override", "nil", "true", "false", "where", "as", "is", "some",
                    "any", "break", "continue", "defer", "inout", "typealias", "actor", "mutating", "lazy", "weak",
                ], lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\""])
            case "js", "javascript", "jsx", "ts", "typescript", "tsx", "node":
                return Spec(keywords: [
                    "const", "let", "var", "function", "return", "if", "else", "for", "while", "do", "switch", "case",
                    "break", "continue", "class", "extends", "new", "this", "super", "import", "from", "export",
                    "default", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "null",
                    "undefined", "true", "false", "of", "in", "interface", "type", "enum", "implements", "yield",
                    "delete", "void", "static", "public", "private", "protected", "readonly", "as",
                ], lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'", "`"])
            case "py", "python":
                return Spec(keywords: [
                    "def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or", "is",
                    "import", "from", "as", "with", "try", "except", "finally", "raise", "lambda", "none", "true",
                    "false", "pass", "break", "continue", "yield", "global", "nonlocal", "async", "await", "del", "assert",
                ], lineComments: ["#"], stringDelimiters: ["\"", "'"], caseInsensitive: false)
            case "sh", "bash", "zsh", "shell", "console":
                return Spec(keywords: [
                    "if", "then", "else", "elif", "fi", "for", "do", "done", "while", "case", "esac", "function", "in",
                    "echo", "cd", "export", "local", "return", "exit", "sudo", "source", "alias", "unset", "read",
                ], lineComments: ["#"], stringDelimiters: ["\"", "'"], highlightTypes: false, highlightFunctions: false)
            case "json", "jsonc":
                return Spec(keywords: ["true", "false", "null"], stringDelimiters: ["\""],
                            highlightTypes: false, highlightFunctions: false, keysBeforeColon: true)
            case "html", "xml", "svg":
                return Spec(lineComments: [], blockComment: ("<!--", "-->"), stringDelimiters: ["\"", "'"],
                            highlightTypes: false, highlightFunctions: false, isMarkup: true)
            case "css", "scss":
                return Spec(lineComments: [], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'"],
                            highlightTypes: false, highlightFunctions: false, keysBeforeColon: true)
            case "sql":
                return Spec(keywords: [
                    "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table",
                    "drop", "alter", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "having",
                    "limit", "and", "or", "not", "null", "as", "distinct", "union", "primary", "key", "foreign",
                    "references", "index", "like", "in", "is", "between", "case", "when", "then", "else", "end", "asc", "desc",
                ], lineComments: ["--"], blockComment: ("/*", "*/"), stringDelimiters: ["'", "\""],
                            caseInsensitive: true, highlightTypes: false)
            case "go", "golang":
                return Spec(keywords: [
                    "package", "import", "func", "return", "if", "else", "for", "range", "switch", "case", "default",
                    "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer", "select", "break",
                    "continue", "nil", "true", "false", "fallthrough",
                ], lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "`"])
            case "rust", "rs":
                return Spec(keywords: [
                    "fn", "let", "mut", "pub", "struct", "enum", "impl", "trait", "use", "mod", "match", "if", "else",
                    "for", "while", "loop", "return", "self", "crate", "as", "in", "ref", "move", "async", "await",
                    "unsafe", "const", "static", "true", "false", "where", "type", "dyn",
                ], lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\""])
            case "c", "cpp", "c++", "cc", "h", "hpp", "java", "kotlin", "kt", "cs", "csharp", "dart", "php", "scala":
                return Spec(keywords: cLike, lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'"])
            default:

                return Spec(lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'"],
                            highlightTypes: false, highlightFunctions: false)
            }
        }
    }

    struct Tokenizer {
        let spec: Spec

        func tokens(in code: String) -> [Token] {
            let chars = Array(code.utf16)
            var tokens: [Token] = []
            var i = 0

            func matches(_ s: String, at position: Int) -> Bool {
                let units = Array(s.utf16)
                guard position + units.count <= chars.count else { return false }
                return Array(chars[position..<(position + units.count)]) == units
            }
            func isIdentStart(_ c: unichar) -> Bool {
                c == 95 || c == 36 || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
            }
            func isIdent(_ c: unichar) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) || c == 45 && spec.keysBeforeColon }
            func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }
            func nextNonSpace(from position: Int) -> unichar? {
                var p = position
                while p < chars.count, chars[p] == 32 || chars[p] == 9 { p += 1 }
                return p < chars.count ? chars[p] : nil
            }

            outer: while i < chars.count {
                let c = chars[i]

                if spec.isMarkup, c == 60 , !matches("<!--", at: i) {
                    var j = i + 1
                    var quote: unichar?
                    while j < chars.count {
                        if let q = quote { if chars[j] == q { quote = nil } }
                        else if chars[j] == 34 || chars[j] == 39 { quote = chars[j] }
                        else if chars[j] == 62 { j += 1; break }
                        j += 1
                    }
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .keyword))
                    i = j
                    continue
                }
                for prefix in spec.lineComments where matches(prefix, at: i) {
                    var j = i
                    while j < chars.count, chars[j] != 10 { j += 1 }
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .comment))
                    i = j
                    continue outer
                }
                if let block = spec.blockComment, matches(block.open, at: i) {
                    var j = i + block.open.utf16.count
                    while j < chars.count, !matches(block.close, at: j) { j += 1 }
                    j = min(chars.count, j + block.close.utf16.count)
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .comment))
                    i = j
                    continue
                }
                if let delimiter = spec.stringDelimiters.first(where: { String($0).utf16.first == c }) {
                    let quote = String(delimiter).utf16.first!
                    var j = i + 1
                    while j < chars.count, chars[j] != quote {
                        if chars[j] == 92, j + 1 < chars.count { j += 1 }
                        if chars[j] == 10, quote != 96 { break }
                        j += 1
                    }
                    let end = min(chars.count, j < chars.count && chars[j] == quote ? j + 1 : j)
                    let isKey = spec.keysBeforeColon && nextNonSpace(from: end) == 58
                    tokens.append(Token(range: NSRange(location: i, length: end - i), kind: isKey ? .key : .string))
                    i = end
                    continue
                }
                if isDigit(c) || (c == 46 && i + 1 < chars.count && isDigit(chars[i + 1])) {
                    var j = i + 1
                    while j < chars.count, isDigit(chars[j]) || chars[j] == 46 || chars[j] == 95
                            || (chars[j] >= 97 && chars[j] <= 102) || (chars[j] >= 65 && chars[j] <= 70)
                            || chars[j] == 120 || chars[j] == 88 { j += 1 }
                    tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .number))
                    i = j
                    continue
                }
                if isIdentStart(c) {
                    var j = i + 1
                    while j < chars.count, isIdent(chars[j]) { j += 1 }
                    let word = String(utf16CodeUnits: Array(chars[i..<j]), count: j - i)
                    let lookup = spec.caseInsensitive ? word.lowercased() : word
                    let range = NSRange(location: i, length: j - i)
                    if spec.keywords.contains(lookup) {
                        tokens.append(Token(range: range, kind: .keyword))
                    } else if spec.keysBeforeColon, nextNonSpace(from: j) == 58 {
                        tokens.append(Token(range: range, kind: .key))
                    } else if spec.highlightTypes, let first = word.unicodeScalars.first,
                              CharacterSet.uppercaseLetters.contains(first), word.count > 1 {
                        tokens.append(Token(range: range, kind: .type))
                    } else if spec.highlightFunctions, j < chars.count, chars[j] == 40 {
                        tokens.append(Token(range: range, kind: .function))
                    }
                    i = j
                    continue
                }
                i += 1
            }
            return tokens
        }
    }
}
