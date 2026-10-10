#!/bin/zsh
# 出发布包：一条命令从源码做到公证过的 build/release/Stampy.dmg。
#   ./scripts/release.sh                  完整发布：编译 → 签名 → 公证 App → 做 DMG → 签 DMG → 公证 DMG → 验证
#   ./scripts/release.sh --skip-notarize  本地试：不提交公证（出来的 DMG 别人打开会被 Gatekeeper 拦，别发出去）
#   ./scripts/release.sh --allow-dirty    工作区有没提交的改动也照样出包（默认会停下）
#
# 只编到 build/release/，不安装、不启动、不碰 ~/Applications/小章.app，不开 Finder 窗口。
# 签名和公证用谁的身份，写在 scripts/release.local.sh 里（不进仓库），照 scripts/release.local.example.sh 抄一份改：
#   TEAM_ID、SIGNING_IDENTITY（Developer ID Application 证书全名）、NOTARY_PROFILE（钥匙串里 notarytool 凭据的名字）、APPLE_ID。
# 第一次配公证凭据（在你自己的终端里跑，密码只进钥匙串）：
#   xcrun notarytool store-credentials <NOTARY_PROFILE> --apple-id <APPLE_ID> --team-id <TEAM_ID>
set -euo pipefail
# 注意：开了 pipefail，管道里别用 grep -q（它一找到就退出，前面的命令被 SIGPIPE 打断，整条管道会算失败）。
zmodload zsh/system

ROOT="${0:A:h:h}"
APP_NAME="小章"
DMG_NAME="Stampy.dmg"
VOLUME_NAME="小章 Stampy"
[[ -f "$ROOT/scripts/release.local.sh" ]] && source "$ROOT/scripts/release.local.sh"
TEAM_ID="${TEAM_ID:-}"
IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-<你的 Apple ID>}"
OUT="$ROOT/build/release"
APP="$OUT/$APP_NAME.app"
DMG="$OUT/$DMG_NAME"
DMGBUILD_VERSION="1.6.7"

SKIP_NOTARIZE=0
ALLOW_DIRTY=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) print -u2 "不认识的参数：$arg（用 --help 看用法）"; exit 2 ;;
  esac
done

