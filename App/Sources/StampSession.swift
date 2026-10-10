import AppKit
import Combine
import PDFKit
import StampCore
import SwiftUI
import UniformTypeIdentifiers

/// 一次「拿起印章 → 盖下去 → 另存为」的过程。
///
/// 拿起印章后每块屏幕上会铺一层几乎透明的浮层接住点击（不会点到「预览」里），
/// 印章图跟着鼠标走；悬停在「预览」的页面上时，按页面缩放实时调整印章大小，所见即所得。
@MainActor
final class StampSession {
    struct Hooks {
        /// 鼠标是不是点在菜单栏图标上（再点一次图标 = 放下印章）。
        var isOnStatusItem: (CGPoint) -> Bool
        var toast: ToastController
        var onFinish: () -> Void
    }

    private let design: StampDesign
    private let store: StampStore
    private let history: HistoryStore
    private let hooks: Hooks

    private let stampID: String
    private let date = Date()
    private var text: StampText { design.statement.stampText(date: date, stampID: stampID) }

    /// 盖在哪、提示写什么、该弹哪张卡片：逻辑都在 Core 的 StampFlow 里（有单元测试），这里只管窗口。
    private var flow: StampFlow
    private var overlays: [NSWindow] = []
    private let stampWindow = StampCursorWindow()
    private var confirmPanel: FloatingPanel<ConfirmCard>?
    private var confirmModel: ConfirmModel?
    private var confirmObserver: AnyCancellable?
    private var passwordPanel: FloatingPanel<PasswordCard>?
    private var passwordModel: PasswordModel?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var hoverTarget: PreviewTarget?
    private var lastInspection = Date.distantPast
    private var sizeHintTask: Task<Void, Never>?
    private var scrollAccumulator: CGFloat = 0

    init(design: StampDesign, store: StampStore, history: HistoryStore, hooks: Hooks) {
        self.design = design
        self.store = store
        self.history = history
        self.hooks = hooks
        stampID = store.nextStampID
        let text = design.statement.stampText(date: date, stampID: stampID)
        flow = StampFlow(stampSize: StampRenderer.boundingSize(text, design: design), sizeMultiplier: store.sizeMultiplier)
    }

    // MARK: 开始 / 结束

    func begin() {
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            // 完全透明的窗口点击会穿透下去，所以留 1% 的不透明度。
            window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = CrosshairView()
            window.orderFrontRegardless()
            overlays.append(window)
        }
        (overlays.first { $0.screen == NSScreen.main } ?? overlays.first)?.makeKey()
        stampWindow.orderFrontRegardless()

