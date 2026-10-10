import AppKit
import StampCore
import SwiftUI

enum InspectorField: Hashable {
    case recipient, purpose, english, main, sub, seal, custom

    /// 画布上点了哪块，就跳到哪个输入框。
    static func field(for region: StampRegion, design: StampDesign) -> InspectorField {
        if design.statement.useCustomText { return .custom }
        switch region {
        case .main: return design.statement.mainText.isEmpty ? .recipient : .main
        case .sub: return .sub
        case .meta: return .recipient
        case .seal: return .seal
        }
    }
}

/// 右侧检查器（工坊右栏）：写点什么 / 长什么样 / 颜色和大小。
struct InspectorView: View {
    @Binding var design: StampDesign
    var focus: FocusState<InspectorField?>.Binding

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if design.shape == .square {
                    sealSection
                } else if design.statement.useCustomText {
                    customSection
                } else {
                    textSection
                }
                lookSection
                colorSection
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .cardShadow()
    }

    // MARK: 写点什么

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeading(L("写点什么"))
                Spacer()
                MochiSegmented(options: StatementPhrasing.allCases.map { ($0, $0.shortLabel) },
                               selection: $design.statement.phrasing,
                               style: .ink, height: 22, fontSize: 11, trackPadding: 2, fill: false, itemPadding: 9)
            }
            FieldWell {
                switch design.statement.phrasing {
                case .chinese:
                    WellRow(L("给谁")) { field(L("招商银行"), $design.statement.recipient, .recipient) }
                    WellRow(L("做什么")) { field(L("办理开户"), $design.statement.purpose, .purpose) }
                    mainOverrideRow
                    WellRow(L("副文字")) { field(L("他用无效"), $design.statement.subText, .sub) }
                case .english:
                    WellRow(L("给谁")) { field(design.statement.recipient.isEmpty ? "the Embassy" : design.statement.recipient,
                                            $design.statement.recipientEN, .recipient) }
                    WellRow(L("做什么")) { field(design.statement.purpose.isEmpty ? "visa application" : design.statement.purpose,
                                             $design.statement.purposeEN, .purpose) }
                    mainOverrideRow
                    WellRow(L("副文字")) { field("Not valid for other use", $design.statement.subTextEN, .sub) }
                case .bilingual:
                    WellRow(L("给谁")) { field(L("××使馆"), $design.statement.recipient, .recipient) }
                    WellRow(L("做什么")) { field(L("签证申请"), $design.statement.purpose, .purpose) }
                    WellRow(L("英文")) { field("visa application", $design.statement.purposeEN, .english) }
                    mainOverrideRow
                    WellRow(L("副文字")) { field(L("他用无效"), $design.statement.subText, .sub) }
                }
            }
            HStack(spacing: 6) {
                ChipToggle(L("日期"), isOn: $design.statement.includeDate)
                ChipToggle(L("编号"), isOn: $design.statement.includeID)
                    .help(L("每盖一次换一个编号，可在「盖过的章」里追溯"))
                if containsLatin {
                    ChipToggle(L("大写"), isOn: $design.uppercaseLatin)
                }
                Button(L("自己写整句…")) {
                    if design.statement.customText.isEmpty {
                        design.statement.customText = design.statement.bodyLines.joined(separator: "\n")
                    }
                    design.statement.useCustomText = true
                    DispatchQueue.main.async { focus.wrappedValue = .custom }
                }
                .buttonStyle(.mochi(.text, height: 24, padding: 6, fontSize: 12))
            }
        }
    }

    /// 旧版本可以手改主文字；改过的章在这里还能看到、清空。
    @ViewBuilder private var mainOverrideRow: some View {
        if !design.statement.mainText.isEmpty || focus.wrappedValue == .main {
            WellRow(L("主文字")) { field(design.statement.autoMainText, $design.statement.mainText, .main) }
        }
    }

    private var containsLatin: Bool {
        design.statement.bodyLines.contains { $0.range(of: "[A-Za-z]", options: .regularExpression) != nil }
    }

    private func field(_ placeholder: String, _ text: Binding<String>, _ id: InspectorField) -> some View {
        TextField(placeholder, text: text)
            .focused(focus, equals: id)
            .mochiField(focused: focus.wrappedValue == id)
    }

    // MARK: 自己写整句

    private var customSection: some View {
        let lines = design.statement.customText.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeading(L("写点什么"))
                Spacer()
                Button(L("恢复自动生成")) { design.statement.useCustomText = false }
                    .buttonStyle(.mochi(.secondary, height: 24, padding: 10, fontSize: 11))
            }
            Text(L("一行一句，最多三行")).font(Theme.body(12)).foregroundStyle(Theme.ink2)
            TextEditor(text: Binding(get: { design.statement.customText }, set: { value in
                // 最多三行。
                let parts = value.components(separatedBy: "\n")
                design.statement.customText = parts.prefix(3).joined(separator: "\n")
            }))
            .focused(focus, equals: .custom)
            .font(Theme.body(13, .medium))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .lineSpacing(6)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .frame(height: 92)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous).fill(Color.white))
            .insetStroke(focus.wrappedValue == .custom ? Theme.coralLine : Theme.line,
                         width: focus.wrappedValue == .custom ? 2 : 1, radius: Theme.Radius.field)
            HStack(spacing: 6) {
                Text(L("%ld / 3 行", lines))
                    .font(Theme.round(11)).foregroundStyle(Theme.butterInk)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(Capsule().fill(Theme.butter))
                Text(L("字越多，章越宽；保持一句话最好")).font(Theme.body(11)).foregroundStyle(Theme.ink2)
            }
            HStack(spacing: 6) {
                ChipToggle(L("日期"), isOn: $design.statement.includeDate)
                ChipToggle(L("编号"), isOn: $design.statement.includeID)
            }
        }
    }

    // MARK: 方印

    private var sealSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(L("印文"))
            HStack(spacing: 12) {
                StampThumbnail(design: design, box: CGSize(width: 48, height: 48))
                    .frame(width: 72, height: 72)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.well))
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("四个字以内")).font(Theme.body(12)).foregroundStyle(Theme.ink2)
                    TextField(L("他用无效"), text: Binding(get: { design.sealText }, set: { design.sealText = String($0.prefix(9)) }))
                        .focused(focus, equals: .seal)
                        .font(.custom("STSongti-SC-Bold", fixedSize: 15))
                        .tracking(3)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous).fill(Color.white))
                        .insetStroke(focus.wrappedValue == .seal ? Theme.coralLine : Theme.line,
                                     width: focus.wrappedValue == .seal ? 2 : 1, radius: Theme.Radius.field)
                }
            }
            MochiSegmented(options: [(SealStyle.yang, L("朱文 · 红字")), (.yin, L("白文 · 红底"))], selection: $design.sealStyle,
                           style: .ink, height: 28, fontSize: 12, trackPadding: 3)
            Text(L("方印从右往左、从上往下读；字会自动撑满格子。"))
                .font(Theme.body(11)).foregroundStyle(Theme.ink2).lineSpacing(3)
        }
    }

    // MARK: 长什么样

    private var lookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(L("长什么样"))
            HStack(spacing: 6) {
                ForEach(StampShape.allCases) { shape in
                    let selected = design.shape == shape
                    Button {
                        design.shape = shape
                        if shape == .plain { design.border = .none } else if design.border == .none { design.border = .double }
                    } label: {
                        ShapeGlyph(shape: shape, color: selected ? Theme.coralInk : Theme.tileInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .selectableTile(selected, radius: 10)
                    }
                    .buttonStyle(.plain)
                    .help(shape.label)
                    .accessibilityLabel(shape.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack(spacing: 4) {
                ForEach(StampFont.allCases) { font in
                    let selected = design.font == font
                    Button { design.font = font } label: {
                        Text(font.glyph)
                            .font(.custom(font.tileFontName, fixedSize: font == .serif ? 14 : 15))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .selectableTile(selected, radius: 10)
                    }
                    .buttonStyle(.plain)
                    .help(font.label)
                    .accessibilityLabel(font.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if design.shape != .square && design.shape != .plain {
                HStack(spacing: 8) {
                    Text(L("边框")).font(Theme.body(12)).foregroundStyle(Theme.ink2).frame(width: 44, alignment: .leading)
                    MochiSegmented(options: StampBorder.allCases.map { ($0, $0.shortLabel) }, selection: $design.border,
                                   style: .soft, height: 24, fontSize: 11, trackPadding: 2)
                }
            }
        }
    }

    // MARK: 颜色和大小

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(L("颜色和大小"))
            // 四个圆点，选中的外面一圈细环、旁边写颜色名（以前是四个大胶囊，比按钮还大）。
            HStack(spacing: 12) {
                ForEach(StampColor.allCases) { color in
                    let selected = design.color == color
                    Button { design.color = color } label: {
                        Circle().fill(Color(.sRGB, red: color.rgb.r, green: color.rgb.g, blue: color.rgb.b))
                            .frame(width: 22, height: 22)
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? Theme.ink2 : .clear, lineWidth: 1.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(color.label)
                    .accessibilityLabel(color.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Text(design.color.label).font(Theme.body(12)).foregroundStyle(Theme.ink2)
                Spacer(minLength: 0)
            }
            FieldWell(rowSpacing: 12) {
                SliderRow(L("大小"), value: $design.fontSize, range: 3.5...12, step: 0.1) { _ in
                    String(format: "%.0fmm", design.longSideMM)
                }
                SliderRow(L("歪一点"), value: $design.rotation, range: -20...20, step: 1, centered: true) { v in
                    v < 0 ? "−\(Int(-v))°" : "\(Int(v))°"
                }
                SliderRow(L("浓淡"), value: $design.opacity, range: 0.5...1, step: 0.01) { "\(Int(($0 * 100).rounded()))%" }
            }
            MochiSegmented(options: InkTexture.allCases.map { ($0, $0.label) }, selection: $design.texture,
                           style: .soft, height: 24, fontSize: 11, trackPadding: 2)
        }
    }
}

// MARK: - 小部件

struct SectionHeading: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(Theme.round(13)).foregroundStyle(Theme.ink)
    }
}

/// 一组输入或滑块：左边 44 宽的标签列。
private struct FieldWell<Content: View>: View {
    var rowSpacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        // 不再垫一层底色：白卡片里再套浅粉块、再放白输入框，层次太多。
        VStack(spacing: rowSpacing) { content }
    }
}

private struct WellRow<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field

    init(_ label: String, @ViewBuilder field: () -> Field) {
        self.label = label
        self.field = field()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.body(12)).foregroundStyle(Theme.ink2).frame(width: 44, alignment: .leading)
            field
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var centered = false
    let format: (Double) -> String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, centered: Bool = false,
         format: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.centered = centered
        self.format = format
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.body(12)).foregroundStyle(Theme.ink2).frame(width: 44, alignment: .leading)
            MochiSlider(value: $value, range: range, step: step, centered: centered)
                .accessibilityLabel(title)
            Text(format(value)).font(Theme.round(12)).foregroundStyle(Theme.ink).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// 外形格里的小图标（小方块示意）。
private struct ShapeGlyph: View {
    let shape: StampShape
    let color: Color

    var body: some View {
        switch shape {
        case .rectangle:
            Rectangle().strokeBorder(color, lineWidth: 1.3).frame(width: 20, height: 9)
        case .pill:
            Capsule().strokeBorder(color, lineWidth: 1.3).frame(width: 20, height: 9)
        case .circle:
            Circle().strokeBorder(color, lineWidth: 1.3).frame(width: 15, height: 15)
        case .square:
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 13, height: 13)
        case .plain:
            Rectangle().fill(color).frame(width: 20, height: 1.3)
        }
    }
}

extension StatementPhrasing {
    var shortLabel: String {
        switch self {
        case .chinese: return L("中")
        case .english: return "En"
        case .bilingual: return L("中英")
        }
    }
}

extension StampBorder {
    var shortLabel: String {
        switch self {
        case .double: return L("双线")
        case .single: return L("单线")
        case .thickThin: return L("粗细")
        case .none: return L("无")
        }
    }
}

extension StampFont {
    /// 字体格里那一个字。
    var glyph: String {
        switch self {
        case .songti: return L("宋")
        case .kaiti: return L("楷")
        case .fangsong: return L("仿")
        case .libian: return L("隶")
        case .weibei: return L("魏")
        case .heiti: return L("黑")
        case .serif: return "Aa"
        }
    }

    var tileFontName: String {
        switch self {
        case .songti: return "STSongti-SC-Bold"
        case .kaiti: return "STKaitiSC-Regular"
        case .fangsong: return "STFangsong"
        case .libian: return "STLibianSC-Regular"
        case .weibei: return "WeibeiSC-Bold"
        case .heiti: return "PingFangSC-Semibold"
        case .serif: return "Baskerville"
        }
    }
}
