import Foundation

/// Any JSON value. The rooms' views grow over time (the server only adds fields), so the app decodes what it knows
/// from this and ignores the rest.
public enum JSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public subscript(key: String) -> JSON { if case let .object(o) = self { return o[key] ?? .null }; return .null }
    public subscript(index: Int) -> JSON {
        if case let .array(a) = self, a.indices.contains(index) { return a[index] }; return .null
    }
    public var string: String? { if case let .string(s) = self { return s }; return nil }
    public var double: Double? { if case let .number(n) = self { return n }; return nil }
    public var int: Int? { if case let .number(n) = self, n.rounded() == n, abs(n) < 1e15 { return Int(n) }; return nil }
    public var bool: Bool? { if case let .bool(b) = self { return b }; return nil }
    public var array: [JSON] { if case let .array(a) = self { return a }; return [] }
    public var object: [String: JSON]? { if case let .object(o) = self { return o }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }
    /// True for JSON's truthy values the rooms use as flags (true, a non-zero number, a non-empty string).
    public var truthy: Bool {
        switch self {
        case .null: return false
        case let .bool(b): return b
        case let .number(n): return n != 0
        case let .string(s): return !s.isEmpty
        default: return true
        }
    }

    public static func parse(_ text: String) -> JSON? { parse(Data(text.utf8)) }
    public static func parse(_ data: Data) -> JSON? { try? JSONDecoder().decode(JSON.self, from: data) }

    /// Compact JSON text, keys sorted (stable for tests).
    public var text: String {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? enc.encode(self)) ?? Data("null".utf8), as: UTF8.self)
    }
}

extension JSON: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n):
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral, ExpressibleByFloatLiteral {
    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .number(Double(v)) }
    public init(floatLiteral v: Double) { self = .number(v) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(arrayLiteral v: JSON...) { self = .array(v) }
    public init(dictionaryLiteral v: (String, JSON)...) { self = .object(Dictionary(v, uniquingKeysWith: { $1 })) }
    public init(nilLiteral: ()) { self = .null }
}
