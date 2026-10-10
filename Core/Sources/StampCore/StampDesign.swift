import CoreGraphics
import CoreText
import Foundation

// MARK: - 印章的各项属性

public enum StampShape: String, Codable, CaseIterable, Sendable, Identifiable {
    case rectangle, pill, circle, square, plain

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rectangle: return L("长章")
        case .pill: return L("胶囊")
        case .circle: return L("圆章")
        case .square: return L("方印")
        case .plain: return L("签注")
        }
    }
}

public enum StampBorder: String, Codable, CaseIterable, Sendable, Identifiable {
    case double, single, thickThin, none

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .double: return L("双线")
        case .single: return L("单线")
        case .thickThin: return L("粗细线")
        case .none: return L("无框")
        }
    }
}

public enum StampFont: String, Codable, CaseIterable, Sendable, Identifiable {
    case songti, kaiti, fangsong, libian, weibei, heiti, serif

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .songti: return L("宋体")
        case .kaiti: return L("楷体")
        case .fangsong: return L("仿宋")
        case .libian: return L("隶书")
        case .weibei: return L("魏碑")
        case .heiti: return L("黑体")
        case .serif: return "Serif"
        }
    }

    /// 正文用的字重。
    var mainName: String {
        switch self {
        case .songti: return "STSongti-SC-Bold"
        case .kaiti: return "STKaitiSC-Bold"
        case .fangsong: return "STFangsong"
        case .libian: return "STLibianSC-Regular"
        case .weibei: return "WeibeiSC-Bold"
        case .heiti: return "PingFangSC-Semibold"
        case .serif: return "Baskerville-SemiBold"
        }
    }

    /// 日期 / 编号这类小字用的字重。
    var metaName: String {
        switch self {
        case .songti, .libian, .weibei: return "STSongti-SC-Regular"
        case .kaiti: return "STKaitiSC-Regular"
        case .fangsong: return "STFangsong"
        case .heiti: return "PingFangSC-Regular"
        case .serif: return "Baskerville"
        }
    }

    /// 方印用的字重：笔画要重一些才压得住。
    var sealName: String {
        switch self {
        case .songti: return "STSongti-SC-Black"
        case .kaiti: return "STKaitiSC-Black"
        case .heiti: return "PingFangSC-Semibold"
        default: return mainName
        }
    }

    /// 字体选择器里用来展示这款字体本身的样子。
    public var previewFontName: String { mainName }
}

public enum StampColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case red, crimson, blue, black

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .red: return L("朱砂")
        case .crimson: return L("胭脂")
        case .blue: return L("藏蓝")
        case .black: return L("墨")
        }
    }

    public var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .red: return (0.79, 0.20, 0.16)
        case .crimson: return (0.62, 0.11, 0.18)
        case .blue: return (0.13, 0.24, 0.45)
        case .black: return (0.14, 0.13, 0.12)
        }
    }

    var cgColor: CGColor { CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1) }
}

/// 方印的刻法：朱文是红字，白文是红底白字。
public enum SealStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case yang, yin

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .yang: return L("朱文")
        case .yin: return L("白文")
        }
    }
}

public enum InkTexture: String, Codable, CaseIterable, Sendable, Identifiable {
    case clean, light, aged

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .clean: return L("干净")
        case .light: return L("印泥")
        case .aged: return L("做旧")
        }
    }
}

