import CryptoKit
import Foundation

public enum StampID {
    /// 去掉了 0/O、1/I/L 等容易看错的字符。
    static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    /// 界面上只为占位的示例编号（缩略图里看不清，不代表真实编号）。
    public static let sample = "A7K3Q2"

    public static func make(length: Int = 6) -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &rng)! })
    }
}

public struct StampedFile: Codable, Equatable, Sendable, Hashable {
    public var sourceName: String
    public var outputPath: String
    /// 输出文件的指纹：将来流出的文件可以按它对上是哪一次给出去的。
    public var sha256: String
    /// 这一份 PDF 盖了哪几页（从 0 数）。批量盖章时每份各记各的；单份盖章记在 `StampRecord.pages` 里。
    public var pages: [Int]?

    public init(sourceName: String, outputPath: String, sha256: String, pages: [Int]? = nil) {
        self.sourceName = sourceName
        self.outputPath = outputPath
        self.sha256 = sha256
        self.pages = pages
    }

    /// 「第 2 页」「第 1–5 页」；没有页码信息时为 nil。
    public var pagesLabel: String? {
        guard let pages, !pages.isEmpty else { return nil }
        return StampRecord.pagesLabel(pages)
    }
}

public struct StampRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var date: Date
    public var recipient: String
    public var purpose: String
    public var lines: [String]
    public var files: [StampedFile]
    /// 盖章时用的那枚印章，记录列表里画缩略图用。旧记录没有。
    public var design: StampDesign?
    /// PDF 盖了哪几页（从 0 数）。照片和旧记录没有。
    public var pages: [Int]?

    public init(id: String, date: Date, recipient: String, purpose: String, lines: [String], files: [StampedFile],
                design: StampDesign? = nil, pages: [Int]? = nil) {
        self.id = id
        self.date = date
        self.recipient = recipient
        self.purpose = purpose
        self.lines = lines
        self.files = files
        self.design = design
        self.pages = pages
    }

    /// 「第 2 页」「第 1–5 页」「第 1、3、4 页」；没有页码信息时为 nil。
    public var pagesLabel: String? {
        guard let pages, !pages.isEmpty else { return nil }
        return Self.pagesLabel(pages)
    }

    public static func pagesLabel(_ pages: [Int]) -> String {
        let sorted = pages.sorted().map { $0 + 1 }
        if sorted.count == 1 { return L("第 %ld 页", sorted[0]) }
        if sorted.last! - sorted.first! == sorted.count - 1 { return L("第 %ld–%ld 页", sorted.first!, sorted.last!) }
        if sorted.count <= 4 { return L("第 %@ 页", sorted.map(String.init).joined(separator: L("、"))) }
        return Localization.count(sorted.count, "页")
    }
}

/// 发送记录，保存在本机 `~/Library/Application Support/小印章/history.json`，不上传任何地方。
/// 文件夹沿用改名（小章）之前的「小印章」：改了就找不到以前的记录。
public final class HistoryStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("小印章", isDirectory: true).appendingPathComponent("history.json") // l10n-ignore：文件夹名 / 印章上的字，不翻译
    }

    public init(fileURL: URL = HistoryStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// 按时间先后排列。
    public func load() -> [StampRecord] {
        lock.lock(); defer { lock.unlock() }
        return unlockedLoad()
    }

    public func append(_ record: StampRecord) throws {
        lock.lock(); defer { lock.unlock() }
        var records = unlockedLoad()
        records.append(record)
        try unlockedSave(records)
    }

    public func delete(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        try unlockedSave(unlockedLoad().filter { $0.id != id })
    }

    public func find(sha256: String) -> (record: StampRecord, file: StampedFile)? {
        let needle = sha256.lowercased()
        for record in load().reversed() {
            if let file = record.files.first(where: { $0.sha256 == needle }) { return (record, file) }
        }
        return nil
    }

    public func find(fileAt url: URL) -> (record: StampRecord, file: StampedFile)? {
        guard let hash = try? Self.sha256(of: url) else { return nil }
        return find(sha256: hash)
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func unlockedLoad() -> [StampRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([StampRecord].self, from: data)) ?? []
    }

    private func unlockedSave(_ records: [StampRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(records).write(to: fileURL, options: .atomic)
    }
}