# ── 输出和出错处理 ─────────────────────────────────────────────
STEP="准备"
HINT=""
step() { STEP="$1"; HINT="${2:-}"; print -P "\n%B▶ $1%b"; }
ok()   { print "  ✓ $*"; }
warn() { print -u2 "  ⚠︎ $*"; }
die() {
  print -u2 "\n✗ 失败在「$STEP」：$1"
  [[ -n "${2:-$HINT}" ]] && print -u2 "  怎么办：${2:-$HINT}"
  exit 1
}
# 没被 die 接住的命令出错时（set -e 退出前），也说清楚是哪一步
TRAPZERR() {
  print -u2 "\n✗ 失败在「$STEP」：上面那条命令出错了。"
  [[ -n "$HINT" ]] && print -u2 "  怎么办：$HINT"
}
MOUNT=""
cleanup() { [[ -n "$MOUNT" && -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true; }
trap cleanup EXIT

# 提交公证并等结果；通过就打印 submission id，不通过把 Apple 的日志拉下来再停。
notarize() {
  local file="$1" label="$2" json id st
  # stdout 只有一段 JSON；stderr 的进度和报错单独存，免得混进 JSON 里
  json="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 1h \
            --output-format json 2>"$OUT/notary-$label.stderr")" || true
  field() {  # 从输出里找第一段 JSON，取一个字段
    print -r -- "$json" | /usr/bin/python3 -c 'import json,sys
t=sys.stdin.read(); i=t.find("{")
try: print(json.JSONDecoder().raw_decode(t[i:])[0].get(sys.argv[1],"") if i >= 0 else "")
except Exception: print("")' "$1" 2>/dev/null
  }
  id="$(field id)"
  st="$(field status)"
  if [[ "$st" != "Accepted" ]]; then
    print -u2 -r -- "$json"
    cat "$OUT/notary-$label.stderr" >&2 2>/dev/null || true
    if [[ -n "$id" ]]; then
      xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$OUT/notary-$label.log.json" >/dev/null 2>&1 || true
      die "Apple 没通过公证（状态：${st:-未知}，submission id：$id）。" \
          "看 $OUT/notary-$label.log.json 里的 issues，或运行 xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE。常见原因：没开 hardened runtime、签名没带时间戳、带了 get-task-allow。改好后重跑本脚本。"
    fi
    die "提交公证没成功（网络或凭据问题）。" "确认能上网，并运行 xcrun notarytool history --keychain-profile $NOTARY_PROFILE 看凭据是否可用。"
  fi
  print -r -- "$id" > "$OUT/notary-$label.id"
  ok "公证通过（$label）：submission id $id"
}

# ── 1. 检查工作区 ───────────────────────────────────────────────
step "1/9 检查工作区" "按提示补齐工具或凭据后重跑。"
for tool in xcodegen xcodebuild hdiutil codesign lipo /usr/bin/python3 swift; do
  command -v "$tool" >/dev/null || die "找不到 $tool。" "xcodegen 用 brew install xcodegen 装；其余装 Xcode 和命令行工具。"
done
[[ -n "$TEAM_ID" && -n "$IDENTITY" ]] || die "没设签名身份 TEAM_ID / SIGNING_IDENTITY。" "照 scripts/release.local.example.sh 抄一份 scripts/release.local.sh，填上你自己的 Developer ID。"
security find-identity -v -p codesigning | grep -F "$IDENTITY" >/dev/null \
  || die "钥匙串里没有签名证书「$IDENTITY」。" "在「钥匙串访问」里确认 Developer ID Application 证书和私钥都在。"
ok "签名证书：$IDENTITY"

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *\([^ ]*\).*/\1/p' "$ROOT/App/project.yml" | head -1)"
BUILD_NUMBER="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *\([^ ]*\).*/\1/p' "$ROOT/App/project.yml" | head -1)"
[[ -n "$VERSION" && -n "$BUILD_NUMBER" ]] || die "在 App/project.yml 里读不到 MARKETING_VERSION / CURRENT_PROJECT_VERSION。"
ok "版本：$VERSION（$BUILD_NUMBER）"
if [[ -f "$ROOT/website/version.json" ]]; then
  SITE_VERSION="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "$ROOT/website/version.json" 2>/dev/null || true)"
  [[ "$SITE_VERSION" == "$VERSION" ]] || warn "website/version.json 写的是「$SITE_VERSION」，和 App 的 $VERSION 不一样：发布前记得对齐。"
fi

if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  DIRTY="$(git -C "$ROOT" status --porcelain)"
  COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || print '（还没有提交）')"
  if [[ -n "$DIRTY" ]]; then
    print -r -- "$DIRTY" | head -20 | sed 's/^/    /'
    if (( ALLOW_DIRTY || SKIP_NOTARIZE )); then
      warn "工作区有没提交的改动（上面），这次照样出包。"
    else
      die "工作区有没提交的改动（上面）。发布包应该和某次提交一一对应。" "先提交，或加 --allow-dirty 照样出包。"
    fi
  fi
  ok "源码：提交 $COMMIT"
fi

if (( SKIP_NOTARIZE )); then
  warn "--skip-notarize：这次不提交公证。"
else
  [[ -n "$NOTARY_PROFILE" ]] || die "没设公证凭据的名字 NOTARY_PROFILE。" "写进 scripts/release.local.sh（照 release.local.example.sh），或只想本地试就加 --skip-notarize。"
  # 可以写好几个候选（空格隔开），用第一个能用的。
  if [[ "$NOTARY_PROFILE" == *" "* ]]; then
    candidates=(${=NOTARY_PROFILE})
    NOTARY_PROFILE="${candidates[1]}"
    for p in $candidates; do
      xcrun notarytool history --keychain-profile "$p" >/dev/null 2>&1 && { NOTARY_PROFILE="$p"; break; }
    done
  fi
  command -v xcrun >/dev/null && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "钥匙串里的公证凭据「$NOTARY_PROFILE」用不了。" \
           "在你自己的终端里运行：xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id $APPLE_ID --team-id $TEAM_ID（按提示粘贴 App 专用密码，在 https://account.apple.com 生成），再重跑。只想本地试就加 --skip-notarize。"
  ok "公证凭据：$NOTARY_PROFILE"
fi
mkdir -p "$OUT"
rm -f "$OUT"/notary-*(N)

# ── 2. 编译通用二进制 ───────────────────────────────────────────
step "2/9 编译（arm64 + x86_64，Developer ID + hardened runtime + 时间戳）" \
     "看 $OUT/xcodebuild.log 末尾的 error。签名时要联网取时间戳，断网会在 CodeSign 这步失败。"
# 和 scripts/build.sh 用同一把锁：别的任务同时编译时，xcodegen 不会在别人编到一半时重写工程文件。
mkdir -p "$ROOT/build"; touch "$ROOT/build/.compile.lock"
zsystem flock -f LOCKFD -t 1800 "$ROOT/build/.compile.lock"
(cd "$ROOT/App" && xcodegen generate --quiet)
# 命令行覆盖只在这里：通用二进制、签名带安全时间戳。hardened runtime 和不注入 get-task-allow 在 project.yml 里已经开了，这里再写一遍兜底。
if ! (cd "$ROOT/App" && xcodebuild -project XiaoYinZhang.xcodeproj -scheme XiaoYinZhang -configuration Release \
        -derivedDataPath "$OUT/DerivedData" -destination 'generic/platform=macOS' \
        ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
        ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
        DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global COPY_PHASE_STRIP=YES \
        clean build -quiet > "$OUT/xcodebuild.log" 2>&1); then
  zsystem flock -u $LOCKFD
  grep -E "error:|failed" "$OUT/xcodebuild.log" | head -20 >&2 || tail -20 "$OUT/xcodebuild.log" >&2
  die "xcodebuild 编译失败。"
fi
zsystem flock -u $LOCKFD
rm -rf "$APP"
/usr/bin/ditto "$OUT/DerivedData/Build/Products/Release/$APP_NAME.app" "$APP"
ok "$APP"

# ── 3. 验证签名和架构 ───────────────────────────────────────────
step "3/9 验证签名和架构" "多半是 project.yml 的签名设置被改了：确认 ENABLE_HARDENED_RUNTIME: YES、CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO。"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
SIGINFO="$(codesign -d --verbose=4 "$APP" 2>&1)"
print -r -- "$SIGINFO" | grep "^Authority=Developer ID Application: .*($TEAM_ID)" >/dev/null || die "签名的不是 Developer ID Application（$TEAM_ID）。"
print -r -- "$SIGINFO" | grep -E '^CodeDirectory .*flags=0x[0-9a-f]*\(.*runtime' >/dev/null || die "签名里没有 hardened runtime 标志。"
# 发出去的 App 里不能有本机路径（会带出用户名）：调试符号在签名前已经去掉，这里再查一遍。
if LC_ALL=C grep -a -o -E "/[U]sers/[^[:cntrl:]]{0,60}" -r "$APP" | head -3 | sed 's/^/    /' | grep . >&2; then
  die "App 里还有本机路径（上面）。" "确认 xcodebuild 带了 DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES。"
fi
print -r -- "$SIGINFO" | grep '^Timestamp=' >/dev/null || die "签名没带安全时间戳（公证会拒）。" "确认能上网（时间戳要连 Apple 服务器），然后重跑。"
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
if [[ "$ENTS" == *get-task-allow* ]]; then die "签名里带了 com.apple.security.get-task-allow（公证会拒）。"; fi
ok "Developer ID（$TEAM_ID）· hardened runtime · $(print -r -- "$SIGINFO" | grep '^Timestamp=' | head -1)"
ok "entitlements：$( [[ "$ENTS" == *"<key>"* ]] && print '有（见 codesign -d --entitlements -）' || print '无')"

ARCHES="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
[[ " $ARCHES " == *" arm64 "* && " $ARCHES " == *" x86_64 "* ]] || die "主程序不是通用二进制（只有：$ARCHES）。"
# 包里其他 Mach-O 也要两个架构都有（StampCore 是静态链接进主程序的，这里兜底以后加进来的框架）
find "$APP" -type f -perm -u+x ! -path "*/MacOS/$APP_NAME" | while read -r f; do
  if file "$f" | grep 'Mach-O' >/dev/null; then
    a="$(lipo -archs "$f")"
    [[ " $a " == *" arm64 "* && " $a " == *" x86_64 "* ]] || die "$f 不是通用二进制（只有：$a）。"
  fi
done
ok "架构：$ARCHES"

PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]] || die "Info.plist 里的版本号不是 $VERSION。"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")" == "$BUILD_NUMBER" ]] || die "Info.plist 里的 build 号不是 $BUILD_NUMBER。"
ok "Info.plist：$VERSION（$BUILD_NUMBER）"

