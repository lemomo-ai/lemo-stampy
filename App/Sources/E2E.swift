import AppKit
import ApplicationServices
import CryptoKit
import PDFKit
import StampCore
import SwiftUI

/// 这次运行用哪套设置、记录存在哪：平常是用户自己的；端到端测试时换成临时的，不碰用户的印章和记录。
enum AppEnvironment {
    nonisolated(unsafe) static var defaults: UserDefaults = .standard
    nonisolated(unsafe) static var historyURL: URL = HistoryStore.defaultURL

    /// 截图、官网素材、端到端测试用的临时设置：系统会在程序退出后才把空文件写回去，删不干净，所以每次开始前把上次剩下的清掉。
    static func temporaryDefaults(_ prefix: String) -> (UserDefaults, String)? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        where ["site-media-", "snapshots-", "e2e-"].contains(where: { name.hasPrefix($0) }) && name.hasSuffix(".plist") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        let suite = "\(prefix)-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite).map { ($0, suite) }
    }
}

/// 端到端测试（自动测试第 4 层）：`小章 --e2e <目录>`，由 scripts/e2e.sh 启动。
/// 真的用「预览」打开测试文件，程序自己移动鼠标、点、滚轮、打字，盖完检查副本：章在不在点的地方、有没有出界、原件变没变。
/// 会动鼠标和键盘，跑的时候人别碰电脑（大约 1 分钟）。用临时设置和临时记录，存储面板换成固定的输出文件夹。
@MainActor
enum E2E {
    nonisolated(unsafe) static var outputDirectory: URL?
    nonisolated(unsafe) private static var root: URL?
    nonisolated(unsafe) private static var suite: String?

    static var isRunning: Bool { outputDirectory != nil }

