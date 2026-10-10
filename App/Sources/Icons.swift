import AppKit
import StampCore

enum Icons {
    enum MenuBarState { case normal, holding, unauthorized }

    /// 菜单栏图标：小章的脸（15×14、圆角 4.5）。模板图，自动适配深浅色菜单栏。
    /// - normal：1.5 描边 + 两只 2×3 的眼睛
    /// - holding：实心，眼睛镂空
    /// - unauthorized：闭眼的两道短线，右上角一个 5px 的小圆点
    static func menuBarImage(_ state: MenuBarState = .normal) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let face = CGRect(x: 2.5, y: 2, width: 15, height: 14)
            NSColor.black.set()
            switch state {
            case .normal:
                let path = NSBezierPath(roundedRect: face.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.75, yRadius: 3.75)
                path.lineWidth = 1.5
                path.stroke()
                NSBezierPath(roundedRect: CGRect(x: face.minX + 4.5, y: face.minY + 5.5, width: 2, height: 3), xRadius: 1, yRadius: 1).fill()
                NSBezierPath(roundedRect: CGRect(x: face.maxX - 6.5, y: face.minY + 5.5, width: 2, height: 3), xRadius: 1, yRadius: 1).fill()
            case .holding:
                NSBezierPath(roundedRect: face, xRadius: 4.5, yRadius: 4.5).fill()
                ctx.setBlendMode(.clear)
                NSBezierPath(roundedRect: CGRect(x: face.minX + 4, y: face.minY + 5, width: 2, height: 3), xRadius: 1, yRadius: 1).fill()
                NSBezierPath(roundedRect: CGRect(x: face.maxX - 6, y: face.minY + 5, width: 2, height: 3), xRadius: 1, yRadius: 1).fill()
                ctx.setBlendMode(.normal)
            case .unauthorized:
                let path = NSBezierPath(roundedRect: face.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.75, yRadius: 3.75)
                path.lineWidth = 1.5
                path.stroke()
                NSBezierPath(rect: CGRect(x: face.minX + 3.5, y: face.minY + 6.5, width: 3, height: 1.5)).fill()
                NSBezierPath(rect: CGRect(x: face.maxX - 6.5, y: face.minY + 6.5, width: 3, height: 1.5)).fill()
                // 小圆点外圈先挖空 1.5，和脸的描边分开。
                let dot = CGRect(x: face.minX + 12.5, y: face.minY - 2, width: 5, height: 5)
                ctx.setBlendMode(.clear)
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
                ctx.setBlendMode(.normal)
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L("小章")
        return image
    }
}
