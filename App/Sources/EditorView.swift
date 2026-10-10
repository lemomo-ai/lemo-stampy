import AppKit
import StampCore
import SwiftUI

/// 刻章工坊：窗口 1100×740，外边距 12，三列 232 | 画布 | 288。
struct EditorView: View {
    @EnvironmentObject var store: StampStore
    let onPickUp: () -> Void
    @FocusState private var focus: InspectorField?

    var body: some View {
        HStack(spacing: 12) {
            LibrarySidebar()
                .frame(width: 232)
            StampCanvas(focus: $focus, onPickUp: onPickUp)
                .frame(minWidth: 380, maxWidth: .infinity)
            InspectorView(design: $store.current, focus: $focus)
                .frame(width: 288)
        }
        .padding(12)
        .frame(minWidth: 960, minHeight: 640)
        .mochiWindowBackground()
        .ignoresSafeArea()
        .sheet(isPresented: $store.showLibrary) {
            TemplateLibraryView().environmentObject(store)
        }
    }
}

// MARK: - 左：我的印章 + 模板

private struct LibrarySidebar: View {
    @EnvironmentObject var store: StampStore
    @State private var deleting: StampDesign?

    // 模板只放在模板库里：左栏以前还塞了一份模板格子，和模板库重复，也把「我的印章」挤小了。
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                stamps
            }
            Button { store.showLibrary = true } label: {
                Text(L("从模板新建…")).font(Theme.body(12, .medium))
            }
            .buttonStyle(.mochi(.secondary, height: 32, fullWidth: true))
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .cardShadow()
        .alert(L("删除「%@」？", deleting?.displayName ?? ""), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L("删除"), role: .destructive) {
                if let deleting { store.delete(deleting) }
                deleting = nil
            }
            Button(L("取消"), role: .cancel) { deleting = nil }
        } message: {
            Text(L("删除后不能恢复。盖过的记录不受影响。"))
        }
    }

    private var stamps: some View {
        VStack(alignment: .leading, spacing: 14) {
            TrafficLights().frame(height: 12)
            HStack(spacing: 10) {
                Mascot(mood: .normal, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("刻章工坊")).font(Theme.round(17)).foregroundStyle(Theme.ink)
                    Text(L("今天想刻一枚什么章？")).font(Theme.body(11)).foregroundStyle(Theme.ink2)
                }
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("我的印章")).font(Theme.round(12)).foregroundStyle(Theme.ink2)
                    Spacer()
                    Button { store.showLibrary = true } label: {
                        Text("+").font(Theme.round(15)).foregroundStyle(Theme.coralInk)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.coralSoft))
                    }
                    .buttonStyle(.plain)
                    .help(L("刻一枚新章"))
                    .accessibilityLabel(L("刻一枚新章"))
                }
                .padding(EdgeInsets(top: 0, leading: 2, bottom: 4, trailing: 2))
                ForEach(store.designs) { design in
                    MyStampRow(design: design, deleting: $deleting)
                }
            }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
    }
}

