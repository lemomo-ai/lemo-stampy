#!/bin/zsh
# 端到端测试（自动测试第 4 层）：真的用「预览」打开测试文件，程序自己移动鼠标、点、滚轮、打字，盖完检查副本。
#   ./scripts/e2e.sh
# ⚠️ 会动鼠标和键盘，大约 1 分钟，跑的时候别碰电脑。屏幕下方会有一条「小章正在自动测试」的提示。
# 用临时设置和临时记录，不碰你的印章、记录和文件；只关它自己打开的「预览」窗口。
# 测的是装在 ~/Applications 里的那个小章（它有你给的「辅助功能」权限）；正在运行的会先退出，测完再打开。
set -uo pipefail
ROOT="${0:A:h:h}"
APP="$HOME/Applications/小章.app"
DIR="$ROOT/小印章测试/自动测试/最近一次/端到端"
[[ -d "$APP" ]] || { echo "✗ 没找到 $APP，先运行 ./scripts/build.sh 安装"; exit 1; }

was_running=0
if pgrep -x 小章 >/dev/null; then was_running=1; pkill -x 小章; sleep 1; fi

echo "▸ 开始端到端测试：别动鼠标和键盘（约 1 分钟）"
open -W -n "$APP" --args --e2e "$DIR"
code=$?

if [[ $was_running == 1 ]]; then open "$APP"; fi

if [[ -f "$DIR/报告.md" ]]; then
  cat "$DIR/报告.md"
  grep -q "✗" "$DIR/报告.md" && exit 1 || exit 0
else
  echo "✗ 没有生成报告（$DIR/报告.md），可能中途崩了"
  exit 1
fi
