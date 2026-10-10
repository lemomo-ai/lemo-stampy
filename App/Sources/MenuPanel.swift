import AppKit
import StampCore
import SwiftUI

/// 右键菜单栏图标弹出的面板：替代系统菜单，宽 300、圆角 18。
struct MenuPanelView: View {
    struct Actions {
        var pickUp: () -> Void
        var openEditor: () -> Void
        var newStamp: () -> Void
        var openHistory: () -> Void
        var batch: () -> Void
        var grant: () -> Void
        var setLaunchAtLogin: (Bool) -> Void
        var checkForUpdates: () -> Void = {}
        var quit: () -> Void
    }

    @ObservedObject var store: StampStore
    let trusted: Bool
    let historyCount: Int
    let launchAtLogin: Bool
    let actions: Actions
    @State private var login = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if trusted {
                currentCard
                switcher
                Divider8()
                PanelRow(icon: "pencil", title: L("刻章工坊…"), action: actions.openEditor) {
                    Text("⌘ ,").font(Theme.body(12)).foregroundStyle(Theme.ink2)
                }
                .keyboardShortcut(",", modifiers: .command)
                PanelRow(icon: "square.on.square", title: L("批量盖章…"), action: actions.batch) {
                    Text(L("不用开「预览」")).font(Theme.body(11)).foregroundStyle(Theme.ink3)
                }
                historyRow
                PanelRow(icon: "power", title: L("开机自动启动"), action: { login.toggle() }) {
                    MochiSwitch(isOn: $login)
                }
                LanguageRow()
                updateRow
            } else {
                grantCard
                dimmedCurrent
                Divider8(top: 0)
                PanelRow(icon: "pencil", title: L("刻章工坊…"), action: actions.openEditor) {
                    Text("⌘ ,").font(Theme.body(12)).foregroundStyle(Theme.ink2)
                }
                .keyboardShortcut(",", modifiers: .command)
                PanelRow(icon: "square.on.square", title: L("批量盖章…"), action: actions.batch) {
                    Text(L("不用开「预览」")).font(Theme.body(11)).foregroundStyle(Theme.ink3)
                }
                historyRow
                LanguageRow()
                updateRow
            }
            Divider8()
            Button(action: actions.quit) {
                HStack {
                    Text(L("退出小章"))
                    Spacer()
                    Text("⌘ Q")
                }
                .font(Theme.body(12))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverRowStyle())
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .floatShadow(cornerRadius: Theme.Radius.card)
        .onAppear { login = launchAtLogin }
        .onChange(of: login) { _, value in
            if value != launchAtLogin { actions.setLaunchAtLogin(value) }
        }
    }

    // MARK: 当前印章

    private var currentCard: some View {
        let design = store.current
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                StampThumbnail(design: design, box: CGSize(width: 56, height: 36))
                    .frame(width: 64, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(design.displayName).font(Theme.round(15)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text("\(design.subtitle) · \(design.sizeLabel)").font(Theme.body(11)).foregroundStyle(Theme.coralSoftInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Button(action: actions.pickUp) {
                // 小字也用圆体、和大字对齐基线：两种字体混在一行，大小字像是拼起来的。
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(L("拿起印章"))
                    Text(L("或左键点图标")).font(Theme.round(11.5, .regular)).opacity(0.78)
                }
            }
            .buttonStyle(.mochi(.primary, height: 36, fullWidth: true))
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.coralSoft))
    }

    private var switcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("换一枚")).font(Theme.round(12)).foregroundStyle(Theme.ink2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(switcherDesigns) { design in
                    let current = design.id == store.currentID
                    Button {
                        store.currentID = design.id
                    } label: {
                        StampThumbnail(design: design, box: CGSize(width: 50, height: 32))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .selectableTile(current, radius: 12)
                    }
                    .buttonStyle(.plain)
                    .help(design.displayName)
                    .accessibilityLabel(design.displayName + (current ? L("（当前）") : ""))
                }
                Button(action: actions.newStamp) {
                    Text("+")
                        .font(Theme.round(18))
                        .foregroundStyle(Theme.coralInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .help(L("刻一枚新章"))
                .accessibilityLabel(L("刻一枚新章"))
            }
        }
        .padding(EdgeInsets(top: 10, leading: 8, bottom: 8, trailing: 8))
    }

    /// 最多 7 枚 + 一个「+」，两行；当前那枚一定在里面。
    private var switcherDesigns: [StampDesign] {
        var list = Array(store.designs.prefix(7))
        if !list.contains(where: { $0.id == store.currentID }) { list[list.count - 1] = store.current }
        return list
    }

    /// 只在点了才去官网看有没有新版本，右边是现在的版本号。
    private var updateRow: some View {
        PanelRow(icon: "arrow.triangle.2.circlepath", title: L("检查更新…"), action: actions.checkForUpdates) {
            Text(AppVersion.short).font(Theme.body(11)).foregroundStyle(Theme.ink3)
        }
    }

    private var historyRow: some View {
        PanelRow(icon: "clock", title: L("盖过的章"), action: actions.openHistory) {
            if historyCount > 0 {
                Text("\(historyCount)")
                    .font(Theme.round(11))
                    .foregroundStyle(Theme.butterInk)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule().fill(Theme.butter))
            }
        }
    }

    // MARK: 还没授权

    private var grantCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    Mascot(mood: .sleepy, size: 28)
                        .frame(width: 64, height: 44)
                    SleepyZ(size: 10).offset(x: 44, y: 3)
                }
                .frame(width: 64, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.butterWell))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("还差一步")).font(Theme.round(15)).foregroundStyle(Theme.butterTitle)
                    Text(L("打开「辅助功能」，我才看得到「预览」里的页面"))
                        .font(Theme.body(11)).foregroundStyle(Theme.butterInk)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button(action: actions.grant) {
                HStack(spacing: 8) {
                    Text(L("去打开"))
                    Text(L("系统设置 › 辅助功能")).font(Theme.body(11)).opacity(0.75)
                }
            }
            .buttonStyle(.mochi(.ink, height: 36, fullWidth: true))
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.butter))
    }

    private var dimmedCurrent: some View {
        HStack(spacing: 12) {
            StampThumbnail(design: store.current, box: CGSize(width: 56, height: 36), opacity: 0.55)
                .frame(width: 64, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.well))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.current.displayName).font(Theme.round(15)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(L("授权后就能拿起来盖")).font(Theme.body(11)).foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

/// 面板里 32 高的一行：图标 + 文字 + 右边的附加物；悬停时 chip 底。
private struct PanelRow<Trailing: View>: View {
    let icon: String
    let title: String
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 16, height: 16)
                Text(title).font(Theme.body(13)).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }
}

