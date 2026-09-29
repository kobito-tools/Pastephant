#!/bin/zsh
# GitHubのReleasesへ添付するファイルを作る。
#   dist/Pastephant_<版>.dmg                開くと「Applications へドラッグ」の画面が出る（ふつうはこちら）
#   dist/Pastephant_<版>_universal.zip      PopNote! と同じ形式
# dmg の窓の並べ方は Finder に頼む（初回は「Finder を操作する許可」を求められることがある）。
set -euo pipefail
cd "${0:A:h}/.."
./build.sh >/dev/null
version=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' build.sh)
mkdir -p dist

# zip：Finderの「圧縮」と同じ形式（拡張属性・署名を保ったまま）で固める。
archive="dist/Pastephant_${version}_universal.zip"
rm -f "$archive"
ditto -c -k --keepParent "Pastephant.app" "$archive"
echo "$PWD/$archive"

# dmg：アプリ・Applications へのリンク・背景を置き、窓の並べ方を決めてから、読み取り専用に圧縮する。
volume="Pastephant"
image="dist/Pastephant_${version}.dmg"
work="$(mktemp -d)"
trap 'hdiutil detach "/Volumes/$volume" -quiet 2>/dev/null || true; rm -rf "$work"' EXIT
stage="$work/stage"
mkdir -p "$stage/.background"
ditto "Pastephant.app" "$stage/Pastephant.app"
ln -s /Applications "$stage/Applications"
tiffutil -cathidpicheck assets/dmg/background.png assets/dmg/background@2x.png -out "$stage/.background/background.tiff" >/dev/null
cp assets/icon/AppIcon.icns "$stage/.VolumeIcon.icns"

hdiutil detach "/Volumes/$volume" -quiet 2>/dev/null || true
# hdiutil create はときどき「Resource busy」で失敗するので、少し待って試し直す。
for attempt in 1 2 3; do
  if hdiutil create -quiet -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$work/rw.dmg"; then break; fi
  if (( attempt == 3 )); then echo "dmg を作れませんでした" >&2; exit 1; fi
  sleep 2
done
hdiutil attach -quiet -readwrite -noverify -noautoopen "$work/rw.dmg"
# ボリュームのアイコンを使う印（Xcode のコマンドラインツールの SetFile があるときだけ）。
command -v SetFile >/dev/null && SetFile -a C "/Volumes/$volume" || true

if ! osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
  tell disk "$volume"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Pastephant.app" of container window to {150, 195}
    set position of item "Applications" of container window to {450, 195}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
then
  echo "注意：Finder で窓を並べられませんでした（背景なしの dmg になります）。システム設定の「プライバシーとセキュリティ」→「オートメーション」で Finder の操作を許可してください。" >&2
fi

chmod -Rf go-w "/Volumes/$volume" 2>/dev/null || true
sync
# Finder が窓を閉じ終えるまで少し待ち、外せなければ何度か試してから強制的に外す。
for attempt in 1 2 3 4 5; do
  if hdiutil detach -quiet "/Volumes/$volume" 2>/dev/null; then break; fi
  if (( attempt == 5 )); then hdiutil detach -quiet -force "/Volumes/$volume"; else sleep 1; fi
done
rm -f "$image"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$image"
echo "$PWD/$image"