        // 系统弹窗（比如「允许访问桌面文件夹」）抢走焦点时，立刻放下印章、撤掉浮层，
        // 否则弹窗被浮层盖住点不到，看起来就像卡死。
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        })
        observers.append(center.addObserver(forName: PreviewInspector.pageSizeLoaded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.flow.state == .hovering else { return }
                self.refresh(force: true)
            }
        })
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        refresh(force: true)
    }

    func cancel() {
        finish()
    }

    private func finish() {
        guard !flow.isFinished else { return }
        flow.finish()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        sizeHintTask?.cancel()
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        stampWindow.orderOut(nil)
        closeConfirmPanel()
        closePasswordPanel()
        hooks.onFinish()
    }

    // MARK: 事件

    private func handle(_ event: NSEvent) -> NSEvent? {
        // 确认卡片上的按钮、缩略图，密码卡片上的输入框照常响应。
        if let panel = confirmPanel, event.window === panel { return event }
        if let panel = passwordPanel, event.window === panel { return event }

        switch event.type {
        case .mouseMoved, .leftMouseDragged:
            if flow.state == .hovering { refresh() }
            return nil
        case .leftMouseDown:
            if case .unlocking = flow.state {} else if hooks.isOnStatusItem(NSEvent.mouseLocation) { cancel(); return nil }
            click()
            return nil
        case .rightMouseDown:
            // 输密码时右键点别处：只收起密码卡片，接着拿着章。
            if case .unlocking = flow.state { backToHovering() } else { cancel() }
            return nil
        case .scrollWheel:
            resize(by: event)
            return nil
        case .keyDown:
            switch event.keyCode {
            case 53: cancel()                                     // esc
            case 36, 76: if flow.isConfirming { saveAs() }        // ↩ / enter
            default: break
            }
            return nil
        default:
            return event
        }
    }

    /// 滚一格 ±10%，范围 40%–400%。触控板按滑动距离累计。
    private func resize(by event: NSEvent) {
        var steps = 0
        if event.hasPreciseScrollingDeltas {
            scrollAccumulator += event.scrollingDeltaY
            while scrollAccumulator >= 12 { steps += 1; scrollAccumulator -= 12 }
            while scrollAccumulator <= -12 { steps -= 1; scrollAccumulator += 12 }
        } else if event.scrollingDeltaY != 0 {
            steps = event.scrollingDeltaY > 0 ? 1 : -1
        }
        guard steps != 0 else { return }
        let moved = flow.scroll(steps: steps)
        store.sizeMultiplier = flow.sizeMultiplier

        if case .confirming(let target, let placement) = flow.state, moved != nil {
            // 变大以后可能出界：StampFlow 已经往里推过，屏幕上的章跟着挪。
            showStamp(at: target.screenPoint(x: placement.x, y: placement.y), target: target, hint: nil)
            confirmModel?.placement = placement
            layoutConfirmPanel()
        } else {
            sizeHintTask?.cancel()
            sizeHintTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.05))
                guard !Task.isCancelled, let self, self.flow.state == .hovering else { return }
                self.flow.hideSizeHint()
                self.refresh(force: false)
            }
            refresh(force: true)
        }
    }

    /// 鼠标位置：辅助功能坐标（左上角原点）。
    private var axMouse: CGPoint {
        let p = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    private func refresh(force: Bool = false) {
        // 辅助功能查询每 30ms 最多一次，印章位置每次都跟。
        if force || Date().timeIntervalSince(lastInspection) > 0.03 {
            lastInspection = Date()
            hoverTarget = PreviewInspector.target(at: axMouse)
        }
        // 在页面上时，靠边的章贴着页边停住，不跑出页面：看到哪儿就盖在哪儿。
        let hover = flow.hover(over: hoverTarget, at: axMouse)
        if let target = hoverTarget, let placement = hover.placement {
            showStamp(at: target.screenPoint(x: placement.x, y: placement.y), target: target, hint: hover.hint)
        } else {
            showStamp(at: NSEvent.mouseLocation, target: hoverTarget, hint: hover.hint)
        }
    }

    private func showStamp(at point: CGPoint, target: PreviewTarget?, hint: StampFlow.Hint?) {
        let kind: HoldHint.Kind?
        switch hint {
        case .offPage: kind = .offPage
        case .onPage(let text): kind = .onPage(text)
        case .size(let value): kind = .size(value)
        case nil: kind = nil
        }
        let usable = target.flatMap { $0.isLocked ? nil : $0 }
        let pointsPerStampPoint = (usable?.screenPointsPerStampPoint ?? 1) * CGFloat(flow.sizeMultiplier)
        stampWindow.show(text: text, design: design, pointsPerStampPoint: pointsPerStampPoint,
                         center: point, active: usable != nil, hint: kind)
    }

    private func click() {
        let target = PreviewInspector.target(at: axMouse)
        switch flow.click(on: target, at: axMouse) {
        case .missed:
            NSSound.beep()
        case .askPassword:
            if let target { showPasswordPanel(target: target) }
        case .placed(let placement):
            if let target { placed(on: target, placement) }
        case .cancelledUnlock:
            backToHovering()
        case .ignored:
            break
        }
    }

    private func placed(on target: PreviewTarget, _ placement: StampPlacement) {
        showStamp(at: target.screenPoint(x: placement.x, y: placement.y), target: target, hint: nil)
        stampWindow.playDrop()
        showConfirmPanel(target: target, placement: placement)
    }

    // MARK: 输密码

    private func showPasswordPanel(target: PreviewTarget) {
        showStamp(at: NSEvent.mouseLocation, target: target, hint: flow.hover(over: target, at: axMouse).hint)
        closePasswordPanel()
        let model = PasswordModel(fileName: target.documentURL.lastPathComponent)
        passwordModel = model
        let panel = FloatingPanel(rootView: makePasswordCard(model), margin: 40, keyable: true,
                                  level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2))
        passwordPanel = panel
        let size = panel.contentSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        var rect = CGRect(x: mouse.x - size.width / 2, y: mouse.y - 40 - size.height, width: size.width, height: size.height)
        if rect.minY < screen.visibleFrame.minY + 8 { rect.origin.y = mouse.y + 40 }
        rect.origin.x = min(max(rect.minX, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        panel.place(contentFrame: rect)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePasswordCard(_ model: PasswordModel) -> PasswordCard {
        PasswordCard(model: model,
                     onUnlock: { [weak self] in self?.tryUnlock() },
                     onCancel: { [weak self] in self?.backToHovering() })
    }

    private func tryUnlock() {
        guard case .unlocking(let target, _) = flow.state, let model = passwordModel, !model.checking else { return }
        let url = target.documentURL, index = target.pageIndex, password = model.password
        model.checking = true
        model.wrong = false
        // 读文件放后台：桌面 / 文稿里的文件可能触发系统授权框。
        Task.detached(priority: .userInitiated) {
            let size: CGSize? = DocumentStamper.unlock(url, password: password)
                ? try? DocumentStamper.pageSize(of: url, pageIndex: index) : nil
            await MainActor.run { [weak self] in
                guard let self, case .unlocking = self.flow.state else { return }
                model.checking = false
                guard let size else {
                    model.wrong = true
                    return
                }
                PreviewInspector.didUnlock(url, pageIndex: index, size: size)
                self.closePasswordPanel()
                self.overlays.first { $0.screen == NSScreen.main }?.makeKey()
                // 解开了：直接盖在刚才点的地方。
                let unlocked = PreviewTarget(documentURL: url, kind: .pdf, pageIndex: index, pageFrame: target.pageFrame, pageSize: size)
                if let placement = self.flow.unlocked(unlocked) { self.placed(on: unlocked, placement) }
            }
        }
    }

    private func backToHovering() {
        closePasswordPanel()
        guard !flow.isFinished else { return }
        flow.cancelUnlock()
        (overlays.first { $0.screen == NSScreen.main } ?? overlays.first)?.makeKey()
        refresh(force: true)
    }

    private func closePasswordPanel() {
        passwordPanel?.orderOut(nil)
        passwordPanel = nil
        passwordModel = nil
    }

    // MARK: 确认卡片

    private func showConfirmPanel(target: PreviewTarget, placement: StampPlacement) {
        // 换位置时沿用同一张卡片：页的勾选和「每一页都盖」不丢。
        if let model = confirmModel, model.documentURL == target.documentURL {
            model.clickedPage = target.pageIndex
            model.placement = placement
            layoutConfirmPanel()
            return
        }
        closeConfirmPanel()
        let model = ConfirmModel(target: target, placement: placement, design: design, text: text)
        confirmModel = model
        let panel = FloatingPanel(rootView: makeCard(model, arrowX: 170, arrowOnTop: true), margin: 40, keyable: false,
                                  level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2))
        confirmPanel = panel
        layoutConfirmPanel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        // 卡片内容一变（切换「每一页都盖」、缩略图到了），大小跟着变。
        confirmObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layoutConfirmPanel() } }
        }
        model.load()
    }

    private func makeCard(_ model: ConfirmModel, arrowX: CGFloat, arrowOnTop: Bool) -> ConfirmCard {
        ConfirmCard(model: model, arrowX: arrowX, arrowOnTop: arrowOnTop,
                    onSave: { [weak self] in self?.saveAs() },
                    onCancel: { [weak self] in self?.cancel() })
    }

    /// 卡片放在印章下方 24pt，箭头对准印章中心；贴近屏幕底部时改放上方。
    private func layoutConfirmPanel() {
        guard let panel = confirmPanel, let model = confirmModel,
              case .confirming(let target, let placement) = flow.state else { return }
        let point = target.screenPoint(x: placement.x, y: placement.y)
        let stamp = stampWindow.stampRect
        let size = panel.contentSize
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main!
        var rect = CGRect(x: point.x - size.width / 2, y: stamp.minY - 24 - size.height, width: size.width, height: size.height)
        var arrowOnTop = true
        if rect.minY < screen.visibleFrame.minY + 8 {
            rect.origin.y = stamp.maxY + 24
            arrowOnTop = false
        }
        rect.origin.x = min(max(rect.minX, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let arrowX = min(max(point.x - rect.minX, 24), size.width - 24)
        panel.update(makeCard(model, arrowX: arrowX, arrowOnTop: arrowOnTop))
        panel.place(contentFrame: rect)
    }

    private func closeConfirmPanel() {
        confirmObserver = nil
        confirmModel?.cancelLoading()
        confirmModel = nil
        confirmPanel?.orderOut(nil)
        confirmPanel = nil
    }

    // MARK: 另存为

    private func saveAs() {
        guard case .confirming(let target, _) = flow.state else { return }
        let allPages = confirmModel.map { $0.allPages && $0.pageCount > 1 } ?? false
        let placements = flow.placementsToSave(allPages: allPages, selected: confirmModel?.selected ?? [],
                                               pageCount: confirmModel?.pageCount ?? 1)
        if allPages {
            ConfirmModel.rememberAllPages(true, for: target.documentURL)
        } else if target.kind == .pdf {
            ConfirmModel.rememberAllPages(false, for: target.documentURL)
        }
        guard !placements.isEmpty else { return }

        // 浮层会挡住存储面板，先收起来。
        overlays.forEach { $0.orderOut(nil) }
        stampWindow.orderOut(nil)
        confirmPanel?.orderOut(nil)

        let source = target.documentURL
        let output: URL
        if let directory = E2E.outputDirectory {
            // 端到端测试：不弹存储面板，直接存进测试的输出文件夹。
            output = DocumentStamper.suggestedOutputURL(for: source, directory: directory)
        } else {
            guard let chosen = runSavePanel(for: target) else {
                finish()
                return
            }
            output = chosen
        }
        let toast = hooks.toast
        if output.standardizedFileURL == source.standardizedFileURL {
            finish()
            toast.show(.failure(title: L("不能覆盖原文件"), message: L("小章只生成副本，请换一个文件名。")))
            return
        }

        let design = design, text = text, history = history, stampID = stampID, date = date, store = store
        let pages = target.kind == .pdf ? placements.map(\.pageIndex) : nil
        finish()

        // 大 PDF 才看得到「正在盖…」：0.4 秒内盖完就直接跳到「盖好啦」。
        let job = StampJob()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            if !job.isDone {
                job.shown = true
                toast.show(.progress(done: job.done, total: placements.count))
            }
        }
        Task.detached(priority: .userInitiated) {
            do {
                try DocumentStamper.stamp(input: source, output: output, placements: placements, design: design, text: text) { done, total in
                    Task { @MainActor in
                        job.done = done
                        if !job.isDone, job.shown { toast.show(.progress(done: done, total: total)) }
                    }
                }
                let file = StampedFile(sourceName: source.lastPathComponent, outputPath: output.path,
                                       sha256: (try? HistoryStore.sha256(of: output)) ?? "")
                try? history.append(StampRecord(id: stampID, date: date, recipient: design.statement.recipient,
                                                purpose: design.statement.purpose, lines: text.allLines, files: [file],
                                                design: design, pages: pages))
                await MainActor.run {
                    job.isDone = true
                    toast.show(.success(output: output, pages: pages?.count, stampID: stampID))
                    store.didUse(stampID: stampID)
                    if !E2E.isRunning { Self.openInPreview(output) }
                    NotificationCenter.default.post(name: HistoryStore.didChange, object: nil)
                }
            } catch {
                await MainActor.run {
                    job.isDone = true
                    if case StampError.encryptedPDF = error {
                        toast.show(.failure(title: L("这份 PDF 加了密码"), message: L("先在「预览」里解锁另存，再来盖一次。")))
                    } else {
                        toast.show(.failure(title: L("没有盖上"), message: error.localizedDescription))
                    }
                }
            }
        }
    }

    private func runSavePanel(for target: PreviewTarget) -> URL? {
        let source = target.documentURL
        let suggested = DocumentStamper.suggestedOutputURL(for: source)
        let panel = NSSavePanel()
        panel.title = L("另存盖章副本")
        panel.message = L("原文件不会被修改")
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let type = UTType(filenameExtension: source.pathExtension) {
            panel.allowedContentTypes = target.kind == .pdf ? [.pdf] : [type, .jpeg, .png]
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// 端到端测试要看确认卡片（勾「每一页都盖」）。
    var confirmModelForTesting: ConfirmModel? { confirmModel }

    private static func openInPreview(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: PreviewInspector.previewBundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: configuration)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 后台盖章的进度，只在主线程读写。
@MainActor
private final class StampJob {
    var done = 0
    var isDone = false
    var shown = false
}

extension HistoryStore {
    /// 记录有变化（盖了一次、删了一条）：「盖过的章」窗口和面板的数字跟着刷新。
    static let didChange = Notification.Name("HistoryStore.didChange")
}

// MARK: - 浮层与浮动印章

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// 浮层上显示十字光标，提示「现在点下去就是盖章」。
private final class CrosshairView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

/// 跟着鼠标走的提示条（30 高、墨色胶囊、12px 苹方 Medium），在印章下方 12pt、鼠标左边 24pt 起。
struct HoldHint: View {
    enum Kind: Equatable {
        case offPage
        case onPage(String)
        case size(Double)
    }

    let kind: Kind

    var body: some View {
        Group {
            switch kind {
            case .offPage:
                HStack(spacing: 8) {
                    MiniMascot()
                    Text(L("移到「预览」的页面上"))
                }
                .padding(.leading, 6).padding(.trailing, 12)
            case .onPage(let text):
                HStack(spacing: 8) {
                    MiniMascot(expectant: true)
                    Text(text)
                }
                .padding(.leading, 6).padding(.trailing, 12)
            case .size(let multiplier):
                HStack(spacing: 10) {
                    Text(L("大小"))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.onInk.opacity(0.25))
                        Capsule().fill(Theme.onInk).frame(width: 64 * CGFloat((multiplier - 0.4) / 3.6))
                    }
                    .frame(width: 64, height: 4)
                    Text("\(Int((multiplier * 100).rounded()))%").font(Theme.round(12))
                }
                .padding(.horizontal, 12)
            }
        }
        .font(Theme.body(12, .medium))
        .foregroundStyle(Theme.onInk)
        .frame(height: 30)
        .background(Capsule().fill(Theme.ink))
        .compositingGroup().shadow(color: .warm(59, 42, 38, 0.25), radius: 8, y: 6)
        .fixedSize()
        .padding(16) // 给阴影留地方
    }
}

/// 跟着鼠标走的印章图 + 提示条。
final class StampCursorWindow: NSPanel {
    private let imageView = NSImageView()
    private let hintHost = NSHostingView(rootView: HoldHint(kind: .offPage))
    private var hint: HoldHint.Kind?
    private var cacheKey: String?
    private let margin: CGFloat = 16
    /// 印章在屏幕上的矩形（不含阴影边距）。
    private(set) var stampRect: CGRect = .zero

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let content = NSView()
        content.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        content.addSubview(imageView)
        content.addSubview(hintHost)
        contentView = content
    }

    func show(text: StampText, design: StampDesign, pointsPerStampPoint: CGFloat, center: CGPoint, active: Bool,
              hint: HoldHint.Kind?) {
        let backing = NSScreen.screens.first { $0.frame.contains(center) }?.backingScaleFactor ?? 2
        // 尺寸变化不到 1% 就复用上一张图，移动鼠标时不重画。
        let key = "\(design.hashValue)-\(text.hashValue)-\(Int(pointsPerStampPoint * 100))"
        if key != cacheKey, let cg = StampRenderer.image(text, design: design, pixelsPerPoint: pointsPerStampPoint * backing) {
            imageView.image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / backing, height: CGFloat(cg.height) / backing))
            cacheKey = key
        }
        // 没对准页面：40% 透明；对准了：悬在纸上，下面一道 6pt 的柔和投影。
        imageView.alphaValue = active ? 1 : 0.4
        if active {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(srgbRed: 59 / 255, green: 42 / 255, blue: 38 / 255, alpha: 0.18)
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.shadowBlurRadius = 6
            imageView.shadow = shadow
        } else {
            imageView.shadow = nil
        }

        if hint != self.hint {
            self.hint = hint
            if let hint { hintHost.rootView = HoldHint(kind: hint) }
        }
        hintHost.isHidden = hint == nil

        let stampSize = imageView.image?.size ?? .zero
        let stamp = CGRect(x: center.x - stampSize.width / 2, y: center.y - stampSize.height / 2,
                           width: stampSize.width, height: stampSize.height)
        stampRect = stamp
        var frame = stamp.insetBy(dx: -margin, dy: -margin)
        var hintFrame = CGRect.zero
        if hint != nil {
            let size = hintHost.fittingSize // 含 16 的阴影边距
            hintFrame = CGRect(x: center.x - 24 - 16, y: stamp.minY - 12 - 30 - 16, width: size.width, height: size.height)
            frame = frame.union(hintFrame)
        }
        setFrame(frame, display: false)
        imageView.frame = stamp.offsetBy(dx: -frame.minX, dy: -frame.minY)
        hintHost.frame = hintFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        display()
    }

    /// 落章：120ms 内从 104% 压到 100%，浓度 60%→100%，外圈一道淡淡的涟漪散开。
    func playDrop() {
        let final = imageView.frame
        imageView.frame = final.insetBy(dx: -final.width * 0.02, dy: -final.height * 0.02)
        imageView.alphaValue = 0.6
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            imageView.animator().frame = final
            imageView.animator().alphaValue = 1
        }
        guard let layer = contentView?.layer else { return }
        let ripple = CALayer()
        ripple.frame = final.insetBy(dx: -4, dy: -4)
        ripple.cornerRadius = min(ripple.frame.height / 2, 12)
        ripple.borderWidth = 6
        ripple.borderColor = NSColor(srgbRed: 224 / 255, green: 83 / 255, blue: 61 / 255, alpha: 0.18).cgColor
        layer.addSublayer(ripple)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.96
        grow.toValue = 1.08
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.opacity = 0
        ripple.add(group, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ripple.removeFromSuperlayer() }
    }
}

