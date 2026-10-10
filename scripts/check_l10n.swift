// 界面文字检查：swift scripts/check_l10n.swift [--list]
//   1. 代码里每一句 L("…")、日期格式 mochi("…")、量词 Localization.count(n, "…")、模板名和说明，都要在英文对照表里有翻译。
//   2. 界面代码里不能有没包 L() 的中文（注释、印章上的字、测试和官网素材除外）。行尾写 `// l10n-ignore` 可以跳过一行。
//   --list：打印所有要翻译的中文原文（写对照表时用）。
// 有问题时退出码为 1。
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let listOnly = CommandLine.arguments.contains("--list")
let dictFile = root.appendingPathComponent("Core/Sources/StampCore/Localization+English.swift")
/// 不检查「漏包 L()」的文件：测试数据、官网素材、截图样例，以及印章内容（模板里的句子是盖在纸上的字）。
let skipUnwrapped: Set<String> = ["E2E.swift", "SiteMedia.swift", "PromoFilm.swift", "Snapshots.swift", "Localization+English.swift", "Localization.swift",
                                  "StampTemplates.swift", "Statement.swift"]

func swiftFiles(_ dir: String) -> [URL] {
    let base = root.appendingPathComponent(dir)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
    return names.filter { $0.hasSuffix(".swift") }.sorted().map { base.appendingPathComponent($0) }
}

let files = swiftFiles("App/Sources") + swiftFiles("Core/Sources/StampCore")
let hanRange = "\\p{Han}"
func matches(_ pattern: String, in text: String) -> [[String]] {
    let re = try! NSRegularExpression(pattern: pattern)
    return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
        (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
func unescape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"")
}

var keys: [String: String] = [:] // 原文 → 第一次出现的位置
var problems: [String] = []
let literal = "\"((?:[^\"\\\\]|\\\\.)*)\""

for file in files {
    let name = file.lastPathComponent
    guard let text = try? String(contentsOf: file, encoding: .utf8), name != "Localization+English.swift" else { continue }
    for (n, line) in text.components(separatedBy: "\n").enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") { continue }
        var code = line
        if let r = line.range(of: " // "), line[..<r.lowerBound].filter({ $0 == "\"" }).count % 2 == 0 { code = String(line[..<r.lowerBound]) }
        let place = "\(name):\(n + 1)"
        var keyed = Set<String>()
        for pattern in ["\\bL\\(" + literal, "mochi\\(" + literal, "count\\([^,]+, " + literal + "\\)"] {
            for m in matches(pattern, in: code) {
                let key = unescape(m[1])
                keyed.insert(m[1])
                if keys[key] == nil { keys[key] = place }
            }
        }
        if name == "StampTemplates.swift" {
            for m in matches("(?:name|blurb): " + literal, in: code) where !matches(hanRange, in: m[1]).isEmpty {
                keyed.insert(m[1])
                if keys[unescape(m[1])] == nil { keys[unescape(m[1])] = place }
            }
        }
        guard !skipUnwrapped.contains(name), !line.contains("l10n-ignore") else { continue }
        for m in matches(literal, in: code) where !matches(hanRange, in: m[1]).isEmpty && !keyed.contains(m[1]) {
            problems.append("没包 L()：\(place)  \"\(m[1])\"")
        }
    }
}

if listOnly {
    for key in keys.keys.sorted() { print(key.replacingOccurrences(of: "\n", with: "\\n")) }
    exit(0)
}

let dictText = (try? String(contentsOf: dictFile, encoding: .utf8)) ?? ""
var english: [String: String] = [:]
for m in matches(literal + "\\s*:\\s*" + literal, in: dictText) {
    // 字典字面量里键重复，App 一启动就会崩。
    if english[unescape(m[1])] != nil { problems.append("对照表里重复：\"\(m[1])\"") }
    english[unescape(m[1])] = unescape(m[2])
}

for (key, place) in keys.sorted(by: { $0.value < $1.value }) where english[key] == nil {
    problems.append("缺英文：\(place)  \"\(key.replacingOccurrences(of: "\n", with: "\\n"))\"")
}
// 格式里的参数（%@、%ld）个数要对得上。
for (key, value) in english {
    let a = matches("%(?:\\d\\$)?(?:@|ld|d|%)", in: key).count, b = matches("%(?:\\d\\$)?(?:@|ld|d|%)", in: value).count
    if a != b { problems.append("参数个数不一致：\"\(key)\" → \"\(value)\"") }
}
let unused = english.keys.filter { keys[$0] == nil }.sorted()

problems.forEach { print("✗ \($0)") }
if !unused.isEmpty { print("（对照表里有 \(unused.count) 条代码里没用到，可以删：\(unused.prefix(8).joined(separator: "、"))…）") }
print(problems.isEmpty ? "界面文字：\(keys.count) 句都有英文 ✓" : "界面文字：\(problems.count) 个问题")
exit(problems.isEmpty ? 0 : 1)
