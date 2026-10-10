import AppKit
import StampCore
import SwiftUI

/// 盖章之后从菜单栏图标下方滑出的小提示：宽 300，4 秒后收起，鼠标停在上面时等移开再收；出错时要点「知道了」。
enum ToastContent: Equatable {
    case progress(done: Int, total: Int)
    case success(output: URL, pages: Int?, stampID: String)
    /// 批量盖完：盖好几份、跳过几份。
    case batch(done: Int, skipped: Int, outputs: [URL], stampID: String)
    case failure(title: String, message: String)
    /// 检查更新：正在问官网 / 已经是最新版 / 有新版本。
    case checkingUpdate
    case upToDate(version: String)
    case updateAvailable(version: String, notes: String?, url: URL)
}

struct ToastView: View {
    let content: ToastContent
    let onReveal: ([URL]) -> Void
    let onDismiss: () -> Void
    var onOpen: (URL) -> Void = { _ in }

    var body: some View {
        Group {
            switch content {
            case .progress(let done, let total):
                HStack(spacing: 12) {
                    Mascot(mood: .expectant, size: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L("正在盖…")).font(Theme.round(14)).foregroundStyle(Theme.ink)
                            Spacer()
                            if total > 1 {
                                Text(L("%ld / %ld 页", done, total)).font(Theme.body(11)).foregroundStyle(Theme.ink2)
                            }
                        }
                        ProgressBar(fraction: total > 1 ? Double(done) / Double(total) : nil)
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))

            case .success(let output, let pages, let stampID):
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Mascot(mood: .happy, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("盖好啦")).font(Theme.round(15)).foregroundStyle(Theme.ink)
                            Text(successDetail(output, pages))
                                .font(Theme.body(11)).foregroundStyle(Theme.ink2)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    HStack(spacing: 8) {
                        Button(L("在访达中显示")) { onReveal([output]) }
                            .buttonStyle(.mochi(.secondary, height: 28))
                        Text("No.\(stampID)")
                            .font(Theme.round(11))
                            .foregroundStyle(Theme.butterInk)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Capsule().fill(Theme.butter))
                            .textSelection(.enabled)
                    }
                    .padding(.leading, 48)
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))

            case .batch(let done, let skipped, let outputs, let stampID):
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Mascot(mood: done > 0 ? .happy : .troubled, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(done > 0 ? L("盖好啦 · %@", Localization.count(done, "份")) : L("一份都没盖上")).font(Theme.round(15)).foregroundStyle(Theme.ink)
                            Text(skipped > 0 ? L("跳过 %@ · 原件都没动", Localization.count(skipped, "份")) : L("原件都没动"))
                                .font(Theme.body(11)).foregroundStyle(Theme.ink2)
                        }
                    }
                    if done > 0 {
                        HStack(spacing: 8) {
                            Button(L("在访达中显示")) { onReveal(outputs) }
                                .buttonStyle(.mochi(.secondary, height: 28))
                            Text("No.\(stampID)")
                                .font(Theme.round(11))
                                .foregroundStyle(Theme.butterInk)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(Capsule().fill(Theme.butter))
                                .textSelection(.enabled)
                        }
                        .padding(.leading, 48)
                    } else {
                        Button(L("知道了"), action: onDismiss)
                            .buttonStyle(.mochi(.secondary, height: 28))
                            .padding(.leading, 48)
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))

            case .failure(let title, let message):
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Mascot(mood: .troubled, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(Theme.round(15)).foregroundStyle(Theme.ink)
                            Text(message).font(Theme.body(11)).foregroundStyle(Theme.ink2)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button(L("知道了"), action: onDismiss)
                        .buttonStyle(.mochi(.ink, height: 28))
                        .keyboardShortcut(.defaultAction)
                        .padding(.leading, 48)
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))

            case .checkingUpdate:
                HStack(spacing: 12) {
                    Mascot(mood: .expectant, size: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("正在检查更新…")).font(Theme.round(14)).foregroundStyle(Theme.ink)
                        ProgressBar(fraction: nil)
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))

            case .upToDate(let version):
                HStack(spacing: 12) {
                    Mascot(mood: .happy, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("已经是最新版")).font(Theme.round(15)).foregroundStyle(Theme.ink)
                        Text(L("小章 %@", version)).font(Theme.body(11)).foregroundStyle(Theme.ink2)
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))

            case .updateAvailable(let version, let notes, let url):
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Mascot(mood: .expectant, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("有新版本 %@", version)).font(Theme.round(15)).foregroundStyle(Theme.ink)
                            Text(notes ?? L("去官网下载，装好后替换旧的就行。"))
                                .font(Theme.body(11)).foregroundStyle(Theme.ink2)
                                .lineSpacing(3)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 8) {
                        Button(L("去官网下载")) { onOpen(url) }
                            .buttonStyle(.mochi(.primary, height: 28))
                            .keyboardShortcut(.defaultAction)
                        Button(L("以后再说"), action: onDismiss)
                            .buttonStyle(.mochi(.secondary, height: 28))
                    }
                    .padding(.leading, 48)
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            }
        }
        .frame(width: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .floatShadow(cornerRadius: Theme.Radius.card)
    }

    private func successDetail(_ output: URL, _ pages: Int?) -> String {
        var parts = [output.lastPathComponent]
        if let pages, pages > 1 { parts.append(L("盖了 %@", Localization.count(pages, "页"))) }
        parts.append(L("原件没动"))
        return parts.joined(separator: " · ")
    }
}

