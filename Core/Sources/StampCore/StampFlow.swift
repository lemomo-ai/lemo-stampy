import CoreGraphics
import Foundation

/// 鼠标下面的那一页：哪个文件、第几页、这一页在屏幕上的位置。
/// App 从「预览」的辅助功能信息里读出来；测试里直接造一个。
public struct PageTarget: Equatable, Sendable {
    public let documentURL: URL
    public let kind: DocumentKind
    public let pageIndex: Int
    /// 页面在屏幕上的矩形（全局坐标，原点在主屏左上角，与辅助功能 API 一致）。
    public let pageFrame: CGRect
    /// 页面的文档尺寸：PDF 为点，照片为像素，均按显示方向。加了密码、还没输密码的 PDF 为 .zero。
    public let pageSize: CGSize
    /// 加了密码的 PDF，小章还不知道密码：点一下先输密码。
    public var isLocked: Bool

    public init(documentURL: URL, kind: DocumentKind, pageIndex: Int, pageFrame: CGRect, pageSize: CGSize, isLocked: Bool = false) {
        self.documentURL = documentURL
        self.kind = kind
        self.pageIndex = pageIndex
        self.pageFrame = pageFrame
        self.pageSize = pageSize
        self.isLocked = isLocked
    }

    /// 屏幕上每个点对应多少个「印章点」：用来让浮动印章和最终盖上去的一样大。
    public var screenPointsPerStampPoint: CGFloat {
        let zoom = pageFrame.width / max(pageSize.width, 1)
        return zoom * DocumentStamper.unitsPerPoint(kind: kind, pageSize: pageSize)
    }

    /// 屏幕上的点在这一页上的相对位置（0…1，从左、从上）。
    public func relativePosition(of point: CGPoint) -> (x: Double, y: Double) {
        (Double((point.x - pageFrame.minX) / pageFrame.width), Double((point.y - pageFrame.minY) / pageFrame.height))
    }

    /// 页面上的相对位置在屏幕上的哪儿（辅助功能坐标，原点在主屏左上角）。
    public func axPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: pageFrame.minX + CGFloat(x) * pageFrame.width, y: pageFrame.minY + CGFloat(y) * pageFrame.height)
    }

    /// 靠边时往里推，整枚章都留在页面里（`stampSize` 是旋转后的外接尺寸，单位：印章点）。
    public func keptInside(_ placement: StampPlacement, stampSize: CGSize) -> StampPlacement {
        let unit = DocumentStamper.unitsPerPoint(kind: kind, pageSize: pageSize) * CGFloat(placement.scale)
        return placement.keptInside(pageSize: pageSize, stampSize: CGSize(width: stampSize.width * unit, height: stampSize.height * unit))
    }

    public var displayName: String {
        let name = documentURL.lastPathComponent
        return kind == .pdf ? L("「%@」第 %ld 页", name, pageIndex + 1) : L("「%@」", name)
    }
}

/// 拿起印章以后的整个过程，只有逻辑、不碰屏幕：鼠标在哪、点了什么、滚轮、输密码、确认、存。
/// App 里的 StampSession 把系统事件喂给它，再按它的结果摆窗口；单元测试直接喂假的页面。
public struct StampFlow: Sendable {
    public enum State: Equatable, Sendable {
        case hovering
        /// 点在加了密码的 PDF 上，正在输密码；`point` 是点的位置，解开后就盖在那儿。
        case unlocking(target: PageTarget, point: CGPoint)
        case confirming(target: PageTarget, placement: StampPlacement)
        case finished
    }

    /// 跟着鼠标走的提示条写什么。
    public enum Hint: Equatable, Sendable {
        case offPage
        case onPage(String)
        case size(Double)
    }

    /// 拿着章移动时，章该画在哪、什么样。
    public struct Hover: Equatable, Sendable {
        /// 对准了能盖的页面：章贴着这里（已经往里推过）；nil 表示跟着鼠标。
        public var placement: StampPlacement?
        /// 对准了能盖的页面（不透明、带投影）。
        public var active: Bool
        public var hint: Hint?
    }

    public enum ClickResult: Equatable, Sendable {
        /// 没点在「预览」的页面上：响一声，什么都不做。
        case missed
        /// 加了密码：先弹密码卡片。
        case askPassword
        /// 盖下去了，弹确认卡片。
        case placed(StampPlacement)
        /// 正在输密码时点了别处：收起密码卡片，接着拿着章。
        case cancelledUnlock
        /// 已经结束了。
        case ignored
    }

    public static let minScale = 0.4
    public static let maxScale = 4.0
    public static var lockedHint: String { L("这份 PDF 加了密码 · 点一下输入密码") }

