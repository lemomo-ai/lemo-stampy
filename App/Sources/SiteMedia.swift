import AppKit
import PDFKit
import StampCore
import SwiftUI

/// 官网素材：`小章 --render-site-media <目录> [--english]` 用真实的界面组件和盖章引擎画出官网要用的动画帧、印章图和界面图，然后退出。
/// 加 `--english` 画英文界面的那一套（英文官网用；印章图只在中文这一遍导出，stamps.json 里中英文名字都有）。
/// 用一套临时设置，不碰用户自己的印章和记录。`scripts/make_site_media.sh` 再把帧编成 MP4、拷进 website/。
@MainActor
enum SiteMedia {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-site-media"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        let english = args.contains("--english")
        guard let (defaults, suite) = AppEnvironment.temporaryDefaults("site-media") else { return true }
        defaults.set(StampID.sample, forKey: "nextStampID")
        Clock.now = { Snapshots.fixedNow }
        AppEnvironment.defaults = defaults
        AppVersion.fixed = "1.0.0"
        _ = LanguageSettings.shared // 见 Snapshots：先建好，免得画到一半按本机偏好换了语言
        Localization.language = english ? .en : .zh
        SiteMediaRenderer(dir: dir, defaults: defaults, english: english).run()
        defaults.removePersistentDomain(forName: suite)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: plist)
        return true
    }
}

// MARK: - 图层：把一个 SwiftUI 界面画成透明底的图

struct Layer {
    let image: NSImage
    let pad: CGFloat
    var size: CGSize { image.size }

    func draw(at origin: CGPoint, alpha: CGFloat = 1) {
        guard alpha > 0.001 else { return }
        image.draw(in: CGRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: alpha,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
}

@MainActor
func makeLayer<V: View>(_ view: V, pad: CGFloat = 40) -> Layer {
    let host = NSHostingView(rootView: view.padding(pad).environment(\.colorScheme, .light))
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    host.layoutSubtreeIfNeeded()
    let image = NSImage(size: host.bounds.size)
    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: rep)
        image.addRepresentation(rep)
    }
    window.close()
    return Layer(image: image, pad: pad)
}

// MARK: - 帧：场景坐标（点，左上角为原点）→ 输出像素

struct Camera {
    var rect: CGRect
    var out: CGSize
    var scale: CGFloat { out.width / rect.width }
}

/// 一段动画：按 25 帧/秒写 PNG，最后 0.4 秒淡回第一帧，循环播放时不跳。
private final class Reel {
    static let fps: Double = 25
    let dir: URL
    private var count = 0

