import AppKit
import StampCore
import SwiftUI

/// 第一次打开的欢迎窗口，520×600。等「辅助功能」打开的时候每秒看一次，打开了就换成右边那张。
struct OnboardingView: View {
    let starterCount: Int
    let onOpenSettings: () -> Void
    let onShowStamps: () -> Void
    let onClose: () -> Void
    @State private var trusted = PreviewInspector.isTrusted
    @State private var pulse = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                TrafficLights(minimizable: false, zoomable: false)
                Spacer()
                // 第一次打开时跟随系统；看不懂的话在这儿就能换。
                MochiSegmented(options: [(UILanguage.zh, "中文"), (.en, "English")], selection: Binding( // l10n-ignore
                    get: { Localization.language },
                    set: { LanguageSettings.shared.preference = $0 == .zh ? .zh : .en }),
                               style: .soft, height: 22, fontSize: 11, trackPadding: 2, fill: false, itemPadding: 8)
                    .fixedSize()
            }
            .frame(height: 22)
            VStack(spacing: 12) {
                Mascot(mood: trusted ? .happy : .normal, size: 88)
                Text(trusted ? L("可以开始盖章啦") : L("你好，我是小章"))
                    .font(Theme.round(22)).foregroundStyle(Theme.ink)
                Text(trusted ? L("以后在菜单栏右上角找我就行。\n左键拿起印章，右键换章、刻章。")
                             : L("帮你在申请材料上盖一枚「仅供××使用，他用无效」的小章。\n每次都另存一份，原件永远不动。"))
                    .font(Theme.body(13)).foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .padding(.top, 4)

            if trusted { doneSteps } else { waitingSteps }

            Spacer(minLength: 0)
            if trusted {
                HStack(spacing: 10) {
                    Button(L("先看看我的章"), action: onShowStamps).buttonStyle(.mochi(.secondary, height: 36))
                    Button(L("好的"), action: onClose).buttonStyle(.mochi(.primary, height: 36)).keyboardShortcut(.defaultAction)
                }
            } else {
                Button(L("稍后再说"), action: onClose)
                    .buttonStyle(.plain)
                    .font(Theme.body(12)).foregroundStyle(Theme.ink2)
                    .frame(height: 28)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 28, bottom: 24, trailing: 28))
        .frame(width: 520, height: 600)
        .mochiWindowBackground()
        .onReceive(timer) { _ in
            let now = PreviewInspector.isTrusted
            if now != trusted { withAnimation(.easeOut(duration: 0.25)) { trusted = now } }
        }
    }

    // MARK: 等待授权

    private var waitingSteps: some View {
        VStack(spacing: 8) {
            StepRow(state: .done, number: 1, title: L("刻好的章"), detail: L("已经备了 %ld 枚模板章，随时能改", starterCount))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    StepBadge(state: .current, number: 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("打开「辅助功能」权限")).font(Theme.body(13, .medium)).foregroundStyle(Theme.ink)
                        Text(L("只用来看「预览」里是哪个文件、第几页、点在哪")).font(Theme.body(11)).foregroundStyle(Theme.ink2)
                    }
                }
                HStack(spacing: 10) {
                    Button(L("打开系统设置"), action: onOpenSettings)
                        .buttonStyle(.mochi(.primary, height: 36))
                        .keyboardShortcut(.defaultAction)
                    HStack(spacing: 6) {
                        Circle().fill(Theme.coral).frame(width: 6, height: 6).opacity(pulse ? 0.25 : 0.6)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                            .onAppear { pulse = true }
                        Text(L("等你打开开关…")).font(Theme.body(11)).foregroundStyle(Theme.ink2)
                    }
                }
                .padding(.leading, 36)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Color.white))
            .insetStroke(Theme.coralLine, width: 2, radius: Theme.Radius.row)
            StepRow(state: .later, number: 3, title: L("在「预览」里打开材料，点菜单栏的小章"), detail: L("印章跟着鼠标走，点哪儿盖哪儿"))
        }
    }

    // MARK: 授权完成

    private var doneSteps: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Text("Wi‑Fi").font(Theme.body(12)).foregroundStyle(Theme.ink2)
                Image(nsImage: Icons.menuBarImage())
                    .renderingMode(.template)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.coralSoft))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.coralLine, lineWidth: 2).padding(-2))
                Text(Clock.now().mochi("M月d日 EEE HH:mm"))
                    .font(Theme.body(12)).foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
            .insetStroke(Theme.line, radius: 10)

            VStack(spacing: 8) {
                StepRow(state: .done, number: 1, title: L("刻好的章"), detail: nil, compact: true)
                StepRow(state: .done, number: 2, title: L("「辅助功能」已打开"), detail: nil, compact: true)
            }
        }
    }
}

private enum StepState { case done, current, later }

private struct StepBadge: View {
    let state: StepState
    let number: Int

    var body: some View {
        Text(state == .done ? "✓" : "\(number)")
            .font(Theme.round(12))
            .foregroundStyle(state == .done ? Theme.coralInk : state == .current ? .white : Theme.ink2)
            .frame(width: 24, height: 24)
            .background(Circle().fill(state == .done ? Theme.coralSoft : state == .current ? Theme.coralDeep : Theme.chip))
    }
}

private struct StepRow: View {
    let state: StepState
    let number: Int
    let title: String
    let detail: String?
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            StepBadge(state: state, number: number)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.body(13, .medium)).foregroundStyle(Theme.ink)
                if let detail { Text(detail).font(Theme.body(11)).foregroundStyle(Theme.ink2) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 10 : 12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Color.white))
        .opacity(state == .later ? 0.6 : 1)
    }
}