/// 一枚刻好的印章。
public struct StampDesign: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var statement: Statement
    public var shape: StampShape
    public var border: StampBorder
    public var font: StampFont
    public var color: StampColor
    /// 墨色浓度 0…1。
    public var opacity: Double
    /// 正文字号，单位是页面上的点（1pt ≈ 0.35mm）。
    public var fontSize: Double
    /// 字距，单位是字号的倍数。
    public var tracking: Double
    /// 旋转角度（度），正数为逆时针。
    public var rotation: Double
    public var texture: InkTexture
    /// 方印上的字（印文）。
    public var sealText: String
    public var sealStyle: SealStyle
    /// 英文全部大写。
    public var uppercaseLatin: Bool

    public init(id: UUID = UUID(), name: String, statement: Statement = Statement(), shape: StampShape = .rectangle,
                border: StampBorder = .double, font: StampFont = .songti, color: StampColor = .red, opacity: Double = 0.92,
                fontSize: Double = 6.5, tracking: Double = 0.12, rotation: Double = 0, texture: InkTexture = .light,
                sealText: String = "他用无效", sealStyle: SealStyle = .yin, uppercaseLatin: Bool = true) { // l10n-ignore：文件夹名 / 印章上的字，不翻译
        self.id = id
        self.name = name
        self.statement = statement
        self.shape = shape
        self.border = border
        self.font = font
        self.color = color
        self.opacity = opacity
        self.fontSize = fontSize
        self.tracking = tracking
        self.rotation = rotation
        self.texture = texture
        self.sealText = sealText
        self.sealStyle = sealStyle
        self.uppercaseLatin = uppercaseLatin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StampDesign(name: "")
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "印章" // l10n-ignore：文件夹名 / 印章上的字，不翻译
        statement = try c.decodeIfPresent(Statement.self, forKey: .statement) ?? d.statement
        shape = try c.decodeIfPresent(StampShape.self, forKey: .shape) ?? d.shape
        border = try c.decodeIfPresent(StampBorder.self, forKey: .border) ?? d.border
        font = try c.decodeIfPresent(StampFont.self, forKey: .font) ?? d.font
        color = try c.decodeIfPresent(StampColor.self, forKey: .color) ?? d.color
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        tracking = try c.decodeIfPresent(Double.self, forKey: .tracking) ?? d.tracking
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? d.rotation
        texture = try c.decodeIfPresent(InkTexture.self, forKey: .texture) ?? d.texture
        sealText = try c.decodeIfPresent(String.self, forKey: .sealText) ?? d.sealText
        sealStyle = try c.decodeIfPresent(SealStyle.self, forKey: .sealStyle) ?? d.sealStyle
        uppercaseLatin = try c.decodeIfPresent(Bool.self, forKey: .uppercaseLatin) ?? d.uppercaseLatin
    }

    /// 把另一枚印章（通常是模板）的外观套到自己身上：形状、边框、字体、颜色、大小、角度、质感、朱白文。
    /// 名字和写的内容（文字、措辞、日期编号开关、方印印文）都保留自己的。
    public func applyingLook(of template: StampDesign) -> StampDesign {
        var result = template
        result.id = id
        result.name = name
        result.statement = statement
        result.sealText = sealText
        return result
    }
}

/// 印章上可以点选编辑的区域。
public enum StampRegion: String, CaseIterable, Sendable {
    case main, sub, meta, seal
}

// MARK: - 绘制

/// 画印章。尺寸以「页面上的点」为单位，`scale` 把它换算到目标画布。
public enum StampRenderer {
    static let mmPerPoint: CGFloat = 25.4 / 72

    struct Layout {
        let size: CGSize
        /// 各可编辑区域在印章局部坐标里的位置（未旋转、y 轴向上）。
        let regions: [StampRegion: CGRect]
        let draw: (CGContext) -> Void
    }

    /// 未旋转时印章的尺寸（已乘 scale）。
    public static func size(_ text: StampText, design: StampDesign, scale: CGFloat = 1) -> CGSize {
        layout(text, design: design, scale: scale).size
    }

    /// 实际大小（毫米）。
    public static func physicalSize(_ text: StampText, design: StampDesign) -> CGSize {
        let s = size(text, design: design)
        return CGSize(width: s.width * mmPerPoint, height: s.height * mmPerPoint)
    }

    /// 旋转后的外接矩形尺寸（已乘 scale）。
    public static func boundingSize(_ text: StampText, design: StampDesign, scale: CGFloat = 1) -> CGSize {
        rotatedBounds(size(text, design: design, scale: scale), degrees: design.rotation)
    }

