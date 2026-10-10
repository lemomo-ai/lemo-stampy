import Foundation

/// 界面语言：中文和英文两套。印章上盖的字不跟它走（那是 `StatementPhrasing`，是盖给别人看的）。
public enum UILanguage: String, Codable, CaseIterable, Sendable {
    case zh, en

    /// 系统首选语言是中文（简体、繁体都算）就用中文，其他一律英文。
    public static var system: UILanguage {
        let first = Locale.preferredLanguages.first ?? "zh-Hans"
        return first.hasPrefix("zh") ? .zh : .en
    }
}

/// 用户的选择：跟随系统，或者固定一种。
public enum LanguagePreference: String, Codable, CaseIterable, Sendable {
    case system, zh, en

    public var resolved: UILanguage {
        switch self {
        case .system: return .system
        case .zh: return .zh
        case .en: return .en
        }
    }
}

/// 界面文字的翻译：代码里写中文原文，`L("拿起印章")` 在英文界面下换成英文。
/// 中文原文就是键，英文对照表在 `Localization+English.swift`。缺翻译时显示中文原文，scripts/check_l10n.swift 会查出来。
public enum Localization {
    /// 默认中文（单元测试、命令行都按中文）；App 启动时按用户的选择改。
    nonisolated(unsafe) public static var language: UILanguage = .zh

    public static var isEnglish: Bool { language == .en }

    public static func text(_ key: String) -> String {
        guard language == .en else { return key }
        return english[key] ?? key
    }

    /// 「3 份」「1 page / 3 pages」：中文量词，英文分单复数。英文的单复数写在对照表里，形如 "file|files"。
    public static func count(_ n: Int, _ unit: String) -> String {
        guard language == .en else { return "\(n) \(unit)" }
        let forms = (english[unit] ?? unit).split(separator: "|").map(String.init)
        let word = n == 1 ? forms.first ?? unit : forms.last ?? unit
        return "\(n) \(word)"
    }
}

/// 界面文字：中文原文进，当前语言出。
public func L(_ key: String) -> String {
    Localization.text(key)
}

/// 带参数的界面文字：`L("盖 %@", Localization.count(3, "份"))`。参数用 %@（字符串）或 %ld（整数）。
public func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localization.text(key), arguments: args)
}
