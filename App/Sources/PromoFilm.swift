import AppKit
import StampCore
import SwiftUI

/// 介绍视频：`小章 --render-promo <timeline.json> <目录> [--range 起:止] [--every n]`
/// 按时间轴 timeline.json 画出 1920×1080 的每一帧（英文界面 + 中英字幕），写成 <目录>/00000.png…，然后退出。
/// 中间的功能演示复用官网动画（SiteMediaRenderer 的英文模式），时间按旁白拉伸；开头、片名、隐私、结尾是这里画的。
/// 用一套临时设置，不碰用户自己的印章和记录；之后再另外配上旁白、音乐、音效。
@MainActor
enum PromoFilm {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-promo"), i + 2 < args.count else { return false }
        let timelineURL = URL(fileURLWithPath: args[i + 1])
        let dir = URL(fileURLWithPath: args[i + 2], isDirectory: true)
        guard let data = try? Data(contentsOf: timelineURL), let timeline = try? JSONDecoder().decode(PromoTimeline.self, from: data) else {
            FileHandle.standardError.write("读不了时间轴：\(timelineURL.path)\n".data(using: .utf8)!)
            exit(1)
        }
        var range = 0.0...timeline.duration
        if let r = args.firstIndex(of: "--range"), r + 1 < args.count {
            let parts = args[r + 1].split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { range = parts[0]...parts[1] }
        }
        var every = 1
        if let e = args.firstIndex(of: "--every"), e + 1 < args.count { every = max(1, Int(args[e + 1]) ?? 1) }

        guard let (defaults, suite) = AppEnvironment.temporaryDefaults("promo") else { return true }
        AppEnvironment.defaults = defaults
        AppVersion.fixed = "1.0.0"
        _ = LanguageSettings.shared // 见 Snapshots：先建好，免得画到一半按本机偏好换了语言
        Localization.language = .en
        defaults.set(StampID.sample, forKey: "nextStampID")
        Clock.now = { Snapshots.fixedNow }
        PromoRenderer(timeline: timeline, dir: dir, defaults: defaults).run(range: range, every: every)
        defaults.removePersistentDomain(forName: suite)
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: plist)
        return true
    }
}

struct PromoTimeline: Decodable {
    struct Cue: Decodable { let t0: Double; let t1: Double; let zh: String; let en: String }
    struct Scene: Decodable { let name: String; let t0: Double; let t1: Double }
    let fps: Double
    let duration: Double
    let cues: [Cue]
    let marks: [String: Double]
    let remap: [String: [[Double]]]
    let scenes: [Scene]
}

// MARK: - 小工具

private func easeOutBack(_ x: Double) -> Double {
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}

private func easeIn(_ x: Double) -> Double { x * x * x }

private func lerp(_ a: CGRect, _ b: CGRect, _ x: Double) -> CGRect {
    CGRect(x: lerp(a.minX, b.minX, x), y: lerp(a.minY, b.minY, x), width: lerp(a.width, b.width, x), height: lerp(a.height, b.height, x))
}

/// 标题、按钮、数字：和 App 一样用 Theme 的系统圆角字体（中文接苹方），最粗到 semibold。
private func roundFont(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont {
    Theme.nsFont(size, weight, rounded: true)
}

/// 正文、字幕：Theme 的系统字体（中文接苹方）。
private func bodyFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    Theme.nsFont(size, weight, rounded: false)
}

/// 颜色都从 Theme 取（NSColor 版）。
private enum Ink {
    static let ink = NSColor(Theme.ink)
    static let ink2 = NSColor(Theme.ink2)
    static let ink3 = NSColor(Theme.ink3)
    static let coral = NSColor(Theme.coral)
    static let coralDeep = NSColor(Theme.coralDeep)
    static let coralSoft = NSColor(Theme.coralSoft)
    static let coralLine = NSColor(Theme.coralLine)
    static let coralInk = NSColor(Theme.coralInk)
    static let paper = NSColor(Theme.paper)
    static let well = NSColor(Theme.well)
    static let chip = NSColor(Theme.chip)
    static let line = NSColor(Theme.line)
    /// 示意文件上的灰色字行（和官网动画里的文件一样）。
    static let docLine = NSColor(hex: 0xDEDAD6)
    /// Theme 里阴影用的暖棕 rgba(150,70,50,a)。
    static func warm(_ a: CGFloat) -> NSColor { NSColor(srgbRed: 150 / 255, green: 70 / 255, blue: 50 / 255, alpha: a) }
}

/// Theme 的 float 阴影（0 12 32 rgba(150,70,50,.20)），按画面比例放大 k 倍。阴影向下。
@MainActor
private func floatShadow(_ k: CGFloat = 1.5, alpha: CGFloat = 1) {
    cg.setShadow(offset: CGSize(width: 0, height: -12 * k), blur: 32 * k, color: Ink.warm(0.20 * alpha).cgColor)
}

/// 在 (center) 处画一行字，返回占的大小。
@discardableResult
private func text(_ s: String, _ font: NSFont, _ color: NSColor, center: CGPoint, alpha: CGFloat = 1, kern: CGFloat = 0) -> CGSize {
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color.withAlphaComponent(color.alphaComponent * alpha),
                                                       .kern: kern])
    let size = a.size()
    a.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    return size
}

