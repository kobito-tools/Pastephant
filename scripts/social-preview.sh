#!/bin/zsh
# シリーズの紹介画像（1280×640。Tomelet の assets/icon/kobito-series/social_preview.py と同じ作り）を
# assets/icon/Pastephant-1280x640.png に書き出す。Google Chrome と Tomelet（フォント）が必要。
# 使い方: scripts/social-preview.sh [Tomeletのフォルダ（既定 ../DailyLog）]
set -euo pipefail
cd "${0:A:h}/.."
tomelet="${1:-../DailyLog}"
font="${tomelet:A}/assets/fonts/NotoSansJP.ttf"
[[ -f "$font" ]] || { echo "フォントが見つかりません: $font" >&2; exit 1; }
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/og.html" <<HTML
<html><head><style>
@font-face{font-family:Noto;src:url(file://$font)}
html,body{margin:0;width:1280px;height:640px;overflow:hidden}
body{background:linear-gradient(180deg,#8FA2B3,#728698);font-family:Noto,sans-serif;color:#F7F4EC;position:relative}
img{position:absolute;left:80px;top:100px;width:440px;height:440px}
.text{position:absolute;left:560px;right:64px;top:0;bottom:0;display:flex;flex-direction:column;justify-content:center}
h1{margin:0;font-weight:700;font-size:84px;letter-spacing:-.01em;line-height:1}
.ja{margin-top:30px;font-size:30px;white-space:nowrap;font-weight:500;line-height:1.5}
.en{margin-top:10px;font-size:24px;opacity:.78}
.org{position:absolute;right:64px;bottom:48px;font-size:22px;letter-spacing:.06em;opacity:.7}
</style></head><body><img src="file://${PWD}/assets/icon/icon.svg"><div class="text"><h1>Pastephant</h1><div class="ja">コピーした物を忘れない、<br>クリップボード履歴</div><div class="en">A clipboard history that never forgets.</div></div><div class="org">kobito-tools</div></body></html>
HTML
"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=1280,640 \
  --screenshot="$work/og.png" "file://$work/og.html" >/dev/null 2>&1
cp "$work/og.png" assets/icon/Pastephant-1280x640.png
echo assets/icon/Pastephant-1280x640.png
