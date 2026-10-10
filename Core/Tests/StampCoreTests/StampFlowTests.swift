import CoreGraphics
import Foundation
@testable import StampCore
import XCTest

/// 拿起印章以后的流程：不开「预览」、不动鼠标，造几页假的页面直接喂给 StampFlow。
/// 页边裁切、密码 PDF 这些出过的问题都在这里守着。
final class StampFlowTests: XCTestCase {
    /// A4 纵向，屏幕上显示成 595×842（100%），左上角在 (100, 50)。
    let pdf = PageTarget(documentURL: URL(fileURLWithPath: "/tmp/合同.pdf"), kind: .pdf, pageIndex: 1,
                         pageFrame: CGRect(x: 100, y: 50, width: 595, height: 842), pageSize: CGSize(width: 595, height: 842))
    let locked = PageTarget(documentURL: URL(fileURLWithPath: "/tmp/加密.pdf"), kind: .pdf, pageIndex: 0,
                            pageFrame: CGRect(x: 100, y: 50, width: 595, height: 842), pageSize: .zero, isLocked: true)
    let photo = PageTarget(documentURL: URL(fileURLWithPath: "/tmp/照片.jpg"), kind: .image, pageIndex: 0,
                           pageFrame: CGRect(x: 0, y: 0, width: 400, height: 300), pageSize: CGSize(width: 4000, height: 3000))
    /// 一枚 100×40 印章点的长章。
    let stamp = CGSize(width: 100, height: 40)

    func makeFlow(scale: Double = 1) -> StampFlow { StampFlow(stampSize: stamp, sizeMultiplier: scale) }

    // MARK: 移动和提示条

    func testOffPageFollowsMouse() {
        let hover = makeFlow().hover(over: nil, at: CGPoint(x: 5, y: 5))
        XCTAssertNil(hover.placement)
        XCTAssertFalse(hover.active)
        XCTAssertEqual(hover.hint, .offPage)
    }

    func testOnPageHintSaysWhichPage() {
        let flow = makeFlow()
        XCTAssertEqual(flow.hover(over: pdf, at: CGPoint(x: 300, y: 300)).hint, .onPage("第 2 页 · 点一下就盖"))
        XCTAssertEqual(flow.hover(over: photo, at: CGPoint(x: 200, y: 150)).hint, .onPage("照片 · 点一下就盖"))
        XCTAssertTrue(flow.hover(over: pdf, at: CGPoint(x: 300, y: 300)).active)
    }

