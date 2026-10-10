import AppKit
import StampCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 批量盖章的数据

/// 批量盖章窗口：一次放进好几份文件，统一选章、位置、页，一键盖完。
/// 不需要辅助功能权限：拖进来、选进来的文件系统已经给了读写权限，也不用去读「预览」。
@MainActor
final class BatchModel: ObservableObject {
    struct File: Identifiable, Equatable {
        enum Result: Equatable {
            case done(URL)
            case failed(String)
        }

        let url: URL
        var id: String { url.standardizedFileURL.path }
        var kind: DocumentKind?
        /// nil：还在读。
        var pageCount: Int?
        var locked = false
        var unreadable: String?
        var thumbnail: CGImage?
        var result: Result?

        var name: String { url.lastPathComponent }
        var isReading: Bool { kind != nil && pageCount == nil && !locked && unreadable == nil }
        var isReady: Bool { kind != nil && pageCount != nil && !locked && unreadable == nil }
    }

    enum Output: Equatable {
        case beside
        case folder(URL)
    }

    /// 大预览：选中那份文件要盖的那一页（不带章，章另外叠上去）。
    struct Preview: Equatable {
        let fileID: String
        let pageIndex: Int
        let kind: DocumentKind
        let image: CGImage
        let pageSize: CGSize
    }

    @Published private(set) var files: [File] = []
    @Published var selectedID: String? { didSet { if selectedID != oldValue { selectionChanged() } } }
    @Published var designID: UUID { didSet { settingsChanged() } }
    @Published var position = RelativePoint.bottomRight { didSet { settingsChanged() } }
    @Published var overrides: [String: RelativePoint] = [:] { didSet { settingsChanged() } }
    /// true：拖动只改选中的这一份。
    @Published var onlyThis = false
    @Published var pages: BatchPages = .first { didSet { settingsChanged(); loadPreview() } }
    @Published var scale: Double { didSet { settingsChanged() } }
    @Published var output: Output = .beside { didSet { settingsChanged() } }
    @Published private(set) var running = false
    @Published private(set) var progress = (done: 0, total: 0)
    @Published private(set) var finished = false
    @Published private(set) var preview: Preview?
    @Published private(set) var passwordModel: PasswordModel?

    let store: StampStore
    private var previewGeneration = 0
    /// 章上和记录里的时间：每盖一批取一次（窗口可能开着好几天、盖好几批）。
    @Published private(set) var date = Clock.now()

    init(store: StampStore) {
        self.store = store
        designID = store.currentID
        scale = store.sizeMultiplier
    }

    var design: StampDesign { store.designs.first { $0.id == designID } ?? store.current }
    var text: StampText { design.statement.stampText(date: date, stampID: store.nextStampID) }
    var selected: File? { files.first { $0.id == selectedID } }
    var readyFiles: [File] { files.filter(\.isReady) }
    var outputs: [URL] { files.compactMap { if case .done(let url) = $0.result { return url } else { return nil } } }

    /// 要盖的总页数（只算准备好的）。
    var totalPages: Int {
        readyFiles.reduce(0) { sum, file in
            sum + (file.kind == .image ? 1 : pages.pageIndices(count: file.pageCount ?? 0).count)
        }
    }

    func point(for id: String) -> RelativePoint { overrides[id] ?? position }

    // MARK: 加文件

