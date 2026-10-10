import Foundation

/// 模板库：刻章的起点，套用后什么都可以再改。
/// 只做个人用途声明章，不提供仿公章（红圆 + 五角星 + 机构名）的样式。
public enum StampTemplates {
    public enum Category: String, CaseIterable, Sendable, Identifiable {
        case common, copy, english, seal

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .common: return L("常用")
            case .copy: return L("复印件")
            case .english: return L("英文")
            case .seal: return L("方印")
            }
        }

        public var blurb: String {
            switch self {
            case .common: return L("「仅供××使用，他用无效」，最常见的一句")
            case .copy: return L("身份证、户口本、房产证复印件常用的写法")
            case .english: return L("签证、海外开户、留学材料")
            case .seal: return L("只有几个字的小印，压在签名旁边")
            }
        }
    }

    public struct Template: Sendable, Identifiable {
        public let category: Category
        /// 模板卡片上的一句说明，例如「长章 · 双线 · 宋体」。
        public let blurb: String
        public let design: StampDesign

        public var id: UUID { design.id }
    }

    private static func S(_ recipient: String = "××银行", _ purpose: String = "办理开户", phrasing: StatementPhrasing = .chinese,
                          date: Bool = true, id: Bool = true, sub: String = "他用无效",
                          subEN: String = "Not valid for other use") -> Statement {
        Statement(recipient: recipient, purpose: purpose, phrasing: phrasing, includeDate: date, includeID: id,
                  subText: sub, subTextEN: subEN)
    }

    /// 前 8 个是最早的模板，顺序不要动：「我的印章」的初始几枚和旧数据升级都按下标取。
    public static let library: [Template] = [
        Template(category: .common, blurb: "长章 · 双线 · 宋体", design:
            StampDesign(name: "细框长章", statement: S(),
                        shape: .rectangle, border: .double, font: .songti, color: .red, fontSize: 6.2, tracking: 0.12)),
        Template(category: .common, blurb: "胶囊 · 单线 · 宋体 · 胭脂", design:
            StampDesign(name: "胶囊签", statement: Statement(purpose: "签证申请", includeID: false),
                        shape: .pill, border: .single, font: .songti, color: .crimson, fontSize: 5.5, tracking: 0.06)),
        Template(category: .common, blurb: "圆章 · 双线 · 宋体", design:
            StampDesign(name: "圆章", statement: S(),
                        shape: .circle, border: .double, font: .songti, color: .red, fontSize: 5.6, tracking: 0.14)),
        Template(category: .seal, blurb: "他用无效 · 红底白字", design:
            StampDesign(name: "方印 · 白文", statement: Statement(includeDate: false, includeID: false),
                        shape: .square, font: .songti, color: .red, fontSize: 5, sealText: "他用无效", sealStyle: .yin)),
        Template(category: .seal, blurb: "限用 · 隶书", design:
            StampDesign(name: "方印 · 朱文", statement: Statement(includeDate: false, includeID: false),
                        shape: .square, font: .libian, color: .red, fontSize: 5, sealText: "限用", sealStyle: .yang)),
        Template(category: .common, blurb: "无框 · 楷体 · 藏蓝，像手写", design:
            StampDesign(name: "签注", statement: Statement(purpose: "租房签约"),
                        shape: .plain, border: .none, font: .kaiti, color: .blue,
                        opacity: 0.9, fontSize: 7, tracking: 0.04, texture: .clean)),
        Template(category: .english, blurb: "长章 · 粗细线 · Serif", design:
            StampDesign(name: "英文长章", statement: Statement(purpose: "visa application", phrasing: .english),
                        shape: .rectangle, border: .thickThin, font: .serif, color: .blue, fontSize: 5.2, tracking: 0.1)),
        Template(category: .english, blurb: "长章 · 单线 · 中英两行", design:
            StampDesign(name: "中英双语",
                        statement: Statement(recipient: "××使馆", purpose: "签证申请", recipientEN: "the Embassy",
                                             purposeEN: "visa application", phrasing: .bilingual),
                        shape: .rectangle, border: .single, font: .songti, color: .red, fontSize: 5.6, tracking: 0.08)),

        Template(category: .common, blurb: "长章 · 粗细线 · 仿宋 · 墨", design:
            StampDesign(name: "墨色长章", statement: S(),
                        shape: .rectangle, border: .thickThin, font: .fangsong, color: .black, fontSize: 6, tracking: 0.12)),
        Template(category: .common, blurb: "圆章 · 单线 · 魏碑 · 藏蓝", design:
            StampDesign(name: "藏蓝圆章", statement: S(),
                        shape: .circle, border: .single, font: .weibei, color: .blue, fontSize: 5.6, tracking: 0.14)),
        Template(category: .copy, blurb: "长章 · 黑体 · 三行", design:
            StampDesign(name: "再次复印无效", statement: S(sub: "他用无效 · 再次复印无效"),
                        shape: .rectangle, border: .single, font: .heiti, color: .red, fontSize: 5.6, tracking: 0.08)),
        Template(category: .copy, blurb: "长章 · 双线 · 胭脂 · 本人确认", design:
            StampDesign(name: "与原件一致", statement: S(id: false, sub: "复印件与原件一致"),
                        shape: .rectangle, border: .double, font: .songti, color: .crimson, fontSize: 5.8, tracking: 0.1)),
        Template(category: .copy, blurb: "胶囊 · 黑体 · 一行写完", design:
            StampDesign(name: "身份证复印件", statement: S(id: false, sub: "再次复印无效"),
                        shape: .pill, border: .single, font: .heiti, color: .red, fontSize: 4.6, tracking: 0.04)),
        Template(category: .english, blurb: "圆章 · 双线 · COPY ONLY", design:
            StampDesign(name: "英文圆章", statement: S("", "visa application", phrasing: .english, subEN: "Copy only"),
                        shape: .circle, border: .double, font: .serif, color: .blue, fontSize: 5, tracking: 0.1)),
        Template(category: .english, blurb: "胶囊 · Serif · 墨 · 一句话", design:
            StampDesign(name: "英文胶囊", statement: S("", "visa application", phrasing: .english, id: false, subEN: ""),
                        shape: .pill, border: .single, font: .serif, color: .black, fontSize: 5, tracking: 0.06)),
        Template(category: .seal, blurb: "复印无效 · 红底白字", design:
            StampDesign(name: "方印 · 复印无效", statement: Statement(includeDate: false, includeID: false),
                        shape: .square, font: .songti, color: .red, fontSize: 5, sealText: "复印无效", sealStyle: .yin)),
        Template(category: .seal, blurb: "专用 · 楷体 · 胭脂", design:
            StampDesign(name: "方印 · 专用", statement: Statement(includeDate: false, includeID: false),
                        shape: .square, font: .kaiti, color: .crimson, fontSize: 5, sealText: "专用", sealStyle: .yang)),
    ]

    public static var all: [StampDesign] { library.map(\.design) }

    public static func templates(in category: Category?) -> [Template] {
        guard let category else { return library }
        return library.filter { $0.category == category }
    }
}
