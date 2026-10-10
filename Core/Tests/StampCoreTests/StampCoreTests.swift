import CoreGraphics
import ImageIO
import PDFKit
@testable import StampCore
import UniformTypeIdentifiers
import XCTest

final class StampCoreTests: XCTestCase {
    var dir: URL!
    let design = StampDesign(name: "测试", statement: Statement(recipient: "招商银行", purpose: "办理开户"))
    var text: StampText { design.statement.stampText(date: Date(timeIntervalSince1970: 1_790_000_000), stampID: "TEST23") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("StampCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: 文字

    func testChineseStampLines() {
        XCTAssertEqual(text.body, ["仅供招商银行办理开户使用", "他用无效"])
        XCTAssertEqual(text.meta?.hasSuffix("No.TEST23"), true)
        XCTAssertEqual(Statement().bodyLines, ["仅供指定用途使用", "他用无效"])
    }

    func testEnglishFallsBackAndBilingual() {
        let en = Statement(purpose: "签证申请", purposeEN: "visa application", phrasing: .english)
        XCTAssertEqual(en.bodyLines, ["For visa application only", "Not valid for other use"])
        let both = Statement(recipient: "法国使馆", purpose: "签证申请", purposeEN: "visa application", phrasing: .bilingual)
        XCTAssertEqual(both.bodyLines, ["仅供法国使馆签证申请使用", "For visa application only", "他用无效"])
    }

    func testCustomTextAndNoMeta() {
        let s = Statement(useCustomText: true, customText: "第一行\n\n 第二行 ", includeDate: false, includeID: false)
        let t = s.stampText(date: Date(), stampID: "X")
        XCTAssertEqual(t.body, ["第一行", "第二行"])
        XCTAssertNil(t.meta)
    }

    func testOldSavedDesignStillDecodes() throws {
        let d = try JSONDecoder().decode(StampDesign.self, from: #"{"name":"旧印章","statement":{"recipient":"A"}}"#.data(using: .utf8)!)
        XCTAssertEqual(d.name, "旧印章")
        XCTAssertEqual(d.statement.recipient, "A")
        XCTAssertEqual(d.shape, .rectangle)
        XCTAssertEqual(d.font, .songti)
    }

    func testStampSizeScalesAndRotationGrowsBounds() {
        let s1 = StampRenderer.size(text, design: design, scale: 1)
        let s2 = StampRenderer.size(text, design: design, scale: 2)
        XCTAssertEqual(s2.width, s1.width * 2, accuracy: 2)
        let mm = StampRenderer.physicalSize(text, design: design)
        XCTAssertTrue((20...45).contains(mm.width), "长章应在 2–4.5cm 宽，实际 \(mm.width)mm")
        XCTAssertTrue((8...18).contains(mm.height), "实际 \(mm.height)mm")
        var tilted = design
        tilted.rotation = 20
        XCTAssertGreaterThan(StampRenderer.boundingSize(text, design: tilted).height, s1.height)
    }

    func testEveryTemplateRendersSmall() throws {
        for t in StampTemplates.all {
            let text = t.statement.stampText(date: Date(), stampID: "A7K3Q2")
            let mm = StampRenderer.physicalSize(text, design: t)
            XCTAssertLessThanOrEqual(max(mm.width, mm.height), 40, "\(t.name) 太大：\(mm)")
            XCTAssertNotNil(StampRenderer.image(text, design: t, pixelsPerPoint: 4), t.name)
        }
    }

    func testApplyLookKeepsMyWords() {
        var mine = design
        mine.statement.includeDate = false
        mine.statement.useCustomText = true
        mine.statement.customText = "仅供本人签证使用"
        mine.statement.phrasing = .chinese
        mine.sealText = "柠檬工厂"
        var look = StampDesign(name: "模板", shape: .pill, font: .kaiti, color: .blue, fontSize: 8, rotation: 5, texture: .aged,
                               sealText: "他用无效", sealStyle: .yang)
        look.statement.includeDate = true
        look.statement.phrasing = .english
        let result = mine.applyingLook(of: look)
        XCTAssertEqual(result.id, mine.id)
        XCTAssertEqual(result.name, mine.name)
        XCTAssertEqual(result.statement, mine.statement, "文字、措辞、日期编号开关都保留自己的")
        XCTAssertEqual(result.sealText, "柠檬工厂")
        XCTAssertEqual(result.shape, .pill)
        XCTAssertEqual(result.font, .kaiti)
        XCTAssertEqual(result.color, .blue)
        XCTAssertEqual(result.rotation, 5)
        XCTAssertEqual(result.texture, .aged)
        XCTAssertEqual(result.sealStyle, .yang)
    }

    func testSquareSealGrid() {
        var d = StampDesign(name: "方", shape: .square, fontSize: 5, sealText: "他用无效")
        let four = StampRenderer.size(StampText(body: []), design: d)
        XCTAssertEqual(four.width, four.height, accuracy: 1, "四个字排成正方形")
        d.sealText = "限用"
        let two = StampRenderer.size(StampText(body: []), design: d)
        XCTAssertGreaterThan(two.height, two.width, "两个字竖排")
    }

    func testTextureIsDeterministic() {
        let a = StampRenderer.textureMask(width: 200, height: 80, pixelsPerPoint: 4, level: .light, seed: 42)
        let b = StampRenderer.textureMask(width: 200, height: 80, pixelsPerPoint: 4, level: .light, seed: 42)
        XCTAssertEqual(a?.dataProvider?.data as Data?, b?.dataProvider?.data as Data?)
    }

    // MARK: PDF

    func testPDFStampLandsOnRightPageAndSpot() throws {
        let input = try writePDF()
        let inputHash = try HistoryStore.sha256(of: input)
        let output = dir.appendingPathComponent("out.pdf")
        try DocumentStamper.stamp(input: input, output: output, placement: StampPlacement(pageIndex: 1, x: 0.25, y: 0.75),
                                  design: design, text: text)
        let doc = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(doc.pageCount, 3)
        XCTAssertEqual(doc.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 842, height: 595))
        // 原文字仍可选中（页面保持矢量，没有被转成图片）
        XCTAssertTrue(doc.page(at: 1)?.string?.contains("ORIGINALBODY") == true)
        XCTAssertFalse(hasRed(try render(doc.page(at: 0)!, scale: 3), near: CGPoint(x: 0.25, y: 0.75)), "其他页不受影响")

        // 印章中心应在 (25%, 从上 75%) 处：那里有红色像素，对角的位置没有
        let image = try render(doc.page(at: 1)!, scale: 3)
        XCTAssertTrue(hasRed(image, near: CGPoint(x: 0.25, y: 0.75)))
        XCTAssertFalse(hasRed(image, near: CGPoint(x: 0.75, y: 0.25)))

        XCTAssertEqual(try HistoryStore.sha256(of: input), inputHash, "原文件一个字节都不能变")
    }

    /// 白文方印的字要从印面上「刻」空：PDF 里不支持 .clear 混合，以前盖出来是一整块实心色。
    func testYinSealCarvesCharactersInPDF() throws {
        for texture in [InkTexture.clean, .light] {
            let seal = StampDesign(name: "方", shape: .square, font: .weibei, opacity: 1, fontSize: 9.6, texture: texture,
                                   sealText: "柠檬工厂", sealStyle: .yin)
            let input = try writePDF()
            let output = dir.appendingPathComponent("seal-\(texture.rawValue).pdf")
            let scale = 4.0
            try DocumentStamper.stamp(input: input, output: output, placement: StampPlacement(pageIndex: 0, x: 0.5, y: 0.5, scale: scale),
                                      design: seal, text: StampText(body: []))
            let page = try XCTUnwrap(PDFDocument(url: output)?.page(at: 0))
            let image = try render(page, scale: 2)
            let side = StampRenderer.size(StampText(body: []), design: seal, scale: scale).width * 2
            let (red, white) = countRedAndWhite(image, center: CGPoint(x: image.width / 2, y: image.height / 2), half: Int(side * 0.4))
            XCTAssertGreaterThan(red, 0, "\(texture)：印面是红的")
            XCTAssertGreaterThan(Double(white) / Double(red + white), 0.15, "\(texture)：字被刻空，露出白纸")
        }
    }

    func testEveryPageStampsSameRelativeSpotAndSkipsOthers() throws {
        let input = try writePDF()
        let output = dir.appendingPathComponent("all.pdf")
        let base = StampPlacement(pageIndex: 1, x: 0.25, y: 0.75)
        var progress: [Int] = []
        try DocumentStamper.stamp(input: input, output: output, placements: [base.onPage(0), base, base.onPage(1)],
                                  design: design, text: text) { done, total in progress.append(done); XCTAssertEqual(total, 2) }
        XCTAssertEqual(progress, [1, 2], "重复的页只盖一次")
        let doc = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(doc.pageCount, 3)
        XCTAssertTrue(hasRed(try render(doc.page(at: 0)!, scale: 3), near: CGPoint(x: 0.25, y: 0.75)))
        XCTAssertTrue(hasRed(try render(doc.page(at: 1)!, scale: 3), near: CGPoint(x: 0.25, y: 0.75)))
        XCTAssertFalse(hasRed(try render(doc.page(at: 2)!, scale: 3), near: CGPoint(x: 0.25, y: 0.75)), "没选的页不动")
        XCTAssertTrue(doc.page(at: 0)?.string?.contains("ORIGINALBODY") == true)
    }

    func testStampNeverHangsOffThePage() {
        let page = CGSize(width: 600, height: 800), stamp = CGSize(width: 120, height: 20)
        let edge = StampPlacement(pageIndex: 0, x: 0.99, y: 0.01)
        XCTAssertEqual(DocumentStamper.center(for: edge, pageSize: page, stampSize: stamp), CGPoint(x: 540, y: 790), "点的那一页也往里推")
        XCTAssertEqual(DocumentStamper.center(for: edge.onPage(3), pageSize: page, stampSize: stamp), CGPoint(x: 540, y: 790))
        let inside = edge.keptInside(pageSize: page, stampSize: stamp)
        XCTAssertEqual(inside.x, 0.9, accuracy: 1e-9)
        XCTAssertEqual(inside.y, 0.0125, accuracy: 1e-9)
        let middle = StampPlacement(x: 0.5, y: 0.5)
        XCTAssertEqual(middle.keptInside(pageSize: page, stampSize: stamp), middle, "不靠边就不动")
        XCTAssertEqual(StampRecord.pagesLabel([1]), "第 2 页")
        XCTAssertEqual(StampRecord.pagesLabel([4, 0, 1, 2, 3]), "第 1–5 页")
        XCTAssertEqual(StampRecord.pagesLabel([0, 2]), "第 1、3 页")
    }

    func testRotatedPagePlacementFollowsDisplayedOrientation() throws {
        let input = try writePDF()
        let output = dir.appendingPathComponent("rot.pdf")
        try DocumentStamper.stamp(input: input, output: output, placement: StampPlacement(pageIndex: 2, x: 0.8, y: 0.2),
                                  design: design, text: text)
        let page = try XCTUnwrap(PDFDocument(url: output)?.page(at: 2))
        XCTAssertEqual(DocumentStamper.displaySize(of: page), CGSize(width: 842, height: 595))
        let image = try render(page, scale: 3)
        XCTAssertTrue(hasRed(image, near: CGPoint(x: 0.8, y: 0.2)))
        XCTAssertFalse(hasRed(image, near: CGPoint(x: 0.2, y: 0.8)))
    }

    func testEncryptedPDFAndBadPage() throws {
        let input = try writePDF()
        let locked = dir.appendingPathComponent("locked.pdf")
        XCTAssertTrue(PDFDocument(url: input)!.write(to: locked, withOptions: [.userPasswordOption: "1234", .ownerPasswordOption: "o"]))
        XCTAssertThrowsError(try DocumentStamper.stamp(input: locked, output: dir.appendingPathComponent("x.pdf"),
                                                       placement: StampPlacement(x: 0.5, y: 0.5), design: design, text: text)) {
            XCTAssertEqual($0 as? StampError, .encryptedPDF("locked.pdf"))
        }
        XCTAssertFalse(DocumentStamper.unlock(locked, password: "wrong"))
        XCTAssertNil(PDFPasswords.password(for: locked), "密码不对就不记")

        // 输对密码后照常盖，副本用同一个密码加密。
        XCTAssertTrue(DocumentStamper.unlock(locked, password: "1234"))
        let output = dir.appendingPathComponent("unlocked.pdf")
        try DocumentStamper.stamp(input: locked, output: output, placement: StampPlacement(x: 0.5, y: 0.5), design: design, text: text)
        let copy = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertTrue(copy.isLocked, "副本也要密码")
        XCTAssertFalse(copy.unlock(withPassword: ""))
        XCTAssertTrue(copy.unlock(withPassword: "1234"))
        XCTAssertTrue(hasRed(try render(copy.page(at: 0)!, scale: 2), near: CGPoint(x: 0.5, y: 0.5)))

        XCTAssertThrowsError(try DocumentStamper.stamp(input: input, output: dir.appendingPathComponent("y.pdf"),
                                                       placement: StampPlacement(pageIndex: 9, x: 0.5, y: 0.5), design: design, text: text)) {
            XCTAssertEqual($0 as? StampError, .pageOutOfRange(9))
        }
    }

    func testNeverWritesOverInput() throws {
        let input = try writePDF()
        XCTAssertThrowsError(try DocumentStamper.stamp(input: input, output: input, placement: StampPlacement(x: 0.5, y: 0.5),
                                                       design: design, text: text))
    }

    // MARK: 照片

    func testPhotoOrientationPlacementAndMetadata() throws {
        // 横着存、EXIF 说要顺时针转 90° 的「竖拍」照片
        let input = try writeImage(width: 3600, height: 2400, type: .jpeg, name: "photo.jpg", props: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 39.9, kCGImagePropertyGPSLatitudeRef: "N"],
        ])
        XCTAssertEqual(try DocumentStamper.pageSize(of: input), CGSize(width: 2400, height: 3600))
        let output = dir.appendingPathComponent("out.jpg")
        try DocumentStamper.stamp(input: input, output: output, placement: StampPlacement(x: 0.3, y: 0.8), design: design, text: text)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 2400)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 3600)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary], "副本不应带 GPS")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertTrue(hasRed(image, near: CGPoint(x: 0.3, y: 0.8)))
        XCTAssertFalse(hasRed(image, near: CGPoint(x: 0.7, y: 0.2)))
    }

    func testImageFormatFollowsOutputExtension() throws {
        let input = try writeImage(width: 400, height: 300, type: .heic, name: "p.heic")
        let heic = dir.appendingPathComponent("a.heic"), png = dir.appendingPathComponent("a.png")
        try DocumentStamper.stamp(input: input, output: heic, placement: StampPlacement(x: 0.5, y: 0.5), design: design, text: text)
        try DocumentStamper.stamp(input: input, output: png, placement: StampPlacement(x: 0.5, y: 0.5), design: design, text: text)
        XCTAssertEqual(type(of: heic), .heic)
        XCTAssertEqual(type(of: png), .png)
    }

    func testImageStampLooksSameSizeAtAnyResolution() {
        let small = DocumentStamper.unitsPerPoint(kind: .image, pageSize: CGSize(width: 842, height: 595))
        let big = DocumentStamper.unitsPerPoint(kind: .image, pageSize: CGSize(width: 8420, height: 5950))
        XCTAssertEqual(small, 1, accuracy: 0.001)
        XCTAssertEqual(big, 10, accuracy: 0.001)
    }

    // MARK: 命名 / 记录

    func testSuggestedNameNeverCollides() throws {
        let input = try writePDF()
        let first = DocumentStamper.suggestedOutputURL(for: input)
        XCTAssertEqual(first.lastPathComponent, "doc_已盖章.pdf")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        XCTAssertEqual(DocumentStamper.suggestedOutputURL(for: input).lastPathComponent, "doc_已盖章 2.pdf")
    }

    func testHistoryFindsStampedCopy() throws {
        let input = try writePDF()
        let output = dir.appendingPathComponent("o.pdf")
        try DocumentStamper.stamp(input: input, output: output, placement: StampPlacement(x: 0.5, y: 0.5), design: design, text: text)
        let store = HistoryStore(fileURL: dir.appendingPathComponent("h/history.json"))
        try store.append(StampRecord(id: "TEST23", date: Date(), recipient: "招商银行", purpose: "办理开户", lines: text.allLines,
                                     files: [StampedFile(sourceName: "doc.pdf", outputPath: output.path, sha256: try HistoryStore.sha256(of: output))]))
        XCTAssertEqual(store.find(fileAt: output)?.record.id, "TEST23")
        XCTAssertNil(store.find(fileAt: input))
    }

    func testStampIDAlphabet() {
        let id = StampID.make()
        XCTAssertEqual(id.count, 6)
        XCTAssertTrue(id.allSatisfy { StampID.alphabet.contains($0) })
    }

    // MARK: helpers

    private func type(of url: URL) -> UTType? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }.flatMap { UTType($0) }
    }

    private func writeImage(width: Int, height: Int, type: UTType, name: String, props: [CFString: Any] = [:]) throws -> URL {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = dir.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    /// 三页：A4 竖、A4 横、A4 竖但 /Rotate 90。
    private func writePDF() throws -> URL {
        let url = dir.appendingPathComponent("doc.pdf")
        var a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &a4, nil))
        for box in [a4, CGRect(x: 0, y: 0, width: 842, height: 595), a4] {
            var b = box
            ctx.beginPage(mediaBox: &b)
            let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "ORIGINALBODY", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ]))
            ctx.textPosition = CGPoint(x: 60, y: box.height / 2)
            CTLineDraw(line, ctx)
            ctx.endPage()
        }
        ctx.closePDF()
        let doc = try XCTUnwrap(PDFDocument(url: url))
        doc.page(at: 2)?.rotation = 90
        XCTAssertTrue(doc.write(to: url))
        return url
    }

    private func render(_ page: PDFPage, scale: CGFloat) throws -> CGImage {
        let size = DocumentStamper.displaySize(of: page)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: ctx)
        return try XCTUnwrap(ctx.makeImage())
    }

    /// 以 `center`（像素）为中心、边长 2×`half` 的方块里，红色像素和白色像素各有多少。
    private func countRedAndWhite(_ image: CGImage, center: CGPoint, half: Int) -> (red: Int, white: Int) {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var red = 0, white = 0
        for y in max(0, Int(center.y) - half)..<min(h, Int(center.y) + half) {
            for x in max(0, Int(center.x) - half)..<min(w, Int(center.x) + half) {
                let i = (y * w + x) * 4
                let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
                if r - g > 60, r - b > 60 { red += 1 } else if r > 235, g > 235, b > 235 { white += 1 }
            }
        }
        return (red, white)
    }

    /// `rel` 是相对位置（从左、从上），在它周围 6% 范围内找明显的红色像素。
    private func hasRed(_ image: CGImage, near rel: CGPoint) -> Bool {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let cx = Int(rel.x * Double(w)), cy = Int(rel.y * Double(h)) // 内存里第 0 行是图像顶部
        let rx = max(4, w * 6 / 100), ry = max(4, h * 6 / 100)
        for y in max(0, cy - ry)..<min(h, cy + ry) {
            for x in max(0, cx - rx)..<min(w, cx + rx) {
                let i = (y * w + x) * 4
                if Int(data[i]) - Int(data[i + 1]) > 60, Int(data[i]) - Int(data[i + 2]) > 60 { return true }
            }
        }
        return false
    }
}
