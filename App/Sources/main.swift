import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    if Snapshots.runIfRequested() { exit(0) }
    if SiteMedia.runIfRequested() { exit(0) }
    if PromoFilm.runIfRequested() { exit(0) }
    if PosterArt.runIfRequested() { exit(0) }
    E2E.configureIfRequested()
    _ = LanguageSettings.shared // 先定好界面语言，再建菜单栏、窗口
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
