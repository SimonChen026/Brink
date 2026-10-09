import Foundation

/// A tiny expression language used everywhere in scenario JSON.
///
/// Grammar (lowest to highest precedence):
///   expr    := or
///   or      := and ( '||' and )*
///   and     := cmp ( '&&' cmp )*
///   cmp     := sum ( ('<'|'<='|'>'|'>='|'=='|'!=') sum )?
///   sum     := term ( ('+'|'-') term )*
///   term    := unary ( ('*'|'/'|'%') unary )*
///   unary   := ('-'|'!') unary | primary
///   primary := number | identifier | identifier '(' args ')' | '(' expr ')'
///
/// Identifiers may contain letters, digits, '_' and '.', e.g. `res.food`, `var.signal`,
/// `weather.blizzard`, `actor.skill.survival`. Booleans are numbers (0 = false).
public indirect enum ExprNode: Sendable {
    case number(Double)
    case ident(String)
    case call(String, [ExprNode])
    case unary(String, ExprNode)
    case binary(String, ExprNode, ExprNode)
}

public struct ExprError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public var description: String { message }
}

public enum Expr {
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: ExprNode] = [:]

    public static let functions: Set<String> = [
        "min", "max", "clamp", "abs", "floor", "ceil", "round", "sqrt", "pow", "rand", "randRange", "if", "exp", "log"
    ]

    /// Parse (with caching).
    public static func parse(_ source: String) throws -> ExprNode {
        cacheLock.lock()
        if let hit = cache[source] { cacheLock.unlock(); return hit }
        cacheLock.unlock()
        var parser = ExprParser(source)
        let node = try parser.parseAll()
        cacheLock.lock()
        cache[source] = node
        cacheLock.unlock()
        return node
    }

    /// Collect all identifiers referenced by an expression (for validation).
    public static func identifiers(in node: ExprNode) -> [String] {
        switch node {
        case .number: return []
        case .ident(let s): return [s]
        case .call(_, let args): return args.flatMap { identifiers(in: $0) }
        case .unary(_, let a): return identifiers(in: a)
        case .binary(_, let a, let b): return identifiers(in: a) + identifiers(in: b)
        }
    }

    public static func functionsUsed(in node: ExprNode) -> [String] {
        switch node {
        case .number, .ident: return []
        case .call(let name, let args): return [name] + args.flatMap { functionsUsed(in: $0) }
        case .unary(_, let a): return functionsUsed(in: a)
        case .binary(_, let a, let b): return functionsUsed(in: a) + functionsUsed(in: b)
        }
    }

    public static func evaluate(_ node: ExprNode, resolve: (String) -> Double?, random: () -> Double) -> Double {
        switch node {
        case .number(let v):
            return v
        case .ident(let name):
            if name == "true" { return 1 }
            if name == "false" { return 0 }
            return resolve(name) ?? 0
        case .unary(let op, let a):
            let v = evaluate(a, resolve: resolve, random: random)
            switch op {
            case "-": return -v
            case "!": return v == 0 ? 1 : 0
            default: return v
            }
        case .binary(let op, let a, let b):
            // short-circuit logic
            if op == "&&" {
                let l = evaluate(a, resolve: resolve, random: random)
                if l == 0 { return 0 }
                return evaluate(b, resolve: resolve, random: random) != 0 ? 1 : 0
            }
            if op == "||" {
                let l = evaluate(a, resolve: resolve, random: random)
                if l != 0 { return 1 }
                return evaluate(b, resolve: resolve, random: random) != 0 ? 1 : 0
            }
            let l = evaluate(a, resolve: resolve, random: random)
            let r = evaluate(b, resolve: resolve, random: random)
            switch op {
            case "+": return l + r
            case "-": return l - r
            case "*": return l * r
            case "/": return r == 0 ? 0 : l / r
            case "%": return r == 0 ? 0 : l.truncatingRemainder(dividingBy: r)
            case "<": return l < r ? 1 : 0
            case "<=": return l <= r ? 1 : 0
            case ">": return l > r ? 1 : 0
            case ">=": return l >= r ? 1 : 0
            case "==": return abs(l - r) < 1e-9 ? 1 : 0
            case "!=": return abs(l - r) >= 1e-9 ? 1 : 0
            default: return 0
            }
        case .call(let name, let args):
            let v = args.map { evaluate($0, resolve: resolve, random: random) }
            func arg(_ i: Int) -> Double { i < v.count ? v[i] : 0 }
            switch name {
            case "min": return v.min() ?? 0
            case "max": return v.max() ?? 0
            case "clamp": return Swift.min(Swift.max(arg(0), arg(1)), arg(2))
            case "abs": return Swift.abs(arg(0))
            case "floor": return Foundation.floor(arg(0))
            case "ceil": return Foundation.ceil(arg(0))
            case "round": return Foundation.round(arg(0))
            case "sqrt": return Foundation.sqrt(Swift.max(0, arg(0)))
            case "pow": return Foundation.pow(arg(0), arg(1))
            case "exp": return Foundation.exp(arg(0))
            case "log": return arg(0) > 0 ? Foundation.log(arg(0)) : 0
            case "rand": return random()
            case "randRange": return arg(0) + (arg(1) - arg(0)) * random()
            case "if": return arg(0) != 0 ? arg(1) : arg(2)
            default: return 0
            }
        }
    }
}

