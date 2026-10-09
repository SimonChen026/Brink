import Foundation

/// Game / UI language.
public enum Lang: String, Codable, Sendable, CaseIterable {
    case zh, en

    public var label: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

/// Localization. Text written in code comes in Chinese/English pairs at the call site
/// (`L("中文", "English")`); scenario content is translated by overlay tables
/// (`Scenarios/en/<id>.json`, see ScenarioText).
public enum Loc {
    /// Current interface language (set by the app at launch / when the user switches).
    nonisolated(unsafe) public static var ui: Lang = .zh

    public static var systemDefault: Lang {
        (Locale.preferredLanguages.first ?? "zh").hasPrefix("zh") ? .zh : .en
    }

    /// The Chinese or English text, by language.
    @inlinable
    public static func pick(_ zh: @autoclosure () -> String, _ en: @autoclosure () -> String, _ lang: Lang) -> String {
        lang == .en ? en() : zh()
    }

    /// List separator: 、 or ,
    public static func sep(_ lang: Lang) -> String { lang == .en ? ", " : "、" }
    /// Clause separator: ， or ,
    public static func comma(_ lang: Lang) -> String { lang == .en ? ", " : "，" }
    /// Sentence/section separator: ； or ;
    public static func semi(_ lang: Lang) -> String { lang == .en ? "; " : "；" }
    /// Label colon: ： or :
    public static func colon(_ lang: Lang) -> String { lang == .en ? ": " : "：" }

    /// A name as it reads in the middle of a sentence: parenthetical notes dropped; in English
    /// also without a leading "The" and lower-cased ("Brazier (dries clothes…)" → "brazier").
    public static func inline(_ s: String, _ lang: Lang) -> String {
        var t = s
        for (open, close) in [("（", "）"), ("(", ")")] {
            if let a = t.range(of: open), let b = t.range(of: close, range: a.upperBound..<t.endIndex) {
                t.removeSubrange(a.lowerBound..<b.upperBound)
            }
        }
        t = t.trimmingCharacters(in: .whitespaces)
        guard lang == .en else { return t }
        for article in ["The ", "the "] where t.hasPrefix(article) { t = String(t.dropFirst(article.count)) }
        // keep acronyms (SOS, ELT …) as they are
        if let first = t.first, !(t.count > 1 && t.prefix(2).allSatisfy(\.isUppercase)) {
            t = first.lowercased() + t.dropFirst()
        }
        return t
    }

    /// English value text in the middle of a sentence: first letter lower-cased (acronyms kept).
    public static func lowerFirst(_ s: String, _ lang: Lang) -> String {
        guard lang == .en, let first = s.first, !(s.count > 1 && s.prefix(2).allSatisfy(\.isUppercase)) else { return s }
        return first.lowercased() + s.dropFirst()
    }

    /// True if the string contains CJK characters (used to check English overlays).
    public static func hasCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }
}

/// Interface text in the current UI language.
@inlinable
public func L(_ zh: @autoclosure () -> String, _ en: @autoclosure () -> String) -> String {
    Loc.ui == .en ? en() : zh()
}