/// 分类小标签：选中是浅珊瑚底、珊瑚色字（和「我的印章」选中行一样）。
struct CategoryChip: View {
    let title: String
    let selected: Bool
    var height: CGFloat = 24
    var fontSize: CGFloat = 11
    var count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count { Text("\(count)").font(Theme.body(fontSize)).opacity(0.7) }
            }
            .font(selected ? Theme.round(fontSize) : Theme.round(fontSize, .regular))
            .foregroundStyle(selected ? Theme.coralInk : Theme.ink2)
            .padding(.horizontal, height >= 28 ? 12 : 9)
            .frame(height: height)
            .background(Capsule().fill(selected ? Theme.coralSoft : Theme.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 「我的印章」的一行：56 高，选中时 coralSoft 底；右键是系统菜单。
private struct MyStampRow: View {
    @EnvironmentObject var store: StampStore
    let design: StampDesign
    @Binding var deleting: StampDesign?
    @State private var hovering = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    private var selected: Bool { design.id == store.currentID }
    private var renaming: Bool { store.renamingID == design.id }

    var body: some View {
        HStack(spacing: 10) {
            StampThumbnail(design: design, box: CGSize(width: 38, height: 32))
                .frame(width: 44, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.white : Theme.well))
            VStack(alignment: .leading, spacing: 1) {
                if renaming {
                    TextField(L("印章名字"), text: $draftName)
                        .mochiField(focused: true, height: 24)
                        .focused($nameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { store.renamingID = nil }
                        .onAppear {
                            draftName = design.name
                            DispatchQueue.main.async { nameFocused = true }
                        }
                        .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
                } else {
                    Text(design.displayName)
                        .font(selected ? Theme.round(13) : Theme.body(13, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                Text(design.subtitle).font(Theme.body(11)).foregroundStyle(selected ? Theme.coralSoftInk : Theme.ink2)
            }
            Spacer(minLength: 0)
            if store.freshID == design.id {
                Text(L("新"))
                    .font(Theme.round(10))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(Theme.coralDeep))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            .fill(selected ? Theme.coralSoft : hovering ? Theme.chip.opacity(0.6) : .clear))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { store.currentID = design.id; store.renamingID = design.id }
        .onTapGesture { store.currentID = design.id }
        .contextMenu {
            Button(L("设为当前印章")) { store.currentID = design.id }
            Button(L("重命名")) { store.currentID = design.id; store.renamingID = design.id }
            Button(L("复制一份")) { store.duplicate(design) }
            Divider()
            Button(L("删除…"), role: .destructive) { deleting = design }
                .disabled(store.designs.count <= 1)
        }
    }

    private func commitRename() {
        guard renaming else { return }
        if let i = store.designs.firstIndex(where: { $0.id == design.id }) {
            let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { store.designs[i].name = name }
        }
        store.renamingID = nil
    }
}

// MARK: - 中：画布

private enum CanvasZoom: Hashable {
    case actual, fit
}

private struct StampCanvas: View {
    @EnvironmentObject var store: StampStore
    var focus: FocusState<InspectorField?>.Binding
    let onPickUp: () -> Void
    @State private var zoom: CanvasZoom = .fit
    @State private var hovered: StampRegion?

    private var design: StampDesign { store.current }
    /// 用下一次盖章真正会用的编号，工坊里看到的和盖出来的一模一样。
    private var text: StampText { design.statement.stampText(date: Clock.now(), stampID: store.nextStampID) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                MochiSegmented(options: [(CanvasZoom.actual, L("实际大小")), (.fit, L("放大看"))], selection: $zoom,
                               style: .ink, height: 26, fontSize: 12, trackPadding: 3, fill: false)
                Spacer()
                Text(L("点印章上的字，直接改")).font(Theme.body(12)).foregroundStyle(Theme.ink2)
            }
            .frame(height: 36)
            .padding(.horizontal, 2)

            GeometryReader { geo in
                let paper = CGSize(width: min(500, geo.size.width - 48), height: min(360, geo.size.height - 120))
                let stampPoints = StampRenderer.size(text, design: design)
                let actual = Screen.pointsPerStampPoint
                let fit = min(3.5, (paper.width - 56) / max(stampPoints.width, 1), (paper.height - 90) / max(stampPoints.height, 1))
                let scale = zoom == .actual ? actual : max(fit, actual)
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.canvas, style: .continuous).fill(Theme.canvas)
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Color.white)
                        .frame(width: paper.width, height: paper.height)
                        .shadow(color: .warm(170, 70, 50, 0.14), radius: 20, y: 16)
                    StampOnCanvas(design: design, text: text, scale: scale, hovered: $hovered) { region in
                        focus.wrappedValue = InspectorField.field(for: region, design: design)
                    }
                }
            }

            bottomBar
        }
    }

    private var bottomBar: some View {
        let long = design.longSideMM
        return HStack(spacing: 10) {
            Text(design.sizeLabel).font(Theme.round(15)).foregroundStyle(Theme.ink)
            Text(long <= 50 ? L("小巧") : L("偏大"))
                .font(Theme.round(11))
                .foregroundStyle(long <= 50 ? Theme.butterInk : Theme.coralInk)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(long <= 50 ? Theme.butter : Theme.coralSoft))
            Text(Self.comparison(long)).font(Theme.body(11)).foregroundStyle(Theme.ink2)
            Spacer()
            Button(action: onPickUp) {
                HStack(spacing: 8) {
                    Text(L("拿起印章"))
                    ShortcutHint(text: "⌘↩")
                }
            }
            .buttonStyle(.mochi(.primary, height: 36))
            .keyboardShortcut(.return, modifiers: .command)
            .help(L("拿起印章（⌘↩），去「预览」里点一下就盖上"))
        }
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 10))
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Color.white))
        .cardShadow()
    }

    /// 拿身边的东西比一比大小。
    static func comparison(_ mm: Double) -> String {
        switch mm {
        case ..<12: return L("约一颗纽扣大")
        case ..<26: return L("约一枚硬币大")
        case ..<50: return L("约一根回形针长")
        case ..<90: return L("约一张名片宽")
        default: return L("比名片还宽，可以调小一点")
        }
    }
}

