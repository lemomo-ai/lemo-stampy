import AppKit
import StampCore
import SwiftUI

// MARK: - 按钮

/// 规范里的按钮：主按钮（珊瑚红胶囊）、次按钮（chip 底）、墨色按钮、描边按钮、文字按钮。
struct MochiButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ink, outline, text }

    var kind: Kind = .primary
    var height: CGFloat = 36
    var fullWidth = false
    var horizontalPadding: CGFloat?
    var fontSize: CGFloat?
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding ?? defaultPadding)
            .frame(height: height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var defaultPadding: CGFloat {
        switch height {
        case 36...: return kind == .primary ? 18 : 16
        case 32..<36: return 14
        case 28..<32: return 12
        default: return 10
        }
    }

    private var font: Font {
        let size: CGFloat = fontSize ?? (height >= 36 ? 14 : height >= 32 ? 13 : height >= 28 ? 12 : 11)
        switch kind {
        case .primary, .ink: return Theme.round(size)
        case .secondary: return Theme.body(fontSize ?? (height >= 36 ? 13 : height >= 28 ? 12 : 11), .medium)
        case .outline, .text: return Theme.body(fontSize ?? (height >= 28 ? 12 : 11))
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .ink: return Theme.onInk
        case .secondary, .outline: return Theme.ink
        case .text: return Theme.coralInk
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            Capsule().fill(Theme.coralDeep).shadow(color: .warm(210, 64, 46, 0.28), radius: 6, y: 4)
        case .ink:
            Capsule().fill(Theme.ink)
        case .secondary:
            Capsule().fill(Theme.chip)
        case .outline:
            Capsule().fill(Color.white).overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        case .text:
            Color.clear
        }
    }
}

extension ButtonStyle where Self == MochiButtonStyle {
    static func mochi(_ kind: MochiButtonStyle.Kind = .primary, height: CGFloat = 36, fullWidth: Bool = false,
                      padding: CGFloat? = nil, fontSize: CGFloat? = nil) -> MochiButtonStyle {
        MochiButtonStyle(kind: kind, height: height, fullWidth: fullWidth, horizontalPadding: padding, fontSize: fontSize)
    }
}

/// 按钮里跟在文字后面的快捷键提示（12px、透明度 .8）。
struct ShortcutHint: View {
    let text: String
    var size: CGFloat = 12
    var body: some View {
        Text(text).font(Theme.body(size)).opacity(0.8)
    }
}

/// 键帽：20 高、6 圆角、白底，带一道底边。
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.body(12))
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
            .insetStroke(Theme.line, radius: 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.line).offset(y: 1))
    }
}

// MARK: - 分段控件

struct MochiSegmented<Value: Hashable>: View {
    enum Style {
        /// 圆体字（语言、比例、朱文白文、批量的页和位置）。
        case ink
        /// 正文小字（边框、质感）。
        case soft
    }
    // 两种都是「浅轨道 + 白色滑块」：以前 ink 是墨色实心胶囊，是整屏最重的东西，抢了主按钮。

    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var style: Style = .ink
    var height: CGFloat = 26
    var fontSize: CGFloat = 12
    var trackPadding: CGFloat = 3
    var track: Color = Theme.chip
    /// true：每项等宽撑满；false：按文字宽度。
    var fill = true
    var itemPadding: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let selected = option.value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(font(selected))
                        .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                        .lineLimit(1)
                        .padding(.horizontal, fill ? 4 : itemPadding)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .frame(height: height)
                        .background {
                            if selected {
                                Capsule().fill(Color.white)
                                    .shadow(color: .warm(150, 70, 50, 0.16), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(trackPadding)
        .background(Capsule().fill(track))
    }

    private func font(_ selected: Bool) -> Font {
        switch style {
        case .ink: return selected ? Theme.round(fontSize) : Theme.round(fontSize, .regular)
        case .soft: return Theme.body(fontSize, selected ? .medium : .regular)
        }
    }
}

// MARK: - chip 开关、开关、滑块

/// 24 高的胶囊开关：开是「日期 ✓」珊瑚色，关是灰底。
struct ChipToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(isOn ? "\(title) ✓" : title)
                .font(Theme.round(12))
                .foregroundStyle(isOn ? Theme.coralInk : Theme.ink2)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(isOn ? Theme.coralSoft : Theme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 30×18 的开关，圆钮 14。
struct MochiSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.coralDeep : Theme.switchOff)
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
            .contentShape(Capsule())
            .onTapGesture { isOn.toggle() }
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? L("开") : L("关"))
    }
}