private func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
}

private func draw(_ image: NSImage, center: CGPoint, size: CGSize? = nil, alpha: CGFloat = 1) {
    let s = size ?? image.size
    image.draw(in: CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height), from: .zero,
               operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
}

/// 以 center 为中心缩放、旋转后画一个图层。
@MainActor
private func draw(_ layer: Layer, center: CGPoint, scale: CGFloat = 1, alpha: CGFloat = 1, rotate: CGFloat = 0, shadow: Bool = false) {
    guard alpha > 0.001 else { return }
    cg.saveGState()
    cg.translateBy(x: center.x, y: center.y)
    cg.rotate(by: rotate)
    cg.scaleBy(x: scale, y: scale)
    if shadow {
        // Theme 的窗口级阴影：0 24px 60px rgba(120,50,35,.22)
        cg.setShadow(offset: CGSize(width: 0, height: -24 * scale * frameScale), blur: 60 * scale * frameScale,
                     color: NSColor(srgbRed: 120 / 255, green: 50 / 255, blue: 35 / 255, alpha: 0.22 * alpha).cgColor)
    }
    layer.draw(at: CGPoint(x: -layer.size.width / 2, y: -layer.size.height / 2), alpha: alpha)
    cg.restoreGState()
}

// MARK: - 渲染器

@MainActor
private final class PromoRenderer {
    let tl: PromoTimeline
    let dir: URL
    let film = CGSize(width: 1920, height: 1080)
    /// 字幕占掉画面底下这么多（比例），界面镜头把重要的东西放在它上面。
    let bottomSafe: CGFloat = 0.18

    let site: SiteMediaRenderer
    let flow: SiteMediaRenderer.FlowScene
    let multi: SiteMediaRenderer.CardScene
    let batch: SiteMediaRenderer.BatchScene
    let editors: [Layer]
    let templates: Layer
    let history: Layer
    let mascots: [MascotMood: Layer]
    let stamp: NSImage

