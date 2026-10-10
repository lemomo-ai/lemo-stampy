import AppKit
import StampCore
import SwiftUI
import UniformTypeIdentifiers

/// 盖过的章：每次盖章是一条，记下给了谁、什么用途、输出文件的 SHA-256 指纹。窗口 720×560。
struct HistoryView: View {
    let store: HistoryStore
    @State private var records: [StampRecord] = []
    @State private var verifying = false
    @State private var deleting: StampRecord?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                TrafficLights()
                Text(L("盖过的章")).font(Theme.round(17)).foregroundStyle(Theme.ink)
                if !records.isEmpty {
                    Text(Localization.count(records.count, "次"))
                        .font(Theme.round(11)).foregroundStyle(Theme.butterInk)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(Theme.butter))
                }
                Spacer()
                Button { verifying = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                        Text(L("查验一份文件…"))
                    }
                }
                .buttonStyle(.mochi(.secondary, height: 32))
                .help(L("选一个文件，看它是不是你用小章盖出来的那一份"))
            }
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 0, trailing: 8))

            Group {
                if records.isEmpty {
                    VStack(spacing: 10) {
                        Mascot(mood: .normal, size: 56)
                        Text(L("还没盖过章")).font(Theme.round(15)).foregroundStyle(Theme.ink)
                        Text(L("每次盖章都会在这里留一条记录，\n以后能查到材料给了谁、哪一天。"))
                            .font(Theme.body(12)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center).lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(dayGroups, id: \.title) { group in
                                Text(group.title)
                                    .font(Theme.round(12)).foregroundStyle(Theme.ink2)
                                    .padding(EdgeInsets(top: group.title == dayGroups.first?.title ? 8 : 12, leading: 10, bottom: 4, trailing: 10))
                                ForEach(group.records) { record in
                                    RecordRow(record: record, onDelete: { deleting = record })
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .cardShadow()
        }
        .padding(12)
        .frame(minWidth: 600, minHeight: 420)
        .mochiWindowBackground()
        .ignoresSafeArea()
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.didChange)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in reload() }
        .sheet(isPresented: $verifying) { VerifySheet(store: store) }
        .alert(L("删除这条记录？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L("删除"), role: .destructive) {
                if let deleting { try? store.delete(id: deleting.id) }
                deleting = nil
                reload()
            }
            Button(L("取消"), role: .cancel) { deleting = nil }
        } message: {
            Text(L("只删记录，盖好的文件不动。删了以后就查验不到这一份了。"))
        }
    }

    private func reload() {
        records = store.load()
    }

    /// 按天分组，新的在上面：今天 / 昨天 / 10 月 3 日。
    private var dayGroups: [(title: String, records: [StampRecord])] {
        let calendar = Calendar.current
        var groups: [(title: String, records: [StampRecord])] = []
        for record in records.reversed() {
            let title = Self.dayTitle(record.date, calendar: calendar)
            if groups.last?.title == title { groups[groups.count - 1].records.append(record) } else { groups.append((title, [record])) }
        }
        return groups
    }

    private static func dayTitle(_ date: Date, calendar: Calendar) -> String {
        let now = Clock.now()
        if calendar.isDate(date, inSameDayAs: now) { return L("今天") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return L("昨天") }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? date.mochi("M 月 d 日") : date.mochi("yyyy 年 M 月 d 日")
    }
}

private struct RecordRow: View {
    let record: StampRecord
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 56, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Color.white : Theme.well))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("No.\(record.id)").font(Theme.round(14)).foregroundStyle(Theme.ink).textSelection(.enabled)
                    if let who = record.who {
                        Text(who)
                            .font(Theme.body(11))
                            .foregroundStyle(hovering ? Theme.coralInk : Theme.tileInk)
                            .padding(.horizontal, 8).frame(height: 20)
                            .background(Capsule().fill(hovering ? Theme.coralSoft : Theme.chip))
                    }
                }
                Text(record.fileLine).font(Theme.body(12)).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if hovering {
                HStack(spacing: 6) {
                    Button(L("在访达中显示")) {
                        let urls = record.files.map { URL(fileURLWithPath: $0.outputPath) }
                            .filter { FileManager.default.fileExists(atPath: $0.path) }
                        if urls.isEmpty { NSSound.beep() } else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                    }
                    .buttonStyle(.mochi(.outline, height: 28))
                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink2)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white))
                            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(L("删除这条记录"))
                    .accessibilityLabel(L("删除这条记录"))
                }
            } else {
                Text(record.date.mochi("HH:mm"))
                    .font(Theme.body(12)).foregroundStyle(Theme.ink2)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(hovering ? Theme.well : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L("在访达中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting(record.files.map { URL(fileURLWithPath: $0.outputPath) })
            }
            Button(L("拷贝编号")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.id, forType: .string)
            }
            Divider()
            Button(L("删除这条记录…"), role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let design = record.design {
            StampThumbnail(design: design, box: CGSize(width: 48, height: 34), stampID: record.id)
        } else {
            Image(systemName: "seal").font(.system(size: 18)).foregroundStyle(Theme.coral.opacity(0.7))
        }
    }
}