/// 自绘滑块：4 高的轨道、珊瑚色填充、16 的白色圆钮。`centered` 时从 0 往两边填（「歪一点」）。
struct MochiSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    var centered = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = CGFloat((value - range.lowerBound) / span)
            let zero = centered ? CGFloat((0 - range.lowerBound) / span) : 0
            let x = fraction * width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 4)
                Capsule().fill(Theme.coralDeep)
                    .frame(width: max(abs(x - zero * width), 0), height: 4)
                    .offset(x: min(x, zero * width))
                Circle().fill(Color.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.warm(150, 70, 50, 0.18), lineWidth: 1).padding(-1))
                    .shadow(color: .warm(150, 70, 50, 0.25), radius: 3, y: 2)
                    .offset(x: x - 8)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = min(max(g.location.x / max(width, 1), 0), 1)
                var v = range.lowerBound + Double(f) * span
                if step > 0 { v = (v / step).rounded() * step }
                value = min(max(v, range.lowerBound), range.upperBound)
            })
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { direction in
            let d = step > 0 ? step : (range.upperBound - range.lowerBound) / 20
            value = min(max(value + (direction == .increment ? d : -d), range.lowerBound), range.upperBound)
        }
    }
}

// MARK: - 输入框

/// 32 高、10 圆角、白底；平时 1px 细线，获得焦点时 2px 珊瑚描边。
struct MochiFieldBackground: ViewModifier {
    let focused: Bool
    var height: CGFloat? = 32

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Theme.body(13))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous).fill(Color.white))
            .insetStroke(focused ? Theme.coralLine : Theme.line, width: focused ? 2 : 1, radius: Theme.Radius.field)
    }
}

extension View {
    /// 可选的小方格（外形、字体、印章）：平时浅灰底；选中浅珊瑚底 + 珊瑚细框。全 App 的选中格子都长这样。
    func selectableTile(_ selected: Bool, radius: CGFloat = 10) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(selected ? Theme.coralSoft : Theme.chip))
            .insetStroke(selected ? Theme.coralLine : .clear, width: 1.5, radius: radius)
            .contentShape(RoundedRectangle(cornerRadius: radius))
    }

    func mochiField(focused: Bool, height: CGFloat? = 32) -> some View {
        modifier(MochiFieldBackground(focused: focused, height: height))
    }
}

// MARK: - 小章（吉祥物）

enum MascotMood {
    case normal, expectant, happy, troubled, sleepy
}

/// 吉祥物「小章」：按 36×36 画，其他尺寸整体缩放（24 / 28 / 32 / 56 / 88）。
struct Mascot: View {
    var mood: MascotMood = .normal
    var size: CGFloat = 36