    init(_ root: URL, _ name: String) {
        dir = root.appendingPathComponent("frames/\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    @MainActor
    func record(from start: Double, to end: Double, camera: (Double) -> Camera, draw: (Double) -> Void) {
        let first = render(camera(start)) { draw(start) }
        let fade = 0.4
        var t = start
        while t < end - 0.0001 {
            var frame = render(camera(t)) { draw(t) }
            if t > end - fade {
                let a = CGFloat((t - (end - fade)) / fade)
                frame = blend(frame, first, a)
            }
            write(frame)
            t += 1 / Self.fps
        }
    }

    private func write(_ image: CGImage) {
        count += 1
        let url = dir.appendingPathComponent(String(format: "%04d.png", count))
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private func blend(_ a: CGImage, _ b: CGImage, _ amount: CGFloat) -> CGImage {
        let ctx = bitmap(CGSize(width: a.width, height: a.height))
        let rect = CGRect(x: 0, y: 0, width: a.width, height: a.height)
        ctx.draw(a, in: rect)
        ctx.setAlpha(amount)
        ctx.draw(b, in: rect)
        return ctx.makeImage()!
    }
}

/// 动画帧不带透明通道：带着的话，有损 WebP 的透明度会有误差，浏览器里旧画面会从底下透出来（残影）。
func bitmap(_ size: CGSize) -> CGContext {
    CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

/// 当前帧的缩放：CG 的阴影不跟着坐标缩放，要自己乘。
@MainActor var frameScale: CGFloat = 1

@MainActor
func render(_ camera: Camera, _ draw: () -> Void) -> CGImage {
    let ctx = bitmap(camera.out)
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: camera.out.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.scaleBy(x: camera.scale, y: camera.scale)
    ctx.translateBy(x: -camera.rect.minX, y: -camera.rect.minY)
    frameScale = camera.scale
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

@MainActor var cg: CGContext { NSGraphicsContext.current!.cgContext }

// MARK: - 缓动

func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
/// t 在 [a, b] 里走到哪了（0…1）。
func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp01((t - a) / (b - a)) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ x: Double) -> CGFloat { a + (b - a) * CGFloat(x) }
func lerp(_ a: CGPoint, _ b: CGPoint, _ x: Double) -> CGPoint { CGPoint(x: lerp(a.x, b.x, x), y: lerp(a.y, b.y, x)) }

/// 鼠标沿一串关键点走：[(时间, 位置)]，两点之间缓动，中间加一点弧度，像手在动。
func path(_ keys: [(Double, CGPoint)], _ t: Double) -> CGPoint {
    guard let first = keys.first else { return .zero }
    if t <= first.0 { return first.1 }
    for (a, b) in zip(keys, keys.dropFirst()) where t <= b.0 {
        let x = ease(progress(t, a.0, b.0))
        var p = lerp(a.1, b.1, x)
        let bend = CGFloat(sin(x * .pi)) * 0.08 * hypot(b.1.x - a.1.x, b.1.y - a.1.y)
        p.y -= bend
        return p
    }
    return keys.last!.1
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - 渲染器

@MainActor
final class SiteMediaRenderer {
    let dir: URL
    let store: StampStore
    let date: Date
    let stampID = "A7K3Q2"
    /// 英文版画面（介绍视频用）：界面按英文画，示例文件名、菜单栏、示例印章也换成英文。调用前先把 Localization.language 设成 .en。
    let english: Bool

    init(dir: URL, defaults: UserDefaults, english: Bool = false) {
        self.dir = dir
        self.english = english
        store = StampStore(defaults: defaults)
        if english {
            // 工坊里轮流看的几枚：英文长章、中英双语、中文圆章、方印。
            let picks: [(String, Statement?)] = [("英文长章", Statement(purpose: "rental application", phrasing: .english)),
                                                 ("中英双语", nil), ("藏蓝圆章", Statement(purpose: "办理开户")), ("方印 · 朱文", nil)]
            store.designs = picks.compactMap { name, statement in
                guard var design = StampTemplates.all.first(where: { $0.name == name }) else { return nil }
                design.id = UUID()
                design.name = L(name)
                if let statement { design.statement = statement }
                return design
            }
            store.currentID = store.designs[0].id
        }
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 8
        date = Calendar(identifier: .gregorian).date(from: parts) ?? Date()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func tr(_ zh: String, _ en: String) -> String { english ? en : zh }

    func run() {
        // 印章上的字不跟界面语言走，两遍画出来一样，只在中文这一遍导出。
        if !english { exportStamps() }
        exportStills()
        renderFlow()
        renderMultiPage()
        renderWorkshop()
        renderBatch()
    }

    // MARK: 官网上「试一试」用的印章图、模板墙

    private func exportStamps() {
        let stampDir = dir.appendingPathComponent("stamps", isDirectory: true)
        try? FileManager.default.createDirectory(at: stampDir, withIntermediateDirectories: true)
        var entries: [[String: Any]] = []
        for (i, template) in StampTemplates.library.enumerated() {
            let design = template.design
            let text = design.statement.stampText(date: date, stampID: stampID)
            let ppp: CGFloat = 4
            guard let image = StampRenderer.image(text, design: design, pixelsPerPoint: ppp) else { continue }
            // 英文官网用的名字、说明、分类：临时切到英文取一下，再切回来。
            let saved = Localization.language
            Localization.language = .en
            let en: [String: String] = ["name": L(design.name), "blurb": L(template.blurb), "category": template.category.label]
            Localization.language = saved
            let name = String(format: "t%02d", i)
            savePNG(image, stampDir.appendingPathComponent(name + ".png"))
            let mm = StampRenderer.physicalSize(text, design: design)
            entries.append([
                "file": "stamps/\(name).png", "name": design.name, "blurb": template.blurb,
                "category": template.category.label,
                "name_en": en["name"]!, "blurb_en": en["blurb"]!, "category_en": en["category"]!,
                // 印章点（1/72 英寸）：网页按纸的宽度换算，盖出来和真的一样大。
                "w": Double(image.width) / Double(ppp), "h": Double(image.height) / Double(ppp),
                "mm": [Double(mm.width).rounded(), Double(mm.height).rounded()],
            ])
        }
        if let data = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("stamps.json"))
        }
    }

    // MARK: 静态界面图

    private func exportStills() {
        let ui = dir.appendingPathComponent("ui", isDirectory: true)
        try? FileManager.default.createDirectory(at: ui, withIntermediateDirectories: true)
        func still<V: View>(_ name: String, _ view: V) {
            let layer = makeLayer(view)
            if let rep = layer.image.representations.first as? NSBitmapImageRep {
                try? rep.representation(using: .png, properties: [:])?.write(to: ui.appendingPathComponent(name + ".png"))
            }
        }
        let noop = MenuPanelView.Actions(pickUp: {}, openEditor: {}, newStamp: {}, openHistory: {}, batch: {}, grant: {},
                                         setLaunchAtLogin: { _ in }, quit: {})
        still("panel", MenuPanelView(store: store, trusted: true, historyCount: 4, launchAtLogin: true, actions: noop))
        still("password", PasswordCard(model: PasswordModel(fileName: tr("银行流水（加密）.pdf", "Bank statement (locked).pdf")), onUnlock: {}, onCancel: {}))
        still("templates", templatesView())
        still("onboarding", OnboardingView(starterCount: 4, onOpenSettings: {}, onShowStamps: {}, onClose: {})
            .frame(width: 520, height: 600).clipShape(RoundedRectangle(cornerRadius: 12)).windowShadow(cornerRadius: 12))
        let history = historyLayer()
        if let rep = history.image.representations.first as? NSBitmapImageRep {
            try? rep.representation(using: .png, properties: [:])?.write(to: ui.appendingPathComponent("history.png"))
        }
    }

    func templatesView() -> some View {
        TemplateLibraryView().environmentObject(store).frame(width: 920, height: 640)
            .clipShape(RoundedRectangle(cornerRadius: 12)).windowShadow(cornerRadius: 12)
    }

    /// 「盖过的章」窗口，放 4 条示例记录。
    func historyLayer() -> Layer {
        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent("site-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: historyURL) }
        let history = HistoryStore(fileURL: historyURL)
        let samples: [(String, Double, String, String, String, [Int]?, Int)] = [
            ("A7K3Q2", 0, "", tr("租房签约", "Rental application"), tr("收入证明.pdf", "Proof of Income.pdf"), [0], 0),
            ("9X6CJP", -3600, tr("××银行", "Example Bank"), tr("办理开户", "Account opening"), tr("工资流水.jpg", "Payslip.jpg"), nil, 2),
            ("K2M8TR", -4 * 86400, "", tr("签证申请", "Visa application"), tr("银行流水.pdf", "Bank statement.pdf"), [0, 1, 2, 3, 4], 1),
            ("P4WQ7H", -4 * 86400 - 1800, "", tr("租房申请", "Lease"), tr("身份证复印件.heic", "ID card.heic"), nil, 3),
        ]
        for s in samples.reversed() {
            let design = store.designs.indices.contains(s.6) ? store.designs[s.6] : store.current
            let base = (s.4 as NSString).deletingPathExtension
            let ext = (s.4 as NSString).pathExtension
            try? history.append(StampRecord(id: s.0, date: Clock.now().addingTimeInterval(s.1), recipient: s.2, purpose: s.3, lines: [],
                                            files: [StampedFile(sourceName: s.4, outputPath: "/tmp/\(base)\(L("_已盖章")).\(ext)", sha256: "")],
                                            design: design, pages: s.5))
        }
        return makeLayer(HistoryView(store: history).frame(width: 720, height: 560)
            .clipShape(RoundedRectangle(cornerRadius: 12)).windowShadow(cornerRadius: 12))
    }

    // MARK: 主流程：拿起 → 点一下 → 另存副本

    /// 场景 960×600 点：菜单栏、一扇「预览」窗口、桌面。
    private let scene = CGSize(width: 960, height: 600)
    let iconCenter = CGPoint(x: 706, y: 12)
    private let window = CGRect(x: 120, y: 44, width: 640, height: 534)
    private var page: CGRect { CGRect(x: 180, y: 124, width: 520, height: 520 * 842 / 595) }
    /// 章盖在页面上的相对位置（左上角为原点）。
    private let spot = CGPoint(x: 0.66, y: 0.28)
    private let finalSize: CGFloat = 1.25

    /// 主流程的一整段画面：draw(t) 按官网动画的节奏画第 t 秒；另外给出落章点、确认卡片、章的位置，视频的镜头要用。
    struct FlowScene {
        let draw: (Double) -> Void
        let spot: CGPoint
        let card: CGRect
        let stamp: CGSize
    }

    /// 示例印章：中文版用常用长章，英文版用英文长章。
    func sampleDesign(purpose zh: String, _ en: String) -> StampDesign {
        if english, var design = StampTemplates.all.first(where: { $0.name == "英文长章" }) {
            design.statement = Statement(purpose: en, phrasing: .english)
            return design
        }
        var design = StampTemplates.library[0].design
        design.statement = Statement(purpose: zh)
        return design
    }

    func makeFlow() -> FlowScene {
        let design = sampleDesign(purpose: "租房签约", "rental application")
        let text = design.statement.stampText(date: date, stampID: stampID)
        let stamp = StampRenderer.image(text, design: design, pixelsPerPoint: 5).map {
            NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / 5, height: CGFloat($0.height) / 5))
        } ?? NSImage()

        let bubble = makeLayer(PickUpBubble(name: tr("租房签约", "Rental"), arrowX: 150), pad: 30)
        let offHint = makeLayer(HoldHint(kind: .offPage), pad: 0)
        let onHint = makeLayer(HoldHint(kind: .onPage(L("第 %ld 页 · 点一下就盖", 1))), pad: 0)
        let sizeHints = stride(from: 1.0, through: 1.25001, by: 0.05).map { makeLayer(HoldHint(kind: .size($0)), pad: 0) }

        let pdf = FileManager.default.temporaryDirectory.appendingPathComponent(tr("收入证明.pdf", "Proof of Income.pdf"))
        writeSamplePDF(pdf, pages: 2)
        let target = PreviewTarget(documentURL: pdf, kind: .pdf, pageIndex: 0, pageFrame: CGRect(x: 0, y: 0, width: 595, height: 842),
                                   pageSize: CGSize(width: 595, height: 842))
        let model = ConfirmModel(target: target, placement: StampPlacement(pageIndex: 0, x: spot.x, y: 1 - spot.y, scale: finalSize),
                                 design: design, text: text)
        model.pageCount = 2
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let card = makeLayer(ConfirmCard(model: model, arrowX: 170, arrowOnTop: true, onSave: {}, onCancel: {}), pad: 40)
        let saveButton = CGPoint(x: 319.5, y: 159) // 「另存为」在卡片图层里的中心
        let toast = makeLayer(ToastView(content: .success(output: URL(fileURLWithPath: tr("/tmp/收入证明_已盖章.pdf", "/tmp/Proof of Income_stamped.pdf")), pages: nil,
                                                          stampID: stampID), onReveal: { _ in }, onDismiss: {}), pad: 30)
        try? FileManager.default.removeItem(at: pdf)

        let k = page.width / 595
        let spotPoint = CGPoint(x: page.minX + spot.x * page.width, y: page.minY + spot.y * page.height)
        let cardOrigin = CGPoint(x: spotPoint.x - 170 - 40, y: spotPoint.y + stamp.size.height * k * finalSize / 2 + 6 - 40)
        let savePoint = CGPoint(x: cardOrigin.x + saveButton.x + 6, y: cardOrigin.y + saveButton.y + 4)
        let mouse: [(Double, CGPoint)] = [
            (0.2, CGPoint(x: 560, y: 330)), (1.3, iconCenter),
            (2.0, iconCenter), (3.4, CGPoint(x: 470, y: 300)), (4.0, spotPoint),
            (6.3, spotPoint), (7.3, savePoint), (8.6, savePoint), (10.4, CGPoint(x: 900, y: 420)),
        ]

        let draw: (Double) -> Void = { [self] t in
            let m = path(mouse, t)
            let holding = t >= 1.55 && t < 7.65
            let confirming = t >= 5.7 && t < 7.65
            let saved = t >= 7.65

            wallpaper()
            // 原件：盖章只是浮在上面，存好后浮层消失，原件不动。
            previewWindow(window, title: tr("收入证明.pdf", "Proof of Income.pdf"), subtitle: tr("第 1 页，共 2 页", "Page 1 of 2"), pageRect: page) {}

            // 拿着的章
            if holding || (saved && t < 7.95) {
                var mult: CGFloat = 1
                if t >= 4.1 { mult = lerp(1, finalSize, ease(progress(t, 4.1, 4.9))) }
                let center = confirming ? spotPoint : m
                let onPage = window.contains(center) && page.contains(center) && center.y > window.minY + 52
                let size = CGSize(width: stamp.size.width * k * mult, height: stamp.size.height * k * mult)
                var alpha: CGFloat = onPage ? 1 : 0.4
                var grow: CGFloat = 1
                if t >= 5.7 && t < 5.82 {
                    let x = easeOut(progress(t, 5.7, 5.82))
                    grow = lerp(1.04, 1, x)
                    alpha = lerp(0.6, 1, x)
                }
                if saved { alpha = CGFloat(1 - progress(t, 7.65, 7.95)) }
                if !holding && !saved { alpha = 0 }
                let appear = progress(t, 1.55, 1.75)
                alpha *= CGFloat(appear)
                let rect = CGRect(x: center.x - size.width * grow / 2, y: center.y - size.height * grow / 2,
                                  width: size.width * grow, height: size.height * grow)
                cg.saveGState()
                if onPage { cg.setShadow(offset: CGSize(width: 0, height: -6 * frameScale), blur: 6 * frameScale,
                                         color: NSColor(hex: 0x3B2A26, alpha: 0.18).cgColor) }
                stamp.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.high.rawValue])
                cg.restoreGState()
                if t >= 5.7 && t < 6.15 { ripple(around: rect, progress(t, 5.7, 6.15)) }

                // 提示条：印章下方 12、鼠标左边 24
                // 气泡还在的时候先不出提示条，免得两块叠在一起。
                if holding && !confirming && t >= 2.5 {
                    let hint: Layer
                    if t >= 4.1 && t < 5.3 {
                        let i = Int((Double(mult - 1) / 0.05).rounded())
                        hint = sizeHints[min(max(i, 0), sizeHints.count - 1)]
                    } else {
                        hint = onPage ? onHint : offHint
                    }
                    hint.draw(at: CGPoint(x: center.x - 24 - 16, y: center.y + size.height / 2 + 12 - 16), alpha: CGFloat(progress(t, 2.5, 2.7)))
                }
            }

            menubar(holding: holding, pressed: t >= 1.4 && t < 1.55)

            // 拿起时的气泡
            let bubbleAlpha = progress(t, 1.6, 1.85) * (1 - progress(t, 3.0, 3.3))
            if bubbleAlpha > 0 {
                let dy = lerp(-6, 0, easeOut(progress(t, 1.6, 1.85)))
                bubble.draw(at: CGPoint(x: iconCenter.x - 30 - 150, y: 24 + 2 - 30 + dy), alpha: CGFloat(bubbleAlpha))
            }

            // 确认卡片
            let cardAlpha = progress(t, 5.9, 6.15) * (1 - progress(t, 7.6, 7.8))
            if cardAlpha > 0 {
                let origin = CGPoint(x: cardOrigin.x, y: cardOrigin.y + lerp(6, 0, easeOut(progress(t, 5.9, 6.15))))
                card.draw(at: origin, alpha: CGFloat(cardAlpha))
                if t >= 7.45 && t < 7.62 {
                    let button = CGRect(x: origin.x + saveButton.x - 48, y: origin.y + saveButton.y - 15.5, width: 96, height: 31)
                    NSColor.black.withAlphaComponent(0.12 * CGFloat(cardAlpha)).setFill()
                    NSBezierPath(roundedRect: button, xRadius: 15.5, yRadius: 15.5).fill()
                }
            }

            // 副本：盖好的那一份
            let copyIn = easeOut(progress(t, 8.3, 8.9))
            if copyIn > 0 {
                let frame = CGRect(x: 360, y: 150 + lerp(24, 0, copyIn), width: 540, height: 420)
                let copyPage = CGRect(x: frame.minX + 70, y: frame.minY + 52 + 22, width: 400, height: 400 * 842 / 595)
                cg.saveGState()
                cg.setAlpha(CGFloat(copyIn))
                cg.beginTransparencyLayer(auxiliaryInfo: nil)
                previewWindow(frame, title: tr("收入证明_已盖章.pdf", "Proof of Income_stamped.pdf"), subtitle: tr("第 1 页，共 2 页", "Page 1 of 2"), pageRect: copyPage) {
                    let kk = copyPage.width / 595
                    let size = CGSize(width: stamp.size.width * kk * finalSize, height: stamp.size.height * kk * finalSize)
                    let c = CGPoint(x: copyPage.minX + spot.x * copyPage.width, y: copyPage.minY + spot.y * copyPage.height)
                    stamp.draw(in: CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height))
                }
                cg.endTransparencyLayer()
                cg.restoreGState()
            }

            // 盖好啦
            let toastAlpha = progress(t, 7.9, 8.2)
            if toastAlpha > 0 {
                let x = min(iconCenter.x - toast.size.width / 2, scene.width - toast.size.width + toast.pad - 8)
                toast.draw(at: CGPoint(x: x, y: 24 + 6 - toast.pad + lerp(-8, 0, easeOut(toastAlpha))), alpha: CGFloat(toastAlpha))
            }

            // 点击的小涟漪，让人看清楚点了哪里
            for click in [1.4, 5.7, 7.45] where t >= click && t < click + 0.35 {
                clickPulse(at: m, progress(t, click, click + 0.35))
            }
            cursor(at: m, crosshair: holding && !confirming && t >= 1.6)
        }
        return FlowScene(draw: draw, spot: spotPoint,
                         card: CGRect(x: cardOrigin.x + card.pad, y: cardOrigin.y + card.pad,
                                      width: card.size.width - card.pad * 2, height: card.size.height - card.pad * 2),
                         stamp: CGSize(width: stamp.size.width * k * finalSize, height: stamp.size.height * k * finalSize))
    }