private extension StampRecord {
    /// 「招商银行 · 办理开户」；都没填就不显示标签。
    var who: String? {
        let parts = [recipient, purpose].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 「护照扫描.pdf 第 2 页 → 护照扫描_已盖章.pdf」；批量盖的：「批量 12 份 · 护照.pdf、流水.pdf…」
    var fileLine: String {
        if files.count > 1 {
            return L("批量 %@ · ", Localization.count(files.count, "份")) + files.map(\.sourceName).joined(separator: L("、"))
        }
        return files.map { file in
            let source = [file.sourceName, file.pagesLabel ?? pagesLabel].compactMap { $0 }.joined(separator: " ")
            return "\(source) → \(URL(fileURLWithPath: file.outputPath).lastPathComponent)"
        }
        .joined(separator: "；")
    }
}

// MARK: - 查验一份文件

private struct VerifySheet: View {
    enum Result {
        case found(StampRecord, StampedFile)
        case notFound
    }

    let store: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var result: Result?
    @State private var targeted = false
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            dropZone
            if let result { resultCard(result) }
            HStack(spacing: 8) {
                Spacer()
                Button(result == nil ? L("取消") : L("完成")) { dismiss() }
                    .buttonStyle(.mochi(.secondary, height: 32))
                    .keyboardShortcut(.cancelAction)
                Button(result == nil ? L("选一个文件…") : L("再查一份…"), action: choose)
                    .buttonStyle(.mochi(.primary, height: 32))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(Theme.card)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            if checking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.down.to.line").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.coralDeep)
            }
            Text(L("把文件拖到这里")).font(Theme.round(14)).foregroundStyle(Theme.ink)
            Text(L("PDF、照片都行，只在本机比对指纹")).font(Theme.body(11)).foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: result == nil ? 150 : 110)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(targeted ? Theme.coralSoft : Theme.well))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            .strokeBorder(targeted ? Theme.coralLine : Theme.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { check(url) } }
            }
            return true
        }
    }

    @ViewBuilder private func resultCard(_ result: Result) -> some View {
        switch result {
        case .found(let record, let file):
            HStack(alignment: .top, spacing: 14) {
                Mascot(mood: .happy, size: 36)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("找到了，是这一次盖的")).font(Theme.round(15)).foregroundStyle(Theme.ink)
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 6) {
                        infoRow(L("编号"), Text("No.\(record.id)").font(Theme.round(12)))
                        if let who = record.who { infoRow(L("给谁"), Text(who)) }
                        infoRow(L("时间"), Text(record.date.mochi("yyyy 年 M 月 d 日 HH:mm")))
                        infoRow(L("原件"), Text([file.sourceName, file.pagesLabel ?? record.pagesLabel].compactMap { $0 }.joined(separator: " ")))
                    }
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Color.white))
            .floatShadow(cornerRadius: Theme.Radius.card)
        case .notFound:
            HStack(alignment: .top, spacing: 14) {
                Mascot(mood: .troubled, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("没找到这份文件")).font(Theme.round(15)).foregroundStyle(Theme.ink)
                    Text(L("可能被改过（重新导出、压缩、截图都会变），\n也可能不是从这台 Mac 的小章盖出来的。"))
                        .font(Theme.body(12)).foregroundStyle(Theme.ink2).lineSpacing(4)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Color.white))
            .floatShadow(cornerRadius: Theme.Radius.card)
        }
    }

    private func infoRow(_ label: String, _ value: Text) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.ink2).frame(width: 56, alignment: .leading)
            value
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.prompt = L("查验")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        check(url)
    }

    /// 算指纹要读整个文件：放到后台。
    private func check(_ url: URL) {
        checking = true
        let store = store
        Task.detached(priority: .userInitiated) {
            let hit = store.find(fileAt: url)
            await MainActor.run {
                checking = false
                withAnimation(.easeOut(duration: 0.2)) {
                    result = hit.map { .found($0.record, $0.file) } ?? .notFound
                }
            }
        }
    }
}
