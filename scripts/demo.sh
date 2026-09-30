#!/bin/zsh
# README のデモ（scripts/demo/demo.html の絵）を docs/images/demo.gif に書き出す。Google Chrome、Node.js 22 以降、ffmpeg が必要。
# 使い方: scripts/demo.sh [コマ/秒（既定 15）]
set -euo pipefail
cd "${0:A:h}/.."
fps="${1:-15}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
node scripts/demo/capture.mjs "$work" "$fps"
mkdir -p docs/images
ffmpeg -v error -y -framerate "$fps" -i "$work/frame%04d.png" \
  -vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  docs/images/demo.gif
ls -lh docs/images/demo.gif