// MARK: - 确认卡片的数据

@MainActor
final class ConfirmModel: ObservableObject {
    let documentURL: URL
    let kind: DocumentKind
    let design: StampDesign
    let text: StampText
    @Published var clickedPage: Int
    @Published var placement: StampPlacement { didSet { if placement != oldValue { loadThumbnails() } } }
    @Published var pageCount = 1
    @Published var allPages = false
    @Published var selected: Set<Int> = []
    @Published var thumbnails: [Int: CGImage] = [:]
    private var generation = 0

    init(target: PreviewTarget, placement: StampPlacement, design: StampDesign, text: StampText) {
        documentURL = target.documentURL
        kind = target.kind
        clickedPage = target.pageIndex
        self.placement = placement
        self.design = design
        self.text = text
    }

    var fileName: String { documentURL.lastPathComponent }

    /// 页数要读文件：放到后台。
    func load() {
        guard kind == .pdf else { return }
        let url = documentURL
        Task.detached(priority: .userInitiated) {
            let count = (try? DocumentStamper.pageCount(of: url)) ?? 1
            await MainActor.run {
                self.pageCount = count
                self.selected = Set(0..<count)
                self.allPages = count > 1 && Self.remembersAllPages(for: url)
                if self.allPages { self.loadThumbnails() }
            }
        }
    }