# ── 4. 公证 App 并钉上票据 ──────────────────────────────────────
if (( SKIP_NOTARIZE )); then
  step "4/9 公证 App（跳过）"
else
  step "4/9 公证 App 并钉上票据（等 Apple 出结果，一般 1～5 分钟）"
  rm -f "$OUT/app-notarize.zip"
  /usr/bin/ditto -c -k --keepParent "$APP" "$OUT/app-notarize.zip"
  notarize "$OUT/app-notarize.zip" app
  rm -f "$OUT/app-notarize.zip"
  HINT="App 已经公证过，钉票据要联网从 Apple 取：稍等一会儿再重跑。"
  xcrun stapler staple -q "$APP"
  xcrun stapler validate -q "$APP"
  ok "App 已钉上公证票据（断网第一次打开也不会被拦）"
fi

# ── 5. 做 DMG ───────────────────────────────────────────────────
step "5/9 做 DMG（dmgbuild 直接写布局，不开 Finder）" \
     "dmgbuild 装在 $OUT/.venv-dmgbuild：第一次要联网装；装坏了就删掉这个目录重跑。"
swift "$ROOT/release/dmg/make_background.swift" "$OUT/dmg-background" >/dev/null
VENV="$OUT/.venv-dmgbuild"
if ! "$VENV/bin/python" -c "import dmgbuild, sys; sys.exit(dmgbuild.__version__ != '$DMGBUILD_VERSION')" 2>/dev/null; then
  # dmgbuild 要 Python 3.10 以上；系统自带的 /usr/bin/python3 是 3.9，所以用 PATH 里的（比如 Homebrew 的）
  PY="$(command -v python3 || true)"
  [[ -n "$PY" ]] && "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
    || die "dmgbuild 要 Python 3.10 以上，PATH 里的 python3 不够新。" "brew install python 后重跑。"
  rm -rf "$VENV"
  "$PY" -m venv "$VENV"
  "$VENV/bin/pip" install -q --disable-pip-version-check "dmgbuild==$DMGBUILD_VERSION"
