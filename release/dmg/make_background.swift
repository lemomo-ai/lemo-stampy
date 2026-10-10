// 生成 DMG 窗口的背景图（「糯米」风格：奶油底、软圆角、暖色、珊瑚色箭头）。
//   swift release/dmg/make_background.swift            → 写到本目录 background.png、background@2x.png
//   swift release/dmg/make_background.swift <目录>     → 写到指定目录
// 颜色和字体取自 App/Sources/Theme.swift；尺寸和图标位置要和同目录的 settings.py 对得上。
import AppKit

// MARK: 版面（单位：点，左上角为原点；settings.py 里的数字和这里一一对应）
let width: CGFloat = 640
let height: CGFloat = 400
let appCenter = CGPoint(x: 180, y: 222)    // 小章.app 的图标中心
let appsCenter = CGPoint(x: 460, y: 222)   // 「应用程序」的图标中心
let padSize = CGSize(width: 172, height: 176)
let padCenterY: CGFloat = 236              // 托盘比图标中心略低，把图标下面的名字也包进去

let hintZH = "拖到「应用程序」就装好了"
let hintEN = "Drag to Applications"

// MARK: 颜色（Theme.swift）
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let paper = hex(0xFBF1EB)
let line = hex(0xF1E1D9)
let ink = hex(0x3B2A26)
let ink2 = hex(0x7E665F)
let coral = hex(0xE0533D)
let coralSoft = hex(0xFDE3DB)
let blush = hex(0xFFB3A3)
let butter = hex(0xF7E7C6)

// MARK: 字体（Theme.nsFont：系统圆角字体 + 苹方接中文）
func roundFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    var d = base.fontDescriptor
    if let r = d.withDesign(.rounded) { d = r }
    let pingFang = weight == .semibold ? "PingFangSC-Semibold" : "PingFangSC-Regular"
    d = d.addingAttributes([.cascadeList: [NSFontDescriptor(name: pingFang, size: size)]])
    return NSFont(descriptor: d, size: size) ?? base
}

func draw(scale: CGFloat) -> NSBitmapImageRep {
    // 直接在 sRGB 里画，颜色和 Theme 里的十六进制值一致
    let cg = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                       bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // 换成左上角原点，和 Finder 的图标坐标一致
    cg.scaleBy(x: scale, y: scale)
    cg.translateBy(x: 0, y: height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    // 奶油底
    cg.setFillColor(paper.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // 角落里两团很淡的暖色光晕，让底色不那么平
    func glow(_ c: CGPoint, _ r: CGFloat, _ color: NSColor, _ alpha: CGFloat) {
        let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
        cg.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }
    glow(CGPoint(x: 40, y: 20), 260, blush, 0.22)
    glow(CGPoint(x: 620, y: 400), 300, butter, 0.45)

    // 两个白色软托盘，图标和名字放在上面
    for c in [appCenter, appsCenter] {
        let rect = CGRect(x: c.x - padSize.width / 2, y: padCenterY - padSize.height / 2,
                          width: padSize.width, height: padSize.height)
        let path = CGPath(roundedRect: rect, cornerWidth: 30, cornerHeight: 30, transform: nil)
        // Theme.card 阴影：0 4px 16px rgba(170,70,50,.08)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 16,
                     color: NSColor(srgbRed: 170 / 255, green: 70 / 255, blue: 50 / 255, alpha: 0.10).cgColor)
        cg.addPath(path)
        cg.setFillColor(NSColor.white.withAlphaComponent(0.82).cgColor)
        cg.fillPath()
        cg.restoreGState()
        cg.addPath(path)
        cg.setStrokeColor(line.cgColor)
        cg.setLineWidth(1)
        cg.strokePath()
    }

    // 珊瑚色箭头：一道往上拱的软弧线，圆头圆角
    let start = CGPoint(x: appCenter.x + padSize.width / 2 + 14, y: appCenter.y + 4)
    let end = CGPoint(x: appsCenter.x - padSize.width / 2 - 16, y: appsCenter.y + 4)
    let control = CGPoint(x: (start.x + end.x) / 2, y: appCenter.y - 26)
    let arc = CGMutablePath()
    arc.move(to: start)
    arc.addQuadCurve(to: end, control: control)
    // 箭头尖的方向 = 曲线在终点的切线方向
    let angle = atan2(end.y - control.y, end.x - control.x)
    let head: CGFloat = 13
    let headPath = CGMutablePath()
    headPath.move(to: CGPoint(x: end.x - head * cos(angle - .pi / 4.2), y: end.y - head * sin(angle - .pi / 4.2)))
    headPath.addLine(to: end)
    headPath.addLine(to: CGPoint(x: end.x - head * cos(angle + .pi / 4.2), y: end.y - head * sin(angle + .pi / 4.2)))
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    // 先画一道浅珊瑚的底影，像糯米团子的软边
    cg.saveGState()
    cg.translateBy(x: 0, y: 3)
    cg.setStrokeColor(coralSoft.cgColor)
    cg.setLineWidth(9)
    cg.addPath(arc); cg.addPath(headPath); cg.strokePath()
    cg.restoreGState()
    cg.setStrokeColor(coral.cgColor)
    cg.setLineWidth(6)
    cg.addPath(arc); cg.addPath(headPath); cg.strokePath()

    // 上方的一句话提示：中文在上，英文在下
    func centered(_ text: String, _ font: NSFont, _ color: NSColor, baselineY: CGFloat) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para,
                                                                .kern: font.pointSize * 0.02])
        let size = attr.size()
        attr.draw(at: CGPoint(x: (width - size.width) / 2, y: baselineY - size.height))
    }
    centered(hintZH, roundFont(21, .semibold), ink, baselineY: 74)
    centered(hintEN, roundFont(14, .regular), ink2, baselineY: 100)

    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
    rep.size = NSSize(width: width, height: height)   // 2x 图记成 144 dpi，Finder 才知道它是 Retina 版
    return rep
}

let outDir: URL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent()
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    let data = draw(scale: scale).representation(using: .png, properties: [:])!
    try data.write(to: outDir.appendingPathComponent(name))
    print("✓ \(outDir.appendingPathComponent(name).path)")
}
