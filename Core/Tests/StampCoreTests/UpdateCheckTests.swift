import Foundation
@testable import StampCore
import XCTest

/// 「检查更新」：版本号怎么比、version.json 怎么读。不联网。
final class UpdateCheckTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateCheck.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(UpdateCheck.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(UpdateCheck.isNewer("v2.0", than: "1.9.9"))
        XCTAssertFalse(UpdateCheck.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.9.9", than: "1.0.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.0.0", than: "1.0.0"))
    }

    func testParseAndOutcome() throws {
        let json = #"{"version":"1.1.0","url":"https://example.com/#download","notes":{"zh":"修了几个小问题","en":"Small fixes"}}"#
        let release = try UpdateCheck.parse(Data(json.utf8))
        XCTAssertEqual(release.version, "1.1.0")
        XCTAssertEqual(UpdateCheck.outcome(for: release, current: "1.0.0"), .available(release))
        XCTAssertEqual(UpdateCheck.outcome(for: release, current: "1.1.0"), .upToDate(current: "1.1.0"))
        XCTAssertEqual(release.localizedNotes, "修了几个小问题")
    }

    func testNotesAreOptional() throws {
        let release = try UpdateCheck.parse(Data(#"{"version":"1.0.0","url":"https://example.com"}"#.utf8))
        XCTAssertNil(release.localizedNotes)
    }

    /// 真走一遍读取：用本地文件代替官网。
    func testFetchReadsFeed() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("version-\(UUID().uuidString).json")
        try Data(#"{"version":"1.2.0","url":"https://example.com/#download"}"#.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let newer = try await UpdateCheck.fetch(from: url, current: "1.0.0")
        guard case .available(let release) = newer else { return XCTFail("应该有新版本") }
        XCTAssertEqual(release.version, "1.2.0")
        let same = try await UpdateCheck.fetch(from: url, current: "1.2.0")
        XCTAssertEqual(same, .upToDate(current: "1.2.0"))
    }

    func testBrokenFeedThrows() {
        XCTAssertThrowsError(try UpdateCheck.parse(Data("<html>404</html>".utf8)))
    }
}