    func testLockedPDFAsksForPassword() {
        let hover = makeFlow().hover(over: locked, at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(hover.hint, .onPage(StampFlow.lockedHint))
        XCTAssertFalse(hover.active, "还没输密码，不知道页面尺寸，章不能贴上去")
        XCTAssertNil(hover.placement)
    }

    /// 页边：鼠标在页角，章贴着页边停住，整枚留在纸里。
    func testHoveringAtCornerKeepsWholeStampOnPage() {
        let corner = CGPoint(x: pdf.pageFrame.maxX - 1, y: pdf.pageFrame.maxY - 1)
        let p = makeFlow().hover(over: pdf, at: corner).placement!
        XCTAssertEqual(p.x * 595, 595 - 50, accuracy: 0.5)
        XCTAssertEqual(p.y * 842, 842 - 20, accuracy: 0.5)
    }

    // MARK: 点击

    func testClickOffPageMisses() {
        var flow = makeFlow()
        XCTAssertEqual(flow.click(on: nil, at: .zero), .missed)
        XCTAssertEqual(flow.state, .hovering)
    }

    func testClickPlacesAndConfirms() {
        var flow = makeFlow()
        let result = flow.click(on: pdf, at: CGPoint(x: 100 + 297.5, y: 50 + 421))
        guard case .placed(let p) = result else { return XCTFail("应该盖下去") }
        XCTAssertEqual(p.pageIndex, 1)
        XCTAssertEqual(p.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(p.y, 0.5, accuracy: 0.001)
        XCTAssertTrue(flow.isConfirming)
        XCTAssertNil(flow.hover(over: pdf, at: .zero).hint, "确认中不显示提示条")
    }

    /// 确认卡片出来后点别处 = 换个位置。
    func testClickElsewhereWhileConfirmingMovesStamp() {
        var flow = makeFlow()
        _ = flow.click(on: pdf, at: CGPoint(x: 200, y: 200))
        guard case .placed(let second) = flow.click(on: pdf, at: CGPoint(x: 400, y: 600)) else { return XCTFail() }
        XCTAssertEqual(second.x, 300.0 / 595, accuracy: 0.001)
        guard case .confirming(_, let current) = flow.state else { return XCTFail() }
        XCTAssertEqual(current, second)
    }

    func testClickAfterFinishIsIgnored() {
        var flow = makeFlow()
        flow.finish()
        XCTAssertEqual(flow.click(on: pdf, at: CGPoint(x: 300, y: 300)), .ignored)
        XCTAssertNil(flow.scroll(steps: 1))
    }

    // MARK: 密码

    func testPasswordThenStampExactlyWhereClicked() {
        var flow = makeFlow()
        let point = CGPoint(x: 100 + 595 * 0.25, y: 50 + 842 * 0.75)
        XCTAssertEqual(flow.click(on: locked, at: point), .askPassword)
        guard case .unlocking = flow.state else { return XCTFail("应该在输密码") }
        // 输对了：读到真实尺寸，直接盖在刚才点的地方。
        let open = PageTarget(documentURL: locked.documentURL, kind: .pdf, pageIndex: 0, pageFrame: locked.pageFrame,
                              pageSize: CGSize(width: 595, height: 842))
        let p = flow.unlocked(open)
        XCTAssertNotNil(p)
        XCTAssertEqual(p!.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(p!.y, 0.75, accuracy: 0.001)
        guard case .confirming(let target, _) = flow.state else { return XCTFail("应该进入确认") }
        XCTAssertFalse(target.isLocked)
    }

    func testCancelPasswordKeepsHolding() {
        var flow = makeFlow()
        _ = flow.click(on: locked, at: CGPoint(x: 300, y: 300))
        flow.cancelUnlock()
        XCTAssertEqual(flow.state, .hovering, "esc / 取消：接着拿着章")
        XCTAssertNil(flow.unlocked(pdf), "已经不在输密码了，晚到的解锁结果不能盖章")
    }

    func testClickElsewhereWhileUnlockingOnlyClosesCard() {
        var flow = makeFlow()
        _ = flow.click(on: locked, at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(flow.click(on: pdf, at: CGPoint(x: 300, y: 300)), .cancelledUnlock)
        XCTAssertEqual(flow.state, .hovering, "点外面只收起密码卡片，不顺手盖下去")
    }

    // MARK: 滚轮

    func testScrollChangesSizeInTenPercentSteps() {
        var flow = makeFlow()
        flow.scroll(steps: 2)
        XCTAssertEqual(flow.sizeMultiplier, 1.2, accuracy: 0.0001)
        XCTAssertEqual(flow.hover(over: pdf, at: CGPoint(x: 300, y: 300)).hint, .size(1.2))
        flow.hideSizeHint()
        XCTAssertEqual(flow.hover(over: pdf, at: CGPoint(x: 300, y: 300)).hint, .onPage("第 2 页 · 点一下就盖"))
        flow.scroll(steps: 100)
        XCTAssertEqual(flow.sizeMultiplier, StampFlow.maxScale)
        flow.scroll(steps: -100)
        XCTAssertEqual(flow.sizeMultiplier, StampFlow.minScale)
    }

    func testHoveringPlacementUsesCurrentSize() {
        var flow = makeFlow()
        flow.scroll(steps: 10) // 200%
        let corner = CGPoint(x: pdf.pageFrame.maxX, y: pdf.pageFrame.maxY)
        let p = flow.hover(over: pdf, at: corner).placement!
        XCTAssertEqual(p.scale, 2, accuracy: 0.0001)
        XCTAssertEqual(p.x * 595, 595 - 100, accuracy: 0.5, "两倍大，离边要 100 点")
    }

    /// 盖下去后再调大，章往里挪，不出界。
    func testEnlargingWhileConfirmingPushesStampBackInside() {
        var flow = makeFlow()
        _ = flow.click(on: pdf, at: CGPoint(x: pdf.pageFrame.maxX - 52, y: 300))
        let moved = flow.scroll(steps: 10)
        XCTAssertNotNil(moved)
        XCTAssertEqual(moved!.scale, 2, accuracy: 0.0001)
        XCTAssertEqual(moved!.x * 595, 595 - 100, accuracy: 0.5)
        XCTAssertFalse(flow.showingSize, "确认中调大小不弹大小提示，章直接变")
    }

    // MARK: 存

    func testPlacementsToSave() {
        var flow = makeFlow()
        XCTAssertEqual(flow.placementsToSave(allPages: false, selected: [], pageCount: 1), [], "还没盖下去")
        guard case .placed(let p) = flow.click(on: pdf, at: CGPoint(x: 300, y: 300)) else { return XCTFail() }
        XCTAssertEqual(flow.placementsToSave(allPages: false, selected: [0, 1, 2], pageCount: 6), [p])
        let all = flow.placementsToSave(allPages: true, selected: [5, 0, 2, 9], pageCount: 6)
        XCTAssertEqual(all.map(\.pageIndex), [0, 2, 5], "按页码排好，超出页数的不要")
        XCTAssertTrue(all.allSatisfy { $0.x == p.x && $0.y == p.y && $0.scale == p.scale })
        XCTAssertEqual(flow.placementsToSave(allPages: true, selected: [0], pageCount: 1), [p], "只有一页时就是这一页")
        XCTAssertEqual(flow.placementsToSave(allPages: true, selected: [], pageCount: 6), [], "一页都没勾：不盖")
    }
}

/// 界面语言：默认中文；切到英文后界面文字、量词、页码、副本文件名都换成英文。
final class LocalizationTests: XCTestCase {
    override func tearDown() { Localization.language = .zh }

    func testChineseByDefaultAndEnglishWhenSwitched() {
        XCTAssertEqual(L("拿起印章"), "拿起印章")
        XCTAssertEqual(Localization.count(3, "份"), "3 份")
        Localization.language = .en
        XCTAssertEqual(L("拿起印章"), "Pick up stamp")
        XCTAssertEqual(L("盖 %@", Localization.count(1, "份")), "Stamp 1 file")
        XCTAssertEqual(L("盖 %@", Localization.count(4, "份")), "Stamp 4 files")
        XCTAssertEqual(StampRecord.pagesLabel([1]), "Page 2")
        XCTAssertEqual(StampRecord.pagesLabel([0, 1, 2]), "Pages 1–3")
        XCTAssertEqual(StampRecord.pagesLabel([0, 2]), "Pages 1, 3")
        XCTAssertEqual(DocumentStamper.suggestedOutputURL(for: URL(fileURLWithPath: "/nonexistent/a.pdf")).lastPathComponent, "a_stamped.pdf")
        XCTAssertEqual(StampShape.circle.label, "Round")
        XCTAssertEqual(L("没有这句的翻译"), "没有这句的翻译", "缺翻译时显示中文原文，不会空白")
    }

    func testStampTextNeverFollowsUILanguage() {
        Localization.language = .en
        let text = Statement(recipient: "招商银行", purpose: "办理开户").stampText(date: Date(), stampID: "A7K3Q2")
        XCTAssertTrue(text.allLines.joined().contains("仅供招商银行办理开户使用"), "章上的字是盖给别人看的，不跟界面语言变")
    }

    func testSystemLanguagePicksChineseOnlyForChinese() {
        XCTAssertEqual(LanguagePreference.zh.resolved, .zh)
        XCTAssertEqual(LanguagePreference.en.resolved, .en)
    }
}