    func setAllPages(_ value: Bool) {
        allPages = value
        if value && thumbnails.isEmpty { loadThumbnails() }
    }

    func toggle(_ page: Int) {
        if selected.contains(page) {
            guard selected.count > 1 else { NSSound.beep(); return } // 至少盖一页
            selected.remove(page)
        } else {
            selected.insert(page)
        }
    }

    func selectAll() { selected = Set(0..<pageCount) }

    func cancelLoading() { generation += 1 }

    /// 每页一张 44×62 的缩略图，印章按真实比例画在换算后的位置上。
    func loadThumbnails() {
        guard kind == .pdf, allPages else { return }
        generation += 1
        let gen = generation, url = documentURL, placement = placement, design = design, text = text
        let count = min(pageCount, 200)
        Task.detached(priority: .userInitiated) {
            guard let doc = try? DocumentStamper.openPDF(url) else { return }
            if doc.isLocked { _ = doc.unlock(withPassword: "") }
            for index in 0..<count {
                guard let page = doc.page(at: index) else { continue }
                let image = Self.thumbnail(page, placement: placement.onPage(index), design: design, text: text)
                let stillCurrent = await MainActor.run { () -> Bool in
                    guard gen == self.generation else { return false }
                    if let image { self.thumbnails[index] = image }
                    return true
                }
                if !stillCurrent { return }
            }
        }
    }

