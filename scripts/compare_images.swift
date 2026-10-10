// 截图对比：swift compare_images.swift <基准目录> <新截图目录> <差异图目录>
// 逐张逐像素比；任一通道差超过 24 算「不一样」，不一样的像素超过 0.2% 就算这张变了。
// 变了的会在差异图目录里生成一张：新截图淡化，不一样的地方标红。有变化时退出码为 1。
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count == 4 else { print("用法：compare_images <基准> <新截图> <差异图>"); exit(2) }
let base = URL(fileURLWithPath: args[1]), now = URL(fileURLWithPath: args[2]), diffs = URL(fileURLWithPath: args[3])
try? FileManager.default.removeItem(at: diffs)
try FileManager.default.createDirectory(at: diffs, withIntermediateDirectories: true)

func load(_ url: URL) -> (CGImage, [UInt8])? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    var data = [UInt8](repeating: 0, count: img.width * img.height * 4)
    let ok = data.withUnsafeMutableBytes { buf -> Bool in
        guard let ctx = CGContext(data: buf.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return true
    }
    return ok ? (img, data) : nil
}

let names = Set((try? FileManager.default.contentsOfDirectory(atPath: now.path)) ?? []).filter { $0.hasSuffix(".png") }
let baseNames = Set((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []).filter { $0.hasSuffix(".png") }
var failed = 0
for name in baseNames.subtracting(names).sorted() { print("✗ \(name)：这张截图没了"); failed += 1 }
for name in names.sorted() {
    guard baseNames.contains(name) else { print("＋ \(name)：新截图，还没有基准（--update 收下）"); failed += 1; continue }
    guard let (a, pa) = load(base.appendingPathComponent(name)), let (b, pb) = load(now.appendingPathComponent(name)) else {
        print("✗ \(name)：读不出来"); failed += 1; continue
    }
    if a.width != b.width || a.height != b.height {
        print("✗ \(name)：尺寸变了 \(a.width)×\(a.height) → \(b.width)×\(b.height)"); failed += 1; continue
    }
    var out = pb
    var changed = 0
    for i in stride(from: 0, to: pa.count, by: 4) {
        let d = max(abs(Int(pa[i]) - Int(pb[i])), abs(Int(pa[i + 1]) - Int(pb[i + 1])), abs(Int(pa[i + 2]) - Int(pb[i + 2])), abs(Int(pa[i + 3]) - Int(pb[i + 3])))
        if d > 24 {
            changed += 1
            out[i] = 255; out[i + 1] = 0; out[i + 2] = 0; out[i + 3] = 255
        } else {
            out[i] = UInt8(155 + Int(out[i]) * 100 / 255); out[i + 1] = UInt8(155 + Int(out[i + 1]) * 100 / 255)
            out[i + 2] = UInt8(155 + Int(out[i + 2]) * 100 / 255); out[i + 3] = 255
        }
    }
    let ratio = Double(changed) / Double(a.width * a.height)
    if ratio > 0.002 {
        failed += 1
        print(String(format: "✗ %@：%.2f%% 的像素变了 → 差异图 %@", name, ratio * 100, diffs.appendingPathComponent(name).path))
        out.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: b.width, height: b.height, bitsPerComponent: 8, bytesPerRow: b.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let dest = CGImageDestinationCreateWithURL(diffs.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
            CGImageDestinationFinalize(dest)
        }
    } else {
        print("✓ \(name)")
    }
}
print(failed == 0 ? "截图对比：全部一致（\(names.count) 张）" : "截图对比：\(failed) 张有变化")
exit(failed == 0 ? 0 : 1)