    /// 文件夹只收一层，不往子文件夹里找；同一份只收一次。
    func add(_ urls: [URL]) {
        var list: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let inside = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                           options: [.skipsHiddenFiles])) ?? []
                list += inside.filter { DocumentStamper.kind(of: $0) != nil }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else {
                list.append(url)
            }
        }
        for url in list {
            let file = File(url: url, kind: DocumentStamper.kind(of: url))
            guard !files.contains(where: { $0.id == file.id }) else { continue }
            files.append(file)
            if file.kind == nil { continue }
            inspect(file.id, url: url)
        }
        finished = false
        if selectedID == nil { selectedID = files.first?.id }
    }

    func remove(_ id: String) {
        guard !running else { return }
        files.removeAll { $0.id == id }
        overrides[id] = nil
        if selectedID == id { selectedID = files.first?.id }
    }

    /// 读页数和缩略图放后台：桌面 / 文稿里的文件可能触发系统授权框。
    private func inspect(_ id: String, url: URL) {
        Task.detached(priority: .userInitiated) {
            var count: Int?
            var locked = false
            var unreadable: String?
            do { count = try DocumentStamper.pageCount(of: url) } catch StampError.encryptedPDF {
                locked = true
            } catch {
                unreadable = (error as? LocalizedError)?.errorDescription ?? L("读不出来")
            }
            let thumb = count != nil ? try? DocumentStamper.pageImage(of: url, maxPixel: 96) : nil
            let found = (count: count, locked: locked, unreadable: unreadable)
            await MainActor.run { [weak self] in
                guard let self, let i = self.files.firstIndex(where: { $0.id == id }) else { return }
                self.files[i].pageCount = found.count
                self.files[i].locked = found.locked
                self.files[i].unreadable = found.unreadable
                self.files[i].thumbnail = thumb
                if id == self.selectedID { self.selectionChanged() }
            }
        }
    }

    // MARK: 选中、预览

    func step(_ delta: Int) {
        guard let i = files.firstIndex(where: { $0.id == selectedID }), !files.isEmpty else { return }
        selectedID = files[(i + delta + files.count) % files.count].id
    }

    private func selectionChanged() {
        if let file = selected, file.locked {
            if passwordModel?.fileName != file.name { passwordModel = PasswordModel(fileName: file.name) }
        } else {
            passwordModel = nil
        }
        loadPreview()
    }

    private func previewPage(of file: File) -> Int {
        file.kind == .image ? 0 : (pages.pageIndices(count: file.pageCount ?? 1).first ?? 0)
    }

    func loadPreview() {
        previewGeneration += 1
        let generation = previewGeneration
        guard let file = selected, file.isReady, let kind = file.kind else {
            preview = nil
            return
        }
        let url = file.url, index = previewPage(of: file), id = file.id
        if let preview, preview.fileID == id, preview.pageIndex == index { return }
        Task.detached(priority: .userInitiated) {
            guard let image = try? DocumentStamper.pageImage(of: url, pageIndex: index, maxPixel: 1600),
                  let size = try? DocumentStamper.pageSize(of: url, pageIndex: index) else { return }
            await MainActor.run { [weak self] in
                guard let self, generation == self.previewGeneration else { return }
                self.preview = Preview(fileID: id, pageIndex: index, kind: kind, image: image, pageSize: size)
            }
        }
    }

    // MARK: 位置

    /// 大预览上拖动 / 点九宫格：所有文件一起改，或者（「只调这一份」时）只改选中的那份。
    func move(to point: RelativePoint) {
        if onlyThis, let id = selectedID {
            overrides[id] = point
        } else {
            position = point
        }
    }

    func resetOverride(_ id: String) {
        overrides[id] = nil
    }

    // MARK: 密码

    func unlockSelected() {
        guard let file = selected, file.locked, let model = passwordModel, !model.checking else { return }
        let url = file.url, password = model.password, id = file.id
        model.checking = true
        model.wrong = false
        Task.detached(priority: .userInitiated) {
            let ok = DocumentStamper.unlock(url, password: password)
            await MainActor.run { [weak self] in
                model.checking = false
                guard ok else { model.wrong = true; return }
                guard let self, let i = self.files.firstIndex(where: { $0.id == id }) else { return }
                self.files[i].locked = false
                self.passwordModel = nil
                self.inspect(id, url: url)
            }
        }
    }

    // MARK: 存到哪

    func chooseFolder(for window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("存到这里")
        panel.message = L("盖好的副本都放进这个文件夹，原件不动")
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else {
                if case .folder = self?.output {} else { self?.output = .beside }
                return
            }
            self?.output = .folder(url)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) } else { handle(panel.runModal()) }
    }

    private func settingsChanged() {
        if finished, !running { finished = false }
        if !running { date = Clock.now() }
    }

    // MARK: 盖

    func start(history: HistoryStore, toast: ToastController) {
        guard !running, !readyFiles.isEmpty else { return }
        running = true
        finished = false
        let inputs = readyFiles.map(\.url)
        for i in files.indices where files[i].isReady { files[i].result = nil }
        progress = (0, inputs.count)
        date = Clock.now()
        let position = position, overrides = overrides, scale = scale, pages = pages, design = design
        let folder: URL? = { if case .folder(let url) = output { return url } else { return nil } }()
        let stampID = store.nextStampID, date = date, store = store, fileCount = files.count
        let text = design.statement.stampText(date: date, stampID: stampID)
        store.sizeMultiplier = scale

        Task.detached(priority: .userInitiated) {
            let plan = BatchStamper.plan(inputs: inputs, position: position, scale: scale, pages: pages,
                                         overrides: overrides, outputDirectory: folder)
            let outcomes = BatchStamper.run(plan, design: design, text: text) { done, total in
                Task { @MainActor [weak self] in self?.progress = (done, total) }
            }
            let record = BatchStamper.record(for: outcomes, id: stampID, date: date, design: design, text: text)
            if let record { try? history.append(record) }
            await MainActor.run { [weak self] in
                // 窗口中途关掉了也照样记编号、出提示：这些不靠窗口。
                let done = outcomes.filter(\.succeeded).count
                if record != nil {
                    store.didUse(stampID: stampID)
                    NotificationCenter.default.post(name: HistoryStore.didChange, object: nil)
                }
                toast.show(.batch(done: done, skipped: fileCount - done, outputs: outcomes.filter(\.succeeded).map(\.output),
                                  stampID: stampID))
                self?.apply(outcomes, skipped: plan.skipped)
            }
        }
    }

    /// 盖完了：每一行打勾或写原因，按钮换成「在访达中显示 / 完成」。官网素材也用它摆出「盖好了」的样子。
    func apply(_ outcomes: [BatchOutcome], skipped: [BatchSkip] = []) {
        for outcome in outcomes {
            guard let i = files.firstIndex(where: { $0.id == outcome.input.standardizedFileURL.path }) else { continue }
            files[i].result = outcome.succeeded ? .done(outcome.output) : .failed(outcome.error ?? L("没盖上"))
        }
        for skip in skipped {
            guard let i = files.firstIndex(where: { $0.id == skip.input.standardizedFileURL.path }) else { continue }
            files[i].result = .failed(skip.reason.label)
        }
        running = false
        finished = true
    }
}