    nonisolated private static func thumbnail(_ page: PDFPage, placement: StampPlacement, design: StampDesign, text: StampText) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        let size = (rotation == 90 || rotation == 270) ? CGSize(width: box.height, height: box.width) : box.size
        let pixels: CGFloat = 2
        let s = min(44 / size.width, 62 / size.height) * pixels
        let w = max(Int(size.width * s), 1), h = max(Int(size.height * s), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: s, y: s)
        page.draw(with: .cropBox, to: ctx)
        let scale = CGFloat(placement.scale)
        let stampSize = StampRenderer.boundingSize(text, design: design, scale: scale)
        var clean = design
        clean.texture = .clean
        let center = DocumentStamper.center(for: placement, pageSize: size, stampSize: stampSize)
        StampRenderer.draw(text, design: clean, in: ctx, center: center, scale: scale)
        return ctx.makeImage()
    }

    // 「上次选了每一页都盖，同一份文件下次还是它」。
    nonisolated private static let key = "allPagesFiles"

    nonisolated static func remembersAllPages(for url: URL) -> Bool {
        (AppEnvironment.defaults.stringArray(forKey: key) ?? []).contains(url.path)
    }

    static func rememberAllPages(_ value: Bool, for url: URL) {
        var list = AppEnvironment.defaults.stringArray(forKey: key) ?? []
        list.removeAll { $0 == url.path }
        if value { list.append(url.path) }
        AppEnvironment.defaults.set(Array(list.suffix(200)), forKey: key)
    }
}

