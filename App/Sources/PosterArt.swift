import AppKit
import StampCore
import SwiftUI

/// 海报素材：`小章 --render-poster-art <目录>` 用真实的盖章引擎和界面组件，画出海报要用的高分辨率印章图和界面图，然后退出。
/// 和官网素材一样用一套临时设置，不碰用户自己的印章和记录。之后再用 HTML 排版、headless Chrome 出图。
///   <目录>/stamps/hero-zh.png、hero-en.png   印章（每点 16 像素，透明底）
///   <目录>/ui/toast-zh.png、toast-en.png   「盖好啦」提示（4 倍，透明底，四周留 30 点给阴影）
@MainActor
enum PosterArt {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-poster-art"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        // 前缀用 site-media-：下次开始前 temporaryDefaults 会顺手清掉没删干净的旧文件。
        guard let (defaults, suite) = AppEnvironment.temporaryDefaults("site-media-poster") else { return true }
        defaults.set(StampID.sample, forKey: "nextStampID")
        Clock.now = { Snapshots.fixedNow }
        AppEnvironment.defaults = defaults
        AppVersion.fixed = "1.0.0"
        _ = LanguageSettings.shared // 见 Snapshots：先建好，免得画到一半按本机偏好换了语言
        Localization.language = .zh
        PosterArtRenderer(dir: dir).run()
        defaults.removePersistentDomain(forName: suite)
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: plist)
        return true
    }
}

@MainActor
private final class PosterArtRenderer {
    let dir: URL
    let stampID = "A7K3Q2"
    let date = Snapshots.fixedNow
    /// 印章每点画多少像素：长章约 100 点宽，画出来约 1600 像素，海报上放多大都清楚。
    let ppp: CGFloat = 16
    /// 界面放大倍数。
    let uiScale: CGFloat = 4

    init(dir: URL) {
        self.dir = dir
    }

    func run() {
        exportStamps()
        Localization.language = .zh
        exportUI(lang: "zh")
        Localization.language = .en
        exportUI(lang: "en")
        Localization.language = .zh
    }

    // MARK: 印章

    private func template(_ name: String) -> StampDesign {
        StampTemplates.all.first(where: { $0.name == name }) ?? StampTemplates.library[0].design
    }

    private func exportStamps() {
        let out = dir.appendingPathComponent("stamps", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // 海报主角：和官网动画同一枚（细框长章 · 租房签约）；英文版用英文长章，颜色换成朱砂，和中文版一样是红章。
        var zh = template("细框长章") // l10n-ignore
        zh.statement = Statement(purpose: "租房签约") // l10n-ignore
        var en = template("英文长章") // l10n-ignore
        en.statement = Statement(purpose: "rental application", phrasing: .english)
        en.color = .red

        var named: [(String, StampDesign)] = [("hero-zh", zh), ("hero-en", en)]

        // 「用在哪儿」海报（16x9-scenes）：六个场景各盖一枚，用不同模板，看得出能刻成各种样子。
        // 中文：（模板，用途）；英文：（模板，用途，字体，颜色）。英文都换成 Serif，中文字体写英文不好看。
        let scenesZH: [(String, String)] = [ // l10n-ignore
            ("细框长章", "租房签约"), ("胶囊签", "签证申请"), ("墨色长章", "银行开户"), // l10n-ignore
            ("签注", "入职办理"), ("再次复印无效", "入学申请"), ("身份证复印件", "保险理赔"), // l10n-ignore
        ]
        let scenesEN: [(String, String, StampFont, StampColor)] = [ // l10n-ignore
            ("英文长章", "rental application", .serif, .red), ("英文胶囊", "visa application", .serif, .black), // l10n-ignore
            ("墨色长章", "account opening", .serif, .black), ("签注", "job onboarding", .serif, .blue), // l10n-ignore
            ("细框长章", "school application", .serif, .red), ("英文圆章", "insurance claim", .serif, .blue), // l10n-ignore
        ]
        for (i, (name, purpose)) in scenesZH.enumerated() {
            var d = template(name)
            d.statement.recipient = "" // 模板里默认写了「××银行」，场景章只写用途
            d.statement.purpose = purpose
            named.append(("scene-zh-\(i + 1)", d))
        }
        for (i, (name, purpose, font, color)) in scenesEN.enumerated() {
            var d = template(name)
            d.statement.recipient = ""
            d.statement.recipientEN = ""
            d.statement.purpose = purpose
            d.statement.phrasing = .english
            d.font = font
            d.color = color
            named.append(("scene-en-\(i + 1)", d))
        }

        for (name, design) in named {
            let text = design.statement.stampText(date: date, stampID: stampID)
            guard let image = StampRenderer.image(text, design: design, pixelsPerPoint: ppp) else { continue }
            savePNG(image, out.appendingPathComponent(name + ".png"))
        }
    }

    // MARK: 界面

    private func exportUI(lang: String) {
        let out = dir.appendingPathComponent("ui", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func tr(_ zh: String, _ en: String) -> String { lang == "en" ? en : zh }

        let output = URL(fileURLWithPath: tr("/tmp/收入证明_已盖章.pdf", "/tmp/Income_stamped.pdf")) // l10n-ignore
        save(ToastView(content: .success(output: output, pages: nil, stampID: stampID), onReveal: { _ in }, onDismiss: {})
            .padding(30), "toast-\(lang)")
    }

    /// SwiftUI 界面按 uiScale 倍画成透明底 PNG。
    private func save<V: View>(_ view: V, _ name: String) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = uiScale
        renderer.isOpaque = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let image = renderer.cgImage else {
            FileHandle.standardError.write("画不出 \(name)\n".data(using: .utf8)!) // l10n-ignore
            return
        }
        savePNG(image, dir.appendingPathComponent("ui/\(name).png"))
    }

    private func savePNG(_ image: CGImage, _ url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
