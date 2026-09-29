#!/bin/zsh
# アイコンを描き直す：scripts/make-icon.py → assets/icon/icon.svg → icon-1024.png・AppIcon.icns、パネルの小人（Resources/kobito-cling.png）
set -euo pipefail
cd "${0:A:h}/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
python3 scripts/make-icon.py assets/icon/icon.svg assets/icon/kobito-cling.svg
xcrun swift scripts/render-svg.swift assets/icon/icon.svg assets/icon/icon-1024.png 1024
# パネルにしがみつく小人（64pt を 3倍で）。
xcrun swift scripts/render-svg.swift assets/icon/kobito-cling.svg Resources/kobito-cling.png 192
mkdir "$work/AppIcon.iconset"
for size in 16 32 128 256 512; do
  xcrun swift scripts/render-svg.swift assets/icon/icon.svg "$work/AppIcon.iconset/icon_${size}x${size}.png" $size
  xcrun swift scripts/render-svg.swift assets/icon/icon.svg "$work/AppIcon.iconset/icon_${size}x${size}@2x.png" $((size * 2))
done
iconutil -c icns "$work/AppIcon.iconset" -o assets/icon/AppIcon.icns
echo assets/icon/AppIcon.icns
