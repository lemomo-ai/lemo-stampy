import CoreGraphics
import CryptoKit
import ImageIO
import PDFKit
@testable import StampCore
import UniformTypeIdentifiers
import XCTest

/// 批量盖章：计划（存到哪、盖哪几页、跳过谁）和真的盖出来。
final class BatchStamperTests: XCTestCase {
    var dir: URL!
    let design = StampDesign(name: "测试", statement: Statement(purpose: "签证申请"))
    var text: StampText { design.statement.stampText(date: Date(timeIntervalSince1970: 1_790_000_000), stampID: "BATCH2") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("BatchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: 计划

    func testPagesModes() {
        XCTAssertEqual(BatchPages.first.pageIndices(count: 5), [0])
        XCTAssertEqual(BatchPages.last.pageIndices(count: 5), [4])
        XCTAssertEqual(BatchPages.all.pageIndices(count: 3), [0, 1, 2])
        XCTAssertEqual(BatchPages.all.pageIndices(count: 0), [])
    }

    func testPlanBesideOriginalsWithPagesAndSkips() throws {
        let three = try writePDF("流水.pdf", pages: 3)
        let one = try writePDF("护照.pdf", pages: 1)
        let photo = try writePhoto("身份证.jpg")
        let word = dir.appendingPathComponent("说明.docx")
        try Data("x".utf8).write(to: word)
        let locked = try writePDF("工资.pdf", pages: 2, password: "1234")

        let plan = BatchStamper.plan(inputs: [three, one, photo, word, locked, three], position: .bottomRight, scale: 1, pages: .last)
        XCTAssertEqual(plan.items.map(\.input.lastPathComponent), ["流水.pdf", "护照.pdf", "身份证.jpg"], "重复拖进来的只算一次")
        XCTAssertEqual(plan.items[0].placements.map(\.pageIndex), [2], "最后一页")
        XCTAssertEqual(plan.items[1].placements.map(\.pageIndex), [0])
        XCTAssertEqual(plan.items[2].placements.map(\.pageIndex), [0], "照片只有一页")
        XCTAssertEqual(plan.items[0].output.lastPathComponent, "流水_已盖章.pdf")
        XCTAssertEqual(plan.items[0].output.deletingLastPathComponent().standardizedFileURL, dir.standardizedFileURL, "默认存在原文件旁边")
        XCTAssertEqual(plan.skipped, [BatchSkip(input: word, reason: .unsupported), BatchSkip(input: locked, reason: .needsPassword)])

        // 输了密码之后就能排进去了。
        XCTAssertTrue(DocumentStamper.unlock(locked, password: "1234"))
        let again = BatchStamper.plan(inputs: [locked], position: .bottomRight, scale: 1, pages: .all)
        XCTAssertEqual(again.items.first?.placements.map(\.pageIndex), [0, 1])
    }

    func testOverrideAndScale() throws {
        let a = try writePDF("a.pdf", pages: 1)
        let b = try writePDF("b.pdf", pages: 1)
        let mine = RelativePoint(x: 0.3, y: 0.4)
        let plan = BatchStamper.plan(inputs: [a, b], position: .bottomRight, scale: 1.5, pages: .first,
                                     overrides: [b.standardizedFileURL.path: mine])
        XCTAssertEqual(plan.items[0].placements[0].x, RelativePoint.bottomRight.x)
        XCTAssertEqual(plan.items[1].placements[0].x, 0.3, "单独调过的那份用自己的位置")
        XCTAssertEqual(plan.items[1].placements[0].y, 0.4)
        XCTAssertTrue(plan.items.allSatisfy { $0.placements[0].scale == 1.5 })
    }

    /// 存到同一个文件夹时，不同文件夹里的同名文件不能互相覆盖；磁盘上已有的也不覆盖。
    func testOutputNamesNeverCollide() throws {
        let sub1 = dir.appendingPathComponent("一"), sub2 = dir.appendingPathComponent("二")
        try FileManager.default.createDirectory(at: sub1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sub2, withIntermediateDirectories: true)
        let first = try writePDF("一/合同.pdf", pages: 1)
        let second = try writePDF("二/合同.pdf", pages: 1)
        let out = dir.appendingPathComponent("已盖章")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try Data().write(to: out.appendingPathComponent("合同_已盖章.pdf"))
        let plan = BatchStamper.plan(inputs: [first, second], position: .bottomRight, scale: 1, pages: .first, outputDirectory: out)
        XCTAssertEqual(plan.items.map(\.output.lastPathComponent), ["合同_已盖章 2.pdf", "合同_已盖章 3.pdf"])
    }

    func testAnchorsStayInsideGrid() {
        XCTAssertEqual(RelativePoint.anchor(column: 0, row: 0), RelativePoint(x: 0.18, y: 0.18))
        XCTAssertEqual(RelativePoint.anchor(column: 9, row: -3), RelativePoint(x: 0.82, y: 0.18))
        XCTAssertEqual(RelativePoint(x: 2, y: -1), RelativePoint(x: 1, y: 0), "超出范围的夹回 0…1")
    }

    // MARK: 真的盖

    func testRunStampsEveryFileLeavesOriginalsAndKeepsGoing() throws {
        let three = try writePDF("流水.pdf", pages: 3)
        let photo = try writePhoto("身份证.jpg")
        let doomed = try writePDF("会消失.pdf", pages: 1)
        let originals = try [three, photo].map { try sha(of: $0) }

        var plan = BatchStamper.plan(inputs: [three, doomed, photo], position: .bottomRight, scale: 1, pages: .all)
        XCTAssertEqual(plan.items.count, 3)
        try FileManager.default.removeItem(at: doomed) // 计划之后文件没了：这一份失败，后面的照盖
        var progress: [Int] = []
        let outcomes = BatchStamper.run(plan, design: design, text: text) { done, _ in progress.append(done) }
        XCTAssertEqual(progress, [1, 2, 3])
        XCTAssertEqual(outcomes.map(\.succeeded), [true, false, true])
        XCTAssertNotNil(outcomes[1].error)
        XCTAssertEqual(try [three, photo].map { try sha(of: $0) }, originals, "原件一个字节都不能变")

        let copy = try XCTUnwrap(PDFDocument(url: outcomes[0].output))
        XCTAssertEqual(copy.pageCount, 3)
        for i in 0..<3 {
            XCTAssertTrue(hasRed(try render(copy.page(at: i)!), near: CGPoint(x: 0.82, y: 0.82)), "第 \(i + 1) 页右下角应该有章")
            XCTAssertFalse(hasRed(try render(copy.page(at: i)!), near: CGPoint(x: 0.2, y: 0.2)), "左上角不该有")
        }
        XCTAssertEqual(outcomes[0].pages, [0, 1, 2])
        XCTAssertEqual(outcomes[0].sha256, try sha(of: outcomes[0].output))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcomes[2].output.path))
        XCTAssertNil(outcomes[2].pages, "照片不记页码")
        plan.items.removeAll()
        XCTAssertEqual(BatchStamper.run(plan, design: design, text: text), [])
    }