fi
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s "$ROOT/release/dmg/settings.py" \
  -D app="$APP" -D background="$OUT/dmg-background/background.png" \
  "$VOLUME_NAME" "$DMG" > "$OUT/dmgbuild.log" 2>&1 || { tail -20 "$OUT/dmgbuild.log" >&2; die "dmgbuild 失败（日志在 $OUT/dmgbuild.log）。"; }
ok "$DMG（卷名「$VOLUME_NAME」）"

# ── 6. 签 DMG ───────────────────────────────────────────────────
step "6/9 签 DMG" "签名要联网取时间戳：确认能上网后重跑。"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict --verbose=2 "$DMG" 2>&1 | sed 's/^/    /'
codesign -d --verbose=4 "$DMG" 2>&1 | grep '^Timestamp=' >/dev/null || die "DMG 签名没带时间戳。"
ok "DMG 已用 Developer ID 签名（带时间戳）"

# ── 7. 公证 DMG 并钉上票据 ──────────────────────────────────────
if (( SKIP_NOTARIZE )); then
  step "7/9 公证 DMG（跳过）"
else
  step "7/9 公证 DMG 并钉上票据（再等 1～5 分钟）"
  notarize "$DMG" dmg
  HINT="DMG 已经公证过，钉票据要联网从 Apple 取：稍等一会儿再重跑。"
  xcrun stapler staple -q "$DMG"
  xcrun stapler validate -q "$DMG"
  ok "DMG 已钉上公证票据"