// MARK: - 输密码

/// 加了密码的 PDF：点一下先在这儿输密码。密码只留在内存里，盖好的副本用同一个密码加密。
@MainActor
final class PasswordModel: ObservableObject {
    let fileName: String
    @Published var password = ""
    @Published var wrong = false
    @Published var checking = false

    init(fileName: String) {
        self.fileName = fileName
    }
}

struct PasswordCard: View {
    @ObservedObject var model: PasswordModel
    let onUnlock: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Mascot(mood: model.wrong ? .troubled : .expectant, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("这份 PDF 加了密码")).font(Theme.round(15)).foregroundStyle(Theme.ink)
                    Text(model.fileName).font(Theme.body(11)).foregroundStyle(Theme.ink2)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SecureField("", text: $model.password, prompt: Text(L("打开它的密码")).foregroundStyle(Theme.ink3))
                    .focused($focused)
                    .mochiField(focused: focused)
                    .onSubmit(onUnlock)
                    .onChange(of: model.password) { model.wrong = false }
                Text(model.wrong ? L("密码不对，再试一次") : L("盖好的副本也用这个密码。密码不会被保存。"))
                    .font(Theme.body(11))
                    .foregroundStyle(model.wrong ? Theme.coralInk : Theme.ink2)
            }
            HStack(spacing: 8) {
                Spacer()
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Text(L("取消"))
                        Text("esc").font(Theme.body(10)).foregroundStyle(Theme.ink2)
                    }
                }
                .buttonStyle(.mochi(.secondary, height: 30))
                .keyboardShortcut(.cancelAction)
                Button(model.checking ? L("解锁中…") : L("解锁"), action: onUnlock)
                    .buttonStyle(.mochi(.primary, height: 30))
                    .disabled(model.password.isEmpty || model.checking)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .frame(width: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .floatShadow(cornerRadius: Theme.Radius.card)
        .onAppear { focused = true }
    }
}