/// 画布上的印章，带可点的文字区域：悬停时珊瑚色高亮，上方一个墨色小标签。
private struct StampOnCanvas: View {
    let design: StampDesign
    let text: StampText
    let scale: CGFloat
    @Binding var hovered: StampRegion?
    let onSelect: (StampRegion) -> Void
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let size = StampRenderer.size(text, design: design, scale: scale)
        let regions = StampRenderer.regions(text, design: design, scale: scale)
        let image = StampImageCache.shared.image(text, design: design, pixelsPerPoint: scale * displayScale)
        let bounds = image.map { CGSize(width: CGFloat($0.width) / displayScale, height: CGFloat($0.height) / displayScale) } ?? size
        let angle = CGFloat(design.rotation) * .pi / 180

        ZStack {
            if let image {
                Image(decorative: image, scale: displayScale).interpolation(.high)
            }
            ForEach(Array(regions.keys).sorted { $0.rawValue < $1.rawValue }, id: \.self) { region in
                let rect = regions[region]!.insetBy(dx: -5, dy: -4)
                // 区域中心从印章局部坐标（y 向上、未旋转）换算到视图坐标。
                let lx = rect.midX - size.width / 2, ly = rect.midY - size.height / 2
                let rx = lx * cos(angle) - ly * sin(angle), ry = lx * sin(angle) + ly * cos(angle)
                let on = hovered == region
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.coralSoft.opacity(on ? 0.45 : 0.001))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.coralLine.opacity(on ? 1 : 0), lineWidth: 2))
                    .frame(width: rect.width, height: rect.height)
                    .overlay(alignment: .topLeading) {
                        if on {
                            Text(L("%@ · 点一下就跳到输入框", region.label))
                                .font(Theme.round(11)).foregroundStyle(Theme.onInk)
                                .padding(.horizontal, 10).frame(height: 24)
                                .background(Capsule().fill(Theme.ink))
                                .fixedSize()
                                .offset(y: -34)
                        }
                    }
                    .rotationEffect(.radians(-angle))
                    .position(x: bounds.width / 2 + rx, y: bounds.height / 2 - ry)
                    .onHover { hovered = $0 ? region : (hovered == region ? nil : hovered) }
                    .onTapGesture { onSelect(region) }
            }
        }
        .frame(width: bounds.width, height: bounds.height)
    }
}

/// 屏幕上 1 个印章点（1/72 英寸）对应多少个屏幕点，用来显示「实际大小」。
enum Screen {
    static var pointsPerStampPoint: CGFloat {
        guard let screen = NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 1 }
        let millimeters = CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value))
        guard millimeters.width > 0 else { return 1 }
        let pointsPerMM = screen.frame.width / millimeters.width
        return pointsPerMM * 25.4 / 72
    }
}

extension StampRegion {
    var label: String {
        switch self {
        case .main: return L("主文字")
        case .sub: return L("副文字")
        case .meta: return L("日期 / 编号")
        case .seal: return L("印文")
        }
    }
}