    init(timeline: PromoTimeline, dir: URL, defaults: UserDefaults) {
        tl = timeline
        self.dir = dir
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("promo-\(UUID().uuidString)")
        site = SiteMediaRenderer(dir: scratch, defaults: defaults, english: true)
        print("▸ 准备界面图层")
        flow = site.makeFlow()
        multi = site.makeMultiPage()
        editors = site.workshopLayers()
        batch = site.makeBatch()
        templates = makeLayer(site.templatesView())
        history = site.historyLayer()
        var m: [MascotMood: Layer] = [:]
        for mood in [MascotMood.normal, .expectant, .happy] { m[mood] = makeLayer(Mascot(mood: mood, size: 240), pad: 24) }
        mascots = m
        let design = site.store.designs[0]
        let text = design.statement.stampText(date: site.date, stampID: site.stampID)
        let ppp: CGFloat = 12
        stamp = StampRenderer.image(text, design: design, pixelsPerPoint: ppp).map {
            NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / ppp, height: CGFloat($0.height) / ppp))
        } ?? NSImage()
        try? FileManager.default.removeItem(at: scratch)
    }

    func mark(_ name: String) -> Double {
        guard let t = tl.marks[name] else { fatalError("时间轴里没有 mark「\(name)」") }
        return t
    }

    /// 成片时间 → 官网动画时间（分段线性）。
    func remap(_ name: String, _ t: Double) -> Double {
        guard let keys = tl.remap[name], let first = keys.first, let last = keys.last else { return t }
        if t <= first[0] { return first[1] }
        for (a, b) in zip(keys, keys.dropFirst()) where t <= b[0] {
            return b[0] - a[0] < 0.0001 ? b[1] : a[1] + (b[1] - a[1]) * (t - a[0]) / (b[0] - a[0])
        }
        return last[1]
    }

    // MARK: 输出

    func run(range: ClosedRange<Double>, every: Int) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let total = Int((tl.duration * tl.fps).rounded())
        let first = Int((range.lowerBound * tl.fps).rounded()), last = min(total - 1, Int((range.upperBound * tl.fps).rounded()))
        guard first <= last else { return }
        print("▸ 画帧 \(first)…\(last)（每 \(every) 帧一张）")
        let started = Date()
        for i in stride(from: first, through: last, by: every) {
            autoreleasepool {
                let image = frame(Double(i) / tl.fps)
                let url = dir.appendingPathComponent(String(format: "%05d.png", i))
                if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, image, nil)
                    CGImageDestinationFinalize(dest)
                }
            }
            if (i - first) % (every * 150) == 0 { print("  \(i)/\(last)  \(Int(Date().timeIntervalSince(started)))s") }
        }
        print("✓ 帧在 \(dir.path)")
    }

    /// 一帧：当前的段落（交接时后一段在上面淡入），再盖上字幕。
    func frame(_ t: Double) -> CGImage {
        let fade = 0.4
        var layers: [(CGImage, CGFloat)] = []
        for (i, scene) in tl.scenes.enumerated() {
            let end = i == tl.scenes.count - 1 ? scene.t1 + 1 : scene.t1 + fade
            guard t >= scene.t0 && t < end else { continue }
            let alpha = i == 0 ? 1 : CGFloat(ease(progress(t, scene.t0, scene.t0 + fade)))
            layers.append((sceneImage(scene.name, t), alpha))
        }
        let full = Camera(rect: CGRect(origin: .zero, size: film), out: film)
        return render(full) {
            Ink.paper.setFill()
            CGRect(origin: .zero, size: film).fill()
            for (image, alpha) in layers {
                NSImage(cgImage: image, size: film).draw(in: CGRect(origin: .zero, size: film), from: .zero, operation: .sourceOver,
                                                         fraction: alpha, respectFlipped: true, hints: nil)
            }
            subtitles(t)
            // 结尾卡停到最后一帧，不淡成空白：网页、社媒播完停在最后一帧，正好是下载地址（音乐自己淡出）。
        }
    }

    func sceneImage(_ name: String, _ t: Double) -> CGImage {
        let full = Camera(rect: CGRect(origin: .zero, size: film), out: film)
        switch name {
        case "hook": return render(full) { hook(t) }
        case "title": return render(full) { title(t) }
        case "flow":
            let camera = flowCamera(t)
            return render(camera) {
                backdrop(camera)
                flow.draw(remap("flow", t))
                iconPulse(t)
            }
        case "multipage":
            let camera = multiCamera(t)
            return render(camera) { backdrop(camera); multi.draw(remap("multipage", t)) }
        case "batch":
            let camera = batchCamera(t)
            return render(camera) { backdrop(camera); batch.draw(remap("batch", t)) }
        case "workshop": return render(full) { workshop(t) }
        case "history": return render(full) { historyScene(t) }
        case "privacy": return render(full) { privacy(t) }
        case "outro": return render(full) { outro(t) }
        default: return render(full) {}
        }
    }

    // MARK: 镜头

    /// 把 content 放进 16:9 的画面，底下留出字幕的位置。
    func fit(_ content: CGRect, minWidth: CGFloat = 0) -> CGRect {
        let usable = 1 - bottomSafe - 0.04
        let width = max(content.width, content.height / usable * 16 / 9, minWidth)
        let height = width * 9 / 16
        let top = content.minY - (height * usable - content.height) / 2 - height * 0.04
        return CGRect(x: content.midX - width / 2, y: top, width: width, height: height)
    }

    /// 镜头从 start 出发，依次在 [a, b] 里缓动到下一个位置。
    func moves(_ t: Double, from start: CGRect, _ steps: [(Double, Double, CGRect)]) -> Camera {
        var rect = start
        for (a, b, to) in steps {
            if t <= a { break }
            if t < b { rect = lerp(rect, to, ease(progress(t, a, b))); break }
            rect = to
        }
        return Camera(rect: rect, out: film)
    }

    func flowCamera(_ t: Double) -> Camera {
        // 全景：整条菜单栏都在画面里（以前从 y=14 开始，菜单栏被切掉一半）。
        let wide = CGRect(x: 0, y: 0, width: 960, height: 540)
        // 开场贴近菜单栏图标，图标放在画面正中。
        let iconClose = CGRect(x: site.iconCenter.x - 210, y: -8, width: 420, height: 236.25)
        let icon = CGRect(x: 420, y: -6, width: 560, height: 315)
        let spot = fit(CGRect(x: flow.spot.x - 250, y: flow.spot.y - 110, width: 500, height: 220), minWidth: 620)
        let stampRect = CGRect(x: flow.spot.x - flow.stamp.width / 2, y: flow.spot.y - flow.stamp.height / 2,
                               width: flow.stamp.width, height: flow.stamp.height)
        let card = fit(flow.card.union(stampRect).insetBy(dx: -28, dy: -22), minWidth: 600)
        // 「在『预览』里打开文件」：快一点拉远，在全景上停一会儿（以前刚拉远就推回去），再推到菜单栏图标。
        return moves(t, from: iconClose, [
            (mark("menubar") + 0.3, mark("menubar") + 2.2, icon),
            (mark("flowWide") - 0.25, mark("flowWide") + 0.6, wide),
            (mark("iconClick") - 1.05, mark("iconClick") - 0.2, icon),
            (mark("follow") - 0.6, mark("follow") + 0.9, spot),
            (mark("place") + 0.3, mark("place") + 1.1, card),
            (mark("save") + 0.7, mark("copy") + 0.5, wide),
        ])
    }

    /// 说到「住在菜单栏里」时，菜单栏图标外面一圈圈散开的光晕。
    func iconPulse(_ t: Double) {
        let a = mark("menubar") + 0.5, b = mark("flowWide") - 0.3
        guard t > a && t < b else { return }
        let fade = CGFloat(min(progress(t, a, a + 0.3), 1 - progress(t, b - 0.3, b)))
        for k in 0..<2 {
            let x = ((t - a) / 1.1 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
            let r = lerp(11, 22, easeOut(x))
            let ring = NSBezierPath(ovalIn: CGRect(x: site.iconCenter.x - r, y: site.iconCenter.y - r, width: r * 2, height: r * 2))
            ring.lineWidth = 2.5
            Ink.coral.withAlphaComponent(0.6 * CGFloat(1 - x) * fade).setStroke()
            ring.stroke()
        }
    }

    func multiCamera(_ t: Double) -> Camera {
        let single = fit(multi.single.insetBy(dx: -40, dy: -30), minWidth: 640)
        let all = fit(multi.card.insetBy(dx: -40, dy: -30), minWidth: 640)
        return moves(t, from: single, [(mark("allPages") - 0.05, mark("allPages") + 0.5, all)])
    }

    func batchCamera(_ t: Double) -> Camera {
        let base = fit(batch.window.insetBy(dx: -24, dy: -20))
        let wider = base.insetBy(dx: -base.width * 0.03, dy: -base.height * 0.03)
        return Camera(rect: lerp(wider, base, ease(progress(t, mark("batch"), mark("workshop") + 0.4))), out: film)
    }

    /// 界面镜头后面的暖粉色桌面（场景坐标）。
    func backdrop(_ camera: Camera) {
        let r = camera.rect.insetBy(dx: -camera.rect.width * 0.2, dy: -camera.rect.height * 0.2)
        let gradient = NSGradient(colors: [NSColor(hex: 0xFBE6DC), NSColor(hex: 0xF4CFC2), NSColor(hex: 0xEDBCAE)])!
        gradient.draw(in: r, angle: -60)
    }

    /// 片头片尾等画在 1920×1080 上的段落用的底：暖粉渐变 + 几团柔光。
    func filmWallpaper(soft: Bool = false) {
        let rect = CGRect(origin: .zero, size: film)
        let colors = soft ? [NSColor(hex: 0xFDF4EF), NSColor(hex: 0xFBE9E1), NSColor(hex: 0xF7DCD1)]
            : [NSColor(hex: 0xFBE6DC), NSColor(hex: 0xF4CFC2), NSColor(hex: 0xEDBCAE)]
        NSGradient(colors: colors)!.draw(in: rect, angle: -60)
        for (c, r, a) in [(CGPoint(x: 180, y: 900), 520.0, 0.35), (CGPoint(x: 1760, y: 260), 600.0, 0.28), (CGPoint(x: 1040, y: 1180), 460.0, 0.2)] {
            let g = NSGradient(colors: [NSColor.white.withAlphaComponent(a), NSColor.white.withAlphaComponent(0)])!
            g.draw(in: NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), relativeCenterPosition: .zero)
        }
    }

    // MARK: 开头：签证、开户、租房 → 一沓复印件 → 被复制走

    func hook(_ t: Double) {
        filmWallpaper()
        let cards: [(String, String, String, String)] = [("airplane", "Visa", "签证", "card1"), ("building.columns.fill", "Bank account", "开户", "card2"),
                                                          ("house.fill", "Rental", "租房", "card3")]
        let up = ease(progress(t, mark("copies") - 0.35, mark("copies") + 0.35))
        let dim = CGFloat(progress(t, mark("reuse"), mark("reuse") + 0.6))
        for (i, card) in cards.enumerated() {
            let x = progress(t, mark(card.3), mark(card.3) + 0.5)
            guard x > 0 else { continue }
            let pop = CGFloat(easeOutBack(x))
            let center = CGPoint(x: 560 + CGFloat(i) * 400 + lerp(0, CGFloat(i - 1) * -60, up), y: lerp(430, 210, up))
            let scale = (0.6 + 0.4 * pop) * lerp(1, 0.62, up)
            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.scaleBy(x: scale, y: scale)
            cg.setAlpha(CGFloat(min(1, x * 3)) * (1 - dim * 0.35))
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            let rect = CGRect(x: -170, y: -200, width: 340, height: 400)
            cg.saveGState()
            floatShadow(1.4)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 40, yRadius: 40).fill()
            cg.restoreGState()
            Ink.coralSoft.setFill()
            NSBezierPath(ovalIn: CGRect(x: -86, y: -150, width: 172, height: 172)).fill()
            if let image = symbol(card.0, 78, .semibold, Ink.coral) { draw(image, center: CGPoint(x: 0, y: -64)) }
            text(card.1, roundFont(40), Ink.ink, center: CGPoint(x: 0, y: 88))
            text(card.2, roundFont(30, .regular), Ink.ink2, center: CGPoint(x: 0, y: 140))
            cg.endTransparencyLayer()
            cg.restoreGState()
        }

        // 一沓复印件落下来
        let drop = progress(t, mark("copies") - 0.1, mark("copies") + 0.5)
        guard drop > 0 else { return }
        let base = CGPoint(x: 960, y: 640)
        for (i, angle) in [-7.0, 5.0, -1.5].enumerated() {
            let delay = Double(i) * 0.12
            let x = easeOutBack(progress(t, mark("copies") - 0.1 + delay, mark("copies") + 0.45 + delay))
            guard x > 0 else { continue }
            let p = CGPoint(x: base.x + CGFloat(i - 1) * 22, y: lerp(1300, base.y, x))
            copySheet(at: p, angle: angle, alpha: 1, scale: 1.15)
        }
        // 复印件被拿去复制：几份虚影飞走，带问号
        let reuse = progress(t, mark("reuse"), mark("reuse") + 2.3)
        if reuse > 0 {
            let targets: [(CGFloat, CGFloat, Double)] = [(-640, -150, -18), (620, -190, 16), (-560, 170, 12), (650, 150, -14)]
            for (i, target) in targets.enumerated() {
                let x = easeOut(progress(t, mark("reuse") + Double(i) * 0.25, mark("reuse") + 1.2 + Double(i) * 0.25))
                guard x > 0 else { continue }
                let p = CGPoint(x: base.x + target.0 * CGFloat(x), y: base.y + target.1 * CGFloat(x))
                let alpha = CGFloat(min(1, x * 4)) * 0.85
                copySheet(at: p, angle: target.2 * x - 1.5, alpha: alpha, scale: lerp(1, 0.7, x), ghost: true)
                let badge = CGPoint(x: p.x + 92 * lerp(1, 0.7, x), y: p.y - 150 * lerp(1, 0.7, x))
                let pop = CGFloat(easeOutBack(progress(t, mark("reuse") + 0.5 + Double(i) * 0.25, mark("reuse") + 0.9 + Double(i) * 0.25)))
                if pop > 0 {
                    Ink.coralDeep.withAlphaComponent(alpha).setFill()
                    let r = 30 * pop
                    NSBezierPath(ovalIn: CGRect(x: badge.x - r, y: badge.y - r, width: r * 2, height: r * 2)).fill()
                    text("?", roundFont(38 * pop), .white, center: badge, alpha: alpha)
                }
            }
        }
    }

    /// 一张证件复印件：左上角照片，几行字，右上角「COPY」。
    func copySheet(at p: CGPoint, angle: Double, alpha: CGFloat, scale: CGFloat = 1, ghost: Bool = false) {
        cg.saveGState()
        cg.translateBy(x: p.x, y: p.y)
        cg.rotate(by: CGFloat(angle) * .pi / 180)
        cg.scaleBy(x: scale, y: scale)
        cg.setAlpha(alpha)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        let sheet = CGRect(x: -130, y: -170, width: 260, height: 340)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: Ink.warm(0.18).cgColor)
        (ghost ? NSColor(white: 1, alpha: 0.75) : NSColor.white).setFill()
        NSBezierPath(roundedRect: sheet, xRadius: 10, yRadius: 10).fill()
        cg.restoreGState()
        if ghost {
            let edge = NSBezierPath(roundedRect: sheet.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9)
            edge.lineWidth = 3
            edge.setLineDash([12, 8], count: 2, phase: 0)
            Ink.coralLine.setStroke()
            edge.stroke()
        }
        NSColor(hex: 0xD9E1EA).setFill()
        NSBezierPath(roundedRect: CGRect(x: -100, y: -134, width: 70, height: 88), xRadius: 6, yRadius: 6).fill()
        Ink.docLine.setFill()
        for i in 0..<3 { NSBezierPath(roundedRect: CGRect(x: -16, y: -126 + CGFloat(i) * 24, width: 116 - CGFloat(i) * 22, height: 10), xRadius: 3, yRadius: 3).fill() }
        for i in 0..<6 { NSBezierPath(roundedRect: CGRect(x: -100, y: -18 + CGFloat(i) * 28, width: 200 - CGFloat((i * 37) % 70), height: 9), xRadius: 3, yRadius: 3).fill() }
        text("COPY", roundFont(22), Ink.ink3, center: CGPoint(x: 64, y: 138), kern: 3)
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    // MARK: 片名

    func title(_ t: Double) {
        filmWallpaper(soft: true)
        let t0 = mark("title")
        let pop = progress(t, t0 + 0.05, t0 + 0.6)
        if pop > 0, let mascot = mascots[.happy] {
            let bob = CGFloat(sin((t - t0) * 2.4)) * 6
            draw(mascot, center: CGPoint(x: 960, y: 360 + bob), scale: CGFloat(0.5 + 0.5 * easeOutBack(pop)), alpha: CGFloat(min(1, pop * 3)))
        }
        let name = easeOut(progress(t, t0 + 0.4, t0 + 0.9))
        if name > 0 {
            text("Stampy", roundFont(108), Ink.ink, center: CGPoint(x: 960, y: 590 + lerp(24, 0, name)), alpha: CGFloat(name))
        }
        let zh = easeOut(progress(t, t0 + 0.65, t0 + 1.15))
        if zh > 0 {
            text("小章", roundFont(58), Ink.coral, center: CGPoint(x: 960, y: 690 + lerp(20, 0, zh)), alpha: CGFloat(zh), kern: 6)
        }
    }

    // MARK: 刻章工坊

    func workshop(_ t: Double) {
        filmWallpaper()
        let end = mark("history")
        // editors：0 英文长章、1 中英双语、2 藏蓝圆章、3 方印。旁白念到「圆章、方印、长章，中文英文」时，画面跟着换到那一枚。
        let editor = 820.0 / 740
        var shots: [(start: Double, layer: Layer, scale: CGFloat, fade: Double)] = []
        func add(_ start: Double, _ index: Int, fade: Double = 0.16) {
            if editors.indices.contains(index) { shots.append((start, editors[index], CGFloat(editor), fade)) }
        }
        add(mark("workshop"), 0, fade: 0)
        shots.append((mark("templates"), templates, 1.16, 0.3))
        add(mark("wsRound"), 2, fade: 0.3)
        add(mark("wsSquare"), 3)
        add(mark("wsLong"), 0)
        add(mark("wsChinese"), 1)
        // 整段一起慢慢推近，几枚章之间换的时候窗口不跳。
        let push = CGFloat(lerp(1, 1.04, progress(t, mark("workshop"), end + 0.4)))
        let center = CGPoint(x: 960, y: 40 + 820 / 2)
        for (i, shot) in shots.enumerated() {
            let next = i + 1 < shots.count ? shots[i + 1] : nil
            let until = next.map { $0.start } ?? end + 1
            guard t >= shot.start - shot.fade || i == 0, t < until else { continue }
            let alpha = i == 0 ? 1 : CGFloat(ease(progress(t, shot.start - shot.fade, shot.start)))
            draw(shot.layer, center: center, scale: shot.scale * push, alpha: alpha, shadow: shot.layer.pad == 0)
        }
    }

    // MARK: 盖过的章：每一枚都有编号

    func historyScene(_ t: Double) {
        filmWallpaper()
        let t0 = mark("history")
        let push = CGFloat(lerp(1.0, 1.03, progress(t, t0, mark("privacy") + 0.4)))
        let windowCenter = CGPoint(x: 700, y: 440), windowScale = 1.32 * push
        draw(history, center: windowCenter, scale: windowScale)
        let s = progress(t, mark("stampID") - 0.16, mark("stampID"))
        guard s > 0 else { return }
        let width: CGFloat = 520
        let size = CGSize(width: width, height: width * stamp.size.height / max(stamp.size.width, 1))
        let center = CGPoint(x: 1490, y: 420)
        let grow = lerp(1.5, 1, easeIn(s))
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: -0.06)
        cg.scaleBy(x: grow, y: grow)
        cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: Ink.warm(0.14 * CGFloat(s)).cgColor)
        draw(stamp, center: .zero, size: size, alpha: CGFloat(s))
        cg.restoreGState()
        stampRipple(center: center, size: size, x: progress(t, mark("stampID"), mark("stampID") + 0.5))
        // 编号：跟记录第一行是同一个。牌子用 App 里编号的样子（奶油黄底）；第一行同时框出来，看得出是同一枚。
        let label = easeOut(progress(t, mark("stampID") + 0.35, mark("stampID") + 0.8))
        if label > 0 {
            let p = CGPoint(x: center.x, y: center.y + size.height / 2 + 70 + lerp(12, 0, label))
            let font = roundFont(40)
            let w = NSAttributedString(string: "No.A7K3Q2", attributes: [.font: font]).size().width + 60
            NSColor(Theme.butter).withAlphaComponent(CGFloat(label)).setFill()
            NSBezierPath(roundedRect: CGRect(x: p.x - w / 2, y: p.y - 36, width: w, height: 72), xRadius: 36, yRadius: 36).fill()
            text("No.A7K3Q2", font, NSColor(Theme.butterInk), center: p, alpha: CGFloat(label))

            // 第一行在「盖过的章」窗口里的位置（图层坐标，窗口 720×560 加 40 边距）。
            let row = CGRect(x: 58, y: 146, width: 684, height: 56)
            let size = history.size
            let r = CGRect(x: windowCenter.x + (row.minX - size.width / 2) * windowScale, y: windowCenter.y + (row.minY - size.height / 2) * windowScale,
                           width: row.width * windowScale, height: row.height * windowScale)
            let ring = NSBezierPath(roundedRect: r, xRadius: 14 * windowScale, yRadius: 14 * windowScale)
            ring.lineWidth = 3
            Ink.coralLine.withAlphaComponent(CGFloat(label)).setStroke()
            ring.stroke()
        }
    }

    func stampRipple(center: CGPoint, size: CGSize, x: Double) {
        guard x > 0 && x < 1 else { return }
        let s = lerp(1.0, 1.18, easeOut(x))
        let r = CGRect(x: center.x - size.width * s / 2 - 10, y: center.y - size.height * s / 2 - 10,
                       width: size.width * s + 20, height: size.height * s + 20)
        let path = NSBezierPath(roundedRect: r, xRadius: 24, yRadius: 24)
        path.lineWidth = 10
        Ink.coral.withAlphaComponent(0.22 * CGFloat(1 - x)).setStroke()
        path.stroke()
    }

    // MARK: 文件不上传

    func privacy(_ t: Double) {
        filmWallpaper(soft: true)
        let t0 = mark("privacy")
        let rise = easeOut(progress(t, t0 + 0.1, t0 + 0.7))
        let center = CGPoint(x: 960, y: 420 + lerp(40, 0, rise))
        let size = CGSize(width: 760, height: 470)
        laptop(center: center, size: size, alpha: CGFloat(rise))
        let screen = CGPoint(x: center.x, y: center.y - 30)
        let happy = progress(t, mark("noUpload") - 0.2, mark("noUpload") + 0.1)
        let pop = progress(t, t0 + 0.4, t0 + 0.9)
        if pop > 0 {
            let scale = CGFloat(0.42 + 0.18 * easeOutBack(pop))
            if let normal = mascots[.expectant] { draw(normal, center: screen, scale: scale, alpha: CGFloat(min(1, pop * 3)) * CGFloat(1 - happy)) }
            if let smile = mascots[.happy] { draw(smile, center: screen, scale: scale, alpha: CGFloat(happy)) }
        }
        // 云：划掉（文件不上传）
        let cloud = progress(t, mark("noUpload"), mark("noUpload") + 0.5)
        if cloud > 0, let image = symbol("icloud.slash", 116, .medium, Ink.coral) {
            let p = CGPoint(x: center.x + size.width * 0.5 + 90, y: center.y - size.height * 0.38)
            let shake = CGFloat(sin(progress(t, mark("noUpload") + 0.3, mark("noUpload") + 0.9) * .pi * 4)) * 8
            cg.saveGState()
            cg.translateBy(x: p.x + shake, y: p.y)
            cg.scaleBy(x: CGFloat(easeOutBack(cloud)), y: CGFloat(easeOutBack(cloud)))
            cg.saveGState()
            floatShadow(1.2)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: -125, y: -125, width: 250, height: 250)).fill()
            cg.restoreGState()
            Ink.coralSoft.setFill()
            NSBezierPath(ovalIn: CGRect(x: -108, y: -108, width: 216, height: 216)).fill()
            draw(image, center: .zero)
            cg.restoreGState()
        }
    }

    /// 一台简笔的 MacBook，「糯米」风格：白色边框、奶油色屏幕、浅色底座、暖色阴影（不用深墨色）。
    func laptop(center: CGPoint, size: CGSize, alpha: CGFloat) {
        cg.saveGState()
        cg.setAlpha(alpha)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        let screen = CGRect(x: center.x - size.width * 0.4, y: center.y - size.height / 2, width: size.width * 0.8, height: size.height * 0.86)
        let lid = NSBezierPath(roundedRect: screen, xRadius: 30, yRadius: 30)
        cg.saveGState()
        floatShadow(1.6)
        NSColor.white.setFill()
        lid.fill()
        cg.restoreGState()
        lid.lineWidth = 2
        Ink.warm(0.2).setStroke()
        lid.stroke()
        let display = NSBezierPath(roundedRect: screen.insetBy(dx: 18, dy: 18), xRadius: 14, yRadius: 14)
        Ink.well.setFill()
        display.fill()
        display.lineWidth = 1.5
        Ink.line.setStroke()
        display.stroke()
        Ink.line.setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 4, y: screen.minY + 5, width: 8, height: 8)).fill()

        let base = NSBezierPath()
        let top = screen.maxY + 4, w = size.width, h = size.height * 0.07
        base.move(to: CGPoint(x: center.x - w / 2 + 10, y: top))
        base.line(to: CGPoint(x: center.x + w / 2 - 10, y: top))
        base.curve(to: CGPoint(x: center.x + w / 2 - 40, y: top + h), controlPoint1: CGPoint(x: center.x + w / 2 + 6, y: top + 2),
                   controlPoint2: CGPoint(x: center.x + w / 2 - 10, y: top + h))
        base.line(to: CGPoint(x: center.x - w / 2 + 40, y: top + h))
        base.curve(to: CGPoint(x: center.x - w / 2 + 10, y: top), controlPoint1: CGPoint(x: center.x - w / 2 + 10, y: top + h),
                   controlPoint2: CGPoint(x: center.x - w / 2 - 6, y: top + 2))
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: Ink.warm(0.18).cgColor)
        Ink.chip.setFill()
        base.fill()
        cg.restoreGState()
        base.lineWidth = 2
        Ink.warm(0.2).setStroke()
        base.stroke()
        Ink.line.setFill()
        NSBezierPath(roundedRect: CGRect(x: center.x - 70, y: top, width: 140, height: h * 0.38), xRadius: 6, yRadius: 6).fill()
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    // MARK: 结尾：收尾语 + 落章 + 免费下载和网址（停到最后一帧，也是封面）

    func outro(_ t: Double) {
        filmWallpaper(soft: true)
        let t0 = mark("outro"), slam = mark("slam"), said = mark("outroLine"), cta = mark("cta")
        // 小章：先在画面中间出场（配乐主题这一句），收尾语出来时往上让位；落章那一下跟着轻轻弹一下
        let pop = progress(t, t0 + 0.2, t0 + 0.75)
        if pop > 0, let mascot = mascots[.happy] {
            let bob = CGFloat(sin((t - t0) * 2.4)) * 5
            let up = ease(progress(t, said - 0.45, said + 0.15))
            let x = t - slam
            let bounce = x > 0 && x < 0.6 ? CGFloat(sin(x / 0.6 * .pi * 2) * exp(-x * 5)) * 0.08 : 0
            let size = lerp(0.85, 0.6, up)
            draw(mascot, center: CGPoint(x: 960, y: lerp(470, 206, up) + bob), scale: CGFloat(0.5 + 0.5 * easeOutBack(pop)) * size * (1 + bounce),
                 alpha: CGFloat(min(1, pop * 3)))
        }
        // 收尾语：和旁白同时出来，这一段画面里不另加字幕。
        let zh = easeOut(progress(t, said - 0.1, said + 0.4))
        if zh > 0 {
            text("小章。小小一枚，安心一点。", roundFont(68), Ink.ink, center: CGPoint(x: 960, y: 392 + lerp(22, 0, zh)), alpha: CGFloat(zh), kern: 2)
        }
        let en = easeOut(progress(t, said + 0.1, said + 0.6))
        if en > 0 {
            text("Stampy. A small stamp, for peace of mind.", roundFont(40, .regular), Ink.ink2, center: CGPoint(x: 960, y: 472 + lerp(18, 0, en)),
                 alpha: CGFloat(en))
        }
        // 落章
        let s = progress(t, slam - 0.16, slam)
        if s > 0 {
            let width: CGFloat = 430
            let size = CGSize(width: width, height: width * stamp.size.height / max(stamp.size.width, 1))
            let center = CGPoint(x: 960, y: 622)
            let grow = lerp(1.5, 1, easeIn(s))
            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.rotate(by: -0.04)
            cg.scaleBy(x: grow, y: grow)
            draw(stamp, center: .zero, size: size, alpha: CGFloat(s))
            cg.restoreGState()
            stampRipple(center: center, size: size, x: progress(t, slam, slam + 0.5))
        }
        // 免费下载 + 网址（海报、视频结尾用的短地址）
        let c = easeOut(progress(t, cta, cta + 0.5))
        if c > 0 {
            let y = 818 + lerp(20, 0, c)
            let label = NSAttributedString(string: "免费下载  Free download", attributes: [.font: roundFont(36), .foregroundColor: NSColor.white])
            let arrow = symbol("arrow.down", 30, .semibold, .white)
            let pillW = label.size().width + 64 + 44, pillH: CGFloat = 84
            let url = NSAttributedString(string: "lemomo-ai.github.io/lemo-stampy", attributes: [.font: roundFont(40, .medium), .foregroundColor: Ink.ink])
            let gap: CGFloat = 40
            let total = pillW + gap + url.size().width
            let x0 = 960 - total / 2
            cg.saveGState()
            cg.setAlpha(CGFloat(c))
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            let pill = CGRect(x: x0, y: y - pillH / 2, width: pillW, height: pillH)
            cg.saveGState()
            // 主按钮的阴影：0 4px 12px rgba(210,64,46,.28)
            cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 18,
                         color: NSColor(srgbRed: 210 / 255, green: 64 / 255, blue: 46 / 255, alpha: 0.28).cgColor)
            Ink.coralDeep.setFill()
            NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2).fill()
            cg.restoreGState()
            if let arrow { draw(arrow, center: CGPoint(x: pill.minX + 32 + 15, y: y)) }
            label.draw(at: CGPoint(x: pill.minX + 32 + 44, y: y - label.size().height / 2))
            url.draw(at: CGPoint(x: pill.maxX + gap, y: y - url.size().height / 2))
            cg.endTransparencyLayer()
            cg.restoreGState()
        }
        let os = easeOut(progress(t, cta + 0.3, cta + 0.8))
        if os > 0 {
            text("macOS 14 Sonoma 及以上  ·  macOS 14 Sonoma or later", bodyFont(27), Ink.ink2, center: CGPoint(x: 960, y: 920), alpha: CGFloat(os))
        }
    }

    // MARK: 字幕：中文一行、英文一行，放在一块白色圆角底上（结尾卡自己写着收尾语，不再叠字幕）

    func subtitles(_ t: Double) {
        guard t < mark("outro"), let cue = tl.cues.first(where: { t >= $0.t0 && t < $0.t1 }) else { return }
        let alpha = CGFloat(min(progress(t, cue.t0, cue.t0 + 0.12), 1 - progress(t, cue.t1 - 0.12, cue.t1)))
        guard alpha > 0 else { return }
        let zh = NSAttributedString(string: cue.zh, attributes: [.font: bodyFont(44, .semibold), .foregroundColor: Ink.ink.withAlphaComponent(alpha)])
        let en = NSAttributedString(string: cue.en, attributes: [.font: bodyFont(32, .medium), .foregroundColor: Ink.ink2.withAlphaComponent(alpha)])
        let zs = zh.size(), es = en.size()
        let width = max(zs.width, es.width) + 88
        let height = zs.height + es.height + 36
        // 底边留 60：手机上播放器的进度条、社媒的按钮不会压住字幕。
        let box = CGRect(x: (film.width - width) / 2, y: film.height - 60 - height, width: width, height: height)
        let shape = NSBezierPath(roundedRect: box, xRadius: 28, yRadius: 28)
        cg.saveGState()
        floatShadow(1.0, alpha: 0.8 * alpha)
        NSColor.white.withAlphaComponent(0.92 * alpha).setFill()
        shape.fill()
        cg.restoreGState()
        shape.lineWidth = 1.5
        Ink.warm(0.10 * alpha).setStroke()
        shape.stroke()
        zh.draw(at: CGPoint(x: box.midX - zs.width / 2, y: box.minY + 15))
        en.draw(at: CGPoint(x: box.midX - es.width / 2, y: box.minY + 19 + zs.height))
    }
}
