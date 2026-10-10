# dmgbuild 的布局设置：直接写 .DS_Store，不开 Finder 窗口。
# scripts/release.sh 这样调用（-D 传入路径）：
#   dmgbuild -s release/dmg/settings.py -D app=<小章.app> -D background=<background.png> "小章 Stampy" Stampy.dmg
# 数字要和 make_background.swift 里的版面对得上：窗口 640×400，图标中心 (180, 222) 和 (460, 222)。
import os.path

app = defines["app"]  # noqa: F821  （dmgbuild 注入）
app_name = os.path.basename(app.rstrip("/"))

files = [app]
# 右边的「应用程序」快捷方式（指向 /Applications）。Finder 不翻译快捷方式的名字，中文系统下也显示 Applications，
# 所以背景上的提示中英文都写了。
symlinks = {"Applications": "/Applications"}

# 卷图标用 App 自己的图标
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

# 同目录的 background@2x.png 会被自动合成进去（Retina）
background = defines["background"]  # noqa: F821

format = "UDZO"
filesystem = "HFS+"

window_rect = ((200, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 112
text_size = 13
arrange_by = None
label_pos = "bottom"
icon_locations = {
    app_name: (180, 222),
    "Applications": (460, 222),
}