// MARK: - 窗口

struct BatchView: View {
    @ObservedObject var model: BatchModel
    @ObservedObject var store: StampStore
    let onStart: () -> Void
    let onAddFiles: () -> Void
    let onClose: () -> Void
    @State private var dropTargeted = false
    @State private var window: NSWindow?

    var body: some View {
        VStack(spacing: 12) {
            header
            HStack(alignment: .top, spacing: 12) {
                fileColumn.frame(width: 268)
                canvas
                settings.frame(width: 268)
            }
        }
        .padding(12)
        .frame(minWidth: 960, minHeight: 620)
        .mochiWindowBackground()
        .ignoresSafeArea()
        .background(WindowReader { window = $0 })
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard !model.running else { return false }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.add([url]) }
                }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.coralLine, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 14) {
            TrafficLights()
            Text(L("批量盖章")).font(Theme.round(17)).foregroundStyle(Theme.ink)
            Text(L("一次盖好几份，原件都不动")).font(Theme.body(12)).foregroundStyle(Theme.ink2)
            Spacer()
        }
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 0, trailing: 8))
    }

    // MARK: 左：文件

    private var fileColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("文件")).font(Theme.round(13)).foregroundStyle(Theme.ink)
                if !model.files.isEmpty {
                    Text("\(model.files.count)")
                        .font(Theme.round(11)).foregroundStyle(Theme.butterInk)
                        .padding(.horizontal, 7).frame(height: 18)
                        .background(Capsule().fill(Theme.butter))
                }
                Spacer()
            }
            .padding(EdgeInsets(top: 14, leading: 14, bottom: 8, trailing: 14))
            if model.files.isEmpty {
                VStack(spacing: 8) {
                    Text(L("还没有文件")).font(Theme.body(12)).foregroundStyle(Theme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.files) { file in
                            FileRow(file: file, selected: file.id == model.selectedID, pages: model.pages,
                                    hasOwnSpot: model.overrides[file.id] != nil, running: model.running,
                                    onSelect: { model.selectedID = file.id },
                                    onRemove: { model.remove(file.id) })
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            Button(action: onAddFiles) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text(model.files.isEmpty ? L("选文件…") : L("再加几份…"))
                }
            }
            .buttonStyle(.mochi(.secondary, height: 32, fullWidth: true))
            .disabled(model.running)
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .cardShadow()
    }

    // MARK: 中：大预览

    private var canvas: some View {
        VStack(spacing: 0) {
            if model.files.count > 1 {
                HStack(spacing: 10) {
                    MochiSegmented(options: [(false, L("所有文件一样")), (true, L("只调这一份"))], selection: $model.onlyThis,
                                   style: .soft, height: 26, fontSize: 12, track: Theme.chip.opacity(0.9), fill: false)
                        .fixedSize()
                    Spacer()
                    if let index = model.files.firstIndex(where: { $0.id == model.selectedID }) {
                        Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(CircleIconStyle())
                            .accessibilityLabel(L("上一份"))
                        Text("\(index + 1) / \(model.files.count)").font(Theme.round(12)).foregroundStyle(Theme.ink2)
                            .monospacedDigit()
                        Button { model.step(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(CircleIconStyle())
                            .accessibilityLabel(L("下一份"))
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))
            }
            ZStack {
                canvasContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            if model.selected?.isReady == true {
                canvasFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.canvas, style: .continuous).fill(Theme.canvas)
        )
    }

    @ViewBuilder private var canvasContent: some View {
        if model.files.isEmpty {
            EmptyDrop(onChoose: onAddFiles)
        } else if let file = model.selected {
            if file.locked, let password = model.passwordModel {
                PasswordCard(model: password, onUnlock: { model.unlockSelected() }, onCancel: { model.step(1) })
            } else if file.kind == nil || file.unreadable != nil {
                Notice(mood: .troubled, title: file.kind == nil ? L("这份文件盖不了") : L("这份文件读不出来"),
                       message: file.kind == nil ? L("只支持 PDF 和照片（JPG、PNG、HEIC 等）。盖的时候会跳过它。")
                                                 : (file.unreadable ?? "") + L("\n盖的时候会跳过它。"))
            } else if let preview = model.preview, preview.fileID == file.id {
                PagePreview(preview: preview, point: model.point(for: file.id), scale: model.scale,
                            design: model.design, text: model.text, onMove: { model.move(to: $0) })
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var canvasFooter: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(L("快捷位置")).font(Theme.body(11)).foregroundStyle(Theme.ink2).fixedSize()
                AnchorGrid(current: model.selectedID.map { model.point(for: $0) } ?? model.position) { model.move(to: $0) }
            }
            if let id = model.selectedID, model.overrides[id] != nil {
                Button(L("跟其他文件一样")) { model.resetOverride(id) }
                    .buttonStyle(.mochi(.text, height: 24))
                    .fixedSize()
                    .help(L("这一份不再单独放，回到所有文件共用的位置"))
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                Text(L("大小")).font(Theme.body(11)).foregroundStyle(Theme.ink2).fixedSize()
                MochiSlider(value: $model.scale, range: 0.4...2.5, step: 0.1).frame(minWidth: 80, maxWidth: 120)
                Text("\(Int((model.scale * 100).rounded()))%").font(Theme.round(12)).foregroundStyle(Theme.ink)
                    .monospacedDigit().frame(width: 40, alignment: .trailing)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 14, trailing: 16))
    }

    // MARK: 右：设置

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("用哪枚章")).font(Theme.round(13)).foregroundStyle(Theme.ink)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(store.designs) { design in
                            let current = design.id == model.designID
                            Button { model.designID = design.id } label: {
                                StampThumbnail(design: design, box: CGSize(width: 60, height: 34))
                                    .frame(maxWidth: .infinity).frame(height: 46)
                                    .selectableTile(current, radius: 12)
                            }
                            .buttonStyle(.plain)
                            .help(design.displayName)
                            .accessibilityLabel(design.displayName + (current ? L("（选中）") : ""))
                        }
                    }
                    .padding(2)
                }
                .frame(maxHeight: 112)
                Text("\(model.design.displayName) · \(model.design.sizeLabel)")
                    .font(Theme.body(11)).foregroundStyle(Theme.coralSoftInk).lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L("盖哪几页")).font(Theme.round(13)).foregroundStyle(Theme.ink)
                MochiSegmented(options: BatchPages.allCases.map { ($0, $0.label) }, selection: $model.pages,
                               style: .ink, height: 28, fontSize: 12)
                Text(L("PDF 按这个来；照片只有一页。")).font(Theme.body(11)).foregroundStyle(Theme.ink2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L("存到哪")).font(Theme.round(13)).foregroundStyle(Theme.ink)
                MochiSegmented(options: [(false, L("原文件旁边")), (true, L("一个文件夹"))], selection: Binding(
                    get: { if case .folder = model.output { return true } else { return false } },
                    set: { wantsFolder in
                        if wantsFolder { model.chooseFolder(for: window) } else { model.output = .beside }
                    }), style: .ink, height: 28, fontSize: 12)
                if case .folder(let url) = model.output {
                    HStack(spacing: 6) {
                        Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(Theme.ink2)
                        Text(url.lastPathComponent).font(Theme.body(12, .medium)).foregroundStyle(Theme.ink)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button(L("换一个…")) { model.chooseFolder(for: window) }
                            .buttonStyle(.mochi(.text, height: 22))
                    }
                }
                Text(L("文件名后面加「_已盖章」，重名自动加序号，不覆盖任何文件。"))
                    .font(Theme.body(11)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            summary
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .cardShadow()
    }

    private var summary: some View {
        let ready = model.readyFiles.count
        let waiting = model.files.count - ready
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("这一批的编号")).font(Theme.body(11)).foregroundStyle(Theme.ink2)
                Text("No.\(store.nextStampID)")
                    .font(Theme.round(11)).foregroundStyle(Theme.butterInk)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(Capsule().fill(Theme.butter))
            }
            if waiting > 0, !model.finished {
                Text(L("%@先跳过（要密码、不支持或还在读）", Localization.count(waiting, "份")))
                    .font(Theme.body(11)).foregroundStyle(Theme.coralInk)
            }
            if model.finished, !model.running {
                HStack(spacing: 8) {
                    Button(L("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting(model.outputs) }
                        .buttonStyle(.mochi(.secondary, height: 40))
                        .disabled(model.outputs.isEmpty)
                    Button(L("完成"), action: onClose)
                        .buttonStyle(.mochi(.primary, height: 40, fullWidth: true))
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Button(action: onStart) {
                    if model.running {
                        Text(L("正在盖 %ld / %ld…", model.progress.done, model.progress.total))
                    } else {
                        HStack(spacing: 6) {
                            Text(ready > 0 ? L("盖 %@", Localization.count(ready, "份")) : L("盖章"))
                            if ready > 0 { Text(L("共 %@", Localization.count(model.totalPages, "页"))).font(Theme.body(11)).opacity(0.85) }
                        }
                    }
                }
                .buttonStyle(.mochi(.primary, height: 40, fullWidth: true))
                .disabled(ready == 0 || model.running)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - 小零件

/// 左边一行文件：缩略图、名字、状态。
private struct FileRow: View {
    let file: BatchModel.File
    let selected: Bool
    let pages: BatchPages
    let hasOwnSpot: Bool
    let running: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Group {
                    if let thumb = file.thumbnail {
                        Image(decorative: thumb, scale: 2).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.ink3)
                    }
                }
                .frame(width: 30, height: 40)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                .opacity(file.isReady || file.isReading ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(Theme.body(12, .medium)).foregroundStyle(Theme.ink)
                        .lineLimit(1).truncationMode(.middle)
                    Text(status).font(Theme.body(11)).foregroundStyle(statusColor).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                trailing
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(selected ? Theme.coralSoft : (hovering ? Theme.well : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L("从这一批里拿掉"), action: onRemove).disabled(running)
        }
    }

    private var icon: String {
        if file.locked { return "lock.fill" }
        if file.kind == nil { return "doc.questionmark" }
        return "doc"
    }

    @ViewBuilder private var trailing: some View {
        switch file.result {
        case .done:
            Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Theme.coralDeep))
                .accessibilityLabel(L("盖好了"))
        case .failed:
            Image(systemName: "exclamationmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.butterInk)
                .frame(width: 18, height: 18).background(Circle().fill(Theme.butter))
                .accessibilityLabel(L("没盖上"))
        case nil:
            if hovering && !running {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.ink2)
                        .frame(width: 18, height: 18).background(Circle().fill(Theme.chip))
                }
                .buttonStyle(.plain)
                .help(L("从这一批里拿掉"))
                .accessibilityLabel(L("拿掉 %@", file.name))
            } else if file.locked {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.coralInk)
            }
        }
    }

    private var status: String {
        switch file.result {
        case .done(let url): return L("盖好了 → %@", url.lastPathComponent)
        case .failed(let message): return L("没盖上：%@", message)
        case nil: break
        }
        if file.kind == nil { return L("不支持这种文件") }
        if file.locked { return L("要密码 · 点一下输入") }
        if let message = file.unreadable { return message }
        guard let count = file.pageCount else { return L("读取中…") }
        if file.kind == .image { return hasOwnSpot ? L("照片 · 单独位置") : L("照片") }
        var parts = ["PDF " + Localization.count(count, "页")]
        let n = pages.pageIndices(count: count).count
        parts.append(n == count && count > 1 ? L("每页都盖") : (pages == .last && count > 1 ? L("盖最后一页") : L("盖第 1 页")))
        if hasOwnSpot { parts.append(L("单独位置")) }
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch file.result {
        case .done: return Theme.coralSoftInk
        case .failed: return Theme.butterInk
        case nil: break
        }
        if file.locked { return Theme.coralInk }
        if file.kind == nil || file.unreadable != nil { return Theme.ink3 }
        return Theme.ink2
    }
}