    var body: some View {
        ZStack(alignment: .topLeading) {
            body36
        }
        .frame(width: 36, height: 36, alignment: .topLeading)
        .scaleEffect(size / 36, anchor: .topLeading)
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private let face = Theme.onInk

    @ViewBuilder private var body36: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        // 身体：inset 0 -3px 0 rgba(0,0,0,.10) —— 底下一道暗边。
        ZStack {
            Color.black.opacity(0.10)
            Theme.coral.clipShape(shape).offset(y: -3)
        }
        .frame(width: 36, height: 36)
        .clipShape(shape)
        Ellipse().fill(Color.white.opacity(0.35)).frame(width: 9, height: 4).offset(x: 6, y: 5)

        switch mood {
        case .normal:
            eye(11, 14); eye(21, 14)
            blush(6, 22, 6); blush(24, 22, 6)
        case .expectant:
            eye(11, 16); eye(21, 16)
            Circle().strokeBorder(face, lineWidth: 1.5).frame(width: 4, height: 4).offset(x: 16, y: 24)
            blush(6, 23, 6); blush(24, 23, 6)
        case .happy:
            Arc(up: true).stroke(face, style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 7, height: 4).offset(x: 8.5, y: 15)
            Arc(up: true).stroke(face, style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 7, height: 4).offset(x: 20.5, y: 15)
            Arc(up: false).stroke(face, style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 6, height: 4).offset(x: 15, y: 20)
            blush(5, 21, 7); blush(24, 21, 7)
        case .troubled:
            line(10, 16, angle: 12)
            line(20, 16, angle: -12)
            line(15, 23)
        case .sleepy:
            line(10, 18); line(20, 18)
            blush(6, 23, 6); blush(24, 23, 6)
        }
    }

    private func eye(_ x: CGFloat, _ y: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(face).frame(width: 4, height: 6).offset(x: x, y: y)
    }

    private func blush(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Theme.blush).frame(width: w, height: 3).offset(x: x, y: y)
    }

    private func line(_ x: CGFloat, _ y: CGFloat, angle: Double = 0) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(face).frame(width: 6, height: 2)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
    }

    /// 眯眼（∩）和笑嘴（∪）。
    private struct Arc: Shape {
        let up: Bool
        func path(in r: CGRect) -> Path {
            var p = Path()
            // 两端收进来一点：CSS 的圆角边框两头是渐细的，眼睛和嘴不会连在一起。
            if up {
                p.move(to: CGPoint(x: r.minX + 1.5, y: r.maxY))
                p.addCurve(to: CGPoint(x: r.maxX - 1.5, y: r.maxY), control1: CGPoint(x: r.minX + 1.5, y: r.minY + 0.5),
                           control2: CGPoint(x: r.maxX - 1.5, y: r.minY + 0.5))
            } else {
                p.move(to: CGPoint(x: r.minX + 1.5, y: r.minY + 1.5))
                p.addCurve(to: CGPoint(x: r.maxX - 1.5, y: r.minY + 1.5), control1: CGPoint(x: r.minX + 1.5, y: r.maxY),
                           control2: CGPoint(x: r.maxX - 1.5, y: r.maxY))
            }
            return p
        }
    }
}

/// 提示条里 18 的小小章：圆角 6、眼睛 2×3，期待时多一张小圆嘴。
struct MiniMascot: View {
    var expectant = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.coral).frame(width: 18, height: 18)
            RoundedRectangle(cornerRadius: 1).fill(Theme.onInk).frame(width: 2, height: 3).offset(x: 5, y: 8)
            RoundedRectangle(cornerRadius: 1).fill(Theme.onInk).frame(width: 2, height: 3).offset(x: 11, y: 8)
            if expectant {
                Circle().strokeBorder(Theme.onInk, lineWidth: 1).frame(width: 3, height: 3).offset(x: 7.5, y: 12)
            }
        }
        .frame(width: 18, height: 18, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// 睡着的小章右上角那个「z」。
struct SleepyZ: View {
    var size: CGFloat = 11
    var body: some View {
        Text("z").font(Theme.round(size)).foregroundStyle(Theme.coralInk)
    }
}

// MARK: - 现在

/// 界面上的「现在」（印章上的日期、记录分组）。截图自查时固定成同一天，截出来每次都一样。
enum Clock {
    nonisolated(unsafe) static var now: () -> Date = { Date() }
}

// MARK: - 印章缩略图

/// 把印章按「放进一个框里」的大小画出来（不放大超过 `maxScale`）。
struct StampThumbnail: View {
    let design: StampDesign
    let box: CGSize
    var maxScale: CGFloat = 4
    var opacity: Double = 1
    /// 小缩略图上编号看不清，用示例编号就行；「盖过的章」传那次的真编号。
    var stampID = StampID.sample
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let text = design.statement.stampText(date: Clock.now(), stampID: stampID)
        let size = StampRenderer.boundingSize(text, design: design)
        let ppp = min(box.width / max(size.width, 1), box.height / max(size.height, 1), maxScale)
        if let image = StampImageCache.shared.image(text, design: design, pixelsPerPoint: ppp * displayScale) {
            Image(decorative: image, scale: displayScale)
                .interpolation(.high)
                .opacity(opacity)
        }
    }
}