    private func renderFlow() {
        let draw = makeFlow().draw
        let full = Camera(rect: CGRect(origin: .zero, size: scene), out: CGSize(width: 1440, height: 900))
        Reel(dir, "flow").record(from: 0, to: 11.6, camera: { _ in full }, draw: draw)

        let step = CGSize(width: 720, height: 540)
        Reel(dir, "step1").record(from: 0.6, to: 4.0, camera: { t in
            let x = ease(progress(t, 2.0, 3.4))
            return Camera(rect: CGRect(x: lerp(392, 240, x), y: lerp(0, 60, x), width: 560, height: 420), out: step)
        }, draw: draw)
        Reel(dir, "step2").record(from: 3.4, to: 7.4, camera: { _ in
            Camera(rect: CGRect(x: 318, y: 240, width: 400, height: 300), out: step)
        }, draw: draw)
        Reel(dir, "step3").record(from: 7.0, to: 11.0, camera: { _ in
            Camera(rect: CGRect(x: 280, y: 20, width: 680, height: 510), out: step)
        }, draw: draw)
    }

    // MARK: 多页 PDF：每一页都盖、去掉一页

    /// 多页确认卡片：draw(t) 不画底色；card 是展开后（每一页都盖）卡片的位置，single 是一开始那张小卡片。
    struct CardScene {
        let draw: (Double) -> Void
        let single: CGRect
        let card: CGRect
    }