fi

# ── 8. 最后验证 ─────────────────────────────────────────────────
step "8/9 验证 DMG" "Gatekeeper 不放行就别发出去：看上面 spctl 的 source=，多半是没公证或没钉票据。"
gatekeeper() {  # $1 = 说明，其余 = spctl 参数
  local label="$1"; shift
  local out; out="$(spctl -a -vvv "$@" 2>&1 || true)"
  print -r -- "$out" | sed 's/^/    /'
  if print -r -- "$out" | grep ': accepted' >/dev/null; then ok "Gatekeeper 放行（$label）"
  elif (( SKIP_NOTARIZE )); then warn "Gatekeeper 不放行（$label）：没公证，这是预期的。"
  else die "Gatekeeper 不放行（$label）。"; fi
}
gatekeeper "DMG，-t install" -t install "$DMG"
gatekeeper "DMG，打开" -t open --context context:primary-signature "$DMG"
(( SKIP_NOTARIZE )) || { xcrun stapler validate "$DMG" | sed 's/^/    /'; }

MOUNT="$(mktemp -d "$OUT/.mount.XXXXXX")"
hdiutil attach "$DMG" -nobrowse -noautoopen -readonly -mountpoint "$MOUNT" -quiet
[[ -d "$MOUNT/$APP_NAME.app" ]] || die "DMG 里没有 $APP_NAME.app。"
[[ "$(readlink "$MOUNT/Applications")" == "/Applications" ]] || die "DMG 里没有指向 /Applications 的「应用程序」快捷方式。"
[[ -f "$MOUNT/.DS_Store" && -f "$MOUNT/.background.tiff" ]] || die "DMG 里缺 .DS_Store 或背景图（窗口布局会乱）。"
codesign --verify --deep --strict "$MOUNT/$APP_NAME.app" || die "DMG 里的 App 签名不完整。"
[[ "$(lipo -archs "$MOUNT/$APP_NAME.app/Contents/MacOS/$APP_NAME")" == "$ARCHES" ]] || die "DMG 里的 App 和编出来的不一样。"
if (( ! SKIP_NOTARIZE )); then
  xcrun stapler validate -q "$MOUNT/$APP_NAME.app" || die "DMG 里的 App 没钉公证票据。"
  gatekeeper "DMG 里的 App" -t exec "$MOUNT/$APP_NAME.app"
fi
ok "DMG 内容：$APP_NAME.app、Applications → /Applications、背景图、窗口布局"
hdiutil detach "$MOUNT" -quiet
rmdir "$MOUNT" 2>/dev/null || true
MOUNT=""

# ── 9. 汇总 ─────────────────────────────────────────────────────
step "9/9 完成"
BYTES="$(stat -f %z "$DMG")"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
print -r -- "$SHA  $DMG_NAME" > "$OUT/$DMG_NAME.sha256"
print ""
print "  版本    $VERSION（$BUILD_NUMBER）· $ARCHES"
print "  文件    $DMG"
print "  卷名    $VOLUME_NAME"
print "  大小    $BYTES 字节（$(/usr/bin/python3 -c "print(f'{$BYTES/1048576:.2f}')") MB）"
print "  sha256  $SHA"
if (( SKIP_NOTARIZE )); then
  print "\n  ⚠︎ 没有公证：只能本机试，别发出去。去掉 --skip-notarize 再跑一遍出正式包。"
else
  print "  公证    App $(cat "$OUT/notary-app.id") · DMG $(cat "$OUT/notary-dmg.id")"
  print "\n  ✓ 已签名、公证、钉票据，可以作为 Release 附件上传（文件名保持 $DMG_NAME）。"
fi