// MARK: - 确认卡片

struct ConfirmCard: View {
    @ObservedObject var model: ConfirmModel
    let arrowX: CGFloat
    let arrowOnTop: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    private var multi: Bool { model.allPages && model.pageCount > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Mascot(mood: .expectant, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(multi ? L("每一页都盖在这个位置？") : L("就盖在这儿？"))
                        .font(Theme.body(13, .medium)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(Theme.body(11)).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.middle)
                }
            }
            if model.pageCount > 1 {
                MochiSegmented(options: [(false, L("只盖第 %ld 页", model.clickedPage + 1)), (true, L("每一页都盖 · %@", Localization.count(model.pageCount, "页")))],
                               selection: Binding(get: { model.allPages }, set: { model.setAllPages($0) }),
                               style: .ink, height: 26, fontSize: 12, trackPadding: 3)
            }
            if multi { pageStrip }
            HStack(spacing: 8) {
                Text(multi ? L("点缩略图去掉 / 加回") : L("点别处可换位置"))
                    .font(Theme.body(11)).foregroundStyle(Theme.ink2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Text(L("取消"))
                        Text("esc").font(Theme.body(10)).foregroundStyle(Theme.ink2)
                    }
                }
                .buttonStyle(.mochi(.secondary, height: 32, padding: 12))
                .fixedSize() // 按钮字永远完整（英文「Save As…」比中文长），挤不下时让左边的提示缩小
                Button(action: onSave) {
                    HStack(spacing: 6) {
                        Text(L("另存为…"))
                        Text("↩").font(Theme.body(11)).opacity(0.85)
                    }
                }
                .buttonStyle(.mochi(.primary, height: 32, padding: 14))
                .fixedSize()
            }
        }
        .padding(12)
        .frame(width: multi ? 380 : 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .floatShadow(cornerRadius: Theme.Radius.card)
        .overlay(alignment: arrowOnTop ? .topLeading : .bottomLeading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.card)
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(45))
                .offset(x: arrowX - 6, y: arrowOnTop ? -6 : 6)
        }
    }

    private var subtitle: String {
        if model.kind == .image || multi { return L("「%@」· 另存一份，原件不动", model.fileName) }
        return L("「%@」第 %ld 页 · 另存一份，原件不动", model.fileName, model.clickedPage + 1)
    }

    private var pageStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: model.pageCount > 6) {
                HStack(alignment: .top, spacing: model.pageCount <= 6 ? stripSpacing : 12) {
                    ForEach(0..<min(model.pageCount, 200), id: \.self) { index in
                        PageThumb(index: index, image: model.thumbnails[index], on: model.selected.contains(index),
                                  here: index == model.clickedPage) { model.toggle(index) }
                    }
                }
                .padding(.top, 6).padding(.horizontal, 6)
            }
            .frame(height: 96)
            HStack {
                Text(summary).font(Theme.body(11)).foregroundStyle(Theme.ink2)
                Spacer()
                if model.selected.count < model.pageCount {
                    Button(L("全选")) { model.selectAll() }
                        .buttonStyle(.plain)
                        .font(Theme.body(11, .medium)).foregroundStyle(Theme.coralInk)
                        .padding(.horizontal, 8).frame(height: 22)
                }
            }
        }
        .padding(EdgeInsets(top: 6, leading: 6, bottom: 10, trailing: 12))
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.well))
    }

    /// 6 页以内撑满一行（两端对齐）。
    private var stripSpacing: CGFloat {
        let n = CGFloat(model.pageCount)
        return n > 1 ? max(12, (380 - 24 - 18 - 12 - n * 44) / (n - 1)) : 12
    }

    private var summary: String {
        let skipped = (0..<model.pageCount).filter { !model.selected.contains($0) }
        var s = L("盖 %@", Localization.count(model.selected.count, "页"))
        if !skipped.isEmpty {
            s += " · " + (skipped.count <= 3 ? L("跳过%@", StampRecord.pagesLabel(skipped))
                                             : L("跳过 %@", Localization.count(skipped.count, "页")))
        }
        return s
    }
}

