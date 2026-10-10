import Foundation

/// 版本号和检查更新的地址。
enum AppVersion {
    /// 截图模式固定成一个版本号，升版本时截图基准不跟着变。
    nonisolated(unsafe) static var fixed: String?

    /// 比如 1.0.0。
    static var short: String {
        fixed ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    /// 官网上的 version.json：写在 Info.plist 的 StampyUpdateFeed（project.yml 里改）。
    /// 测试时可以用 `defaults write com.lemolab.xiaoyinzhang updateFeed <地址>` 临时换掉。
    static var updateFeed: URL? {
        let override = UserDefaults.standard.string(forKey: "updateFeed")
        let plist = Bundle.main.object(forInfoDictionaryKey: "StampyUpdateFeed") as? String
        guard let text = [override, plist].compactMap({ $0?.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        return URL(string: text)
    }
}