/// 悬停时铺一层 chip 底的行。
struct HoverRowStyle: ButtonStyle {
    var radius: CGFloat = 10
    var hoverFill: Color = Theme.chip

    func makeBody(configuration: Configuration) -> some View {
        HoverRow(label: configuration.label, pressed: configuration.isPressed, radius: radius, fill: hoverFill)
    }

    private struct HoverRow<Label: View>: View {
        let label: Label
        let pressed: Bool
        let radius: CGFloat
        let fill: Color
        @State private var hovering = false

        var body: some View {
            label
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(hovering || pressed ? fill : .clear))
                .onHover { hovering = $0 }
        }
    }
}

private struct Divider8: View {
    var top: CGFloat = 4
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(EdgeInsets(top: top, leading: 8, bottom: 4, trailing: 8))
    }
}

// MARK: - 面板窗口

@MainActor
final class MenuPanelController {
    private var panel: FloatingPanel<AnyView>?
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?

    var isOpen: Bool { panel?.isVisible == true }

    func show(_ view: AnyView, below anchor: CGRect) {
        close()
        let panel = FloatingPanel(rootView: view, margin: 40, keyable: true, level: .popUpMenu)
        let size = panel.contentSize
        var rect = CGRect(x: anchor.midX - size.width / 2, y: anchor.minY - 6 - size.height, width: size.width, height: size.height)
        rect = clampToScreen(rect, near: CGPoint(x: anchor.midX, y: anchor.minY - 1))
        panel.place(contentFrame: rect)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        // 点面板外面、按 esc、切到别的 app 都收起来。
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
                return event
            }
            if event.window !== panel { self.close() }
            return event
        } as Any)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

// MARK: - 左键拿起时的提示气泡

struct PickUpBubble: View {
    let name: String
    var arrowX: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.ink)
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(45))
                .offset(x: arrowX - 6)
                .padding(.bottom, -7)
            HStack(spacing: 10) {
                Mascot(mood: .expectant, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("拿起「%@」", name)).font(Theme.round(13)).foregroundStyle(Theme.onInk)
                    Text(L("移到「预览」的页面上，点一下就盖")).font(Theme.body(11)).foregroundStyle(Theme.onInk2)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 14))
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink))
            .compositingGroup().shadow(color: .warm(150, 70, 50, 0.20), radius: 16, y: 12)
        }
        .fixedSize()
    }
}

@MainActor
final class BubbleController {
    private var panel: FloatingPanel<PickUpBubble>?
    private var hideTask: Task<Void, Never>?

    /// 在图标下方显示 1.6 秒后淡出。
    func show(name: String, below anchor: CGRect) {
        hide(animated: false)
        let panel = FloatingPanel(rootView: PickUpBubble(name: name), margin: 40,
                                  level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3))
        panel.ignoresMouseEvents = true
        let size = panel.contentSize
        var rect = CGRect(x: anchor.midX - size.width * 0.7, y: anchor.minY - 4 - size.height, width: size.width, height: size.height)
        rect = clampToScreen(rect, near: CGPoint(x: anchor.midX, y: anchor.minY - 1))
        panel.update(PickUpBubble(name: name, arrowX: min(max(anchor.midX - rect.minX, 18), size.width - 18)))
        panel.place(contentFrame: rect)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    func hide(animated: Bool) {
        hideTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}
