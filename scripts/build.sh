#!/bin/zsh
# 编译小章并安装到 ~/Applications，然后启动。
#   ./scripts/build.sh            编译 + 安装 + 启动
#   ./scripts/build.sh --no-install  只编译，产物在 build/小章.app
# 设了 BUILD_DIR 就编到那里（几件事同时编译时各用各的目录，互不打架）。
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="小章"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
INSTALL_DIR="$HOME/Applications"

cd "$ROOT/App"

if [[ ! -f Resources/Assets.xcassets/AppIcon.appiconset/Contents.json ]]; then
  echo "▸ 生成图标"
  swift "$ROOT/scripts/make_icon.swift" Resources/Assets.xcassets/AppIcon.appiconset
fi

# 生成工程和编译时加锁：几件事同时编译时，xcodegen 不会在别人编译到一半时重写工程文件。
zmodload zsh/system
mkdir -p "$ROOT/build"; touch "$ROOT/build/.compile.lock"
zsystem flock -f LOCKFD -t 1800 "$ROOT/build/.compile.lock"

echo "▸ 生成 Xcode 工程"
xcodegen generate --quiet

# 有 scripts/release.local.sh 就用里面的 Developer ID 签名：同一把证书签出来的 App，「辅助功能」授权重编后还在。
# 没有就用临时签名，每次重编后可能要重新打开一次「辅助功能」。
SIGN=()
[[ -f "$ROOT/scripts/release.local.sh" ]] && source "$ROOT/scripts/release.local.sh"
[[ -n "${SIGNING_IDENTITY:-}" ]] && SIGN=(CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" DEVELOPMENT_TEAM="${TEAM_ID:-}")

echo "▸ 编译（Release）"
xcodebuild -project XiaoYinZhang.xcodeproj -scheme XiaoYinZhang -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" -destination 'platform=macOS' "${SIGN[@]}" build -quiet

PRODUCT="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
rm -rf "$BUILD_DIR/$APP_NAME.app"
cp -R "$PRODUCT" "$BUILD_DIR/$APP_NAME.app"
echo "✓ 编译完成：$BUILD_DIR/$APP_NAME.app"
zsystem flock -u $LOCKFD

if [[ "${1:-}" == "--no-install" ]]; then exit 0; fi

echo "▸ 安装到 $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
pkill -x "$APP_NAME" 2>/dev/null || true
# 改名前叫「小印章」：退出并删掉旧的，免得装着两个（印章、记录、设置都按同一个 bundle id 存，不受影响）。
pkill -x "小印章" 2>/dev/null || true
rm -rf "$INSTALL_DIR/小印章.app"
sleep 0.5
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$BUILD_DIR/$APP_NAME.app" "$INSTALL_DIR/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$APP_NAME.app"
open "$INSTALL_DIR/$APP_NAME.app"
echo "✓ 已启动：看屏幕右上角菜单栏的小章图标"