    func testOneRecordPerBatch() throws {
        let a = try writePDF("a.pdf", pages: 2)
        let b = try writePDF("b.pdf", pages: 1)
        let outcomes = BatchStamper.run(BatchStamper.plan(inputs: [a, b], position: .bottomRight, scale: 1, pages: .all),
                                        design: design, text: text)
        let record = try XCTUnwrap(BatchStamper.record(for: outcomes, id: "BATCH2", date: Date(), design: design, text: text))
        XCTAssertEqual(record.id, "BATCH2")
        XCTAssertEqual(record.files.map(\.sourceName), ["a.pdf", "b.pdf"])
        XCTAssertEqual(record.files[0].pagesLabel, "第 1–2 页")
        XCTAssertEqual(record.purpose, "签证申请")
        XCTAssertNil(record.pages, "多份时页码记在每份文件上")

        // 记录能存能读，并且能按指纹找回是哪一份。
        let history = HistoryStore(fileURL: dir.appendingPathComponent("history.json"))
        try history.append(record)
        XCTAssertEqual(history.load().first?.files[0].pages, [0, 1])
        XCTAssertEqual(try history.find(fileAt: outcomes[1].output)?.file.sourceName, "b.pdf")

        let failed = [BatchOutcome(input: a, output: a, sha256: nil, error: "x", pages: nil)]
        XCTAssertNil(BatchStamper.record(for: failed, id: "X", date: Date(), design: design, text: text), "一份都没盖上就不记")
    }

    /// 照片也一样：位置给到最角上，章往里推，整枚留在照片里。
    func testPhotoCornerStampStaysInside() throws {
        let photo = try writePhoto("角落.jpg")
        let output = dir.appendingPathComponent("角落_已盖章.jpg")
        try DocumentStamper.stamp(input: photo, output: output, placement: StampPlacement(x: 1, y: 1), design: design, text: text)
        let image = try DocumentStamper.pageImage(of: output, maxPixel: 1200)
        XCTAssertTrue(hasRed(image, near: CGPoint(x: 0.9, y: 0.92)), "推回来以后，右下角里面应该看得到章")
        XCTAssertEqual(image.width, 1200)
    }

    // MARK: 工具

    private func writePDF(_ name: String, pages: Int, password: String? = nil) throws -> URL {
        let url = dir.appendingPathComponent(name)
        var a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &a4, nil))
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
            ctx.fill(CGRect(x: 60, y: 400, width: 300, height: 10))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        if let password {
            XCTAssertTrue(PDFDocument(url: url)!.write(to: url, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password]))
        }
        return url
    }

    private func writePhoto(_ name: String) throws -> URL {
        let ctx = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        let url = dir.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func sha(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func render(_ page: PDFPage) throws -> CGImage {
        let size = DocumentStamper.displaySize(of: page)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        page.draw(with: .cropBox, to: ctx)
        return try XCTUnwrap(ctx.makeImage())
    }

    /// `rel` 是相对位置（从左、从上），在它周围 8% 范围内找明显的红色像素。
    private func hasRed(_ image: CGImage, near rel: CGPoint) -> Bool {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let cx = Int(rel.x * Double(w)), cy = Int(rel.y * Double(h))
        let rx = w * 8 / 100, ry = h * 8 / 100
        for y in max(0, cy - ry)..<min(h, cy + ry) {
            for x in max(0, cx - rx)..<min(w, cx + rx) {
                let i = (y * w + x) * 4
                if Int(data[i]) - Int(data[i + 1]) > 60, Int(data[i]) - Int(data[i + 2]) > 60 { return true }
            }
        }
        return false
    }
}