/// 大预览：页面图 + 叠上去的章（真实比例），在页面上点或拖就换位置。靠边的章和真盖时一样往里推。
private struct PagePreview: View {
    let preview: BatchModel.Preview
    let point: RelativePoint
    let scale: Double
    let design: StampDesign
    let text: StampText
    let onMove: (RelativePoint) -> Void
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let page = preview.pageSize
            let fit = min(geo.size.width / max(page.width, 1), (geo.size.height - 22) / max(page.height, 1))
            let shown = CGSize(width: page.width * fit, height: page.height * fit)
            let unit = DocumentStamper.unitsPerPoint(kind: preview.kind, pageSize: page)
            let stampScale = CGFloat(scale) * unit
            let stampSize = StampRenderer.boundingSize(text, design: design, scale: stampScale)
            let center = DocumentStamper.center(for: StampPlacement(x: point.x, y: point.y, scale: scale),
                                                pageSize: page, stampSize: stampSize)
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    Image(decorative: preview.image, scale: 1).resizable().interpolation(.high)
                        .frame(width: shown.width, height: shown.height)
                    if let image = StampImageCache.shared.image(text, design: design, pixelsPerPoint: fit * stampScale * displayScale) {
                        Image(decorative: image, scale: displayScale)
                            .position(x: center.x * fit, y: (page.height - center.y) * fit)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: shown.width, height: shown.height)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                .shadow(color: .warm(120, 50, 35, 0.14), radius: 14, y: 10)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    // 存「推回页面以后」的位置：看到的就是盖出来的。
                    let raw = StampPlacement(x: Double(g.location.x / shown.width), y: Double(g.location.y / shown.height), scale: scale)
                    let c = DocumentStamper.center(for: raw, pageSize: page, stampSize: stampSize)
                    onMove(RelativePoint(x: Double(c.x / page.width), y: Double(1 - c.y / page.height)))
                })
                .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
                Text(preview.kind == .pdf ? L("第 %ld 页 · 在纸上点一下或拖动，换位置", preview.pageIndex + 1) : L("照片 · 在上面点一下或拖动，换位置"))
                    .font(Theme.body(11)).foregroundStyle(Theme.ink2)
                    .frame(height: 14)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// 九宫格快捷位置：3×3 个小方块，当前位置那格填色。
