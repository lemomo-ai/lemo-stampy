import AppKit
import ServiceManagement
import StampCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = StampStore(defaults: AppEnvironment.defaults)
    let history = HistoryStore(fileURL: AppEnvironment.historyURL)
    let toast = ToastController()
    private var statusController: StatusItemController!
    private var session: StampSession?
    private var editorWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var batchWindow: NSWindow?
    private var batchModel: BatchModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        statusController = StatusItemController(app: self)
        toast.anchor = { [weak self] in self?.statusController.anchorRect ?? .zero }
        NotificationCenter.default.addObserver(forName: LanguageSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.languageChanged() }
        }
        // 窗口关掉的那一刻还算开着：等这一轮处理完再看还要不要 Dock 图标。
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateDockIcon() } }
        }
        if E2E.isRunning {
            Task { await E2E.run(app: self) }
            return
        }
        // 第一次启动：打开欢迎窗口，带着把「辅助功能」打开。
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            showOnboarding()
        }
    }

    /// 点 Dock 图标：有窗口开着就交给系统（把它们带到前面、还原最小化的），一个都没有才打开工坊。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, ownWindows.allSatisfy({ !$0.isMiniaturized }) { showEditor() }
        return true
    }

    // MARK: 盖章

    var isHolding: Bool { session != nil }
    /// 端到端测试要看确认卡片、批量窗口里的状态。
    var currentSession: StampSession? { session }
    var batchModelForTesting: BatchModel? { batchModel }
    var batchWindowForTesting: NSWindow? { batchWindow }

    func pickUpStamp() {
        guard PreviewInspector.isTrusted else {
            showOnboarding()
            return
        }
        session?.cancel()
        statusController.closePanel()
        editorWindow?.orderOut(nil)
        updateDockIcon()
        let hooks = StampSession.Hooks(
            isOnStatusItem: { [weak self] point in self?.statusController.contains(point) ?? false },
            toast: toast,
            onFinish: { [weak self] in
                guard let self else { return }
                self.session = nil
                self.statusController.setHolding(false)
                self.statusController.bubble.hide(animated: true)
            }
        )
        let session = StampSession(design: store.current, store: store, history: history, hooks: hooks)
        self.session = session
        statusController.setHolding(true)
        session.begin()
        statusController.bubble.show(name: store.current.displayName, below: statusController.anchorRect)
    }

    func dropStamp() {
        session?.cancel()
    }

    /// 弹出系统的授权提示、打开「系统设置 › 辅助功能」，同时开着欢迎窗口等开关打开。开关由用户自己点。
    func requestAccessibility() {
        PreviewInspector.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        showOnboarding()
    }

    // MARK: 窗口

    private var ownWindows: [NSWindow] { [onboardingWindow, editorWindow, historyWindow, batchWindow].compactMap { $0 } }

    /// 平时只在菜单栏；开着工坊、批量、记录、欢迎窗口时 Dock 里也有图标，⌘Tab 切得到。最小化的也算开着，不然没地方还原。
    private func updateDockIcon() {
        let open = ownWindows.contains { $0.isVisible || $0.isMiniaturized }
        let policy: NSApplication.ActivationPolicy = open ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    /// 把窗口带到最前面：先让 Dock 图标出来，再激活，不然 ⌘Tab 里没有它。
    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let window = makeMochiWindow(size: NSSize(width: 520, height: 600), title: L("欢迎使用小章"), resizable: false, autosave: nil)
            window.contentViewController = onboardingContent()
            window.setContentSize(NSSize(width: 520, height: 600))
            window.center()
            onboardingWindow = window
        }
        present(onboardingWindow)
    }

    func showEditor(library: Bool = false) {
        if editorWindow == nil {
            let window = makeMochiWindow(size: NSSize(width: 1100, height: 740), title: L("刻章工坊"), resizable: true, autosave: "StampWorkshop")
            window.contentViewController = editorContent()
            window.setContentSize(NSSize(width: 1100, height: 740))
            window.contentMinSize = NSSize(width: 960, height: 640)
            window.center()
            window.setFrameUsingName("StampWorkshop")
            editorWindow = window
        }
        present(editorWindow)
        editorWindow?.makeFirstResponder(nil) // 打开时不自动聚焦输入框，免得一打字就改了字
        if library { store.showLibrary = true }
    }

    func showHistory() {
        if historyWindow == nil {
            let window = makeMochiWindow(size: NSSize(width: 720, height: 560), title: L("盖过的章"), resizable: true, autosave: "HistoryWindow")
            window.contentViewController = historyContent()
            window.setContentSize(NSSize(width: 720, height: 560))
            window.contentMinSize = NSSize(width: 600, height: 420)
            window.center()
            window.setFrameUsingName("HistoryWindow")
            historyWindow = window
        }
        present(historyWindow)
    }

    /// 批量盖章：从面板打开（没带文件就弹出选文件），或者把文件拖到菜单栏的小章上。
    func showBatch(_ urls: [URL] = []) {
        if batchWindow == nil {
            let model = BatchModel(store: store)
            let window = makeMochiWindow(size: NSSize(width: 1040, height: 680), title: L("批量盖章"), resizable: true, autosave: "BatchWindow")
            window.contentViewController = batchContent(model, window: window)
            window.setContentSize(NSSize(width: 1040, height: 680))
            window.contentMinSize = NSSize(width: 960, height: 620)
            window.center()
            window.setFrameUsingName("BatchWindow")
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // 关窗就清空这一批；正在盖的会在后台盖完，提示照常出来。
                    self?.batchWindow = nil
                    self?.batchModel = nil
                }
            }
            batchModel = model
            batchWindow = window
        }
        present(batchWindow)
        if urls.isEmpty {
            if batchModel?.files.isEmpty == true { chooseBatchFiles() }
        } else {
            batchModel?.add(urls)
        }
    }

    // MARK: 窗口内容（换语言时重建一遍）

    private func onboardingContent() -> NSViewController {
        NSHostingController(rootView: OnboardingView(
            starterCount: store.designs.count,
            onOpenSettings: {
                PreviewInspector.requestTrust()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            },
            onShowStamps: { [weak self] in
                self?.onboardingWindow?.close()
                self?.showEditor()
            },
            onClose: { [weak self] in self?.onboardingWindow?.close() }
        ))
    }

    private func editorContent() -> NSViewController {
        NSHostingController(rootView: EditorView(onPickUp: { [weak self] in self?.pickUpStamp() }).environmentObject(store))
    }

    private func historyContent() -> NSViewController {
        NSHostingController(rootView: HistoryView(store: history))
    }

    private func batchContent(_ model: BatchModel, window: NSWindow) -> NSViewController {
        NSHostingController(rootView: BatchView(
            model: model, store: store,
            onStart: { [weak self, weak model] in
                guard let self else { return }
                model?.start(history: self.history, toast: self.toast)
            },
            onAddFiles: { [weak self] in self?.chooseBatchFiles() },
            onClose: { [weak window] in window?.performClose(nil) }
        ))
    }

    /// 换了界面语言：菜单、面板、打开着的窗口都按新语言重建一遍；窗口位置和大小不变，批量窗口里的文件也还在。
    private func languageChanged() {
        NSApp.mainMenu = makeMainMenu()
        statusController.languageChanged()
        func rebuild(_ window: NSWindow?, title: String, _ content: () -> NSViewController) {
            guard let window else { return }
            let frame = window.frame
            window.title = title
            window.contentViewController = content()
            window.setFrame(frame, display: true)
        }
        rebuild(onboardingWindow, title: L("欢迎使用小章"), onboardingContent)
        rebuild(editorWindow, title: L("刻章工坊"), editorContent)
        rebuild(historyWindow, title: L("盖过的章"), historyContent)
        if let model = batchModel, let window = batchWindow {
            rebuild(window, title: L("批量盖章")) { batchContent(model, window: window) }
        }
    }

    private func chooseBatchFiles() {
        guard let window = batchWindow, let model = batchModel, !model.running else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .image, .folder]
        panel.prompt = L("放进这一批")
        panel.message = L("选几份 PDF 或照片，也可以选一整个文件夹")
        panel.beginSheetModal(for: window) { [weak model] response in
            guard response == .OK else { return }
            model?.add(panel.urls)
        }
    }

    // MARK: 检查更新（只在用户点了才联网）

    private var checkingUpdate = false

    func checkForUpdates() {
        guard !checkingUpdate else { return }
        guard let feed = AppVersion.updateFeed else {
            toast.show(.failure(title: L("没检查成功"), message: L("这一版还没写上官网地址，请直接去官网看看。")))
            return
        }
        checkingUpdate = true
        toast.show(.checkingUpdate)
        Task { @MainActor in
            defer { checkingUpdate = false }
            do {
                switch try await UpdateCheck.fetch(from: feed, current: AppVersion.short) {
                case .upToDate(let current):
                    toast.show(.upToDate(version: current))
                case .available(let release):
                    toast.show(.updateAvailable(version: release.version, notes: release.localizedNotes, url: release.url))
                }
            } catch {
                toast.show(.failure(title: L("没连上官网"), message: L("检查更新需要联网。稍后再试一次，或者直接去官网看看。")))
            }
        }
    }

    // MARK: 开机启动

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                toast.show(.failure(title: L("没能改开机启动"), message: error.localizedDescription))
            }
        }
    }

    // MARK: 菜单栏 app 也需要编辑菜单，文本框里的 ⌘C / ⌘V / ⌘Z 才能用

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: L("最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        appMenu.addItem(withTitle: L("退出小章"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("编辑"))
        edit.addItem(withTitle: L("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L("重做"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
