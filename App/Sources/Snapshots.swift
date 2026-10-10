import AppKit
import PDFKit
import StampCore
import SwiftUI

/// 界面截图：`小章 --render-snapshots <目录>` 把各个界面画成 PNG 后退出，用来和回归基准逐张对比，
/// 也是自动测试里「截图对比」那一层的输入（scripts/snapshots.sh）。
/// 不创建菜单栏图标、不碰用户的设置：用一套临时设置、固定的日期和编号，每次截出来都一样。
@MainActor
enum Snapshots {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Clock.now = { fixedNow }
        // 先建好语言设置：它第一次被用到时会按本机 App 的语言偏好改界面语言，画到一半被改掉，截图就和基准对不上了。
        // 也不读用户自己的设置：面板里「语言」一行选中哪项，不能跟着本机设成什么变。
        if let (defaults, _) = AppEnvironment.temporaryDefaults("snapshots") { AppEnvironment.defaults = defaults }
        AppVersion.fixed = "1.0.0"
        _ = LanguageSettings.shared
        // 中文一套、英文一套（文件名带 -en）：英文通常更长，看看会不会挤出框。
        for language in [UILanguage.zh, .en] {
            Localization.language = language
            guard let (defaults, suite) = AppEnvironment.temporaryDefaults("snapshots") else { return true }
            defaults.set(StampID.sample, forKey: "nextStampID")
            render(to: dir, store: StampStore(defaults: defaults), suffix: language == .zh ? "" : "-en")
            defaults.removePersistentDomain(forName: suite)
        }
        return true
    }

    /// 截图里的「现在」：2026 年 10 月 8 日 14:30。
    static let fixedNow: Date = {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 8; parts.hour = 14; parts.minute = 30
        return Calendar(identifier: .gregorian).date(from: parts) ?? Date()
    }()

    private static func render(to dir: URL, store: StampStore, suffix: String) {
        let noop = MenuPanelView.Actions(pickUp: {}, openEditor: {}, newStamp: {}, openHistory: {}, batch: {}, grant: {},
                                         setLaunchAtLogin: { _ in }, quit: {})
        func shot<V: View>(_ name: String, _ view: V, size: CGSize? = nil, bg: Color = Color(hex: 0xEFDCD3)) {
            let wrapped = view.padding(40).background(bg).environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: wrapped)
            let fitting = host.fittingSize
            host.frame = CGRect(origin: .zero, size: size.map { CGSize(width: $0.width + 80, height: $0.height + 80) } ?? fitting)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name + suffix + ".png"))
            window.close()
        }

        shot("N1-panel", MenuPanelView(store: store, trusted: true, historyCount: 12, launchAtLogin: true, actions: noop))
        shot("N1-panel-unauthorized", MenuPanelView(store: store, trusted: false, historyCount: 12, launchAtLogin: false, actions: noop))
        shot("N1-bubble", PickUpBubble(name: store.current.displayName, arrowX: 150))
        shot("N2-hints", VStack(alignment: .leading, spacing: 0) {
            HoldHint(kind: .offPage)
            HoldHint(kind: .onPage("第 2 页 · 点一下就盖"))
            HoldHint(kind: .size(1.2))
        })
        shot("N0-mascots", HStack(spacing: 16) {
            ForEach([MascotMood.normal, .expectant, .happy, .troubled, .sleepy], id: \.self) { Mascot(mood: $0, size: 88) }
            ForEach([24.0, 36, 56], id: \.self) { Mascot(mood: .normal, size: $0) }
        })
        shot("N0-menubar-icons", HStack(spacing: 20) {
            ForEach([Icons.MenuBarState.normal, .holding, .unauthorized], id: \.self) { s in
                Image(nsImage: Icons.menuBarImage(s)).renderingMode(.template).foregroundStyle(.black).scaleEffect(4).frame(width: 90, height: 80)
            }
        }, bg: Color(hex: 0xF4F1EC))

        // 确认卡片：拿一份 6 页的临时 PDF。
        let pdf = FileManager.default.temporaryDirectory.appendingPathComponent("护照扫描.pdf")
        writeSamplePDF(pdf, pages: 6)
        let target = PreviewTarget(documentURL: pdf, kind: .pdf, pageIndex: 1, pageFrame: CGRect(x: 0, y: 0, width: 595, height: 842),
                                   pageSize: CGSize(width: 595, height: 842))
        let placement = StampPlacement(pageIndex: 1, x: 0.48, y: 0.31, scale: 1)
        let text = store.current.statement.stampText(date: fixedNow, stampID: "A7K3Q2")
        let single = ConfirmModel(target: target, placement: placement, design: store.current, text: text)
        single.pageCount = 6
        shot("N3-confirm", ConfirmCard(model: single, arrowX: 170, arrowOnTop: true, onSave: {}, onCancel: {}))
        let multi = ConfirmModel(target: target, placement: placement, design: store.current, text: text)
        multi.pageCount = 6
        multi.selected = Set(0..<5)
        multi.setAllPages(true)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        shot("N3-confirm-all-pages", ConfirmCard(model: multi, arrowX: 190, arrowOnTop: true, onSave: {}, onCancel: {}))

        let locked = PasswordModel(fileName: "06_加了密码（密码1234）.pdf")
        let wrong = PasswordModel(fileName: "06_加了密码（密码1234）.pdf")
        wrong.password = "123"
        wrong.wrong = true
        shot("N3-password", HStack(alignment: .top, spacing: 24) {
            PasswordCard(model: locked, onUnlock: {}, onCancel: {})
            PasswordCard(model: wrong, onUnlock: {}, onCancel: {})
        })

        shot("N3-toasts", HStack(alignment: .top, spacing: 24) {
            ToastView(content: .progress(done: 3, total: 5), onReveal: { _ in }, onDismiss: {})
            ToastView(content: .batch(done: 11, skipped: 1, outputs: [], stampID: "A7K3Q2"), onReveal: { _ in }, onDismiss: {})
            ToastView(content: .success(output: URL(fileURLWithPath: "/tmp/护照扫描_已盖章.pdf"), pages: 5, stampID: "A7K3Q2"),
                      onReveal: { _ in }, onDismiss: {})
            ToastView(content: .failure(title: L("这份 PDF 加了密码"), message: L("先在「预览」里解锁另存，再来盖一次。")),
                      onReveal: { _ in }, onDismiss: {})
        })

        shot("N3-update", HStack(alignment: .top, spacing: 24) {
            ToastView(content: .checkingUpdate, onReveal: { _ in }, onDismiss: {})
            ToastView(content: .upToDate(version: "1.0.0"), onReveal: { _ in }, onDismiss: {})
            ToastView(content: .updateAvailable(version: "1.1.0", notes: L("批量盖章可以记住上次的位置；修了几个小问题。"),
                                                url: URL(string: "https://example.com")!), onReveal: { _ in }, onDismiss: {})
            ToastView(content: .failure(title: L("没连上官网"), message: L("检查更新需要联网。稍后再试一次，或者直接去官网看看。")),
                      onReveal: { _ in }, onDismiss: {})
        })

        shot("N4-onboarding", OnboardingView(starterCount: 4, onOpenSettings: {}, onShowStamps: {}, onClose: {})
            .clipShape(RoundedRectangle(cornerRadius: 12)), size: CGSize(width: 520, height: 600))
        shot("N5-workshop", EditorView(onPickUp: {}).environmentObject(store).frame(width: 1100, height: 740)
            .clipShape(RoundedRectangle(cornerRadius: 12)), size: CGSize(width: 1100, height: 740))
        shot("N8-templates", TemplateLibraryView().environmentObject(store), size: CGSize(width: 920, height: 640))

        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-history-\(UUID().uuidString).json")
        let history = HistoryStore(fileURL: historyURL)
        let now = fixedNow
        let samples: [(String, Double, String, String, String, String, [Int]?, Int)] = [
            ("A7K3Q2", 0, "招商银行", "办理开户", "护照扫描.pdf", "护照扫描_已盖章.pdf", [1], 1),
            ("9X6CJP", -3600, "招商银行", "办理开户", "收入证明.jpg", "收入证明_已盖章.jpg", nil, 1),
            ("K2M8TR", -4 * 86400, "", "签证申请", "银行流水.pdf", "银行流水_已盖章.pdf", [0, 1, 2, 3, 4], 2),
            ("P4WQ7H", -4 * 86400 - 1800, "", "租房申请", "身份证.heic", "身份证_已盖章.heic", nil, 3),
        ]
        for s in samples.reversed() {
            let design = store.designs.indices.contains(s.7) ? store.designs[s.7] : store.current
            try? history.append(StampRecord(id: s.0, date: now.addingTimeInterval(s.1), recipient: s.2, purpose: s.3, lines: [],
                                            files: [StampedFile(sourceName: s.4, outputPath: "/tmp/" + s.5, sha256: "")],
                                            design: design, pages: s.6))
        }
        shot("N7-history", HistoryView(store: history).frame(width: 720, height: 560).clipShape(RoundedRectangle(cornerRadius: 12)),
             size: CGSize(width: 720, height: 560))
        try? FileManager.default.removeItem(at: historyURL)

        // 批量盖章：一份 6 页、一份 1 页、一张照片、一份要密码、一份不支持。
        let batchDir = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-batch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
        let flow = batchDir.appendingPathComponent("银行流水.pdf")
        writeSamplePDF(flow, pages: 6)
        let passport = batchDir.appendingPathComponent("护照首页.pdf")
        writeSamplePDF(passport, pages: 1)
        let lockedPDF = batchDir.appendingPathComponent("工资单（加密）.pdf")
        writeSamplePDF(lockedPDF, pages: 2)
        if let doc = PDFDocument(url: lockedPDF) {
            _ = doc.write(to: lockedPDF, withOptions: [.userPasswordOption: "1234", .ownerPasswordOption: "1234"])
        }
        let photo = batchDir.appendingPathComponent("身份证正面.jpg")
        writeSamplePhoto(photo)
        let word = batchDir.appendingPathComponent("说明.docx")
        try? Data("x".utf8).write(to: word)
        let batch = BatchModel(store: store)
        batch.add([flow, passport, photo, lockedPDF, word])
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let batchView = { BatchView(model: batch, store: store, onStart: {}, onAddFiles: {}, onClose: {})
            .frame(width: 1040, height: 680).clipShape(RoundedRectangle(cornerRadius: 12)) }
        shot("N9-batch", batchView(), size: CGSize(width: 1040, height: 680))
        batch.pages = .all
        batch.onlyThis = true
        batch.selectedID = photo.standardizedFileURL.path
        batch.move(to: .anchor(column: 0, row: 2))
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        shot("N9-batch-photo-own-spot", batchView(), size: CGSize(width: 1040, height: 680))
        batch.selectedID = lockedPDF.standardizedFileURL.path
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        shot("N9-batch-locked", batchView(), size: CGSize(width: 1040, height: 680))
        let empty = BatchModel(store: store)
        shot("N9-batch-empty", BatchView(model: empty, store: store, onStart: {}, onAddFiles: {}, onClose: {})
            .frame(width: 1040, height: 680).clipShape(RoundedRectangle(cornerRadius: 12)), size: CGSize(width: 1040, height: 680))
        try? FileManager.default.removeItem(at: batchDir)
    }

    private static func writeSamplePhoto(_ url: URL) {
        let w = 1600, h = 1000
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.95, blue: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.85, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 120, y: 300, width: 400, height: 500))
        for i in 0..<5 { ctx.fill(CGRect(x: 640, y: 700 - i * 90, width: 760 - i * 60, height: 36)) }
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func writeSamplePDF(_ url: URL, pages: Int) {
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
}
