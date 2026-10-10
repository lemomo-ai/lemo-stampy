// 生成一套盖章测试文件：单页 / 多页 / 混合尺寸 / 旋转页 / 加密 PDF，以及横拍、竖拍（EXIF 旋转）、PNG、HEIC 照片。
// 内容都是明显的「样例」文字，不含任何真实个人信息。
//   swift scripts/make_test_files.swift 小印章测试/样例   （在项目根目录运行；不写目录就是这个）
import AppKit
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let arg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "小印章测试/样例"
let out = URL(fileURLWithPath: (arg as NSString).expandingTildeInPath, isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let A4 = CGSize(width: 595, height: 842)
let A4L = CGSize(width: 842, height: 595)
let A5 = CGSize(width: 420, height: 595)

// MARK: 文字

func draw(_ text: String, at p: CGPoint, size: CGFloat, bold: Bool = false, gray: CGFloat = 0.15, in ctx: CGContext) {
    let font = CTFontCreateWithName((bold ? "PingFangSC-Semibold" : "PingFangSC-Regular") as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: gray, alpha: 1)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    ctx.textPosition = p
    CTLineDraw(line, ctx)
}

/// 一页「文件」：标题、正文若干行、底部页码和「样例」水印。y 轴向上。
func drawPage(_ ctx: CGContext, size: CGSize, title: String, page: Int, total: Int, rows: [String]) {
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))
    let m: CGFloat = size.width > 500 ? 60 : 40
    var y = size.height - m - 10
    draw(title, at: CGPoint(x: m, y: y), size: 20, bold: true, in: ctx)
    y -= 18
    draw("测试样例 · 内容均为虚构，仅用于试用小章", at: CGPoint(x: m, y: y), size: 9, gray: 0.55, in: ctx)
    y -= 14
    ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
    ctx.fill(CGRect(x: m, y: y, width: size.width - m * 2, height: 0.8))
    y -= 28
    for row in rows {
        guard y > m + 40 else { break }
        draw(row, at: CGPoint(x: m, y: y), size: 11.5, in: ctx)
        y -= 22
    }
    draw("第 \(page) 页 / 共 \(total) 页", at: CGPoint(x: size.width / 2 - 34, y: m / 2 + 4), size: 9, gray: 0.5, in: ctx)
    // 右下角一个签字栏，方便试「盖在签名旁边」。
    ctx.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
    ctx.setLineWidth(0.8)
    ctx.stroke(CGRect(x: size.width - m - 170, y: m + 20, width: 170, height: 46))
    draw("签字 / 日期", at: CGPoint(x: size.width - m - 164, y: m + 52), size: 9, gray: 0.5, in: ctx)
}

let body = [
    "兹证明 张三（样例）同志系本单位正式员工，自 2020 年 3 月起在本单位工作至今。",
    "现任职务：产品设计师（样例）。",
    "该员工近十二个月税前月平均收入为人民币 ×××× 元（样例数字）。",
    "本证明仅用于办理相关手续，不作其他用途。",
    "",
    "特此证明。",
    "",
    "样例单位名称：示例科技有限公司（虚构）",
    "联系电话：000-0000-0000（虚构）",
    "开具日期：2026 年 10 月 7 日",
]

func contractRows(_ page: Int) -> [String] {
    let clauses = ["房屋基本情况", "租赁期限", "租金及支付方式", "押金", "房屋使用与维修", "费用承担", "转租与续租", "违约责任", "争议解决", "其他约定"]
    var rows: [String] = []
    for i in 0..<4 {
        let n = (page - 1) * 4 + i + 1
        rows.append("第 \(n) 条　\(clauses[(n - 1) % clauses.count])（样例条款）")
        rows.append("　　甲乙双方就本条事项约定如下：本段文字为虚构样例，用来模拟合同正文的排版。")
        rows.append("　　具体内容以双方实际签署的合同为准，本测试文件不具任何法律效力。")
        rows.append("")
    }
    return rows
}

func statementRows(_ page: Int) -> [String] {
    var rows = ["日期　　　　　摘要　　　　　　收入　　　　支出　　　　余额（均为样例数字）"]
    for d in 0..<22 {
        let day = (page - 1) * 22 + d + 1
        rows.append(String(format: "2026-%02d-%02d　　样例交易 %03d　　　%@　　　　%@　　　　××××", (day / 28) % 12 + 1, day % 28 + 1, day,
                           day % 3 == 0 ? "+×××" : "　　", day % 3 == 0 ? "　　" : "-××"))
    }
    return rows
}

// MARK: PDF