private struct PageThumb: View {
    let index: Int
    let image: CGImage?
    let on: Bool
    let here: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image {
                            Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Color.white
                        }
                    }
                    .frame(width: 44, height: 62)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(here ? Theme.coralLine : Theme.line, lineWidth: here ? 2 : 1).padding(here ? -2 : -1))
                    .shadow(color: .black.opacity(here ? 0.12 : 0.08), radius: 1, y: 1)
                    .opacity(on ? 1 : 0.5)

                    badge.offset(x: 6, y: -6)
                }
                label
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("第 %ld 页", index + 1) + (on ? "" : L("（不盖）")))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var badge: some View {
        if on {
            Image(systemName: "checkmark")
                .font(.system(size: 7.5, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.coralDeep))
                .overlay(Circle().strokeBorder(.white, lineWidth: 2).padding(-2))
        } else {
            Circle().fill(.white).frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color(hex: 0xE0D0C8), lineWidth: 1.5))
                .overlay(Circle().strokeBorder(.white, lineWidth: 2).padding(-2))
        }
    }

    @ViewBuilder private var label: some View {
        if here && on {
            Text(L("第 %ld 页", index + 1)).font(Theme.round(11)).foregroundStyle(Theme.coralInk)
        } else if on {
            Text("\(index + 1)").font(Theme.round(11)).foregroundStyle(Theme.ink)
        } else {
            Text(L("%ld · 不盖", index + 1)).font(Theme.body(11)).foregroundStyle(Theme.ink3)
        }
    }
}
