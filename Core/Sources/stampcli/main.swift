import Foundation
import StampCore

let usage = """
用法: stampcli [选项] 输入文件 [输出文件]
在 PDF 某一页（或照片）的指定位置盖一枚小章，另存为副本，原文件不动。

位置
  --page N           第几页（从 1 开始，默认 1）
  --at X,Y           相对位置，0~1，从左、从上量起（默认 0.75,0.85，右下角）
  --scale 1.0        大小倍率

印章
  --to 机构  --for 用途  --to-en / --for-en  英文措辞用的机构 / 用途
  --lang zh|en|both  --text "自定义\\n两行"   --no-date   --no-id
  --color red|blue|black   --size 11（正文字号，pt）  --rotate 0   --border double|single|none

其他
  --no-history       不写发送记录
  --verify 文件      查这个文件是不是用小章盖过章的副本
"""

var statement = Statement()
var design = StampDesign(name: "命令行", statement: statement)
var placement = StampPlacement(x: 0.75, y: 0.85)
var positional: [String] = []
var recordHistory = true

var args = Array(CommandLine.arguments.dropFirst())
func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}
func value(_ flag: String) -> String {
    guard !args.isEmpty else { fail("\(flag) 缺少参数") }
    return args.removeFirst()
}
func number(_ flag: String) -> Double {
    let raw = value(flag)
    guard let n = Double(raw) else { fail("\(flag) 需要数字，收到 \(raw)") }
    return n
}

if args.isEmpty { print(usage); exit(0) }

while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "-h", "--help": print(usage); exit(0)
    case "--page": placement.pageIndex = Int(number(arg)) - 1
    case "--at":
        let parts = value(arg).split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { fail("--at 需要 X,Y，例如 0.7,0.2") }
        placement.x = parts[0]
        placement.y = parts[1]
    case "--scale": placement.scale = number(arg)
    case "--to": statement.recipient = value(arg)
    case "--for": statement.purpose = value(arg)
    case "--to-en": statement.recipientEN = value(arg)
    case "--for-en": statement.purposeEN = value(arg)
    case "--lang":
        switch value(arg) {
        case "en": statement.phrasing = .english
        case "both": statement.phrasing = .bilingual
        default: statement.phrasing = .chinese
        }
    case "--text":
        statement.useCustomText = true
        statement.customText = value(arg).replacingOccurrences(of: "\\n", with: "\n")
    case "--no-date": statement.includeDate = false
    case "--no-id": statement.includeID = false
    case "--color": design.color = StampColor(rawValue: value(arg)) ?? .red
    case "--size": design.fontSize = number(arg)
    case "--rotate": design.rotation = number(arg)
    case "--border": design.border = StampBorder(rawValue: value(arg)) ?? .double
    case "--no-history": recordHistory = false
    case "--verify":
        let url = URL(fileURLWithPath: value(arg))
        if let hit = HistoryStore().find(fileAt: url) {
            print("✅ 匹配：No.\(hit.record.id) · \(Statement.dateString(hit.record.date)) · \(hit.record.lines.joined(separator: " / "))")
            print("   原文件：\(hit.file.sourceName)")
            exit(0)
        }
        print("未找到记录：这个文件不是本机小章生成的副本，或之后被修改过。")
        exit(1)
    default:
        if arg.hasPrefix("--") { fail("未知选项 \(arg)") }
        positional.append(arg)
    }
}

guard let inputPath = positional.first else { fail("缺少输入文件") }
let input = URL(fileURLWithPath: inputPath)
let output = positional.count > 1 ? URL(fileURLWithPath: positional[1]) : DocumentStamper.suggestedOutputURL(for: input)
design.statement = statement

let stampID = StampID.make()
let date = Date()
let text = statement.stampText(date: date, stampID: stampID)
do {
    try DocumentStamper.stamp(input: input, output: output, placement: placement, design: design, text: text)
} catch {
    fail("✗ \(error.localizedDescription)")
}
if recordHistory {
    let file = StampedFile(sourceName: input.lastPathComponent, outputPath: output.path,
                           sha256: (try? HistoryStore.sha256(of: output)) ?? "")
    try? HistoryStore().append(StampRecord(id: stampID, date: date, recipient: statement.recipient,
                                           purpose: statement.purpose, lines: text.allLines, files: [file]))
}
print("✓ \(output.path)")
print("  \(text.allLines.joined(separator: " / "))")
