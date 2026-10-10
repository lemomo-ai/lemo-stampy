#!/bin/zsh
# 截图对比（自动测试第 3 层）：把各个界面画成 PNG，和小印章测试/回归基准/里的基准逐像素比。
#   ./scripts/snapshots.sh            比对；差异图统一放在小印章测试/自动测试/最近一次/截图对比/差异图，退出码 1
#   ./scripts/snapshots.sh --update   界面是故意改的：看过差异图后，用新截图替换基准
#   加 --no-build 跳过编译（刚编译过时用）
# 只编译不安装，不动正在用的小章，不碰你的设置。
set -euo pipefail
ROOT="${0:A:h:h}"
NOW="$ROOT/小印章测试/自动测试/最近一次/截图对比/当前截图"
DIFF="$ROOT/小印章测试/自动测试/最近一次/截图对比/差异图"
BASE="$ROOT/小印章测试/回归基准"

[[ " $* " == *" --no-build "* ]] || "$ROOT/scripts/build.sh" --no-install >/dev/null
rm -rf "$NOW"
"${BUILD_DIR:-$ROOT/build}/小章.app/Contents/MacOS/小章" --render-snapshots "$NOW"

if [[ " $* " == *" --update "* ]]; then
  mkdir -p "$BASE"
  rm -f "$BASE"/*.png(N)
  cp "$NOW"/*.png "$BASE/"
  echo "✓ 基准已更新：$(ls "$BASE" | wc -l | tr -d ' ') 张"
  exit 0
fi
# 还没有基准（比如刚从 GitHub 拿到源码）：不算失败，提示先生成一份。
if [[ -z "$(print -l "$BASE"/*.png(N))" ]]; then
  echo "• 还没有基准图，这次只画了截图（在 $NOW）。确认界面没问题后运行 ./scripts/snapshots.sh --update 存成基准。"
  exit 0
fi
# 有几张要等后台读完缩略图才完整，电脑很忙时偶尔没等到：不一致就重画一次再比，两次都不一致才算变了。
if ! swift "$ROOT/scripts/compare_images.swift" "$BASE" "$NOW" "$DIFF" >/dev/null; then
  rm -rf "$NOW"
  "${BUILD_DIR:-$ROOT/build}/小章.app/Contents/MacOS/小章" --render-snapshots "$NOW"
fi
swift "$ROOT/scripts/compare_images.swift" "$BASE" "$NOW" "$DIFF"