private struct AnchorGrid: View {
    let current: RelativePoint
    let onPick: (RelativePoint) -> Void

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { column in
                        let anchor = RelativePoint.anchor(column: column, row: row)
                        let on = abs(anchor.x - current.x) < 0.01 && abs(anchor.y - current.y) < 0.01
                        Button { onPick(anchor) } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(on ? Theme.coralDeep : Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(on ? Color.clear : Theme.dashed, lineWidth: 1))
                                .frame(width: 14, height: 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Self.names[row][column])
                    }
                }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.chip))
    }

    static var names: [[String]] { [[L("左上"), L("上边"), L("右上")], [L("左边"), L("正中"), L("右边")], [L("左下"), L("下边"), L("右下")]] }
}

/// 还没放文件：一大块可以拖进来的地方。
private struct EmptyDrop: View {
    let onChoose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Mascot(mood: .expectant, size: 56)
            Text(L("把 PDF 或照片拖进来")).font(Theme.round(17)).foregroundStyle(Theme.ink)
            Text(L("可以一次拖好几份，也可以拖一整个文件夹。\n办签证、开户要交的一沓复印件，一次盖完。"))
                .font(Theme.body(12)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center).lineSpacing(3)
            Button(L("选文件…"), action: onChoose).buttonStyle(.mochi(.primary, height: 36))
        }
        .padding(36)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
    }
}

private struct Notice: View {
    let mood: MascotMood
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Mascot(mood: mood, size: 48)
            Text(title).font(Theme.round(15)).foregroundStyle(Theme.ink)
            Text(message).font(Theme.body(12)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center).lineSpacing(3)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .cardShadow()
    }
}

/// 24 的圆形小按钮（上一份、下一份）。
private struct CircleIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.ink2)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.white))
            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