    /// 可编辑区域（未旋转、y 轴向上、原点在印章左下角，已乘 scale）。
    public static func regions(_ text: StampText, design: StampDesign, scale: CGFloat = 1) -> [StampRegion: CGRect] {
        layout(text, design: design, scale: scale).regions
    }

    /// 以 `center` 为中心画印章（y 轴向上的坐标系）。
    /// 带印泥质感时印章会先栅格化：`rasterResolution` 是每个画布单位对应的像素数（PDF 用 10 左右，位图用 1）。
    public static func draw(_ text: StampText, design: StampDesign, in ctx: CGContext, center: CGPoint, scale: CGFloat = 1,
                            rasterResolution: CGFloat = 1) {
        if design.texture != .clean,
           let image = image(text, design: design, pixelsPerPoint: scale * rasterResolution) {
            let w = CGFloat(image.width) / rasterResolution, h = CGFloat(image.height) / rasterResolution
            ctx.saveGState()
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h))
            ctx.restoreGState()
            return
        }
        let layout = layout(text, design: design, scale: scale)
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: CGFloat(design.rotation) * .pi / 180)
        ctx.translateBy(x: -layout.size.width / 2, y: -layout.size.height / 2)
        ctx.setAlpha(CGFloat(min(max(design.opacity, 0.1), 1)))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        layout.draw(ctx)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// 印章单独渲染成透明底的图（界面预览、跟随鼠标的浮动印章、带质感的输出）。
    public static func image(_ text: StampText, design: StampDesign, pixelsPerPoint: CGFloat) -> CGImage? {
        let layout = layout(text, design: design, scale: pixelsPerPoint)
        let bounds = rotatedBounds(layout.size, degrees: design.rotation)
        let width = max(1, Int(ceil(bounds.width)) + 4), height = max(1, Int(ceil(bounds.height)) + 4)
        guard width * height < 120_000_000,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if design.texture != .clean {
            let seed = stableSeed(text.allLines.joined(separator: "|") + design.id.uuidString + design.sealText)
            if let mask = textureMask(width: width, height: height, pixelsPerPoint: pixelsPerPoint, level: design.texture, seed: seed) {
                ctx.clip(to: CGRect(x: 0, y: 0, width: width, height: height), mask: mask)
            }
        }
        ctx.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        ctx.rotate(by: CGFloat(design.rotation) * .pi / 180)
        ctx.translateBy(x: -layout.size.width / 2, y: -layout.size.height / 2)
        ctx.setAlpha(CGFloat(min(max(design.opacity, 0.1), 1)))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        layout.draw(ctx)
        ctx.endTransparencyLayer()
        return ctx.makeImage()
    }

    static func rotatedBounds(_ s: CGSize, degrees: Double) -> CGSize {
        let a = CGFloat(degrees) * .pi / 180
        return CGSize(width: abs(s.width * cos(a)) + abs(s.height * sin(a)),
                      height: abs(s.width * sin(a)) + abs(s.height * cos(a)))
    }

    // MARK: 排版

    static func layout(_ text: StampText, design: StampDesign, scale: CGFloat) -> Layout {
        let fs = max(CGFloat(design.fontSize) * scale, 0.5)
        var body = text.body
        if design.uppercaseLatin { body = body.map { $0.uppercased() } }
        switch design.shape {
        case .rectangle: return rectangleLayout(body: body, meta: text.meta, design: design, fs: fs, pill: false)
        case .pill: return rectangleLayout(body: [body.joined(separator: " · ")],
                                           meta: text.meta, design: design, fs: fs, pill: true)
        case .circle: return circleLayout(body: body, meta: text.meta, design: design, fs: fs)
        case .square: return squareLayout(design: design, fs: fs)
        case .plain: return plainLayout(body: body, meta: text.meta, design: design, fs: fs)
        }
    }

    /// 长章与胶囊章：正文居中若干行，日期编号小字在最下面。
    private static func rectangleLayout(body: [String], meta: String?, design: StampDesign, fs: CGFloat, pill: Bool) -> Layout {
        let track = CGFloat(design.tracking) * fs
        var lines: [(TypeLine, StampRegion)] = []
        for (i, s) in body.enumerated() where !s.isEmpty {
            // 第一行之后的纯西文行（双语章的英文行）字号收小，免得印章被撑长。
            let size = i == 0 ? fs : (isLatin(s) && !isLatin(body[0]) ? fs * 0.74 : fs * 0.9)
            lines.append((typeset(s, fontName: design.font.mainName, size: size, tracking: track), i == 0 ? .main : .sub))
        }
        if let meta {
            lines.append((typeset(meta, fontName: design.font.metaName, size: fs * 0.6, tracking: fs * 0.06), .meta))
        }
        let gap = fs * 0.34
        let contentWidth = lines.map(\.0.width).max() ?? fs
        let contentHeight = lines.enumerated().reduce(CGFloat(0)) { sum, item in
            sum + item.element.0.height + (item.offset == 0 ? 0 : (item.element.1 == .meta ? gap * 1.15 : gap))
        }

        let border = BorderMetrics(design.border, fs: fs)
        let padY = design.border == .none ? fs * 0.2 : fs * 0.55 + border.thickness
        var padX = design.border == .none ? fs * 0.25 : fs * 0.95 + border.thickness
        let height = ceil(contentHeight + padY * 2)
        if pill { padX = max(padX, height * 0.5 + fs * 0.25) }
        let width = ceil(contentWidth + padX * 2)
        let radius = pill ? height / 2 : fs * 0.16

        var regions: [StampRegion: CGRect] = [:]
        var baseline = height - padY
        var placed: [(TypeLine, CGPoint)] = []
        for (index, (line, region)) in lines.enumerated() {
            if index > 0 { baseline -= (region == .meta ? gap * 1.15 : gap) }
            baseline -= line.ascent
            let origin = CGPoint(x: (width - line.width) / 2, y: baseline)
            placed.append((line, origin))
            regions[region] = (regions[region] ?? .null).union(
                CGRect(x: origin.x, y: baseline - line.descent, width: line.width, height: line.height).insetBy(dx: -fs * 0.15, dy: -fs * 0.1))
            baseline -= line.descent
        }

        return Layout(size: CGSize(width: width, height: height), regions: regions) { ctx in
            let color = design.color.cgColor
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)
            border.stroke(CGRect(x: 0, y: 0, width: width, height: height), radius: radius, in: ctx)
            for (line, origin) in placed { line.draw(at: origin, in: ctx) }
        }
    }

    /// 圆章：正文沿上半圆排，第二行横排在中间，日期编号沿下半圆。
    private static func circleLayout(body: [String], meta: String?, design: StampDesign, fs: CGFloat) -> Layout {
        let track = CGFloat(design.tracking) * fs
        let top = typeset(body.first ?? " ", fontName: design.font.mainName, size: fs, tracking: max(track, fs * 0.1))
        let centerLines = body.dropFirst().filter { !$0.isEmpty }.map {
            typeset($0, fontName: design.font.mainName, size: fs * 1.18, tracking: track * 1.2)
        }
        let centerGap = fs * 0.28
        let centerWidth = centerLines.map(\.width).max() ?? 0
        let centerHeight = centerLines.reduce(CGFloat(0)) { $0 + $1.height } + centerGap * CGFloat(max(centerLines.count - 1, 0))

        let maxSpan: CGFloat = 3.7 // 上弧最多占约 212°
        let fromArc = top.width / maxSpan
        let fromCenter = hypot(centerWidth / 2, centerHeight / 2) + fs * 0.5 + top.descent
        let topRadius = max(fromArc, fromCenter, fs * 2.6)
        let ring = topRadius + top.ascent + fs * 0.32          // 文字外侧的那一圈
        let border = BorderMetrics(design.border == .none ? .none : design.border, fs: fs)
        let outer = ring + border.thickness
        let side = ceil(outer * 2 + fs * 0.1)
        let c = CGPoint(x: side / 2, y: side / 2)

        var metaLine: TypeLine?
        var metaRadius: CGFloat = 0
        if let meta {
            var m = typeset(meta, fontName: design.font.metaName, size: fs * 0.58, tracking: fs * 0.05)
            metaRadius = ring - fs * 0.32 - m.descent
            let maxMetaSpan: CGFloat = 1.75
            if m.width / metaRadius > maxMetaSpan {
                let shrink = maxMetaSpan / (m.width / metaRadius)
                m = typeset(meta, fontName: design.font.metaName, size: fs * 0.58 * shrink, tracking: fs * 0.05 * shrink)
                metaRadius = ring - fs * 0.32 - m.descent
            }
            metaLine = m
        }

        var regions: [StampRegion: CGRect] = [:]
        regions[.main] = CGRect(x: c.x - ring, y: c.y + fromCenter * 0.55, width: ring * 2, height: ring - fromCenter * 0.55)
        if !centerLines.isEmpty {
            regions[.sub] = CGRect(x: c.x - centerWidth / 2, y: c.y - centerHeight / 2, width: centerWidth, height: centerHeight)
                .insetBy(dx: -fs * 0.2, dy: -fs * 0.15)
        }
        if metaLine != nil {
            regions[.meta] = CGRect(x: c.x - ring * 0.7, y: c.y - ring, width: ring * 1.4, height: ring * 0.35)
        }

        return Layout(size: CGSize(width: side, height: side), regions: regions) { ctx in
            let color = design.color.cgColor
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)
            border.strokeCircle(center: c, radius: outer, in: ctx)
            drawArc(top, center: c, radius: topRadius, upper: true, in: ctx)
            var baseline = c.y + centerHeight / 2
            for line in centerLines {
                baseline -= line.ascent
                line.draw(at: CGPoint(x: c.x - line.width / 2, y: baseline), in: ctx)
                baseline -= line.descent + centerGap
            }
            if let metaLine { drawArc(metaLine, center: c, radius: metaRadius, upper: false, in: ctx) }
        }
    }

    /// 方印：印文按传统从右往左、从上往下排进格子，字撑满格子。
    private static func squareLayout(design: StampDesign, fs: CGFloat) -> Layout {
        var chars = design.sealText.filter { !$0.isWhitespace }.map(String.init)
        if chars.isEmpty { chars = ["印"] } // l10n-ignore：文件夹名 / 印章上的字，不翻译
        let n = chars.count
        let (cols, rows): (Int, Int) = {
            switch n {
            case 1: return (1, 1)
            case 2: return (1, 2)
            case 3: return (1, 3)
            case 4: return (2, 2)
            case 5, 6: return (2, 3)
            default: return (3, Int(ceil(Double(n) / 3)))
            }
        }()
        let cell = fs * 1.5
        let frame = design.sealStyle == .yin ? fs * 0.34 : max(fs * 0.17, 0.5)
        let pad = design.sealStyle == .yin ? fs * 0.08 : fs * 0.2
        let width = ceil(CGFloat(cols) * cell + (pad + frame) * 2)
        let height = ceil(CGFloat(rows) * cell + (pad + frame) * 2)
        let box = CGRect(x: 0, y: 0, width: width, height: height)

        let font = makeFont(design.font.sealName, size: cell)
        var glyphs: [(CGPath, CGRect)] = []
        for (i, ch) in chars.enumerated() {
            let col = cols - 1 - i / rows          // 从右往左
            let row = i % rows                     // 从上往下
            let cellRect = CGRect(x: pad + frame + CGFloat(col) * cell,
                                  y: height - pad - frame - CGFloat(row + 1) * cell,
                                  width: cell, height: cell)
            if let path = glyphPath(ch, font: font) { glyphs.append((path, cellRect)) }
        }

        return Layout(size: box.size, regions: [.seal: box]) { ctx in
            let color = design.color.cgColor
            ctx.setFillColor(color)
            ctx.setStrokeColor(color)
            let radius = fs * 0.12
            let placed = glyphs.compactMap { path, cellRect in
                fitted(path, into: cellRect.insetBy(dx: cell * 0.05, dy: cell * 0.05))
            }
            if design.sealStyle == .yin {
                // 字从红底上「刻」掉：用路径相减，而不是 .clear 混合——PDF 里不支持 .clear，字会消失成一整块色。
                var face: CGPath = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
                for glyph in placed { face = face.subtracting(glyph) }
                ctx.addPath(face)
                ctx.fillPath()
            } else {
                ctx.setLineWidth(frame)
                ctx.addPath(CGPath(roundedRect: box.insetBy(dx: frame / 2, dy: frame / 2), cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.strokePath()
                for glyph in placed {
                    ctx.addPath(glyph)
                    ctx.fillPath()
                }
            }
        }
    }

    /// 签注：没有边框，像手写批注，正文下面一条细线，日期编号靠右。
    private static func plainLayout(body: [String], meta: String?, design: StampDesign, fs: CGFloat) -> Layout {
        let track = CGFloat(design.tracking) * fs
        let lines = body.enumerated().filter { !$0.element.isEmpty }.map { i, s in
            (typeset(s, fontName: design.font.mainName, size: i == 0 ? fs : fs * 0.9, tracking: track), i == 0 ? StampRegion.main : .sub)
        }
        let metaLine = meta.map { typeset($0, fontName: design.font.metaName, size: fs * 0.6, tracking: fs * 0.05) }
        let gap = fs * 0.3
        let rule = max(fs * 0.06, 0.3)
        let ruleGap = fs * 0.28
        let contentWidth = max(lines.map(\.0.width).max() ?? fs, metaLine?.width ?? 0)
        let bodyHeight = lines.reduce(CGFloat(0)) { $0 + $1.0.height } + gap * CGFloat(max(lines.count - 1, 0))
        let metaHeight = metaLine.map { $0.height + ruleGap } ?? 0
        let padX = fs * 0.3, padY = fs * 0.2
        let width = ceil(contentWidth + padX * 2)
        let height = ceil(bodyHeight + ruleGap + rule + metaHeight + padY * 2)

        var regions: [StampRegion: CGRect] = [:]
        var placed: [(TypeLine, CGPoint)] = []
        var baseline = height - padY
        for (index, (line, region)) in lines.enumerated() {
            if index > 0 { baseline -= gap }
            baseline -= line.ascent
            let origin = CGPoint(x: (width - line.width) / 2, y: baseline)
            placed.append((line, origin))
            regions[region] = (regions[region] ?? .null).union(CGRect(x: origin.x, y: baseline - line.descent, width: line.width, height: line.height))
            baseline -= line.descent
        }
        let ruleY = baseline - ruleGap
        var metaOrigin: CGPoint?
        if let metaLine {
            let y = ruleY - rule - ruleGap * 0.8 - metaLine.ascent
            metaOrigin = CGPoint(x: width - padX - metaLine.width, y: y)
            regions[.meta] = CGRect(x: metaOrigin!.x, y: y - metaLine.descent, width: metaLine.width, height: metaLine.height)
        }

        return Layout(size: CGSize(width: width, height: height), regions: regions) { ctx in
            let color = design.color.cgColor
            ctx.setFillColor(color)
            ctx.setStrokeColor(color)
            for (line, origin) in placed { line.draw(at: origin, in: ctx) }
            ctx.setLineWidth(rule)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: padX, y: ruleY))
            ctx.addLine(to: CGPoint(x: width - padX, y: ruleY))
            ctx.strokePath()
            if let metaLine, let metaOrigin { metaLine.draw(at: metaOrigin, in: ctx) }
        }
    }

    // MARK: 边框

    private struct BorderMetrics {
        let style: StampBorder
        let outer: CGFloat
        let inner: CGFloat
        let gap: CGFloat

        init(_ style: StampBorder, fs: CGFloat) {
            self.style = style
            let hairline = max(fs * 0.04, 0.25)
            switch style {
            case .double: outer = max(fs * 0.1, 0.4); inner = hairline; gap = fs * 0.16
            case .single: outer = max(fs * 0.085, 0.35); inner = 0; gap = 0
            case .thickThin: outer = max(fs * 0.2, 0.6); inner = hairline; gap = fs * 0.14
            case .none: outer = 0; inner = 0; gap = 0
            }
        }

        /// 边框占掉的厚度（从外沿到内沿）。
        var thickness: CGFloat { style == .none ? 0 : outer + (inner > 0 ? gap + inner : 0) }

        func stroke(_ rect: CGRect, radius: CGFloat, in ctx: CGContext) {
            guard style != .none else { return }
            ctx.setLineWidth(outer)
            let o = rect.insetBy(dx: outer / 2, dy: outer / 2)
            ctx.addPath(CGPath(roundedRect: o, cornerWidth: min(radius, o.height / 2), cornerHeight: min(radius, o.height / 2), transform: nil))
            ctx.strokePath()
            if inner > 0 {
                let inset = outer + gap + inner / 2
                let i = rect.insetBy(dx: inset, dy: inset)
                let r = max(min(radius - inset, i.height / 2), 0)
                ctx.setLineWidth(inner)
                ctx.addPath(CGPath(roundedRect: i, cornerWidth: r, cornerHeight: r, transform: nil))
                ctx.strokePath()
            }
        }

        func strokeCircle(center: CGPoint, radius: CGFloat, in ctx: CGContext) {
            guard style != .none else { return }
            ctx.setLineWidth(outer)
            ctx.addArc(center: center, radius: radius - outer / 2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()
            if inner > 0 {
                ctx.setLineWidth(inner)
                ctx.addArc(center: center, radius: radius - outer - gap - inner / 2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.strokePath()
            }
        }
    }

    // MARK: 文字

    struct TypeLine {
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
        var height: CGFloat { ascent + descent }

        func draw(at origin: CGPoint, in ctx: CGContext) {
            ctx.textMatrix = .identity
            ctx.textPosition = origin
            CTLineDraw(line, ctx)
        }
    }

    static func isLatin(_ s: String) -> Bool {
        !s.unicodeScalars.contains { $0.value >= 0x2E80 }
    }

    static func makeFont(_ name: String, size: CGFloat) -> CTFont {
        var font = CTFontCreateWithName(name as CFString, size, nil)
        if (CTFontCopyPostScriptName(font) as String) != name {
            font = CTFontCreateWithName("STSongti-SC-Bold" as CFString, size, nil) // 字体缺失时退回宋体
        }
        // 西文字体里没有汉字，给它接上宋体
        let cascade = [CTFontDescriptorCreateWithNameAndSize("STSongti-SC-Bold" as CFString, size)]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(font), [
            kCTFontCascadeListAttribute: cascade,
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func typeset(_ string: String, fontName: String, size: CGFloat, tracking: CGFloat) -> TypeLine {
        let font = makeFont(fontName, size: size)
        let attributed = NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        // 字距会加在最后一个字后面，居中时要扣掉。
        let trailing = string.isEmpty ? 0 : tracking
        return TypeLine(line: line, width: max(width - trailing, 0), ascent: ascent, descent: descent)
    }

    /// 逐字沿圆弧排。上弧字头朝外、从左往右顺时针；下弧字头朝圆心、从左往右逆时针。
    private static func drawArc(_ typeLine: TypeLine, center: CGPoint, radius: CGFloat, upper: Bool, in ctx: CGContext) {
        guard radius > 0, let runs = CTLineGetGlyphRuns(typeLine.line) as? [CTRun] else { return }
        ctx.textMatrix = .identity
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let font = attributes[kCTFontAttributeName as String] as! CTFont
            var advances = [CGSize](repeating: .zero, count: count)
            CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, count)
            for i in 0..<count {
                let advance = advances[i].width
                let offset = positions[i].x + advance / 2 - typeLine.width / 2
                let angle = upper ? .pi / 2 - offset / radius : -.pi / 2 + offset / radius
                ctx.saveGState()
                ctx.translateBy(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                ctx.rotate(by: upper ? angle - .pi / 2 : angle + .pi / 2)
                var glyph = glyphs[i]
                var origin = CGPoint(x: -advance / 2, y: 0)
                CTFontDrawGlyphs(font, &glyph, &origin, 1, ctx)
                ctx.restoreGState()
            }
        }
    }

    private static func glyphPath(_ ch: String, font: CTFont) -> CGPath? {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: ch, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]))
        guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first, CTRunGetGlyphCount(run) > 0 else { return nil }
        var glyph: CGGlyph = 0
        CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
        return CTFontCreatePathForGlyph(runFont, glyph, nil)
    }

    /// 把字形按外轮廓撑满格子，像篆刻那样字满印面；长宽比最多拉伸 18%。
    private static func fitted(_ path: CGPath, into rect: CGRect) -> CGPath? {
        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        var sx = rect.width / bounds.width, sy = rect.height / bounds.height
        let limit: CGFloat = 1.18
        if sx > sy * limit { sx = sy * limit }
        if sy > sx * limit { sy = sx * limit }
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: sx, y: sy)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return path.copy(using: &transform)
    }

    // MARK: 印泥质感

    static func stableSeed(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    /// 灰度遮罩：白色保留墨迹，黑色去掉。细密的缺墨颗粒 + 几处淡淡的不均匀。
    static func textureMask(width: Int, height: Int, pixelsPerPoint ppp: CGFloat, level: InkTexture, seed: UInt64) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var rng = SplitMix64(seed: seed)
        let areaPt = CGFloat(width * height) / max(ppp * ppp, 0.0001)
        let strength: CGFloat = level == .aged ? 1 : 0.42

        // 墨色不匀：几块大而淡的斑
        let blotches = Int(max(1, areaPt / 900) * (level == .aged ? 4 : 2))
        for _ in 0..<blotches {
            let r = CGFloat(rng.next(in: 3...9)) * ppp
            let p = CGPoint(x: CGFloat(rng.next(in: 0...1)) * CGFloat(width), y: CGFloat(rng.next(in: 0...1)) * CGFloat(height))
            let g = 1 - CGFloat(rng.next(in: 0.12...0.3)) * strength
            let colors = [CGColor(gray: g, alpha: 1), CGColor(gray: 1, alpha: 1)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
            }
        }
        // 纸纹颗粒：细小的缺墨点
        let specks = Int(areaPt * (level == .aged ? 1.6 : 0.7))
        for _ in 0..<specks {
            let r = CGFloat(rng.next(in: 0.05...0.22)) * ppp * (level == .aged ? 1.4 : 1)
            let p = CGPoint(x: CGFloat(rng.next(in: 0...1)) * CGFloat(width), y: CGFloat(rng.next(in: 0...1)) * CGFloat(height))
            ctx.setFillColor(gray: CGFloat(rng.next(in: 0...0.55)), alpha: 1)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        // 做旧：再加几道断续的缺口
        if level == .aged {
            for _ in 0..<Int(max(2, areaPt / 400)) {
                let r = CGFloat(rng.next(in: 0.3...0.8)) * ppp
                let p = CGPoint(x: CGFloat(rng.next(in: 0...1)) * CGFloat(width), y: CGFloat(rng.next(in: 0...1)) * CGFloat(height))
                ctx.setFillColor(gray: 0, alpha: 1)
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.6, width: r * 2, height: r * 1.2))
            }
        }
        return ctx.makeImage()
    }
}

/// 可复现的随机数：同一枚印章、同一次盖章，质感每次都一样。
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(nextUInt64() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}
