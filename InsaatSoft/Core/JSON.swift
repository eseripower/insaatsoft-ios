import Foundation

/// Sunucunun gevşek yapılı JSON yanıtları için dinamik değer.
/// İnşaatSoft API'si aynı alanda bazen sayı bazen metin döndürür (ör. "deger"), bu yüzden
/// sabit Codable modeller yerine bu tip kullanılır ve okurken dönüştürülür.
enum JSON: Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    // MARK: Ayrıştırma

    static func parse(_ data: Data) -> JSON? {
        guard !data.isEmpty, let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return JSON(any: any)
    }

    init(any: Any?) {
        switch any {
        case nil, is NSNull:
            self = .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String:
            self = .string(s)
        case let a as [Any]:
            self = .array(a.map { JSON(any: $0) })
        case let d as [String: Any]:
            var o: [String: JSON] = [:]
            for (k, v) in d { o[k] = JSON(any: v) }
            self = .object(o)
        default:
            self = .null
        }
    }

    // MARK: Erişim

    subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSON {
        if case .array(let a) = self, index >= 0, index < a.count { return a[index] }
        return .null
    }

    var isNull: Bool { if case .null = self { return true }; return false }

    /// Varsa metin karşılığı (sayılar tam ise ondalıksız yazılır)
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { return String(Int64(n)) }
            return String(n)
        case .bool(let b): return b ? "1" : "0"
        default: return nil
        }
    }

    /// Metin; yoksa boş metin
    var string: String { stringValue ?? "" }

    var int: Int {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces)) ?? Int(Double(s) ?? 0)
        case .bool(let b): return b ? 1 : 0
        default: return 0
        }
    }

    var double: Double {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
        case .bool(let b): return b ? 1 : 0
        default: return 0
        }
    }

    var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return !s.isEmpty && s != "0" && s.lowercased() != "false"
        default: return false
        }
    }

    var array: [JSON] { if case .array(let a) = self { return a }; return [] }
    var object: [String: JSON] { if case .object(let o) = self { return o }; return [:] }
    var isObject: Bool { if case .object = self { return true }; return false }
    var isArray: Bool { if case .array = self { return true }; return false }

    /// Metin dizisi (dizi değilse ve boş değilse tek elemanlı; virgüllü metinler bölünmez)
    var stringArray: [String] {
        switch self {
        case .array(let a): return a.compactMap { $0.stringValue }
        case .null: return []
        default:
            let s = string
            return s.isEmpty ? [] : [s]
        }
    }

    /// Anahtar varsa ve boş değilse metni
    func str(_ key: String) -> String? {
        let v = self[key].string
        return v.isEmpty ? nil : v
    }
}