    static func configureIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--e2e"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("out"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("files"), withIntermediateDirectories: true)
        root = dir
        outputDirectory = dir.appendingPathComponent("out")
        if let (defaults, name) = AppEnvironment.temporaryDefaults("e2e") {
            suite = name
            defaults.set("E2ETST", forKey: "nextStampID")
            defaults.set("zh", forKey: "languagePreference") // 报告和检查都按中文界面
            AppEnvironment.defaults = defaults
        }
        AppEnvironment.historyURL = dir.appendingPathComponent("history.json")
    }

    // MARK: 跑

    private struct Case {
        let name: String
        var passed = true
        var notes: [String] = []
        mutating func check(_ ok: Bool, _ note: String) {
            notes.append((ok ? "✓ " : "✗ ") + note)
            if !ok { passed = false }
        }
    }

    static func run(app: AppDelegate) async {
        guard let root, let out = outputDirectory else { return }
        let files = root.appendingPathComponent("files")
        let banner = showBanner()
        var cases: [Case] = []
        let started = Date()

        if !PreviewInspector.isTrusted {
            var c = Case(name: "辅助功能权限")
            c.check(false, "小章没有辅助功能权限：在「系统设置 › 隐私与安全性 › 辅助功能」里打开后再跑")
            cases.append(c)
        } else {
            let single = files.appendingPathComponent("单页.pdf")
            let multi = files.appendingPathComponent("六页.pdf")
            let locked = files.appendingPathComponent("加密（1234）.pdf")
            let photo = files.appendingPathComponent("照片.jpg")
            let note = files.appendingPathComponent("说明.txt")
            writePDF(single, pages: 1)
            writePDF(multi, pages: 6)
            writePDF(locked, pages: 2, password: "1234")
            writePhoto(photo)
            try? Data("不是 PDF".utf8).write(to: note)
            let originals = Dictionary(uniqueKeysWithValues: [single, multi, locked, photo].map { ($0.path, sha($0)) })

            cases.append(await stampCase("单页 PDF：点哪儿盖哪儿", app: app, file: single, at: CGPoint(x: 0.62, y: 0.38), out: out))
            cases.append(await edgeCase(app: app, file: single, out: out))
            cases.append(await stampCase("滚轮调大 3 格（130%）", app: app, file: single, at: CGPoint(x: 0.5, y: 0.3), out: out, scroll: 3))
            cases.append(await stampCase("多页 PDF：每一页都盖、去掉第 4 页", app: app, file: multi, at: CGPoint(x: 0.7, y: 0.4), out: out,
                                         allPagesExcept: 3))
            cases.append(await passwordCase(app: app, file: locked, out: out))
            cases.append(await stampCase("照片", app: app, file: photo, at: CGPoint(x: 0.3, y: 0.7), out: out))
            cases.append(await escCase(app: app, file: single))
            cases.append(await batchCase(app: app, inputs: [single, multi, photo, locked, note], out: out))

            var c = Case(name: "原件一个字节都没变")
            for (path, hash) in originals {
                c.check(sha(URL(fileURLWithPath: path)) == hash, URL(fileURLWithPath: path).lastPathComponent)
            }
            cases.append(c)
            closePreviewWindows(in: files)
        }

        banner.orderOut(nil)
        let passed = cases.filter(\.passed).count
        var report = "# 小章端到端测试\n\n"
        report += "\(Date().mochi("yyyy-MM-dd HH:mm")) · 用时 \(Int(Date().timeIntervalSince(started))) 秒 · "
        report += "**\(passed) / \(cases.count) 通过**\n\n"
        for c in cases {
            report += "## \(c.passed ? "✓" : "✗") \(c.name)\n\n" + c.notes.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        report += "输出文件在 `\(out.path)`。\n"
        try? report.write(to: root.appendingPathComponent("报告.md"), atomically: true, encoding: .utf8)
        print(report)
        if let suite { AppEnvironment.defaults.removePersistentDomain(forName: suite) }
        if let suite {
            try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(suite).plist"))
        }
        exit(passed == cases.count ? 0 : 1)
    }

    // MARK: 用例

    /// 打开文件 → 拿起章 →（滚轮）→ 点 →（每一页都盖）→ 回车存 → 看副本。
    private static func stampCase(_ name: String, app: AppDelegate, file: URL, at rel: CGPoint, out: URL,
                                  scroll: Int = 0, allPagesExcept skip: Int? = nil) async -> Case {
        var c = Case(name: name)
        app.store.sizeMultiplier = 1
        guard let target = await openAndFindPage(file) else {
            c.check(false, "「预览」里没找到这份文件的页面")
            return c
        }
        let point = visiblePoint(target, rel)
        let before = outputs(in: out)
        app.pickUpStamp()
        await move(to: point)
        if scroll != 0 {
            for _ in 0..<abs(scroll) { postScroll(scroll > 0 ? 1 : -1); await wait(0.12) }
            c.check(abs(app.store.sizeMultiplier - (1 + Double(scroll) * 0.1)) < 0.001,
                    "滚轮把大小调到 \(Int((app.store.sizeMultiplier * 100).rounded()))%")
        }
        await click(at: point)
        guard await until({ app.currentSession?.confirmModelForTesting != nil }) else {
            c.check(false, "点下去以后没出确认卡片")
            app.dropStamp()
            return c
        }
        c.check(true, "点下去出了确认卡片")
        if let skip, let model = app.currentSession?.confirmModelForTesting {
            _ = await until({ model.pageCount > 1 })
            model.setAllPages(true)
            model.selectAll()
            model.toggle(skip)
        }
        postKey(36) // 回车
        guard let output = await newOutput(in: out, before: before) else {
            c.check(false, "回车后没有存出副本")
            return c
        }
        c.check(output.lastPathComponent.contains("_已盖章"), "副本：\(output.lastPathComponent)")
        let expectedRel = target.relativePosition(of: point)
        let pages = images(of: output)
        if let skip {
            c.check(pages.count == 6, "副本还是 6 页")
            for (i, page) in pages.enumerated() {
                let box = redBox(page)
                if i == skip {
                    c.check(box == nil, "第 \(i + 1) 页没盖（去掉了）")
                } else {
                    c.check(box.map { near($0, expectedRel) } ?? false, "第 \(i + 1) 页盖在同一个相对位置")
                }
            }
        } else if let page = pages.first, let box = redBox(page) {
            c.check(near(box, expectedRel), String(format: "章的中心在 (%.2f, %.2f)，点的是 (%.2f, %.2f)",
                                                    box.midX, box.midY, expectedRel.x, expectedRel.y))
            if scroll != 0, let base = baseSize {
                c.check(abs(box.width / base.width - (1 + CGFloat(scroll) * 0.1)) < 0.08,
                        String(format: "章的宽度是 100%% 时的 %.2f 倍", box.width / base.width))
            } else if scroll == 0, file.pathExtension == "pdf", baseSize == nil {
                baseSize = box.size
            }
        } else {
            c.check(false, "副本上没找到章")
        }
        closePreviewWindows(in: file.deletingLastPathComponent())
        return c
    }

    /// 100% 时单页 PDF 上章的相对大小：滚轮、贴边用例拿它比。
    nonisolated(unsafe) private static var baseSize: CGSize?

    /// 页边：点在页面右下角，章要整枚留在纸里。
    private static func edgeCase(app: AppDelegate, file: URL, out: URL) async -> Case {
        var c = Case(name: "贴边：点在页面右下角，章不出界")
        app.store.sizeMultiplier = 1
        guard let target = await openAndFindPage(file) else {
            c.check(false, "「预览」里没找到页面")
            return c
        }
        let visible = visiblePageRect(target)
        let point = CGPoint(x: visible.maxX - 3, y: visible.maxY - 3)
        let before = outputs(in: out)
        app.pickUpStamp()
        await move(to: point)
        await click(at: point)
        guard await until({ app.currentSession?.confirmModelForTesting != nil }) else {
            c.check(false, "没出确认卡片")
            app.dropStamp()
            return c
        }
        postKey(36)
        guard let output = await newOutput(in: out, before: before), let page = images(of: output).first, let box = redBox(page) else {
            c.check(false, "没存出副本或副本上没有章")
            return c
        }
        // 靠边时章会被推到刚好贴着纸边（DocumentStamper.center），所以章的边缘本来就在 0.99 以上；
        // 要看的是推进来了、没被纸边切掉：宽高都和 100% 时一样。
        c.check(box.maxX > 0.97 && box.minX > 0.005, String(format: "贴着右边、整枚在纸里（%.3f – %.3f）", box.minX, box.maxX))
        if let base = baseSize {
            c.check(box.width > base.width * 0.9, String(format: "左右没被切掉：宽度是正常的 %.0f%%", box.width / base.width * 100))
        }
        let rel = target.relativePosition(of: point)
        if rel.y > 0.9 {
            c.check(box.maxY > 0.97, String(format: "贴着下边（%.3f）", box.maxY))
            if let base = baseSize {
                c.check(box.height > base.height * 0.9, String(format: "上下没被切掉：高度是正常的 %.0f%%", box.height / base.height * 100))
            }
        }
        closePreviewWindows(in: file.deletingLastPathComponent())
        return c
    }

    /// 密码 PDF：点在加了密码的 PDF 上 → 输错 → 输对 → 直接盖在刚才点的地方 → 副本也要密码。
    private static func passwordCase(app: AppDelegate, file: URL, out: URL) async -> Case {
        var c = Case(name: "加密 PDF：输错再输对，直接落章，副本也加密")
        app.store.sizeMultiplier = 1
        // 「预览」会先要密码才显示页面：用「预览」自己的密码框解开它（这是「预览」的事，不算小章的）。
        _ = try? await NSWorkspace.shared.open([file], withApplicationAt: previewAppURL, configuration: NSWorkspace.OpenConfiguration())
        await wait(2)
        typeDigits("1234")
        postKey(36)
        await wait(1.5)
        guard let target = await findPage(file, timeout: 8) else {
            c.check(false, "「预览」里没打开加密文件的页面")
            return c
        }
        c.check(target.isLocked, "小章认出这份要密码")
        let point = visiblePoint(target, CGPoint(x: 0.4, y: 0.5))
        let before = outputs(in: out)
        app.pickUpStamp()
        await move(to: point)
        await click(at: point)
        await wait(0.8)
        c.check(NSApp.keyWindow is FloatingPanel<PasswordCard>, "弹出了密码卡片，并且能直接打字")
        typeDigits("9999")
        postKey(36)
        await wait(1)
        c.check(app.currentSession?.confirmModelForTesting == nil, "输错密码：不盖")
        postKey(0, flags: .maskCommand) // ⌘A 选中输错的密码
        typeDigits("1234")
        postKey(36)
        guard await until({ app.currentSession?.confirmModelForTesting != nil }) else {
            c.check(false, "输对密码后没有直接落章")
            app.dropStamp()
            return c
        }
        c.check(true, "输对密码后直接落章，出了确认卡片")
        postKey(36)
        guard let output = await newOutput(in: out, before: before) else {
            c.check(false, "没存出副本")
            return c
        }
        let doc = PDFDocument(url: output)
        c.check(doc?.isLocked == true, "副本要密码")
        c.check(doc?.unlock(withPassword: "1234") == true, "副本用 1234 能打开")
        if let doc, let page = doc.page(at: target.pageIndex), let box = redBox(render(page)) {
            c.check(near(box, target.relativePosition(of: point)), "章盖在点的地方")
        } else {
            c.check(false, "副本上没找到章")
        }
        closePreviewWindows(in: file.deletingLastPathComponent())
        return c
    }

    private static func escCase(app: AppDelegate, file: URL) async -> Case {
        var c = Case(name: "esc 放下印章")
        app.pickUpStamp()
        await wait(0.4)
        c.check(app.isHolding, "拿起来了")
        postKey(53)
        await wait(0.4)
        c.check(!app.isHolding, "按 esc 放下了")
        return c
    }

    private static func batchCase(app: AppDelegate, inputs: [URL], out: URL) async -> Case {
        var c = Case(name: "批量盖章：5 份里 4 份能盖（加密的已经输过密码），txt 跳过")
        app.showBatch(inputs)
        guard let model = app.batchModelForTesting else {
            c.check(false, "没打开批量窗口")
            return c
        }
        _ = await until({ !model.files.contains(where: \.isReading) })
        model.pages = .all
        model.output = .folder(out.appendingPathComponent("批量"))
        let historyBefore = app.history.load().count
        let stampID = app.store.nextStampID
        // 窗口开着过了一阵才盖：记录的时间要是盖的时候，不是开窗口的时候。
        let later = Date().addingTimeInterval(600)
        Clock.now = { later }
        defer { Clock.now = { Date() } }
        model.start(history: app.history, toast: app.toast)
        guard await until({ model.finished }, timeout: 20) else {
            c.check(false, "20 秒没盖完")
            return c
        }
        c.check(model.outputs.count == 4, "盖好 \(model.outputs.count) 份")
        let skipped = model.files.filter { if case .done = $0.result { return false } else { return true } }
        c.check(skipped.map(\.name) == ["说明.txt"], "跳过的：\(skipped.map(\.name).joined(separator: "、"))")
        let records = app.history.load()
        c.check(records.count == historyBefore + 1, "记录里多了一条（一批一条）")
        // 记录从旧到新排：按这批的编号找，别拿 first（那是最旧的一条）。
        let record = records.first { $0.id == stampID }
        c.check(record?.files.count == 4, "这条记录（\(stampID)）里有 \(record?.files.count ?? 0) 份文件")
        c.check(abs((record?.date ?? .distantPast).timeIntervalSince(later)) < 1, "记录的时间是盖的时候，不是开窗口的时候")
        for url in model.outputs {
            let pages = images(of: url, password: "1234")
            let stamped = pages.filter { redBox($0) != nil }.count
            c.check(!pages.isEmpty && stamped == pages.count, "\(url.lastPathComponent)：\(stamped)/\(pages.count) 页有章")
        }
        app.batchWindowForTesting?.close()
        return c
    }

    // MARK: 「预览」

    private static var previewAppURL: URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: PreviewInspector.previewBundleID)
            ?? URL(fileURLWithPath: "/System/Applications/Preview.app")
    }

    private static func openAndFindPage(_ file: URL) async -> PreviewTarget? {
        _ = try? await NSWorkspace.shared.open([file], withApplicationAt: previewAppURL, configuration: NSWorkspace.OpenConfiguration())
        return await findPage(file, timeout: 10)
    }

    /// 在「预览」最前面那个窗口里撒点找页面：PreviewInspector 第一次读页面尺寸在后台，所以多等几轮。
    private static func findPage(_ file: URL, timeout: Double) async -> PreviewTarget? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let frame = previewWindowFrame(for: file) {
                for fy in [0.5, 0.4, 0.6, 0.3, 0.7] {
                    for fx in [0.5, 0.4, 0.6] {
                        let p = CGPoint(x: frame.minX + frame.width * fx, y: frame.minY + frame.height * fy)
                        if let t = PreviewInspector.target(at: p), t.documentURL.standardizedFileURL.path == file.standardizedFileURL.path,
                           t.isLocked || t.pageSize != .zero {
                            return t
                        }
                    }
                }
            }
            await wait(0.4)
        }
        return nil
    }

    private static func previewApp() -> AXUIElement? {
        NSRunningApplication.runningApplications(withBundleIdentifier: PreviewInspector.previewBundleID).first
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    private static func previewWindows() -> [AXUIElement] {
        guard let app = previewApp() else { return [] }
        var value: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    private static func document(of window: AXUIElement) -> URL? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &value)
        return (value as? String).flatMap(URL.init(string:))
    }

    private static func previewWindowFrame(for file: URL) -> CGRect? {
        for window in previewWindows() where document(of: window)?.standardizedFileURL.path == file.standardizedFileURL.path {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            NSRunningApplication.runningApplications(withBundleIdentifier: PreviewInspector.previewBundleID).first?.activate()
            var pos: AnyObject?, size: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pos)
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)
            var p = CGPoint.zero, s = CGSize.zero
            if let pos { AXValueGetValue(pos as! AXValue, .cgPoint, &p) }
            if let size { AXValueGetValue(size as! AXValue, .cgSize, &s) }
            guard s.width > 10 else { continue }
            return CGRect(origin: p, size: s)
        }
        return nil
    }

    /// 只关测试自己打开的窗口，用户自己开着的文件不碰。
    private static func closePreviewWindows(in dir: URL) {
        for window in previewWindows() {
            guard let doc = document(of: window), doc.standardizedFileURL.path.hasPrefix(dir.standardizedFileURL.path) else { continue }
            var button: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button)
            if let button { AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) }
        }
    }

    /// 页面在窗口里看得见的部分（页面可能比窗口长）。
    private static func visiblePageRect(_ target: PreviewTarget) -> CGRect {
        guard let window = previewWindowFrame(for: target.documentURL) else { return target.pageFrame }
        let content = CGRect(x: window.minX, y: window.minY + 60, width: window.width, height: window.height - 70)
        return target.pageFrame.intersection(content)
    }

    private static func visiblePoint(_ target: PreviewTarget, _ rel: CGPoint) -> CGPoint {
        let r = visiblePageRect(target)
        return CGPoint(x: r.minX + r.width * rel.x, y: r.minY + r.height * rel.y)
    }

    // MARK: 鼠标、键盘

    private static func move(to point: CGPoint) async {
        let start = CGEvent(source: nil)?.location ?? point
        for i in 1...12 {
            let t = CGFloat(i) / 12
            let p = CGPoint(x: start.x + (point.x - start.x) * t, y: start.y + (point.y - start.y) * t)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            await wait(0.02)
        }
        await wait(0.3)
    }

    private static func click(at point: CGPoint) async {
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        await wait(0.05)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        await wait(0.4)
    }

    private static func postScroll(_ lines: Int32) {
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    }

    private static func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    private static func typeDigits(_ digits: String) {
        let codes: [Character: CGKeyCode] = ["1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29]
        for ch in digits { if let code = codes[ch] { postKey(code); usleep(40_000) } }
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func until(_ condition: () -> Bool, timeout: Double = 6) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            await wait(0.1)
        }
        return condition()
    }

    // MARK: 检查副本

    private static func outputs(in dir: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    }

    private static func newOutput(in dir: URL, before: Set<String>) async -> URL? {
        var found: URL?
        _ = await until({
            guard let name = outputs(in: dir).subtracting(before).first(where: { !$0.hasPrefix(".") }) else { return false }
            found = dir.appendingPathComponent(name)
            return true
        }, timeout: 10)
        await wait(0.6) // 等写完
        return found
    }

    private static func images(of url: URL, password: String? = nil) -> [CGImage] {
        if DocumentStamper.kind(of: url) == .image {
            return (try? DocumentStamper.pageImage(of: url, maxPixel: 1200)).map { [$0] } ?? []
        }
        guard let doc = PDFDocument(url: url) else { return [] }
        if doc.isLocked, let password { _ = doc.unlock(withPassword: password) }
        return (0..<doc.pageCount).compactMap { doc.page(at: $0).map(render) }
    }

    private static func render(_ page: PDFPage) -> CGImage {
        (try? DocumentStamper.pageImage(of: page)) ?? NSImage().cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    /// 红色像素的外框（相对坐标，从左、从上）；没有红色就是 nil。
    private static func redBox(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if Int(data[i]) - Int(data[i + 1]) > 60, Int(data[i]) - Int(data[i + 2]) > 60 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                      width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
    }

    private static func near(_ box: CGRect, _ rel: (x: Double, y: Double)) -> Bool {
        abs(Double(box.midX) - rel.x) < 0.04 && abs(Double(box.midY) - rel.y) < 0.04
    }

    private static func near(_ box: CGRect, _ rel: CGPoint) -> Bool {
        near(box, (Double(rel.x), Double(rel.y)))
    }

    private static func sha(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 测试文件

    private static func writePDF(_ url: URL, pages: Int, password: String? = nil) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
            for line in 0..<18 { ctx.fill(CGRect(x: 60, y: 760 - CGFloat(line) * 30, width: 470 - CGFloat((line * 37) % 120), height: 9)) }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        if let password, let doc = PDFDocument(url: url) {
            _ = doc.write(to: url, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password])
        }
    }

    private static func writePhoto(_ url: URL) {
        let w = 2400, h = 1600
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        ctx.setFillColor(CGColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(srgbRed: 0.75, green: 0.8, blue: 0.86, alpha: 1))
        for i in 0..<6 { ctx.fill(CGRect(x: 200, y: 1300 - i * 180, width: 1800 - i * 150, height: 60)) }
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }

    // MARK: 提示条

    private static func showBanner() -> NSPanel {
        let view = HStack(spacing: 10) {
            Mascot(mood: .expectant, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("小章正在自动测试").font(Theme.round(14)).foregroundStyle(Theme.onInk)
                Text("别动鼠标和键盘，大约 1 分钟，测完自己关掉").font(Theme.body(11)).foregroundStyle(Theme.onInk2)
            }
        }
        .padding(.horizontal, 14).frame(height: 52)
        .background(Capsule().fill(Theme.ink))
        let panel = FloatingPanel(rootView: view, margin: 20, keyable: false,
                                  level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3))
        panel.ignoresMouseEvents = true
        let size = panel.contentSize
        if let screen = NSScreen.main {
            panel.place(contentFrame: CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 24,
                                             width: size.width, height: size.height))
        }
        panel.orderFrontRegardless()
        return panel
    }
}

extension DocumentStamper {
    /// 端到端测试检查副本用：一页 PDF 画成 1:1 的图。
    static func pageImage(of page: PDFPage) throws -> CGImage {
        let box = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        let size = (rotation == 90 || rotation == 270) ? CGSize(width: box.height, height: box.width) : box.size
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw StampError.renderFailed }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        page.draw(with: .cropBox, to: ctx)
        guard let image = ctx.makeImage() else { throw StampError.renderFailed }
        return image
    }
}
