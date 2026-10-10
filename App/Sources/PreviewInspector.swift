import AppKit
import ApplicationServices
import StampCore

/// 鼠标下面是「预览」里的哪个文件、哪一页。几何换算都在 Core 的 `PageTarget` 里，这里只补屏幕坐标。
typealias PreviewTarget = PageTarget

extension PageTarget {
    /// 页面上的相对位置在屏幕上的哪儿（AppKit 坐标，原点在主屏左下角）。
    func screenPoint(x: Double, y: Double) -> CGPoint {
        let p = axPoint(x: x, y: y)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}

enum PreviewInspector {
    static let previewBundleID = "com.apple.Preview"

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// 页面尺寸要读文件，按 URL + 页码缓存。读文件放在后台：
    /// 文件在桌面 / 文稿里时 macOS 会弹授权框，并卡住读文件的线程，绝不能卡在主线程上。
    private static var sizeCache: [String: CGSize] = [:]
    private static var loading: Set<String> = []
    /// 读的时候发现要密码的 PDF。
    private static var locked: Set<String> = []
    private static let loader = DispatchQueue(label: "xiaoyinzhang.page-size", qos: .userInitiated)
    /// 后台读完页面尺寸时发出，盖章过程据此刷新浮动印章。
    static let pageSizeLoaded = Notification.Name("PreviewInspector.pageSizeLoaded")

    /// `point` 用辅助功能坐标（原点在主屏左上角）。
    static func target(at point: CGPoint) -> PreviewTarget? {
        guard let pid = frontmostWindowOwner(at: point),
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == previewBundleID else { return nil }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3) // 「预览」无响应时别把我们拖住
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, var element = hit else {
            return nil
        }

        var page: AXUIElement?
        var image: AXUIElement?
        var container: AXUIElement?
        var window: AXUIElement?
        for _ in 0..<40 {
            switch string(element, kAXRoleAttribute) {
            case "AXPage": if page == nil { page = element }
            case "AXImage": if image == nil { image = element }
            case "AXWindow": window = element
            default:
                if container == nil, string(element, kAXSubroleAttribute) == "AXSharedDocumentContainer" { container = element }
            }
            if window != nil { break }
            guard let parent = attribute(element, kAXParentAttribute) else { break }
            element = parent as! AXUIElement
        }
        // 命中检测常常只到「文档容器」这一层，到它可见的页面里找包含鼠标的那一页。
        if page == nil, let container {
            let pages = (attribute(container, "AXVisibleChildren") as? [AXUIElement])
                ?? (attribute(container, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            page = pages.first { string($0, kAXRoleAttribute) == "AXPage" && frame(of: $0)?.contains(point) == true }
        }

        guard let window, let docString = string(window, kAXDocumentAttribute),
              let url = URL(string: docString), url.isFileURL,
              let kind = DocumentStamper.kind(of: url) else { return nil }

        switch kind {
        case .pdf:
            guard let page, let frame = frame(of: page) else { return nil }
            let index = (attribute(page, "AXPageIndex") as? NSNumber)?.intValue ?? 0
            guard let size = pageSize(url, index) else {
                guard locked.contains(url.path) else { return nil }
                return PreviewTarget(documentURL: url, kind: .pdf, pageIndex: index, pageFrame: frame, pageSize: .zero, isLocked: true)
            }
            return PreviewTarget(documentURL: url, kind: .pdf, pageIndex: index, pageFrame: frame, pageSize: size)
        case .image:
            guard let image, let frame = frame(of: image), frame.contains(point) else { return nil }
            guard let size = pageSize(url, 0) else { return nil }
            return PreviewTarget(documentURL: url, kind: .image, pageIndex: 0, pageFrame: frame, pageSize: size)
        }
    }

    /// 屏幕上这个点最上面的普通窗口属于哪个进程（跳过小章自己的浮层）。
    private static func frontmostWindowOwner(at point: CGPoint) -> pid_t? {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in windows {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.contains(point) else { continue }
            return pid
        }
        return nil
    }

    /// 输对密码之后：忘掉「要密码」，记下刚读到的页面尺寸。
    static func didUnlock(_ url: URL, pageIndex: Int, size: CGSize) {
        locked.remove(url.path)
        sizeCache["\(url.path)#\(pageIndex)"] = size
    }

    /// 有缓存就直接给；没有就在后台读，这次先返回 nil（浮动印章暂时显示为未对准）。
    private static func pageSize(_ url: URL, _ index: Int) -> CGSize? {
        let key = "\(url.path)#\(index)"
        if let cached = sizeCache[key] { return cached }
        guard !loading.contains(key) else { return nil }
        loading.insert(key)
        loader.async {
            var size: CGSize?
            var needsPassword = false
            do { size = try DocumentStamper.pageSize(of: url, pageIndex: index) } catch StampError.encryptedPDF {
                needsPassword = true
            } catch {}
            DispatchQueue.main.async {
                loading.remove(key)
                if needsPassword {
                    locked.insert(url.path)
                    NotificationCenter.default.post(name: pageSizeLoaded, object: nil)
                }
                guard let size else { return }
                if sizeCache.count > 200 { sizeCache.removeAll() }
                sizeCache[key] = size
                NotificationCenter.default.post(name: pageSizeLoaded, object: nil)
            }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: position, size: size)
    }
}
