import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum StampError: LocalizedError, Equatable {
    case unsupportedType(String)
    case unreadable(String)
    case encryptedPDF(String)
    case pageOutOfRange(Int)
    case renderFailed
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let name): return L("不支持的文件类型：%@（支持 PDF、JPG、PNG、HEIC）", name)
        case .unreadable(let name): return L("无法读取文件：%@", name)
        case .encryptedPDF(let name): return L("PDF 有密码保护：%@。请先在「预览」里解除密码。", name)
        case .pageOutOfRange(let index): return L("找不到第 %ld 页", index + 1)
        case .renderFailed: return L("印章绘制失败")
        case .writeFailed(let name): return L("无法写入文件：%@", name)
        }
    }
}

public enum DocumentKind: Equatable, Sendable {
    case pdf
    case image
}

/// 印章盖在哪：第几页，以及在这一页上的相对位置（0…1，从左、从上量起，按屏幕上看到的方向）。
public struct StampPlacement: Equatable, Sendable {
    public var pageIndex: Int
    public var x: Double
    public var y: Double
    /// 用户在盖章时用滚轮调的大小倍率。
    public var scale: Double
    public init(pageIndex: Int = 0, x: Double, y: Double, scale: Double = 1) {
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
        self.scale = scale
    }

    /// 同一个相对位置换到另一页。
    public func onPage(_ index: Int) -> StampPlacement {
        StampPlacement(pageIndex: index, x: x, y: y, scale: scale)
    }

    /// 往里推到整枚章都在页面里（相对位置）。`stampSize` 是旋转后的外接尺寸（文档单位）。
    public func keptInside(pageSize: CGSize, stampSize: CGSize) -> StampPlacement {
        let c = DocumentStamper.center(for: self, pageSize: pageSize, stampSize: stampSize)
        var result = self
        result.x = Double(c.x / max(pageSize.width, 1))
        result.y = Double(1 - c.y / max(pageSize.height, 1))
        return result
    }
}

public enum DocumentStamper {
    /// 照片没有物理尺寸：把长边当作 A4 长边（842pt）来换算，印章在任何分辨率的照片上看起来都一样大。
    public static let imageReferenceLongSide: CGFloat = 842

    public static func kind(of url: URL) -> DocumentKind? {
        // 先只看扩展名，不碰文件本身：在桌面 / 文稿里的文件，一读就可能触发系统授权框。
        let type = UTType(filenameExtension: url.pathExtension)
            ?? (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        guard let type else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image), !type.conforms(to: .svg) { return .image }
        return nil
    }

    /// 页面在阅读器里显示的尺寸：PDF 用点（考虑 /Rotate），照片用像素（考虑 EXIF 方向）。
    public static func pageSize(of url: URL, pageIndex: Int = 0) throws -> CGSize {
        switch kind(of: url) {
        case .pdf:
            let doc = try openPDF(url)
            guard let page = doc.page(at: pageIndex) else { throw StampError.pageOutOfRange(pageIndex) }
            return displaySize(of: page)
        case .image:
            return try imagePixelSize(url)
        case nil:
            throw StampError.unsupportedType(url.lastPathComponent)
        }
    }

    /// 一个「印章点」等于多少个文档单位。
    public static func unitsPerPoint(kind: DocumentKind, pageSize: CGSize) -> CGFloat {
        switch kind {
        case .pdf: return 1
        case .image: return max(pageSize.width, pageSize.height) / imageReferenceLongSide
        }
    }

    /// 在副本上盖章；`input` 永远不会被修改。
    public static func stamp(input: URL, output: URL, placement: StampPlacement, design: StampDesign, text: StampText) throws {
        try stamp(input: input, output: output, placements: [placement], design: design, text: text)
    }

    /// 一次盖多页（PDF「每一页都盖」）。`progress(已完成, 总数)` 在后台线程回调。照片只用第一个位置。
    public static func stamp(input: URL, output: URL, placements: [StampPlacement], design: StampDesign, text: StampText,
                             progress: ((Int, Int) -> Void)? = nil) throws {
        guard input.standardizedFileURL != output.standardizedFileURL else { throw StampError.writeFailed(output.lastPathComponent) }
        guard let first = placements.first else { throw StampError.renderFailed }
        switch kind(of: input) {
        case .pdf: try stampPDF(input: input, output: output, placements: placements, design: design, text: text, progress: progress)
        case .image: try stampImage(input: input, output: output, placement: first, design: design, text: text)
        case nil: throw StampError.unsupportedType(input.lastPathComponent)
        }
    }

