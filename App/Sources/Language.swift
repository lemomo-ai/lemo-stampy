import AppKit
import StampCore
import SwiftUI

/// 界面语言的设置：跟随系统（默认），或者固定中文 / English。存在 UserDefaults，改了马上生效。
@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    /// 语言变了：AppDelegate 收到后重建打开着的窗口、菜单和面板。
    static let didChange = Notification.Name("LanguageSettings.didChange")
    private static let key = "languagePreference"

    @Published var preference: LanguagePreference {
        didSet {
            guard preference != oldValue else { return }
            AppEnvironment.defaults.set(preference.rawValue, forKey: Self.key)
            let before = Localization.language
            Localization.language = preference.resolved
            if Localization.language != before { NotificationCenter.default.post(name: Self.didChange, object: nil) }
        }
    }

    private init() {
        preference = AppEnvironment.defaults.string(forKey: Self.key).flatMap(LanguagePreference.init(rawValue:)) ?? .system
        Localization.language = preference.resolved
    }

    /// 选项上的字：语言名总是用它自己的文字写，看不懂当前语言的人也认得出。
    static var options: [(value: LanguagePreference, label: String)] {
        [(.system, L("跟随系统")), (.zh, "中文"), (.en, "English")] // l10n-ignore：语言名用它自己的文字
    }
}

/// 面板里的「语言」一行：图标 + 文字 + 三段选择。
struct LanguageRow: View {
    @ObservedObject var settings = LanguageSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.ink2)
                .frame(width: 16, height: 16)
            Text(L("语言")).font(Theme.body(13)).foregroundStyle(Theme.ink).fixedSize()
            Spacer(minLength: 4)
            MochiSegmented(options: LanguageSettings.options, selection: $settings.preference,
                           style: .soft, height: 22, fontSize: 11, trackPadding: 2, fill: false, itemPadding: 7)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }
}
