// 生成 App 图标：朱红方印，白色「印」字。用法：swift scripts/make_icon.swift <appiconset 目录>
import AppKit

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS 图标网格：内容区约占 80%
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let red = NSColor(srgbRed: 0.78, green: 0.09, blue: 0.12, alpha: 1)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.025
    shadow.set()
    red.setFill()
    NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18).fill()
    NSShadow().set()
    // 内框
    let inner = NSBezierPath(roundedRect: body.insetBy(dx: s * 0.06, dy: s * 0.06), xRadius: s * 0.1, yRadius: s * 0.1)
    inner.lineWidth = s * 0.022
    NSColor.white.withAlphaComponent(0.9).setStroke()
    inner.stroke()
    let font = NSFont(name: "STSongti-SC-Black", size: s * 0.46) ?? NSFont.systemFont(ofSize: s * 0.46, weight: .black)
    let text = NSAttributedString(string: "印", attributes: [.font: font, .foregroundColor: NSColor.white])
    let ts = text.size()
    text.draw(at: NSPoint(x: s / 2 - ts.width / 2, y: s / 2 - ts.height / 2 + s * 0.005))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try render(base * scale).write(to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted]).write(to: dir.appendingPathComponent("Contents.json"))
let catalog = dir.deletingLastPathComponent().appendingPathComponent("Contents.json")
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!.write(to: catalog)
print("icon written to \(dir.path)")
