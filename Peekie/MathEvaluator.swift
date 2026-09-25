import Foundation

enum MathEvaluator {
    static func result(forLineEndingIn line: String) -> String? {
        guard let expression = trailingExpression(in: line), let value = evaluate(expression) else { return nil }
        return format(value)
    }

    private static let allowed = Set("0123456789.+-*/×÷^() ")

    private static func trailingExpression(in line: String) -> String? {
        var chars = Array(line)

        while chars.last == " " { chars.removeLast() }
        guard !chars.isEmpty else { return nil }

        var start = chars.count
        while start > 0 {
            let c = chars[start - 1]
            if allowed.contains(c) {
                start -= 1
            } else if c.isLetter, let word = sqrtWord(endingAt: start, in: chars) {
                start -= word
            } else {
                break
            }
        }
        var expression = String(chars[start...]).trimmingCharacters(in: .whitespaces)

        while let first = expression.first, "+*/×÷^)".contains(first) || (first == "-" && start > 0) {
            expression.removeFirst()
            expression = expression.trimmingCharacters(in: .whitespaces)
        }
        return expression.isEmpty ? nil : expression
    }

    private static func sqrtWord(endingAt end: Int, in chars: [Character]) -> Int? {
        guard end >= 4, String(chars[(end - 4)..<end]).lowercased() == "sqrt" else { return nil }
        return 4
    }

    static func evaluate(_ text: String) -> Double? {
        var parser = Parser(text)
        guard let value = parser.parseExpression(), parser.atEnd, parser.sawOperator else { return nil }
        return value.isFinite ? value : nil
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(format: "%.10g", value)
        if text.contains("."), !text.contains("e") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    private struct Parser {
        private let chars: [Character]
        private var index = 0

        private(set) var sawOperator = false

        init(_ text: String) {
            chars = Array(text.replacingOccurrences(of: " ", with: ""))
        }

        var atEnd: Bool { index >= chars.count }

        private var peek: Character? { index < chars.count ? chars[index] : nil }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek, op == "+" || op == "-" {
                index += 1
                sawOperator = true
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parsePower() else { return nil }
            while let op = peek, "*/×÷".contains(op) {
                index += 1
                sawOperator = true
                guard let rhs = parsePower() else { return nil }
                if op == "/" || op == "÷" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        private mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            if peek == "^" {
                index += 1
                sawOperator = true
                guard let exponent = parsePower() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        private mutating func parseUnary() -> Double? {
            if peek == "-" {
                index += 1
                return parseUnary().map { -$0 }
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> Double? {
            guard let c = peek else { return nil }
            if c == "(" {
                index += 1
                guard let value = parseExpression(), peek == ")" else { return nil }
                index += 1
                return value
            }
            if c.isLetter {
                let rest = String(chars[index...]).lowercased()
                guard rest.hasPrefix("sqrt("), rest.count >= 6 else { return nil }
                index += 5
                sawOperator = true
                guard let value = parseExpression(), peek == ")", value >= 0 else { return nil }
                index += 1
                return value.squareRoot()
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Double? {
            let start = index
            var dots = 0
            while let c = peek, c.isNumber || c == "." {
                if c == "." { dots += 1 }
                index += 1
            }
            guard index > start, dots <= 1 else { return nil }
            return Double(String(chars[start..<index]))
        }
    }
}