    /// PDF 有几页；照片算 1 页。
    public static func pageCount(of url: URL) throws -> Int {
        switch kind(of: url) {
        case .pdf: return try openPDF(url).pageCount
        case .image: return 1
        case nil: throw StampError.unsupportedType(url.lastPathComponent)
        }
    }

    /// 印章中心在页面上的位置（文档单位，y 轴向上）。`stampSize` 是旋转后的外接尺寸（文档单位）。
    /// 靠边会出界时往里推到刚好放得下：点的那一页和「每一页都盖」换算过去的页都一样。
    public static func center(for placement: StampPlacement, pageSize: CGSize, stampSize: CGSize) -> CGPoint {
        var c = CGPoint(x: placement.x * pageSize.width, y: (1 - placement.y) * pageSize.height)
        func clamp(_ v: CGFloat, _ half: CGFloat, _ length: CGFloat) -> CGFloat {
            half * 2 >= length ? length / 2 : min(max(v, half), length - half)
        }
        c.x = clamp(c.x, stampSize.width / 2, pageSize.width)
        c.y = clamp(c.y, stampSize.height / 2, pageSize.height)
        return c
    }

    /// 默认副本位置：原文件旁边的「原名_已盖章.扩展名」，已存在就加序号。
    public static func suggestedOutputURL(for input: URL, directory: URL? = nil) -> URL {
        let dir = directory ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent + L("_已盖章")
        let ext = input.pathExtension.isEmpty ? "pdf" : input.pathExtension
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    // MARK: PDF

    /// 打开 PDF；加了密码的先试空密码，再试 `PDFPasswords` 里记下的密码。
    public static func openPDF(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw StampError.unreadable(url.lastPathComponent) }
        if doc.isLocked, !doc.unlock(withPassword: ""),
           !(PDFPasswords.password(for: url).map { doc.unlock(withPassword: $0) } ?? false) {
            throw StampError.encryptedPDF(url.lastPathComponent)
        }
        return doc
    }

    /// 用户输入的密码对不对；对的话记下来（只在内存里），之后读页面、盖章都用它。
    public static func unlock(_ url: URL, password: String) -> Bool {
        guard let doc = PDFDocument(url: url), doc.isLocked, doc.unlock(withPassword: password) else { return false }
        PDFPasswords.set(password, for: url)
        return true
    }

