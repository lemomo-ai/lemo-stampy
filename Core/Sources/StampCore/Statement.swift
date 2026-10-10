import Foundation

/// 印章文字的措辞语言。
public enum StatementPhrasing: String, Codable, CaseIterable, Sendable, Identifiable {
    case chinese
    case english
    case bilingual

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .chinese: return L("中文")
        case .english: return "English"
        case .bilingual: return L("中英")
        }
    }
}

/// 印章上要写的内容：「仅供 ×× 使用，他用无效」+ 日期 / 编号。
public struct Statement: Codable, Equatable, Hashable, Sendable {
    /// 接收方 / 机构，例如「招商银行」。
    public var recipient: String
    /// 用途，例如「办理开户」。
    public var purpose: String
    /// 英文措辞时使用的机构名；留空则沿用 `recipient`。
    public var recipientEN: String
    /// 英文措辞时使用的用途；留空则沿用 `purpose`。
    public var purposeEN: String
    public var phrasing: StatementPhrasing
    /// 打开后用 `customText` 整体替换自动生成的正文（每行一条）。
    public var useCustomText: Bool
    public var customText: String
    public var includeDate: Bool
    public var includeID: Bool
    /// 主文字：留空时按机构和用途自动生成「仅供××使用」，填了就用填的。
    public var mainText: String
    /// 第二行，中文默认「他用无效」，可改成「复印无效」等。
    public var subText: String
    public var subTextEN: String

    public init(
        recipient: String = "",
        purpose: String = "",
        recipientEN: String = "",
        purposeEN: String = "",
        phrasing: StatementPhrasing = .chinese,
        useCustomText: Bool = false,
        customText: String = "",
        includeDate: Bool = true,
        includeID: Bool = true,
        mainText: String = "",
        subText: String = "他用无效",
        subTextEN: String = "Not valid for other use"
    ) {
        self.recipient = recipient
        self.purpose = purpose
        self.recipientEN = recipientEN
        self.purposeEN = purposeEN
        self.phrasing = phrasing
        self.useCustomText = useCustomText
        self.customText = customText
        self.includeDate = includeDate
        self.includeID = includeID
        self.mainText = mainText
        self.subText = subText
        self.subTextEN = subTextEN
    }

    // 逐字段解码并给默认值，旧版本存下的印章缺字段时也能读出来。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Statement()
        recipient = try c.decodeIfPresent(String.self, forKey: .recipient) ?? d.recipient
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? d.purpose
        recipientEN = try c.decodeIfPresent(String.self, forKey: .recipientEN) ?? d.recipientEN
        purposeEN = try c.decodeIfPresent(String.self, forKey: .purposeEN) ?? d.purposeEN
        phrasing = try c.decodeIfPresent(StatementPhrasing.self, forKey: .phrasing) ?? d.phrasing
        useCustomText = try c.decodeIfPresent(Bool.self, forKey: .useCustomText) ?? d.useCustomText
        customText = try c.decodeIfPresent(String.self, forKey: .customText) ?? d.customText
        includeDate = try c.decodeIfPresent(Bool.self, forKey: .includeDate) ?? d.includeDate
        includeID = try c.decodeIfPresent(Bool.self, forKey: .includeID) ?? d.includeID
        mainText = try c.decodeIfPresent(String.self, forKey: .mainText) ?? d.mainText
        subText = try c.decodeIfPresent(String.self, forKey: .subText) ?? d.subText
        subTextEN = try c.decodeIfPresent(String.self, forKey: .subTextEN) ?? d.subTextEN
    }

    private var who: String { recipient.trimmed + purpose.trimmed }

    private var whoEN: (recipient: String, purpose: String) {
        ((recipientEN.trimmed.isEmpty ? recipient : recipientEN).trimmed,
         (purposeEN.trimmed.isEmpty ? purpose : purposeEN).trimmed)
    }

    /// 「仅供招商银行办理开户使用」
    public var chineseLimit: String {
        who.isEmpty ? "仅供指定用途使用" : "仅供\(who)使用"
    }

    /// 「For account opening at CMB only」
    public var englishLimit: String {
        let (r, p) = whoEN
        switch (r.isEmpty, p.isEmpty) {
        case (true, true): return "For the stated purpose only"
        case (false, true): return "For use by \(r) only"
        case (true, false): return "For \(p) only"
        case (false, false): return "For \(p) at \(r) only"
        }
    }

    /// 双语章里的英文行只写用途，保持印章短小。
    public var englishShortLimit: String {
        let (r, p) = whoEN
        if !p.isEmpty { return "For \(p) only" }
        return r.isEmpty ? "For the stated purpose only" : "For use by \(r) only"
    }

    /// 不填主文字时自动生成的那一行。
    public var autoMainText: String {
        phrasing == .english ? englishLimit : chineseLimit
    }

    /// 印章正文（不含日期 / 编号）。
    public var bodyLines: [String] {
        if useCustomText {
            let custom = customText
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmed }
                .filter { !$0.isEmpty }
            if !custom.isEmpty { return custom }
        }
        let sub = subText.trimmed, subEN = subTextEN.trimmed
        let main = mainText.trimmed.isEmpty ? autoMainText : mainText.trimmed
        switch phrasing {
        case .chinese: return [main, sub].filter { !$0.isEmpty }
        case .english: return [main, subEN].filter { !$0.isEmpty }
        case .bilingual: return [main, englishShortLimit, sub].filter { !$0.isEmpty }
        }
    }

    public func stampText(date: Date, stampID: String?) -> StampText {
        var meta: [String] = []
        if includeDate { meta.append(Self.dateString(date)) }
        if includeID, let stampID, !stampID.isEmpty { meta.append("No.\(stampID)") }
        return StampText(body: bodyLines, meta: meta.isEmpty ? nil : meta.joined(separator: " · "))
    }

    public static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

/// 印章上实际画出来的文字：正文若干行 + 一行较小的日期 / 编号。
public struct StampText: Equatable, Hashable, Sendable {
    public var body: [String]
    public var meta: String?

    public init(body: [String], meta: String? = nil) {
        self.body = body
        self.meta = meta
    }

    public var allLines: [String] { body + (meta.map { [$0] } ?? []) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
