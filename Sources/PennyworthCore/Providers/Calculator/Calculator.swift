import Foundation

/// Evaluates arithmetic like `2^10`, `(3 + 4) * 2`, `sqrt(2)/2` or `0xff + 1`.
///
/// Supports `+ - * / % ^ !` (also `×`, `÷`, `−`, `**`), parentheses, implicit
/// multiplication (`2(3+4)`, `2pi`), the constants `pi`/`π`, `tau` and `e`, and
/// common functions (`sqrt`, `cbrt`, `abs`, `round`, `floor`, `ceil`, `exp`, `ln`, `log`,
/// `log2`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `min`, `max`). Numbers may be
/// decimal, scientific (`1.5e3`), hexadecimal (`0x1f`) or binary (`0b101`).
public enum Calculator {
    public struct Evaluation: Sendable, Equatable {
        public let value: Double
        /// Operators and function calls applied. Zero means the input was a lone number
        /// or constant, which isn't worth showing as a calculation.
        public let operationCount: Int
    }

    public enum Failure: Error, Equatable {
        case syntax
        case unknownName(String)
        /// Division by zero, factorial of a fraction, and other undefined results.
        case undefined
    }

    public static func evaluate(_ text: String) throws(Failure) -> Evaluation {
        var parser = Parser(tokens: try tokenize(text))
        let value = try parser.parseExpression()
        guard parser.isAtEnd else { throw .syntax }
        guard value.isFinite else { throw .undefined }
        return Evaluation(value: value == 0 ? 0 : value, operationCount: parser.operations)
    }

    enum Token: Equatable {
        case number(Double)
        case name(String)
        case symbol(Character)
    }

    static func tokenize(_ text: String) throws(Failure) -> [Token] {
        let aliases: [Character: Character] = ["×": "*", "·": "*", "÷": "/", "−": "-"]
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0

        func scan(while predicate: (Character) -> Bool) -> String {
            let start = index
            while index < characters.count, predicate(characters[index]) { index += 1 }
            return String(characters[start..<index])
        }

        while index < characters.count {
            let character = aliases[characters[index]] ?? characters[index]
            if character.isWhitespace {
                index += 1
            } else if character == "0", index + 1 < characters.count,
                      let radix = ["x": 16, "X": 16, "b": 2, "B": 2][characters[index + 1]] {
                index += 2
                let digits = scan { $0.isHexDigit }
                guard let value = UInt64(digits, radix: radix) else { throw .syntax }
                tokens.append(.number(Double(value)))
            } else if character.isNumber || character == "." {
                var literal = scan { $0.isNumber || $0 == "." }
                // An exponent only if digits follow, so `2e` stays 2 × e.
                if index < characters.count, "eE".contains(characters[index]) {
                    var lookahead = index + 1
                    if lookahead < characters.count, "+-".contains(characters[lookahead]) { lookahead += 1 }
                    if lookahead < characters.count, characters[lookahead].isNumber {
                        literal += String(characters[index..<lookahead])
                        index = lookahead
                        literal += scan { $0.isNumber }
                    }
                }
                guard let value = Double(literal) else { throw .syntax }
                tokens.append(.number(value))
            } else if character.isLetter || character == "π" {
                tokens.append(.name(scan { $0.isLetter || $0.isNumber || $0 == "π" }.lowercased()))
            } else if character == "*", index + 1 < characters.count, characters[index + 1] == "*" {
                tokens.append(.symbol("^"))
                index += 2
            } else if "+-*/%^!(),".contains(character) {
                tokens.append(.symbol(character))
                index += 1
            } else {
                throw .syntax
            }
        }
        return tokens
    }

    private static let constants: [String: Double] = ["pi": .pi, "π": .pi, "tau": 2 * .pi, "e": M_E]

