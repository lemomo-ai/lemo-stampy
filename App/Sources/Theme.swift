import AppKit
import SwiftUI

/// 「糯米」设计规范。所有界面颜色、字号、圆角、阴影都从这里取。
enum Theme {
    // MARK: 颜色
    static let paper = Color(hex: 0xFBF1EB)      // 窗口底
    static let card = Color.white                 // 卡片
    static let well = Color(hex: 0xFFF6F1)        // 卡片里的凹槽、缩略图底
    static let chip = Color(hex: 0xF6ECE7)        // 次按钮、分段轨道、悬停行
    static let line = Color(hex: 0xF1E1D9)        // 细线、输入框描边
    static let butter = Color(hex: 0xF7E7C6)      // 数字角标、提醒卡
    static let butterInk = Color(hex: 0x6B4E1E)
    static let butterTitle = Color(hex: 0x4A3712)
    static let butterWell = Color(hex: 0xFFF8EA)
    static let ink = Color(hex: 0x3B2A26)         // 正文
    static let ink2 = Color(hex: 0x7E665F)        // 次要文字
    static let ink3 = Color(hex: 0xB49E96)        // 更弱的文字
    static let onInk = Color(hex: 0xFFF6F0)       // 深色底上的字
    static let onInk2 = Color(hex: 0xE8D6CF)
    static let coral = Color(hex: 0xE0533D)       // 小章的身体
    static let coralDeep = Color(hex: 0xD2402E)   // 主按钮
    static let coralSoft = Color(hex: 0xFDE3DB)   // 选中行、开着的 chip
    static let coralLine = Color(hex: 0xF7B9A9)   // 焦点描边
    static let coralInk = Color(hex: 0xA8331F)    // coralSoft 上的字
    static let coralSoftInk = Color(hex: 0x8C5A4E)
    static let blush = Color(hex: 0xFFB3A3)
    static let track = Color(hex: 0xF1E3DC)       // 滑块轨道
    static let switchOff = Color(hex: 0xE9DCD5)
    static let tileInk = Color(hex: 0x6E4A40)     // 模板格子里的字、外形图标
    static let dashed = Color(hex: 0xE8B8A8)
    static let canvas = Color(hex: 0xF4EAE5)      // 工坊、批量的画布：比窗口底深一点的暖灰，不带粉、不带点

    // MARK: 圆角
    enum Radius {
        static let thumb: CGFloat = 6
        static let field: CGFloat = 10
        static let row: CGFloat = 14
        static let card: CGFloat = 18
        static let canvas: CGFloat = 22
    }

    // MARK: 字体
    /// 标题、按钮、数字：英文和数字用系统圆角字体（SF Rounded），中文接苹方。
    /// 以前用华文圆体：英文、数字、标点都别扭，和正文的苹方放在一起像两套字。
    static func round(_ size: CGFloat, _ weight: RoundWeight = .bold) -> Font {
        Font(nsFont(size, weight.fontWeight, rounded: true))
    }

    enum RoundWeight {
        case light, regular, bold
        var fontWeight: NSFont.Weight {
            switch self {
            case .light: return .light
            case .regular: return .regular
            case .bold: return .semibold
            }
        }
    }

    /// 正文、说明：英文和数字用系统字体（SF Pro），中文接苹方。
    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        let w: NSFont.Weight
        switch weight {
        case .medium: w = .medium
        case .semibold, .bold, .heavy, .black: w = .semibold
        case .light, .thin, .ultraLight: w = .light
        default: w = .regular
        }
        return Font(nsFont(size, w, rounded: false))
    }

    /// 系统字体 + 苹方接中文。直接用系统字体时中文会按系统语言挑字体（英文系统下可能落到别的字体上），这里固定成苹方。
    static func nsFont(_ size: CGFloat, _ weight: NSFont.Weight, rounded: Bool) -> NSFont {
        let key = "\(size)|\(weight.rawValue)|\(rounded)" as NSString
        if let hit = fontCache.object(forKey: key) { return hit }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor
        if rounded, let r = descriptor.withDesign(.rounded) { descriptor = r }
        let pingFang: String
        switch weight {
        case .semibold, .bold, .heavy, .black: pingFang = "PingFangSC-Semibold"
        case .medium: pingFang = "PingFangSC-Medium"
        case .light, .thin, .ultraLight: pingFang = "PingFangSC-Light"
        default: pingFang = "PingFangSC-Regular"
        }
        descriptor = descriptor.addingAttributes([.cascadeList: [NSFontDescriptor(name: pingFang, size: size)]])
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        fontCache.setObject(font, forKey: key)
        return font
    }

    nonisolated(unsafe) private static let fontCache = NSCache<NSString, NSFont>()
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    /// 规范里阴影用的暖棕：rgba(r, g, b, a)。
    static func warm(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

// MARK: - 阴影（CSS 的 blur 是 SwiftUI radius 的两倍）

extension View {
    /// card：0 4px 16px rgba(170,70,50,.08)
    func cardShadow() -> some View {
        compositingGroup().shadow(color: .warm(170, 70, 50, 0.08), radius: 8, y: 4)
    }

    /// float：0 0 0 1px rgba(150,70,50,.10), 0 12px 32px rgba(150,70,50,.20)
    func floatShadow(cornerRadius: CGFloat) -> some View {
        overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.warm(150, 70, 50, 0.10), lineWidth: 1).padding(-1))
            .compositingGroup()
            .shadow(color: .warm(150, 70, 50, 0.20), radius: 16, y: 12)
    }

    /// 窗口级：0 0 0 1px rgba(150,70,50,.14), 0 24px 60px rgba(120,50,35,.22)
    func windowShadow(cornerRadius: CGFloat) -> some View {
        overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.warm(150, 70, 50, 0.14), lineWidth: 1).padding(-1))
            .compositingGroup()
            .shadow(color: .warm(120, 50, 35, 0.22), radius: 30, y: 24)
    }

    /// 白卡片：白底 + 18 圆角 + card 阴影。
    func cardBackground(padding: CGFloat = 16, radius: CGFloat = Theme.Radius.card) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card))
            .cardShadow()
    }

    /// 内描边（CSS 的 inset box-shadow）。
    func insetStroke(_ color: Color, width: CGFloat = 1, radius: CGFloat) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(color, lineWidth: width))
    }
}