/// 4 高的进度条；不知道进度时一小段来回滑。
private struct ProgressBar: View {
    let fraction: Double?
    @State private var phase = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.chip)
                if let fraction {
                    Capsule().fill(Theme.coralDeep).frame(width: geo.size.width * fraction)
                        .animation(.easeOut(duration: 0.2), value: fraction)
                } else {
                    Capsule().fill(Theme.coralDeep).frame(width: geo.size.width * 0.4)
                        .offset(x: phase ? geo.size.width * 0.6 : 0)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: phase)
                        .onAppear { phase = true }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
    }
}

@MainActor
final class ToastController {
    private var panel: FloatingPanel<ToastView>?
    private var hideTask: Task<Void, Never>?
    private var content: ToastContent?
    /// 菜单栏图标在屏幕上的位置；提示从它下面滑出来。
    var anchor: () -> CGRect = { .zero }

    func show(_ content: ToastContent) {
        self.content = content
        let view = makeView(content)
        let anchor = anchor()
        if let panel {
            panel.update(view)
            let size = panel.contentSize
            panel.place(contentFrame: frame(for: size, anchor: anchor))
        } else {
            let panel = FloatingPanel(rootView: view, margin: 40, keyable: false, level: .statusBar)
            let size = panel.contentSize
            let target = frame(for: size, anchor: anchor)
            panel.place(contentFrame: target.offsetBy(dx: 0, dy: 10))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(target.insetBy(dx: -panel.margin, dy: -panel.margin), display: true)
            }
            self.panel = panel
        }
        scheduleHide()
    }

    func dismiss() {
        hideTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        content = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
            panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: 10), display: true)
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func makeView(_ content: ToastContent) -> ToastView {
        ToastView(content: content,
                  onReveal: { [weak self] urls in
                      NSWorkspace.shared.activateFileViewerSelecting(urls)
                      self?.dismiss()
                  },
                  onDismiss: { [weak self] in self?.dismiss() },
                  onOpen: { [weak self] url in
                      NSWorkspace.shared.open(url)
                      self?.dismiss()
                  })
    }

    private func frame(for size: CGSize, anchor: CGRect) -> CGRect {
        let rect = CGRect(x: anchor.midX - size.width / 2, y: anchor.minY - 6 - size.height, width: size.width, height: size.height)
        return clampToScreen(rect, near: CGPoint(x: anchor.midX, y: anchor.minY - 1))
    }

    /// 成功、已经是最新版 4 秒后收起，鼠标停在上面时等它移开；进行中、出错、有新版本不自动收。
    /// 直接看鼠标位置，不靠 onHover：不抢焦点的浮窗里移出事件会丢，提示就一直不收。
    private func scheduleHide() {
        hideTask?.cancel()
        switch content {
        case .success, .upToDate: break
        case .batch(let done, _, _, _) where done > 0: break
        default: return
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            while !Task.isCancelled, self?.isMouseInside == true {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private var isMouseInside: Bool {
        guard let panel else { return false }
        return panel.frame.insetBy(dx: panel.margin, dy: panel.margin).contains(NSEvent.mouseLocation)
    }
}
