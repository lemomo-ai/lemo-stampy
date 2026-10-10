#!/bin/zsh
# 自动测试（不动鼠标，随时能跑）：
#   1. Core 单元测试：盖章引擎、拿章流程（StampFlow）、批量盖章
#   2. 编译 App
#   3. 截图对比：每个界面和基准逐像素比
#   0. 界面文字检查：每一句都有英文，没有漏翻的中文
# 真开「预览」、会动鼠标的端到端测试在 scripts/e2e.sh，要单独跑。
set -euo pipefail
ROOT="${0:A:h:h}"

echo "▸ 0/3 界面文字：每句都有英文"
swift "$ROOT/scripts/check_l10n.swift" || { echo "✗ 界面文字检查没过"; exit 1; }

echo "▸ 1/3 Core 单元测试"
(cd "$ROOT/Core" && swift test 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests" | tail -3)
(cd "$ROOT/Core" && swift test >/dev/null 2>&1) || { echo "✗ 单元测试没过"; exit 1; }

echo "▸ 2/3 编译 App"
"$ROOT/scripts/build.sh" --no-install >/dev/null

echo "▸ 3/3 截图对比"
"$ROOT/scripts/snapshots.sh" --no-build | tail -25
