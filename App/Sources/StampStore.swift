import Foundation
import StampCore

/// 事先编辑好的印章们，以及当前拿在手上的是哪一枚。存在 UserDefaults。
@MainActor
final class StampStore: ObservableObject {
    @Published var designs: [StampDesign] { didSet { save() } }
    @Published var currentID: UUID { didSet { save() } }
    /// 盖章时用滚轮调出来的大小倍率，下次拿起印章时沿用。
    @Published var sizeMultiplier: Double { didSet { save() } }
    /// 刚刻好的那枚：列表里带「新」角标。
    @Published var freshID: UUID?
    /// 正在改名的那枚：名字变成输入框。
    @Published var renamingID: UUID?
    /// 工坊里要不要打开模板库（菜单面板的「+」也会把它打开）。
    @Published var showLibrary = false
    /// 下一次盖章用的编号：工坊里显示的就是它。真的存好一份副本后才换新的，拿起又放下不算。
    @Published private(set) var nextStampID: String { didSet { save() } }

    private let defaults: UserDefaults

    /// 第一次打开时放进「我的印章」的几枚：从模板复制出来，各有自己的 id。
    static var starterDesigns: [StampDesign] {
        StampTemplates.all.prefix(4).map { template in
            var design = template
            design.id = UUID()
            design.name = L(template.name) // 第一次打开时按当前语言起名，之后就是用户自己的名字
            return design
        }
    }

    /// 存储格式版本。v1 是旧的大号印章，升级时保留文字内容、换上新的精致外观。
    private static let designsVersion = 2

    /// `defaults` 只有官网素材生成时才换成临时的一套，不碰用户自己的设置。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded = Self.load([StampDesign].self, key: "designs", from: defaults) ?? []
        if !loaded.isEmpty, defaults.integer(forKey: "designsVersion") < Self.designsVersion {
            loaded = loaded.map { $0.applyingLook(of: StampTemplates.all[0]) }
        }
        defaults.set(Self.designsVersion, forKey: "designsVersion")
        let designs = loaded.isEmpty ? Self.starterDesigns : loaded
        self.designs = designs
        let savedID = defaults.string(forKey: "currentDesign").flatMap(UUID.init(uuidString:))
        currentID = designs.contains { $0.id == savedID } ? savedID! : designs[0].id
        let multiplier = defaults.double(forKey: "sizeMultiplier")
        sizeMultiplier = multiplier > 0 ? multiplier : 1
        nextStampID = defaults.string(forKey: "nextStampID") ?? StampID.make()
        defaults.set(nextStampID, forKey: "nextStampID")
    }

    /// 用 `id` 盖好了一份：下一次换个新编号。
    func didUse(stampID id: String) {
        if nextStampID == id { nextStampID = StampID.make() }
    }

    var current: StampDesign {
        get { designs.first { $0.id == currentID } ?? designs[0] }
        set {
            if let i = designs.firstIndex(where: { $0.id == newValue.id }) { designs[i] = newValue }
        }
    }

    /// 从模板刻一枚新章：插到最上面，名字直接进入编辑。
    func addDesign(from template: StampDesign) {
        var design = template
        design.id = UUID()
        design.name = uniqueName(L(template.name)) // 模板名按当前语言起，之后就是用户自己的名字
        designs.insert(design, at: 0)
        currentID = design.id
        freshID = design.id
        renamingID = design.id
    }

    /// 把模板的外观套到当前印章上，文字内容保留。
    func applyLook(of template: StampDesign) {
        current = current.applyingLook(of: template)
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(designs.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    func duplicate(_ design: StampDesign) {
        var copy = design
        copy.id = UUID()
        copy.name = uniqueName(design.name + L(" 副本"))
        let index = designs.firstIndex { $0.id == design.id }.map { $0 + 1 } ?? designs.count
        designs.insert(copy, at: index)
        currentID = copy.id
        freshID = copy.id
    }

    func delete(_ design: StampDesign) {
        guard designs.count > 1 else { return }
        designs.removeAll { $0.id == design.id }
        if !designs.contains(where: { $0.id == currentID }) { currentID = designs[0].id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(designs) { defaults.set(data, forKey: "designs") }
        defaults.set(currentID.uuidString, forKey: "currentDesign")
        defaults.set(sizeMultiplier, forKey: "sizeMultiplier")
        defaults.set(nextStampID, forKey: "nextStampID")
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
