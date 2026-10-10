import AppKit
import os
import StampCore
import SwiftUI

/// 菜单栏的小章：左键拿起（再点一次放下），右键或按住 Control 点打开面板。
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 24)
    private unowned let app: AppDelegate
    private let panel = MenuPanelController()
    let bubble = BubbleController()
    private var holding = false
    /// 正有文件拖在小章上面。
    private var receiving = false
    private var trusted = PreviewInspector.isTrusted
    private var timer: Timer?

    init(app: AppDelegate) {
        self.app = app
        super.init()
        if let button = statusItem.button {
            button.toolTip = L("小章：点一下拿起印章，右键打开面板")
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // 文件拖到小章上：打开批量盖章。状态栏按钮所在的窗口把拖放转给它的 delegate（就是这里）。
        if let window = statusItem.button?.window {
            window.registerForDraggedTypes([.fileURL])
            window.delegate = self
        }
        refreshIcon()
        // 授权是在系统设置里打开的，没有通知：每 2 秒看一眼，图标上的小圆点跟着变。
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = PreviewInspector.isTrusted
                if now != self.trusted { self.trusted = now; self.refreshIcon() }
            }
        }
    }

    /// 图标在屏幕上的矩形：面板、气泡、提示都从它下面出来。
    var anchorRect: CGRect {
        guard let button = statusItem.button, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func contains(_ point: CGPoint) -> Bool {
        anchorRect.insetBy(dx: -2, dy: -2).contains(point)
    }

    func setHolding(_ value: Bool) {
        holding = value
        refreshIcon()
    }

    private func refreshIcon() {
        let state: Icons.MenuBarState = holding || receiving ? .holding : (trusted ? .normal : .unauthorized)
        guard let button = statusItem.button else { return }
        button.image = Icons.menuBarImage(state)
        // 文件拖在上面时只换图片，菜单栏上看不出变化：当场画、当场提交，再加上系统的按下高亮。
        button.highlight(receiving)
        button.display()
        CATransaction.flush()
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            if panel.isOpen { panel.close() } else { showPanel() }
        } else {
            panel.close()
            if holding { app.dropStamp() } else { app.pickUpStamp() }
        }
    }

    func showPanel() {
        trusted = PreviewInspector.isTrusted
        refreshIcon()
        let actions = MenuPanelView.Actions(
            pickUp: { [weak self] in self?.panel.close(); self?.app.pickUpStamp() },
            openEditor: { [weak self] in self?.panel.close(); self?.app.showEditor() },
            newStamp: { [weak self] in self?.panel.close(); self?.app.showEditor(library: true) },
            openHistory: { [weak self] in self?.panel.close(); self?.app.showHistory() },
            batch: { [weak self] in self?.panel.close(); self?.app.showBatch() },
            grant: { [weak self] in self?.panel.close(); self?.app.requestAccessibility() },
            setLaunchAtLogin: { [weak self] in self?.app.launchAtLogin = $0 },
            checkForUpdates: { [weak self] in self?.panel.close(); self?.app.checkForUpdates() },
            quit: { NSApp.terminate(nil) }
        )
        let view = MenuPanelView(store: app.store, trusted: trusted, historyCount: app.history.load().count,
                                 launchAtLogin: app.launchAtLogin, actions: actions)
        panel.show(AnyView(view), below: anchorRect)
    }

    func closePanel() { panel.close() }

    /// 换了界面语言：提示文字换掉；面板开着就按新语言重新打开（语言就是在面板里换的）。
    func languageChanged() {
        statusItem.button?.toolTip = L("小章：点一下拿起印章，右键打开面板")
        if panel.isOpen { showPanel() }
    }
}

// MARK: - 拖文件到小章上

private let dragLog = Logger(subsystem: "com.lemolab.xiaoyinzhang", category: "drop")

extension StatusItemController: NSWindowDelegate, NSDraggingDestination {
    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private func hasFiles(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    /// 进来、停着都看一眼：有的拖放进来那一下剪贴板还没准备好，停着的时候才读得到。
    private func receive(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = !app.isHolding && hasFiles(sender)
        if ok != receiving {
            receiving = ok
            refreshIcon()
        }
        return ok ? .copy : []
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = receive(sender)
        dragLog.debug("entered: receiving=\(self.receiving)")
        return operation
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        receive(sender)
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        dragLog.debug("exited")
        receiving = false
        refreshIcon()
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragLog.debug("perform")
        receiving = false
        refreshIcon()
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        panel.close()
        app.showBatch(urls)
        return true
    }
}