/// 按实际大小（1 印章点 = 1 屏幕点 × scale）画印章。
struct StampAtScale: View {
    let design: StampDesign
    var scale: CGFloat = 1
    var stampID = StampID.sample
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let text = design.statement.stampText(date: Clock.now(), stampID: stampID)
        if let image = StampImageCache.shared.image(text, design: design, pixelsPerPoint: scale * displayScale) {
            Image(decorative: image, scale: displayScale).interpolation(.high)
        }
    }
}

/// 印章图缓存：列表、模板库里同一枚章会画很多次，带质感时每次都要生成噪点，缓存起来。
final class StampImageCache {
    static let shared = StampImageCache()
    private let cache = NSCache<NSString, CGImage>()

    init() { cache.countLimit = 300 }

    func image(_ text: StampText, design: StampDesign, pixelsPerPoint: CGFloat) -> CGImage? {
        let key = "\(design.hashValue)|\(text.hashValue)|\(Int(pixelsPerPoint * 100))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = StampRenderer.image(text, design: design, pixelsPerPoint: pixelsPerPoint) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

extension StampDesign {
    /// 列表里第二行的小字：「胶囊 · 朱砂」。
    var subtitle: String {
        shape == .square ? L("方印") + " · " + (sealStyle == .yin ? L("白文") : L("朱文")) : "\(shape.label) · \(color.label)"
    }

    var displayName: String { name.isEmpty ? L("未命名") : name }

    /// 「45 × 8 mm」；圆的、方的只写一个数。
    var sizeLabel: String {
        let mm = StampRenderer.physicalSize(statement.stampText(date: Clock.now(), stampID: StampID.sample), design: self)
        if abs(mm.width - mm.height) < 0.6 { return String(format: "%.0f mm", mm.width) }
        return String(format: "%.0f × %.0f mm", mm.width, mm.height)
    }

    var longSideMM: Double {
        let mm = StampRenderer.physicalSize(statement.stampText(date: Clock.now(), stampID: StampID.sample), design: self)
        return Double(max(mm.width, mm.height))
    }
}

// MARK: - 悬浮窗（面板、提示、确认卡片共用）

/// 无边框、透明底的浮动面板，内容是 SwiftUI。四周留出画阴影的边距。
final class FloatingPanel<Content: View>: NSPanel {
    let hosting: NSHostingView<Content>
    let margin: CGFloat
    private let keyable: Bool

    init(rootView: Content, margin: CGFloat = 40, keyable: Bool = false, level: NSWindow.Level = .statusBar) {
        hosting = NSHostingView(rootView: rootView)
        self.margin = margin
        self.keyable = keyable
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let container = NSView()
        container.addSubview(hosting)
        contentView = container
    }

    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }

    /// SwiftUI 内容本身的尺寸（不含阴影边距）。
    var contentSize: CGSize {
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    func update(_ rootView: Content) {
        hosting.rootView = rootView
    }

    /// 把内容（不含边距）放到屏幕上的 `rect`。
    func place(contentFrame rect: CGRect) {
        let frame = rect.insetBy(dx: -margin, dy: -margin)
        setFrame(frame, display: true)
        hosting.frame = NSRect(x: margin, y: margin, width: rect.width, height: rect.height)
    }
}

/// 放在状态栏图标下面时，用图标所在屏幕的可见区域夹住。
func clampToScreen(_ rect: CGRect, near point: CGPoint, inset: CGFloat = 8) -> CGRect {
    let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return rect }
    var r = rect
    r.origin.x = min(max(r.minX, visible.minX + inset), visible.maxX - r.width - inset)
    r.origin.y = min(max(r.minY, visible.minY + inset), visible.maxY - r.height)
    return r
}

// MARK: - 红绿灯

/// 自己画的红绿灯：系统的只能待在标题栏固定位置，这里要放在卡片里（左 24、上 20）。
/// 悬停时显示 × − +，窗口不在前台时变灰。
struct TrafficLights: View {
    var minimizable = true
    var zoomable = true
    @State private var hovering = false
    @State private var window: NSWindow?
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        HStack(spacing: 8) {
            light(Color(hex: 0xFF5F57), glyph: "xmark", enabled: true) { window?.performClose(nil) }
            light(Color(hex: 0xFEBC2E), glyph: "minus", enabled: minimizable) { window?.performMiniaturize(nil) }
            light(Color(hex: 0x28C840), glyph: "plus", enabled: zoomable) { window?.performZoom(nil) }
        }
        .onHover { hovering = $0 }
        .background(WindowReader { window = $0 })
    }

