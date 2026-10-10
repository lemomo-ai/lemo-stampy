#!/bin/zsh
# 生成官网素材：用 App 里真实的界面和盖章引擎画动画帧，编成循环播放的 MP4（加一张 JPG 封面），放进 website/media。
# 中文、英文各画一遍：中文的叫 flow.mp4、panel.webp，英文的叫 flow-en.mp4、panel-en.webp（英文官网用）。
# 印章图只有一套（章上的字不跟界面语言走），stamps.json 里带中英文名字。
# 动画用 MP4 不用动图 WebP：有损动图 WebP 只更新变化的局部，误差会累积，浏览器里能看到旧画面的残影；MP4 没这个问题，体积也只有一半。
#   ./scripts/make_site_media.sh
#   BUILD_DIR=$PWD/build/site ./scripts/make_site_media.sh   几件事同时编译时各用各的目录
# 只编译不安装，不会动正在用的小章；用临时设置，不碰你自己的印章和记录。
# 需要 ffmpeg（编 MP4）和 cwebp（界面截图）：brew install ffmpeg webp
# 介绍视频 media/intro.mp4 不在这里生成，另行制作。
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="${BUILD_DIR:-$ROOT/build}"
OUT="$BUILD/site-media"
SITE="$ROOT/website"

"$ROOT/scripts/build.sh" --no-install

echo "▸ 画帧（中文、英文）"
rm -rf "$OUT"
"$BUILD/小章.app/Contents/MacOS/小章" --render-site-media "$OUT/zh"
"$BUILD/小章.app/Contents/MacOS/小章" --render-site-media "$OUT/en" --english

mkdir -p "$SITE/media" "$SITE/stamps" "$SITE/ui"
rm -f "$SITE"/media/*.webp(N)

for lang in zh en; do
  suffix=""; [[ $lang == en ]] && suffix="-en"
  echo "▸ 编动画（$lang：MP4 + 封面）"
  for dir in "$OUT/$lang"/frames/*(/); do
    name="${dir:t}$suffix"
    ffmpeg -v error -y -framerate 25 -i "$dir/%04d.png" -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p \
      -movflags +faststart -an "$SITE/media/$name.mp4"
    ffmpeg -v error -y -i "$dir/0001.png" -q:v 3 "$SITE/media/$name.jpg"
    echo "  $name.mp4  $(du -h "$SITE/media/$name.mp4" | cut -f1)"
  done
  echo "▸ 界面图（$lang）"
  for png in "$OUT/$lang"/ui/*.png; do
    cwebp -quiet -q 88 -alpha_q 100 "$png" -o "$SITE/ui/${png:t:r}$suffix.webp"
  done
done

echo "▸ 印章图"
rm -f "$SITE"/stamps/*.png(N)
cp "$OUT"/zh/stamps/*.png "$SITE/stamps/"
cp "$OUT/zh/stamps.json" "$SITE/stamps/stamps.json"
echo "✓ 素材在 $SITE"