private struct ExprParser {
    enum Token: Equatable {
        case number(Double)
        case ident(String)
        case op(String)
        case lparen, rparen, comma
        case end
    }

    let source: String
    var tokens: [Token] = []
    var pos = 0

    init(_ source: String) { self.source = source }

    mutating func parseAll() throws -> ExprNode {
        tokens = try tokenize(source)
        pos = 0
        let node = try parseOr()
        guard tokens[pos] == .end else {
            throw ExprError(message: "表达式多余内容: \(source)")
        }
        return node
    }

    private func tokenize(_ s: String) throws -> [Token] {
        var out: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." { j += 1 }
                // exponent
                if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                    var k = j + 1
                    if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                    if k < chars.count, chars[k].isNumber {
                        j = k
                        while j < chars.count, chars[j].isNumber { j += 1 }
                    }
                }
                guard let v = Double(String(chars[i..<j])) else {
                    throw ExprError(message: "无法解析数字: \(String(chars[i..<j])) in \(s)")
                }
                out.append(.number(v))
                i = j
                continue
            }
            if c.isLetter || c == "_" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "." { j += 1 }
                out.append(.ident(String(chars[i..<j])))
                i = j
                continue
            }
            if c == "(" { out.append(.lparen); i += 1; continue }
            if c == ")" { out.append(.rparen); i += 1; continue }
            if c == "," { out.append(.comma); i += 1; continue }
            let two = i + 1 < chars.count ? String(chars[i...i + 1]) : ""
            if ["<=", ">=", "==", "!=", "&&", "||"].contains(two) {
                out.append(.op(two)); i += 2; continue
            }
            if "+-*/%<>!".contains(c) {
                out.append(.op(String(c))); i += 1; continue
            }
            throw ExprError(message: "表达式含非法字符 '\(c)': \(s)")
        }
        out.append(.end)
        return out
    }

    private var current: Token { tokens[pos] }

    private mutating func parseOr() throws -> ExprNode {
        var left = try parseAnd()
        while current == .op("||") {
            pos += 1
            left = .binary("||", left, try parseAnd())
        }
        return left
    }

    private mutating func parseAnd() throws -> ExprNode {
        var left = try parseCmp()
        while current == .op("&&") {
            pos += 1
            left = .binary("&&", left, try parseCmp())
        }
        return left
    }

    private mutating func parseCmp() throws -> ExprNode {
        let left = try parseSum()
        if case .op(let o) = current, ["<", "<=", ">", ">=", "==", "!="].contains(o) {
            pos += 1
            return .binary(o, left, try parseSum())
        }
        return left
    }

    private mutating func parseSum() throws -> ExprNode {
        var left = try parseTerm()
        while case .op(let o) = current, o == "+" || o == "-" {
            pos += 1
            left = .binary(o, left, try parseTerm())
        }
        return left
    }

    private mutating func parseTerm() throws -> ExprNode {
        var left = try parseUnary()
        while case .op(let o) = current, o == "*" || o == "/" || o == "%" {
            pos += 1
            left = .binary(o, left, try parseUnary())
        }
        return left
    }

    private mutating func parseUnary() throws -> ExprNode {
        if case .op(let o) = current, o == "-" || o == "!" {
            pos += 1
            return .unary(o, try parseUnary())
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> ExprNode {
        switch current {
        case .number(let v):
            pos += 1
            return .number(v)
        case .ident(let name):
            pos += 1
            if current == .lparen {
                pos += 1
                var args: [ExprNode] = []
                if current != .rparen {
                    args.append(try parseOr())
                    while current == .comma {
                        pos += 1
                        args.append(try parseOr())
                    }
                }
                guard current == .rparen else { throw ExprError(message: "缺少 ')' : \(source)") }
                pos += 1
                guard Expr.functions.contains(name) else {
                    throw ExprError(message: "未知函数 \(name)() : \(source)")
                }
                return .call(name, args)
            }
            return .ident(name)
        case .lparen:
            pos += 1
            let inner = try parseOr()
            guard current == .rparen else { throw ExprError(message: "缺少 ')' : \(source)") }
            pos += 1
            return inner
        default:
            throw ExprError(message: "表达式语法错误: \(source)")
        }
    }
}