    func makeMultiPage() -> CardScene {
        let design = sampleDesign(purpose: "签证申请", "visa application")
        let text = design.statement.stampText(date: date, stampID: stampID)
        let pdf = FileManager.default.temporaryDirectory.appendingPathComponent(tr("银行流水.pdf", "Bank statement.pdf"))
        writeSamplePDF(pdf, pages: 6)
        let target = PreviewTarget(documentURL: pdf, kind: .pdf, pageIndex: 1, pageFrame: CGRect(x: 0, y: 0, width: 595, height: 842),
                                   pageSize: CGSize(width: 595, height: 842))
        let placement = StampPlacement(pageIndex: 1, x: 0.62, y: 0.3, scale: 1)
        func card(all: Bool, skip: Int?) -> Layer {
            let model = ConfirmModel(target: target, placement: placement, design: design, text: text)
            model.pageCount = 6
            if all {
                model.selected = Set(0..<6).subtracting(skip.map { [$0] } ?? [])
                model.setAllPages(true)
                if let skip { model.selected.remove(skip) }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            return makeLayer(ConfirmCard(model: model, arrowX: 180, arrowOnTop: true, onSave: {}, onCancel: {}), pad: 40)
        }
        let single = card(all: false, skip: nil)
        let multi = card(all: true, skip: nil)
        let minus = card(all: true, skip: 5)
        try? FileManager.default.removeItem(at: pdf)

        let origin = CGPoint(x: 10, y: -14)
        let segment = CGPoint(x: origin.x + 287, y: origin.y + 116)
        let thumb6 = CGPoint(x: origin.x + 367, y: origin.y + 189)
        let save = CGPoint(x: origin.x + 359, y: origin.y + 315)
        let mouse: [(Double, CGPoint)] = [
            (0.3, CGPoint(x: 120, y: 360)), (1.1, segment), (1.9, segment), (2.6, thumb6), (3.4, thumb6), (4.2, save), (5.6, save),
        ]
        let draw: (Double) -> Void = { t in
            let toMulti = CGFloat(ease(progress(t, 1.25, 1.5)))
            let toMinus = CGFloat(ease(progress(t, 2.75, 2.95)))
            single.draw(at: origin, alpha: 1 - toMulti)
            multi.draw(at: origin, alpha: toMulti * (1 - toMinus))
            minus.draw(at: origin, alpha: toMulti * toMinus)
            let m = path(mouse, t)
            for click in [1.2, 2.7, 4.35] where t >= click && t < click + 0.35 {
                self.clickPulse(at: m, progress(t, click, click + 0.35))
            }
            self.cursor(at: m, crosshair: false)
        }
        func inner(_ layer: Layer) -> CGRect {
            CGRect(x: origin.x + layer.pad, y: origin.y + layer.pad, width: layer.size.width - layer.pad * 2, height: layer.size.height - layer.pad * 2)
        }
        return CardScene(draw: draw, single: inner(single), card: inner(multi))
    }

    private func renderMultiPage() {
        let draw = makeMultiPage().draw
        let tight = CGRect(x: 30, y: -58, width: 400, height: 316.7)
        let wide = CGRect(x: 0, y: 0, width: 480, height: 380)
        Reel(dir, "multipage").record(from: 0, to: 5.8, camera: { t in
            // 开头只有一张小卡片：镜头先贴近它，展开成「每一页都盖」时再退远，画面不会空一大块。
            let x = ease(progress(t, 1.2, 1.7)) * (1 - ease(progress(t, 5.3, 5.8)))
            return Camera(rect: CGRect(x: lerp(tight.minX, wide.minX, x), y: lerp(tight.minY, wide.minY, x),
                                       width: lerp(tight.width, wide.width, x), height: lerp(tight.height, wide.height, x)),
                          out: CGSize(width: 720, height: 570))
        }, draw: { t in
            NSColor(hex: 0xFBF1EB).setFill()
            CGRect(x: -100, y: -100, width: 700, height: 600).fill()
            draw(t)
        })
    }

    // MARK: 刻章工坊：几枚章轮流看

    /// 刻章工坊窗口（1100×740，不带边距），当前章依次换成前 4 枚。
    func workshopLayers() -> [Layer] {
        let order = Array(store.designs.indices.prefix(4))
        var layers: [Layer] = []
        for i in order {
            store.currentID = store.designs[i].id
            layers.append(makeLayer(EditorView(onPickUp: {}).environmentObject(store).frame(width: 1100, height: 740)
                .clipShape(RoundedRectangle(cornerRadius: 12)), pad: 0))
        }
        return layers
    }

    private func renderWorkshop() {
        let layers = workshopLayers()
        guard !layers.isEmpty else { return }
        let hold = 1.8, fade = 0.35
        let total = Double(layers.count) * hold
        Reel(dir, "workshop").record(from: 0, to: total, camera: { _ in
            Camera(rect: CGRect(x: 0, y: 0, width: 1100, height: 740), out: CGSize(width: 1320, height: 888))
        }, draw: { t in
            let i = min(Int(t / hold), layers.count - 1)
            layers[i].draw(at: .zero)
            let into = t - Double(i) * hold - (hold - fade)
            if into > 0, i + 1 < layers.count {
                layers[i + 1].draw(at: .zero, alpha: CGFloat(ease(clamp01(into / fade))))
            }
        })
    }

    // MARK: 批量盖章：一沓文件拖进来 → 点「盖 4 份」→ 全部打勾

    struct BatchScene {
        let draw: (Double) -> Void
        let size: CGSize
        /// 窗口（不含阴影边距）在场景里的位置。
        let window: CGRect
    }

    func makeBatch() -> BatchScene {
        // 工坊那段把「当前」换到了方印；批量这段用一枚看得清的长章。
        store.currentID = store.designs[0].id
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("site-batch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let names = english ? ["Bank statement.pdf", "Passport.pdf", "Employment letter.pdf"] : ["银行流水.pdf", "护照首页.pdf", "在职证明.pdf"]
        var inputs: [URL] = []
        for (i, name) in names.enumerated() {
            let url = tmp.appendingPathComponent(name)
            writeSamplePDF(url, pages: [6, 1, 2][i])
            inputs.append(url)
        }
        let photo = tmp.appendingPathComponent(tr("身份证正面.jpg", "ID card.jpg"))
        if let ctx = CGContext(data: nil, width: 1600, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.95, blue: 0.97, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1000))
            ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.85, blue: 0.9, alpha: 1))
            ctx.fill(CGRect(x: 120, y: 300, width: 400, height: 500))
            for i in 0..<5 { ctx.fill(CGRect(x: 640, y: 700 - i * 90, width: 760 - i * 60, height: 36)) }
            if let image = ctx.makeImage() { savePNG(image, photo.deletingPathExtension().appendingPathExtension("png")) }
        }
        let photoPNG = photo.deletingPathExtension().appendingPathExtension("png")
        let photoJPG = photo
        if let src = CGImageSourceCreateWithURL(photoPNG as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
           let dest = CGImageDestinationCreateWithURL(photoJPG as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
        inputs.insert(photoJPG, at: 2)

        func window(_ model: BatchModel) -> Layer {
            makeLayer(BatchView(model: model, store: store, onStart: {}, onAddFiles: {}, onClose: {})
                .frame(width: 1040, height: 680).clipShape(RoundedRectangle(cornerRadius: 12)).windowShadow(cornerRadius: 12), pad: 40)
        }
        let empty = window(BatchModel(store: store))
        let model = BatchModel(store: store)
        model.add(inputs)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let ready = window(model)
        let plan = BatchStamper.plan(inputs: inputs, position: model.position, scale: model.scale, pages: model.pages,
                                     outputDirectory: tmp.appendingPathComponent("out"))
        model.apply(BatchStamper.run(plan, design: model.design, text: model.text))
        let done = window(model)
        let toast = makeLayer(ToastView(content: .batch(done: 4, skipped: 0, outputs: [], stampID: stampID),
                                        onReveal: { _ in }, onDismiss: {}), pad: 30)

        let scene = CGSize(width: 1180, height: 820)
        let origin = CGPoint(x: (scene.width - empty.size.width) / 2, y: 50)
        let button = CGPoint(x: origin.x + 40 + 892, y: origin.y + 40 + 632)
        let dropAt = CGPoint(x: origin.x + 40 + 520, y: origin.y + 40 + 360)
        let mouse: [(Double, CGPoint)] = [
            (0.3, CGPoint(x: 60, y: 760)), (1.6, dropAt), (2.2, dropAt), (3.2, button), (4.6, button), (6.0, CGPoint(x: 1060, y: 520)),
        ]
        let draw: (Double) -> Void = { [self] t in
            wallpaperBatch(scene)
            let toReady = CGFloat(ease(progress(t, 1.75, 2.05)))
            let toDone = CGFloat(ease(progress(t, 3.45, 3.75)))
            empty.draw(at: origin, alpha: 1 - toReady)
            ready.draw(at: origin, alpha: toReady * (1 - toDone))
            done.draw(at: origin, alpha: toReady * toDone)
            let m = path(mouse, t)
            // 拖着的一沓文件
            let carry = progress(t, 0.3, 0.4) * (1 - progress(t, 1.65, 1.8))
            if carry > 0 {
                let hover = progress(t, 1.2, 1.4) * (1 - progress(t, 1.65, 1.8))
                if hover > 0 {
                    NSColor(hex: 0xF7B9A9, alpha: CGFloat(hover)).setStroke()
                    let frame = NSBezierPath(roundedRect: CGRect(x: origin.x + 46, y: origin.y + 46, width: 1028, height: 668), xRadius: 16, yRadius: 16)
                    frame.lineWidth = 3
                    frame.setLineDash([8, 6], count: 2, phase: 0)
                    frame.stroke()
                }
                fileStack(at: m, alpha: CGFloat(carry))
            }
            for click in [3.3] where t >= click && t < click + 0.35 { clickPulse(at: m, progress(t, click, click + 0.35)) }
            if t >= 3.3 && t < 3.5 {
                NSColor.black.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: CGRect(x: button.x - 105, y: button.y - 20, width: 210, height: 40), xRadius: 20, yRadius: 20).fill()
            }
            let toastIn = progress(t, 3.9, 4.2)
            if toastIn > 0 {
                toast.draw(at: CGPoint(x: scene.width - toast.size.width + toast.pad - 24, y: 8 - toast.pad + lerp(-10, 0, easeOut(toastIn))),
                           alpha: CGFloat(toastIn))
            }
            cursor(at: m, crosshair: false)
        }
        return BatchScene(draw: draw, size: scene, window: CGRect(x: origin.x + 40, y: origin.y + 40, width: 1040, height: 680))
    }

    private func renderBatch() {
        let batch = makeBatch()
        Reel(dir, "batch").record(from: 0, to: 6.8, camera: { _ in
            Camera(rect: CGRect(origin: .zero, size: batch.size), out: CGSize(width: 1180, height: 820))
        }, draw: batch.draw)
    }

    private func wallpaperBatch(_ size: CGSize) {
        let gradient = NSGradient(colors: [NSColor(hex: 0xFBE6DC), NSColor(hex: 0xF4CFC2), NSColor(hex: 0xEDBCAE)])!
        gradient.draw(in: CGRect(x: -400, y: -400, width: size.width + 800, height: size.height + 800), angle: -60)
    }

    /// 拖着的一沓文件：三张纸叠在一起，角上一个「4」。
    private func fileStack(at p: CGPoint, alpha: CGFloat) {
        cg.saveGState()
        cg.setAlpha(alpha)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        for (i, angle) in [-10.0, 4.0, -2.0].enumerated() {
            cg.saveGState()
            cg.translateBy(x: p.x + 18 + CGFloat(i) * 4, y: p.y + 16)
            cg.rotate(by: CGFloat(angle) * .pi / 180)
            let sheet = CGRect(x: -22, y: -28, width: 44, height: 58)
            cg.setShadow(offset: CGSize(width: 0, height: -3 * frameScale), blur: 6 * frameScale, color: NSColor.black.withAlphaComponent(0.18).cgColor)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: sheet, xRadius: 4, yRadius: 4).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            NSColor(hex: 0xDEDAD6).setFill()
            for line in 0..<6 { CGRect(x: -15, y: -18 + CGFloat(line) * 7, width: line == 0 ? 18 : 30, height: 2.5).fill() }
            cg.restoreGState()
        }
        let badge = CGRect(x: p.x + 38, y: p.y - 18, width: 22, height: 22)
        NSColor(hex: 0xD2402E).setFill()
        NSBezierPath(ovalIn: badge).fill()
        let n = NSAttributedString(string: "4", attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.white])
        n.draw(at: CGPoint(x: badge.midX - n.size().width / 2, y: badge.midY - n.size().height / 2))
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    // MARK: 场景里的小零件

    private func wallpaper() {
        let rect = CGRect(x: -40, y: -40, width: scene.width + 80, height: scene.height + 80)
        let gradient = NSGradient(colors: [NSColor(hex: 0xFBE6DC), NSColor(hex: 0xF4CFC2), NSColor(hex: 0xEDBCAE)])!
        gradient.draw(in: rect, angle: -60)
        for (c, r, a) in [(CGPoint(x: 90, y: 520), 220.0, 0.35), (CGPoint(x: 880, y: 160), 260.0, 0.25),
                          (CGPoint(x: 520, y: 640), 200.0, 0.2)] {
            let g = NSGradient(colors: [NSColor.white.withAlphaComponent(a), NSColor.white.withAlphaComponent(0)])!
            g.draw(in: NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), relativeCenterPosition: .zero)
        }
    }

    private func menubar(holding: Bool, pressed: Bool) {
        NSColor.white.withAlphaComponent(0.6).setFill()
        CGRect(x: -40, y: -40, width: scene.width + 80, height: 64).fill()
        NSColor.black.withAlphaComponent(0.05).setFill()
        CGRect(x: -40, y: 23.5, width: scene.width + 80, height: 0.5).fill()
        let ink = NSColor.black.withAlphaComponent(0.85)
        var x: CGFloat = 20
        let items = english ? ["Preview", "File", "Edit", "View", "Go", "Tools", "Window", "Help"]
            : ["预览", "文件", "编辑", "显示", "前往", "工具", "窗口", "帮助"]
        for (i, item) in items.enumerated() {
            let font = english ? NSFont.systemFont(ofSize: 13, weight: i == 0 ? .bold : .regular)
                : NSFont(name: i == 0 ? "PingFangSC-Semibold" : "PingFangSC-Regular", size: 13) ?? .systemFont(ofSize: 13)
            let s = NSAttributedString(string: item, attributes: [.font: font, .foregroundColor: ink])
            s.draw(at: CGPoint(x: x, y: 3))
            x += s.size().width + 20
        }
        let time = NSAttributedString(string: tr("10月8日 周四 14:30", "Thu Oct 8  2:30 PM"), attributes: [
            .font: english ? NSFont.systemFont(ofSize: 13) : NSFont(name: "PingFangSC-Regular", size: 13) ?? .systemFont(ofSize: 13),
            .foregroundColor: ink])
        time.draw(at: CGPoint(x: scene.width - 14 - time.size().width, y: 3))
        var right = scene.width - 14 - time.size().width - 18
        for symbol in ["battery.75percent", "wifi", "magnifyingglass"] {
            guard let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) else { continue }
            let size = img.size
            right -= size.width
            img.draw(in: CGRect(x: right, y: 12 - size.height / 2, width: size.width, height: size.height), from: .zero,
                     operation: .sourceOver, fraction: 0.85, respectFlipped: true, hints: nil)
            right -= 16
        }
        if pressed || holding {
            NSColor.black.withAlphaComponent(pressed ? 0.14 : 0.08).setFill()
            NSBezierPath(roundedRect: CGRect(x: iconCenter.x - 14, y: 2, width: 28, height: 20), xRadius: 5, yRadius: 5).fill()
        }
        let icon = Icons.menuBarImage(holding ? .holding : .normal)
        icon.draw(in: CGRect(x: iconCenter.x - 10, y: iconCenter.y - 9, width: 20, height: 18), from: .zero,
                  operation: .sourceOver, fraction: 0.88, respectFlipped: true, hints: nil)
    }

    /// 一扇「预览」窗口：标题栏、红绿灯、灰底上一张纸。`stampOnPage` 在页面坐标里画盖好的章。
    private func previewWindow(_ frame: CGRect, title: String, subtitle: String, pageRect: CGRect, stampOnPage: () -> Void) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -18 * frameScale), blur: 44 * frameScale,
                     color: NSColor(hex: 0x783223, alpha: 0.28).cgColor)
        NSColor(hex: 0xECECEC).setFill()
        shape.fill()
        cg.restoreGState()

        cg.saveGState()
        shape.addClip()
        NSColor(hex: 0xE3E1DF).setFill()
        frame.fill()
        // 纸
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -1 * frameScale), blur: 4 * frameScale, color: NSColor.black.withAlphaComponent(0.18).cgColor)
        NSColor.white.setFill()
        pageRect.fill()
        cg.restoreGState()
        documentContent(in: pageRect)
        stampOnPage()
        // 标题栏 + 工具栏
        let bar = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 52)
        NSColor(hex: 0xF6F5F4).setFill()
        bar.fill()
        NSColor.black.withAlphaComponent(0.09).setFill()
        CGRect(x: bar.minX, y: bar.maxY - 0.5, width: bar.width, height: 0.5).fill()
        for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            NSColor(hex: UInt32(c)).setFill()
            NSBezierPath(ovalIn: CGRect(x: frame.minX + 18 + CGFloat(i) * 20, y: frame.minY + 20, width: 12, height: 12)).fill()
        }
        let titleText = NSAttributedString(string: title, attributes: [
            .font: NSFont(name: "PingFangSC-Semibold", size: 13) ?? .boldSystemFont(ofSize: 13), .foregroundColor: NSColor(hex: 0x2B2B2B)])
        titleText.draw(at: CGPoint(x: frame.minX + 92, y: frame.minY + 9))
        NSAttributedString(string: subtitle, attributes: [
            .font: NSFont(name: "PingFangSC-Regular", size: 11) ?? .systemFont(ofSize: 11), .foregroundColor: NSColor(hex: 0x8A8A8A)])
            .draw(at: CGPoint(x: frame.minX + 92, y: frame.minY + 27))
        var gx = frame.maxX - 22
        for symbol in ["magnifyingglass", "square.and.arrow.up", "pencil.tip.crop.circle", "minus.magnifyingglass", "plus.magnifyingglass"] {
            guard let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) else { continue }
            gx -= img.size.width
            img.draw(in: CGRect(x: gx, y: frame.minY + 26 - img.size.height / 2, width: img.size.width, height: img.size.height),
                     from: .zero, operation: .sourceOver, fraction: 0.55, respectFlipped: true, hints: nil)
            gx -= 22
        }
        cg.restoreGState()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        let edge = NSBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), xRadius: 12, yRadius: 12)
        edge.lineWidth = 0.5
        edge.stroke()
    }

    /// 一页「收入证明」：标题加几段灰条，看得出是文件就行。
    private func documentContent(in page: CGRect) {
        let k = page.width / 595
        let title = NSAttributedString(string: tr("收 入 证 明", "PROOF OF INCOME"), attributes: [
            .font: NSFont(name: english ? "Georgia-Bold" : "STSongti-SC-Bold", size: (english ? 21 : 24) * k) ?? .boldSystemFont(ofSize: 24 * k),
            .foregroundColor: NSColor(hex: 0x333333)])
        title.draw(at: CGPoint(x: page.midX - title.size().width / 2, y: page.minY + 64 * k))
        NSColor(hex: 0xDEDAD6).setFill()
        var y = page.minY + 140 * k
        let paragraphs = [5, 4, 6, 3]
        for (pi, lines) in paragraphs.enumerated() {
            for line in 0..<lines {
                let indent: CGFloat = line == 0 ? 28 : 0
                let full = 470 - indent
                let width = line == lines - 1 ? full * CGFloat([0.55, 0.4, 0.7, 0.35][pi]) : full - CGFloat((line * 29 + pi * 13) % 40)
                NSBezierPath(roundedRect: CGRect(x: page.minX + (62 + indent) * k, y: y, width: width * k, height: 8 * k),
                             xRadius: 2 * k, yRadius: 2 * k).fill()
                y += 22 * k
            }
            y += 16 * k
        }
        for (i, w) in [150.0, 110].enumerated() {
            NSBezierPath(roundedRect: CGRect(x: page.maxX - (62 + CGFloat(w)) * k, y: y + 30 * k + CGFloat(i) * 24 * k,
                                             width: CGFloat(w) * k, height: 8 * k), xRadius: 2 * k, yRadius: 2 * k).fill()
        }
    }

    private func cursor(at p: CGPoint, crosshair: Bool) {
        let c: NSCursor = crosshair ? .crosshair : .arrow
        let img = c.image
        img.draw(in: CGRect(x: p.x - c.hotSpot.x, y: p.y - c.hotSpot.y, width: img.size.width, height: img.size.height),
                 from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func clickPulse(at p: CGPoint, _ x: Double) {
        let r = lerp(6, 22, easeOut(x))
        let ring = NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ring.lineWidth = 3
        NSColor(hex: 0xE0533D, alpha: 0.45 * CGFloat(1 - x)).setStroke()
        ring.stroke()
    }

    /// 落章时外圈散开的一道淡涟漪（和 StampCursorWindow.playDrop 一样）。
    private func ripple(around rect: CGRect, _ x: Double) {
        let s = lerp(0.96, 1.08, easeOut(x))
        let r = rect.insetBy(dx: -4, dy: -4)
        let grown = CGRect(x: r.midX - r.width * s / 2, y: r.midY - r.height * s / 2, width: r.width * s, height: r.height * s)
        let path = NSBezierPath(roundedRect: grown.insetBy(dx: 3, dy: 3), xRadius: min(grown.height / 2, 12), yRadius: min(grown.height / 2, 12))
        path.lineWidth = 6
        NSColor(hex: 0xE0533D, alpha: 0.18 * CGFloat(1 - x)).setStroke()
        path.stroke()
    }

    private func writeSamplePDF(_ url: URL, pages: Int) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        for p in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 0.82, alpha: 1))
            ctx.fill(CGRect(x: 60, y: 760, width: 220, height: 18))
            ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
            for line in 0..<(16 + p) { ctx.fill(CGRect(x: 60, y: 720 - CGFloat(line) * 26, width: 470 - CGFloat((line * 37) % 120), height: 9)) }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    private func savePNG(_ image: CGImage, _ url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
