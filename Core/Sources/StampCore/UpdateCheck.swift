import Foundation

/// 「检查更新」：只在用户点了才去官网读一个很小的 version.json，不自动检查、不带任何标识，也不自己下载安装。
/// 发现新版本就告诉用户，点「去下载」打开官网，由用户自己下载。
///
/// version.json 的格式：
/// ```json
/// { "version": "1.1.0", "url": "https://…/#download",
///   "notes": { "zh": "修了……", "en": "Fixed …" } }
/// ```
public enum UpdateCheck {
    public struct Release: Decodable, Equatable, Sendable {
        public var version: String
        public var url: URL
        public var notes: [String: String]?

        public init(version: String, url: URL, notes: [String: String]? = nil) {
            self.version = version
            self.url = url
            self.notes = notes
        }

        /// 按界面语言取更新说明；没有对应语言就取另一种。
        public var localizedNotes: String? {
            let key = Localization.isEnglish ? "en" : "zh"
            let text = notes?[key] ?? notes?.values.first
            return text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }

    public enum Outcome: Equatable, Sendable {
        case upToDate(current: String)
        case available(Release)
    }

    public static func parse(_ data: Data) throws -> Release {
        try JSONDecoder().decode(Release.self, from: data)
    }

    public static func outcome(for release: Release, current: String) -> Outcome {
        isNewer(release.version, than: current) ? .available(release) : .upToDate(current: current)
    }

    /// 按数字逐段比：1.10.0 比 1.9.2 新，1.0 和 1.0.0 一样。前面带 v 也行。
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }
        return trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// 去官网读 version.json。不用缓存，超时 10 秒。
    public static func fetch(from feed: URL, current: String) async throws -> Outcome {
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return outcome(for: try parse(data), current: current)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