    /// 预览用：把一页画成图（不盖章），长边不超过 `maxPixel`。PDF 按显示方向，照片按 EXIF 摆正。
    /// 批量盖章窗口拿它当底图，章另外叠上去，拖动时不用重画整页。
    public static func pageImage(of url: URL, pageIndex: Int = 0, maxPixel: CGFloat) throws -> CGImage {
        switch kind(of: url) {
        case .pdf:
            let doc = try openPDF(url)
            guard let page = doc.page(at: pageIndex) else { throw StampError.pageOutOfRange(pageIndex) }
            let size = displaySize(of: page)
            let s = maxPixel / max(size.width, size.height)
            let w = max(Int(size.width * s), 1), h = max(Int(size.height * s), 1)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw StampError.renderFailed }
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            ctx.scaleBy(x: s, y: s)
            page.draw(with: .cropBox, to: ctx)
            guard let image = ctx.makeImage() else { throw StampError.renderFailed }
            return image
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                throw StampError.unreadable(url.lastPathComponent)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw StampError.unreadable(url.lastPathComponent)
            }
            return image
        case nil:
            throw StampError.unsupportedType(url.lastPathComponent)
        }
    }

    static func displaySize(of page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        return (rotation == 90 || rotation == 270) ? CGSize(width: box.height, height: box.width) : box.size
    }

    /// 只重画被盖章的那几页（原页面内容保持矢量、文字仍可选中），其他页原样保留。
    static func stampPDF(input: URL, output: URL, placements: [StampPlacement], design: StampDesign, text: StampText,
                         progress: ((Int, Int) -> Void)?) throws {
        let doc = try openPDF(input)
        var seen = Set<Int>()
        let placements = placements.sorted { $0.pageIndex < $1.pageIndex }.filter { seen.insert($0.pageIndex).inserted }
        for p in placements where doc.page(at: p.pageIndex) == nil { throw StampError.pageOutOfRange(p.pageIndex) }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw StampError.renderFailed }
        for (done, placement) in placements.enumerated() {
            let page = doc.page(at: placement.pageIndex)!
            let size = displaySize(of: page)
            var box = CGRect(origin: .zero, size: size)
            ctx.beginPage(mediaBox: &box)
            // draw(with:to:) 自己处理 /Rotate 和裁切框偏移，并把表单内容、批注一起画进来。
            page.draw(with: .cropBox, to: ctx)
            let scale = CGFloat(placement.scale)
            let stampSize = StampRenderer.boundingSize(text, design: design, scale: scale)
            let center = center(for: placement, pageSize: size, stampSize: stampSize)
            StampRenderer.draw(text, design: design, in: ctx, center: center, scale: scale, rasterResolution: 10)
            ctx.endPage()
            progress?(done + 1, placements.count)
        }
        ctx.closePDF()

        guard let stampedDoc = PDFDocument(data: data as Data), stampedDoc.pageCount == placements.count else {
            throw StampError.renderFailed
        }
        for (i, placement) in placements.enumerated() {
            guard let stampedPage = stampedDoc.page(at: i) else { throw StampError.renderFailed }
            doc.removePage(at: placement.pageIndex)
            doc.insert(stampedPage, at: placement.pageIndex)
        }

        let temp = output.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp.pdf")
        defer { try? FileManager.default.removeItem(at: temp) }
        // 原件要密码才能打开的，副本也用同一个密码加密。
        var options: [PDFDocumentWriteOption: Any] = [:]
        if let password = PDFPasswords.password(for: input) {
            options[.userPasswordOption] = password
            options[.ownerPasswordOption] = password
        }
        guard doc.write(to: temp, withOptions: options) else { throw StampError.writeFailed(output.lastPathComponent) }
        try replace(output, with: temp)
    }

    // MARK: 照片

    static func imagePixelSize(_ url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else {
            throw StampError.unreadable(url.lastPathComponent)
        }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    /// 读取并按 EXIF 方向摆正（与「预览」显示的方向一致）。
    static func loadOriented(_ url: URL) throws -> (image: CGImage, dpi: CGFloat?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw StampError.unreadable(url.lastPathComponent)
        }
        let size = try imagePixelSize(url)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(size.width, size.height)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw StampError.unreadable(url.lastPathComponent)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (image, props?[kCGImagePropertyDPIWidth] as? CGFloat)
    }

    /// 副本按扩展名决定格式：jpg / png / heic，其余输出 PNG。
    static func outputType(for url: URL) -> UTType {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .heic) || type.conforms(to: .heif) {
            let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            return writable.contains(UTType.heic.identifier) ? .heic : .jpeg
        }
        if type.conforms(to: .tiff) { return .tiff }
        return .png
    }

    static func stampImage(input: URL, output: URL, placement: StampPlacement, design: StampDesign, text: StampText) throws {
        let (image, dpi) = try loadOriented(input)
        let type = outputType(for: output)
        let w = image.width, h = image.height
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var space = srgb
        if let cs = image.colorSpace, cs.model == .rgb, cs.supportsOutput { space = cs }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
            ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: info) else {
            throw StampError.renderFailed
        }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        if !type.conforms(to: .png), !type.conforms(to: .tiff) {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(rect)
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        let unit = unitsPerPoint(kind: .image, pageSize: CGSize(width: w, height: h))
        // 和 PDF 一样：靠边就往里推，整枚章留在照片里（批量盖章的九宫格位置也靠它兜底）。
        let scale = unit * CGFloat(placement.scale)
        let center = center(for: placement, pageSize: CGSize(width: w, height: h),
                            stampSize: StampRenderer.boundingSize(text, design: design, scale: scale))
        StampRenderer.draw(text, design: design, in: ctx, center: center, scale: scale)
        guard let stamped = ctx.makeImage() else { throw StampError.renderFailed }

        let temp = output.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil) else {
            throw StampError.writeFailed(output.lastPathComponent)
        }
        // 只写像素和 DPI，不带原图的 GPS / 拍摄设备等元数据。
        var props: [CFString: Any] = [:]
        if type == .jpeg || type == .heic { props[kCGImageDestinationLossyCompressionQuality] = 0.92 }
        if let dpi, dpi > 0 {
            props[kCGImagePropertyDPIWidth] = dpi
            props[kCGImagePropertyDPIHeight] = dpi
        }
        CGImageDestinationAddImage(dest, stamped, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw StampError.writeFailed(output.lastPathComponent) }
        try replace(output, with: temp)
    }

    private static func replace(_ output: URL, with temp: URL) throws {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
            try fm.moveItem(at: temp, to: output)
        } catch {
            throw StampError.writeFailed(output.lastPathComponent)
        }
    }
}

/// 用户为加密 PDF 输入的密码：只放在内存里，app 退出就忘，不写进任何文件。
public enum PDFPasswords {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var passwords: [String: String] = [:]

    public static func password(for url: URL) -> String? {
        lock.withLock { passwords[url.standardizedFileURL.path] }
    }

    static func set(_ password: String, for url: URL) {
        lock.withLock { passwords[url.standardizedFileURL.path] = password }
    }
}