    private static let functions: [String: @Sendable ([Double]) -> Double?] = [
        "sqrt": unary(sqrt), "cbrt": unary(cbrt), "abs": unary(abs), "exp": unary(exp),
        "ln": unary(log), "log": unary(log10), "log2": unary(log2),
        "round": unary { $0.rounded() }, "floor": unary(floor), "ceil": unary(ceil),
        "sin": unary(sin), "cos": unary(cos), "tan": unary(tan),
        "asin": unary(asin), "acos": unary(acos), "atan": unary(atan),
        "min": { $0.isEmpty ? nil : $0.min() }, "max": { $0.isEmpty ? nil : $0.max() },
    ]

    private static func unary(
        _ function: @escaping @Sendable (Double) -> Double
    ) -> @Sendable ([Double]) -> Double? {
        { $0.count == 1 ? function($0[0]) : nil }
    }

    /// Recursive descent, lowest precedence first: `+ -`, then `* / %` (and implicit
    /// multiplication), then unary signs, then right-associative `^`, then postfix `!`.
    private struct Parser {
        let tokens: [Token]
        var position = 0
        var operations = 0

        var isAtEnd: Bool { position == tokens.count }

        private var peek: Token? { position < tokens.count ? tokens[position] : nil }

        private mutating func take(_ symbols: String) -> Character? {
            guard case .symbol(let symbol)? = peek, symbols.contains(symbol) else { return nil }
            position += 1
            return symbol
        }

        mutating func parseExpression() throws(Failure) -> Double {
            var value = try parseTerm()
            while let symbol = take("+-") {
                let rhs = try parseTerm()
                value = symbol == "+" ? value + rhs : value - rhs
                operations += 1
            }
            return value
        }

        private mutating func parseTerm() throws(Failure) -> Double {
            var value = try parseSigned()
            while true {
                if let symbol = take("*/%") {
                    let rhs = try parseSigned()
                    switch symbol {
                    case "*": value *= rhs
                    case "/": value /= rhs
                    default: value = fmod(value, rhs)
                    }
                } else if case .name? = peek {
                    value *= try parseSigned()
                } else if case .symbol("(")? = peek {
                    value *= try parseSigned()
                } else {
                    return value
                }
                operations += 1
            }
        }

        private mutating func parseSigned() throws(Failure) -> Double {
            if let symbol = take("+-") {
                let value = try parseSigned()
                return symbol == "-" ? -value : value
            }
            return try parsePower()
        }

        private mutating func parsePower() throws(Failure) -> Double {
            let base = try parseFactorial()
            guard take("^") != nil else { return base }
            // Right-associative, and the exponent may carry a sign: 2^-1.
            let exponent = try parseSigned()
            operations += 1
            return pow(base, exponent)
        }

        private mutating func parseFactorial() throws(Failure) -> Double {
            var value = try parsePrimary()
            while take("!") != nil {
                guard value >= 0, value <= 170, value == value.rounded() else { throw .undefined }
                value = value < 2 ? 1 : (2...Int(value)).reduce(1.0) { $0 * Double($1) }
                operations += 1
            }
            return value
        }

        private mutating func parsePrimary() throws(Failure) -> Double {
            guard let token = peek else { throw .syntax }
            position += 1
            switch token {
            case .number(let value):
                return value
            case .symbol("("):
                let value = try parseExpression()
                guard take(")") != nil else { throw .syntax }
                return value
            case .name(let name):
                if take("(") != nil {
                    guard let function = Calculator.functions[name] else { throw .unknownName(name) }
                    var arguments: [Double] = []
                    if take(")") == nil {
                        repeat { arguments.append(try parseExpression()) } while take(",") != nil
                        guard take(")") != nil else { throw .syntax }
                    }
                    guard let value = function(arguments) else { throw .syntax }
                    operations += 1
                    return value
                }
                guard let constant = Calculator.constants[name] else { throw .unknownName(name) }
                return constant
            case .symbol:
                throw .syntax
            }
        }
    }
}