    private func light(_ color: Color, glyph: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let lit = enabled && (activeState != .inactive || hovering)
        return Button(action: action) {
            Circle()
                .fill(lit ? color : Color(hex: 0xE6DCD6))
                .overlay(Circle().strokeBorder(Color.black.opacity(lit ? 0.12 : 0.05), lineWidth: 0.5))
                .overlay {
                    if hovering && enabled {
                        Image(systemName: glyph).font(.system(size: 6.5, weight: .black)).foregroundStyle(Color.black.opacity(0.5))
                    }
                }
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(glyph == "xmark" ? L("关闭") : glyph == "minus" ? L("最小化") : L("缩放"))
    }
}

/// 拿到 SwiftUI 视图所在的 NSWindow。
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

/// 窗口空白处按住能拖动窗口。它只垫在背景里，滑块、按钮这些控件盖在它上面，按下去不会拖走窗口。
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { false }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

extension View {
    /// 糯米窗口的底：纸色，空白处可以拖动窗口。
    func mochiWindowBackground() -> some View {
        background {
            ZStack {
                Theme.paper
                WindowDragArea()
            }
        }
    }
}

/// 糯米风格的窗口：内容铺满、标题栏透明、系统红绿灯藏起来（用上面自己画的）。
func makeMochiWindow(size: NSSize, title: String, resizable: Bool, autosave: String?) -> NSWindow {
    var style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
    if resizable { style.formUnion([.miniaturizable, .resizable]) }
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
    window.title = title
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    // 不用 isMovableByWindowBackground：它会让拖滑块时整个窗口跟着走。空白处靠 WindowDragArea 拖。
    window.isMovableByWindowBackground = false
    window.isReleasedWhenClosed = false
    window.backgroundColor = NSColor(Theme.paper)
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        window.standardWindowButton(button)?.isHidden = true
    }
    window.setContentSize(size)
    window.center()
    if let autosave { window.setFrameAutosaveName(autosave) }
    return window
}

extension Date {
    /// 跟着界面语言，不跟系统地区走：「10月7日 周三 14:32」「14:32」「2026 年 10 月 7 日 14:33」。
    /// `format` 写中文格式；英文界面下换成对照表里的英文格式（「Oct 7, Wed 14:32」）。
    func mochi(_ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Localization.isEnglish ? "en_US" : "zh_CN")
        f.dateFormat = L(format)
        return f.string(from: self)
    }
}