func writePDF(_ name: String, pages: [(CGSize, (CGContext, CGSize, Int) -> Void)], options: [CFString: Any] = [:]) -> URL {
    let url = out.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    var box = CGRect(origin: .zero, size: A4)
    let ctx = CGContext(url as CFURL, mediaBox: &box, options as CFDictionary)!
    for (i, (size, drawPage)) in pages.enumerated() {
        var media = CGRect(origin: .zero, size: size)
        let info = [kCGPDFContextMediaBox: NSData(bytes: &media, length: MemoryLayout<CGRect>.size)] as CFDictionary
        ctx.beginPDFPage(info)
        drawPage(ctx, size, i + 1)
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return url
}

_ = writePDF("01_单页_收入证明（样例）.pdf", pages: [(A4, { ctx, s, p in
    drawPage(ctx, size: s, title: "收入证明（样例）", page: p, total: 1, rows: body)
})])

_ = writePDF("02_多页_租房合同（样例）_6页.pdf", pages: (1...6).map { n in (A4, { ctx, s, p in
    drawPage(ctx, size: s, title: n == 1 ? "房屋租赁合同（样例）" : "房屋租赁合同（样例）· 续", page: p, total: 6, rows: contractRows(p))
}) })

_ = writePDF("03_多页_银行流水（样例）_12页.pdf", pages: (1...12).map { _ in (A4, { ctx, s, p in
    drawPage(ctx, size: s, title: "账户交易明细（样例）", page: p, total: 12, rows: statementRows(p))
}) })

_ = writePDF("04_多页_混合尺寸（A4竖_A4横_A5）.pdf", pages: [
    (A4, { ctx, s, p in drawPage(ctx, size: s, title: "第 1 页：A4 竖版", page: p, total: 3, rows: body) }),
    (A4L, { ctx, s, p in drawPage(ctx, size: s, title: "第 2 页：A4 横版（试「每一页都盖」的比例换算）", page: p, total: 3, rows: statementRows(1)) }),
    (A5, { ctx, s, p in drawPage(ctx, size: s, title: "第 3 页：A5 小页", page: p, total: 3, rows: Array(body.prefix(6))) }),
])

// 旋转页：第 2 页带 /Rotate 90，「预览」里看到的是横的。
let rotatedSource = writePDF(".tmp_rotate.pdf", pages: (1...3).map { _ in (A4, { ctx, s, p in
    drawPage(ctx, size: s, title: p == 2 ? "这一页被旋转了 90°（/Rotate）" : "旋转页测试", page: p, total: 3, rows: body)
}) })
if let doc = PDFDocument(url: rotatedSource) {
    doc.page(at: 1)?.rotation = 90
    doc.write(to: out.appendingPathComponent("05_旋转页（第2页转了90度）.pdf"))
}
try? FileManager.default.removeItem(at: rotatedSource)

// 加密 PDF：打开要密码 1234，用来看「这份 PDF 加了密码」的提示。
_ = writePDF("06_加了密码（密码1234）.pdf", pages: [(A4, { ctx, s, p in
    drawPage(ctx, size: s, title: "加密 PDF（样例）", page: p, total: 1, rows: ["打开密码：1234", "小章不会去解密码：应该看到「这份 PDF 加了密码」的提示。"])
})], options: [kCGPDFContextUserPassword: "1234", kCGPDFContextOwnerPassword: "owner-1234"])

// MARK: 照片

func makePhoto(width: Int, height: Int, title: String, lines: [String]) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // 桌面底色 + 一张略微倾斜的「纸」，像手机拍的材料。
    ctx.setFillColor(CGColor(srgbRed: 0.72, green: 0.68, blue: 0.63, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let w = CGFloat(width), h = CGFloat(height)
    let paper = CGRect(x: w * 0.12, y: h * 0.1, width: w * 0.76, height: h * 0.8)
    ctx.saveGState()
    ctx.translateBy(x: paper.midX, y: paper.midY)
    ctx.rotate(by: -0.012)
    ctx.translateBy(x: -paper.midX, y: -paper.midY)
    ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.004), blur: w * 0.02, color: CGColor(gray: 0, alpha: 0.35))
    ctx.setFillColor(CGColor(srgbRed: 0.98, green: 0.97, blue: 0.95, alpha: 1))
    ctx.fill(paper)
    ctx.setShadow(offset: .zero, blur: 0)
    let s = paper.width / 595
    var y = paper.maxY - 70 * s
    draw(title, at: CGPoint(x: paper.minX + 50 * s, y: y), size: 22 * s, bold: true, in: ctx)
    y -= 26 * s
    draw("测试样例 · 内容均为虚构", at: CGPoint(x: paper.minX + 50 * s, y: y), size: 10 * s, gray: 0.5, in: ctx)
    y -= 40 * s
    for line in lines {
        draw(line, at: CGPoint(x: paper.minX + 50 * s, y: y), size: 13 * s, in: ctx)
        y -= 26 * s
    }
    ctx.restoreGState()
    return ctx.makeImage()!
}

func writeImage(_ image: CGImage, _ name: String, type: UTType, orientation: Int = 1) {
    let url = out.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    var props: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
    if type != .png { props[kCGImageDestinationLossyCompressionQuality] = 0.9 }
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}

writeImage(makePhoto(width: 4032, height: 3024, title: "毕业证书复印件（样例）", lines: ["本页为虚构样例，用来试横拍照片。", "盖章后副本不带 GPS、拍摄设备信息。"]),
           "07_照片_横拍（样例）.jpg", type: .jpeg)

// 竖拍：像素按横的存，EXIF 方向 6（顺时针转 90° 显示），「预览」里是竖的。
let portrait = makePhoto(width: 3024, height: 4032, title: "学历证明（样例）· 竖拍", lines: ["这张照片带 EXIF 旋转。", "盖出来的章应该是正的，不会歪 90°。"])
let rotatedPixels: CGImage = {
    let ctx = CGContext(data: nil, width: portrait.height, height: portrait.width, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: CGFloat(portrait.height), y: 0)
    ctx.rotate(by: .pi / 2)
    ctx.draw(portrait, in: CGRect(x: 0, y: 0, width: portrait.width, height: portrait.height))
    return ctx.makeImage()!
}()
writeImage(rotatedPixels, "08_照片_竖拍_EXIF旋转（样例）.jpg", type: .jpeg, orientation: 6)

writeImage(makePhoto(width: 1600, height: 1200, title: "截图（样例）", lines: ["PNG 格式，副本也是 PNG。"]), "09_截图（样例）.png", type: .png)
writeImage(makePhoto(width: 3024, height: 4032, title: "证明材料（样例）· HEIC", lines: ["HEIC 格式（iPhone 默认）。"]), "10_照片（样例）.heic", type: .heic)

print("✓ 测试文件已生成：\(out.path)")