    public private(set) var state: State = .hovering
    public private(set) var sizeMultiplier: Double
    /// 滚轮刚调过大小：提示条显示「大小 120%」，App 过 1 秒调 `hideSizeHint()`。
    public private(set) var showingSize = false
    /// 印章旋转后的外接尺寸（印章点，没乘大小倍率）。
    public let stampSize: CGSize

    public init(stampSize: CGSize, sizeMultiplier: Double) {
        self.stampSize = stampSize
        self.sizeMultiplier = min(max(sizeMultiplier, Self.minScale), Self.maxScale)
    }

    public var isConfirming: Bool {
        if case .confirming = state { return true }
        return false
    }

    public var isFinished: Bool { state == .finished }

    /// 点在 `target` 的 `point` 上会盖在哪：按页面比例，靠边往里推。
    public func placement(on target: PageTarget, at point: CGPoint) -> StampPlacement {
        let rel = target.relativePosition(of: point)
        let raw = StampPlacement(pageIndex: target.pageIndex, x: rel.x, y: rel.y, scale: sizeMultiplier)
        return target.keptInside(raw, stampSize: stampSize)
    }

    // MARK: 移动

    public func hover(over target: PageTarget?, at point: CGPoint) -> Hover {
        let usable = target.flatMap { $0.isLocked ? nil : $0 }
        var hover = Hover(placement: nil, active: usable != nil, hint: nil)
        if case .confirming(_, let placement) = state {
            hover.placement = placement
            hover.active = true
            return hover
        }
        if let usable { hover.placement = placement(on: usable, at: point) }
        if showingSize {
            hover.hint = .size(sizeMultiplier)
        } else if let target, target.isLocked {
            hover.hint = .onPage(Self.lockedHint)
        } else if let target {
            hover.hint = .onPage(target.kind == .pdf ? L("第 %ld 页 · 点一下就盖", target.pageIndex + 1) : L("照片 · 点一下就盖"))
        } else {
            hover.hint = .offPage
        }
        return hover
    }

    // MARK: 点击

    /// 确认卡片出来后再点别处 = 换个位置重新盖，所以确认中也照常处理。
    public mutating func click(on target: PageTarget?, at point: CGPoint) -> ClickResult {
        switch state {
        case .finished:
            return .ignored
        case .unlocking:
            state = .hovering
            return .cancelledUnlock
        case .hovering, .confirming:
            guard let target else { return .missed }
            if target.isLocked {
                state = .unlocking(target: target, point: point)
                return .askPassword
            }
            let placement = placement(on: target, at: point)
            state = .confirming(target: target, placement: placement)
            return .placed(placement)
        }
    }

    // MARK: 输密码

    /// 密码对了：`target` 是解开后读到真实页面尺寸的那一页，直接盖在刚才点的地方。
    public mutating func unlocked(_ target: PageTarget) -> StampPlacement? {
        guard case .unlocking(_, let point) = state else { return nil }
        var open = target
        open.isLocked = false
        let placement = placement(on: open, at: point)
        state = .confirming(target: open, placement: placement)
        return placement
    }

    /// 密码卡片点了「取消」或 esc：接着拿着章。
    public mutating func cancelUnlock() {
        if case .unlocking = state { state = .hovering }
    }

    // MARK: 滚轮

    /// 滚一格 ±10%，范围 40%–400%。确认中调大小会重新往里推，返回新的位置；拿着章时返回 nil 并显示大小提示。
    @discardableResult
    public mutating func scroll(steps: Int) -> StampPlacement? {
        guard steps != 0, !isFinished else { return nil }
        let next = ((sizeMultiplier + Double(steps) * 0.1) * 10).rounded() / 10
        sizeMultiplier = min(max(next, Self.minScale), Self.maxScale)
        if case .confirming(let target, var placement) = state {
            placement.scale = sizeMultiplier
            placement = target.keptInside(placement, stampSize: stampSize)
            state = .confirming(target: target, placement: placement)
            return placement
        }
        showingSize = true
        return nil
    }

    public mutating func hideSizeHint() {
        showingSize = false
    }

    // MARK: 存

    /// 要盖哪些页：「每一页都盖」时按勾选的页换算位置，否则只盖点的那一页。
    public func placementsToSave(allPages: Bool, selected: Set<Int>, pageCount: Int) -> [StampPlacement] {
        guard case .confirming(_, let placement) = state else { return [] }
        if allPages, pageCount > 1 {
            return selected.filter { $0 >= 0 && $0 < pageCount }.sorted().map { placement.onPage($0) }
        }
        return [placement]
    }

    public mutating func finish() {
        state = .finished
    }
}
