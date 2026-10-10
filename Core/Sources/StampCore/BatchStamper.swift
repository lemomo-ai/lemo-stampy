import Foundation

/// 批量盖章：一次选好几份文件，统一盖在同一个相对位置。先算「计划」（每份存到哪、盖哪几页、哪些跳过），再一份份盖。
/// 盖章本身走 `DocumentStamper.stamp`，和单份盖章是同一套引擎；原文件永远不动。

/// 盖哪几页：PDF 可以只盖第一页、只盖最后一页或每一页都盖；照片只有一页。
public enum BatchPages: String, Codable, CaseIterable, Sendable, Identifiable {
    case first, last, all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .first: return L("第一页")
        case .last: return L("最后一页")
        case .all: return L("每一页")
        }
    }

    public func pageIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        switch self {
        case .first: return [0]
        case .last: return [count - 1]
        case .all: return Array(0..<count)
        }
    }
}

/// 页面上的相对位置：0…1，从左、从上。
public struct RelativePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    /// 九宫格快捷位：离边留一点。
    public static func anchor(column: Int, row: Int) -> RelativePoint {
        let stops = [0.18, 0.5, 0.82]
        return RelativePoint(x: stops[min(max(column, 0), 2)], y: stops[min(max(row, 0), 2)])
    }

    /// 默认右下角：最常见的盖法，压在签名旁边。
    public static let bottomRight = anchor(column: 2, row: 2)
}

public enum BatchSkipReason: Equatable, Sendable {
    /// 不是 PDF 也不是照片（比如 Word、文件夹）。
    case unsupported
    /// 加了密码，还没输。
    case needsPassword
    case unreadable(String)

    public var label: String {
        switch self {
        case .unsupported: return L("不支持这种文件")
        case .needsPassword: return L("要密码")
        case .unreadable(let message): return message
        }
    }
}

public struct BatchItem: Equatable, Sendable {
    public let input: URL
    public let output: URL
    public let kind: DocumentKind
    public let pageCount: Int
    public let placements: [StampPlacement]
}

public struct BatchSkip: Equatable, Sendable {
    public let input: URL
    public let reason: BatchSkipReason
}

public struct BatchPlan: Equatable, Sendable {
    public var items: [BatchItem]
    public var skipped: [BatchSkip]
}

public struct BatchOutcome: Equatable, Sendable {
    public let input: URL
    public let output: URL
    /// 盖好了：输出文件的 SHA-256；没盖上：nil，看 `error`。
    public let sha256: String?
    public let error: String?
    public let pages: [Int]?

    public var succeeded: Bool { sha256 != nil }
}

public enum BatchStamper {
    /// 算计划。读页数要打开文件，可能触发系统授权框，别在主线程调。
    /// - Parameters:
    ///   - position: 所有文件共用的位置。
    ///   - overrides: 单独调过位置的文件（按路径）。
    ///   - outputDirectory: nil = 存在原文件旁边。
    public static func plan(inputs: [URL], position: RelativePoint, scale: Double, pages: BatchPages,
                            overrides: [String: RelativePoint] = [:], outputDirectory: URL? = nil) -> BatchPlan {
        var plan = BatchPlan(items: [], skipped: [])
        var taken = Set<String>()
        var seen = Set<String>()
        for input in inputs {
            let key = input.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue } // 同一份拖进来两次只盖一次
            guard let kind = DocumentStamper.kind(of: input) else {
                plan.skipped.append(BatchSkip(input: input, reason: .unsupported))
                continue
            }
            let count: Int
            do {
                count = try DocumentStamper.pageCount(of: input)
            } catch StampError.encryptedPDF {
                plan.skipped.append(BatchSkip(input: input, reason: .needsPassword))
                continue
            } catch {
                plan.skipped.append(BatchSkip(input: input, reason: .unreadable((error as? LocalizedError)?.errorDescription ?? L("读不出来"))))
                continue
            }
            let point = overrides[key] ?? position
            let indices = kind == .image ? [0] : pages.pageIndices(count: count)
            let placements = indices.map { StampPlacement(pageIndex: $0, x: point.x, y: point.y, scale: scale) }
            let output = uniqueOutputURL(for: input, directory: outputDirectory, taken: taken)
            taken.insert(output.standardizedFileURL.path)
            plan.items.append(BatchItem(input: input, output: output, kind: kind, pageCount: count, placements: placements))
        }
        return plan
    }

    /// 「原名_已盖章.扩展名」：磁盘上已经有、或者这一批里别的文件已经占了，就加序号。
    public static func uniqueOutputURL(for input: URL, directory: URL?, taken: Set<String>) -> URL {
        let dir = directory ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent + L("_已盖章")
        let ext = input.pathExtension.isEmpty ? "pdf" : input.pathExtension
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) || taken.contains(candidate.standardizedFileURL.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// 一份份盖。一份失败不影响后面的。`progress(已完成份数, 总份数)` 在调用线程回调。
    public static func run(_ plan: BatchPlan, design: StampDesign, text: StampText,
                           progress: ((Int, Int) -> Void)? = nil) -> [BatchOutcome] {
        var outcomes: [BatchOutcome] = []
        for (i, item) in plan.items.enumerated() {
            let pages = item.kind == .pdf ? item.placements.map(\.pageIndex) : nil
            do {
                // 输出文件夹可能是新建的「已盖章_日期」，先建好。
                try FileManager.default.createDirectory(at: item.output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try DocumentStamper.stamp(input: item.input, output: item.output, placements: item.placements, design: design, text: text)
                let sha = (try? HistoryStore.sha256(of: item.output)) ?? ""
                outcomes.append(BatchOutcome(input: item.input, output: item.output, sha256: sha, error: nil, pages: pages))
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                outcomes.append(BatchOutcome(input: item.input, output: item.output, sha256: nil, error: message, pages: pages))
            }
            progress?(i + 1, plan.items.count)
        }
        return outcomes
    }

    /// 一批算一条记录、一个编号：记录里列出每一份。
    public static func record(for outcomes: [BatchOutcome], id: String, date: Date, design: StampDesign, text: StampText) -> StampRecord? {
        let files = outcomes.filter(\.succeeded).map {
            StampedFile(sourceName: $0.input.lastPathComponent, outputPath: $0.output.path, sha256: $0.sha256 ?? "", pages: $0.pages)
        }
        guard !files.isEmpty else { return nil }
        return StampRecord(id: id, date: date, recipient: design.statement.recipient, purpose: design.statement.purpose,
                           lines: text.allLines, files: files, design: design,
                           pages: files.count == 1 ? files[0].pages : nil)
    }
}
