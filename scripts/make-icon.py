# Pastephant のアイコン（assets/icon/icon.svg）を、kobito-tools シリーズの小人で描く。
# 小人の描き方は Tomelet の assets/icon/kobito-series/kobito_icons.py と同じ（元の座標系 viewBox 0 0 49 44 を translate + scale で置く）。
# 使い方: scripts/make-icon.sh から呼ぶ（SVG → PNG・icns への変換もそちらで行う）。
import sys

INK = "#3B4441"
BODY = "#E6E3D9"
SCREEN = "#F6F7F2"


def kobito(tx, ty, s=11, arms="", legs="stand", extra_back="", extra_front="", face="smile"):
    leg = {
        "stand": '<path d="M20 35.5 L19 45"/><path d="M28 35.5 L29 45"/>',
        "walk": '<path d="M19 33 l-2 5 l-3 5"/><path d="M29 33 l2 5 l3 5"/>',
    }[legs]
    mouth = {
        "smile": '<path d="M22 22c2 2 4 2 6 0" fill="none" stroke="%s" stroke-width="1.2" stroke-linecap="round"/>' % INK,
        "open": '<path d="M22.4 21.6c1.6 2.6 3.6 2.6 5.2 0Z" fill="%s" stroke="%s" stroke-width="1" stroke-linejoin="round"/>' % (INK, INK),
    }[face]
    return f'''<g transform="translate({tx} {ty}) scale({s})" stroke-linecap="round" stroke-linejoin="round">
    {extra_back}
    <g fill="none" stroke="{INK}" stroke-width="1.8">{leg}</g>
    <path d="M10 23C10 11 16 5 25 5c8 0 13 6 13 16 0 11-6 16-15 16-8 0-13-5-13-14Z" fill="{BODY}" stroke="{INK}" stroke-width="1.7"/>
    <path d="M15 13c5-4 13-4 18 0v12c-5 4-13 4-18 0Z" fill="{SCREEN}" stroke="{INK}" stroke-width="1.4"/>
    <circle cx="21" cy="18" r="1.4" fill="{INK}"/><circle cx="28" cy="18" r="1.4" fill="{INK}"/>
    {mouth}
    <g fill="none" stroke="{INK}" stroke-width="1.8">{arms}</g>
    {extra_front}
  </g>'''


def squircle(top, bottom, content, uid):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg-{uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
    <clipPath id="clip-{uid}"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
    <filter id="drop-{uid}" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="12" stdDeviation="16" flood-color="#000" flood-opacity=".22"/></filter>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg-{uid})" filter="url(#drop-{uid})"/>
  <g clip-path="url(#clip-{uid})">
{content}
  </g>
</svg>
'''


def ground(y=842, color="#000", opacity=".10", rx=210):
    return f'<ellipse cx="512" cy="{y}" rx="{rx}" ry="22" fill="{color}" opacity="{opacity}"/>'


# --- Pastephant：象の耳を付けた小人が、コピーした物をはさんだクリップボードを胸に抱える ---
def pastephant():
    s = 12.5
    tx, ty = 512 - 24 * s, 236
    # 体の後ろの大きな耳（象は決して忘れない）。
    ears = f'''<path d="M13 10 C4 4 -4.5 9 -4 19 C-3.6 26 0 30.5 4.5 36.5 C5.5 32 8 29.5 11.5 28.5" fill="#B3BDC6" stroke="{INK}" stroke-width="1.6"/>
    <path d="M11.5 13.5 C5 10 0 13.5 0 19.5 C0 24 2.5 27.5 5.5 31 C7 28.5 9 27 11 26.5" fill="#D9C3C0" stroke="none"/>
    <path d="M35 10 C44 4 52.5 9 52 19 C51.6 26 48 30.5 43.5 36.5 C42.5 32 40 29.5 36.5 28.5" fill="#B3BDC6" stroke="{INK}" stroke-width="1.6"/>
    <path d="M36.5 13.5 C43 10 48 13.5 48 19.5 C48 24 45.5 27.5 42.5 31 C41 28.5 39 27 37 26.5" fill="#D9C3C0" stroke="none"/>'''
    arms = '<path d="M11 27 Q7.5 29.5 7.6 33.6"/><path d="M37 27 Q40.5 29.5 40.4 33.6"/>'
    board = f'''<g stroke="{INK}" stroke-linejoin="round">
      <rect x="334" y="604" width="356" height="290" rx="30" fill="#B98A5A" stroke-width="18"/>
      <rect x="366" y="640" width="292" height="240" rx="12" fill="#F4EFE3" stroke-width="12"/>
      <rect x="452" y="580" width="120" height="52" rx="16" fill="#8C938E" stroke-width="14"/>
      <g stroke-width="10">
        <rect x="396" y="670" width="72" height="56" rx="8" fill="#A9C3D6"/>
        <path d="M404 718 L426 694 L442 710 L452 700 L462 718" fill="none" stroke-width="7"/>
      </g>
      <g stroke="#C7BFAE" stroke-width="12" stroke-linecap="round">
        <path d="M496 682 L628 682"/><path d="M496 714 L600 714"/>
        <path d="M396 764 L628 764"/><path d="M396 798 L580 798"/>
      </g>
    </g>'''
    sparkle = '<g stroke="#EEF2F5" stroke-width="14" stroke-linecap="round" opacity=".85"><path d="M760 200 L790 172"/><path d="M790 250 L830 244"/><path d="M226 214 L196 186"/></g>'
    content = sparkle + kobito(tx, ty, s=s, arms=arms, extra_back=ears) + board
    return squircle("#8FA2B3", "#728698", content, "pastephant")


# --- パネルの縁にしがみつく小人（Resources/kobito-cling.png）。右側の x=54 がパネルの縁で、両手でつかむ ---
def cling():
    body = f'''<g transform="translate(5 8) rotate(-8 30 22)" stroke-linecap="round" stroke-linejoin="round">
    <path d="M13 10 C4 4 -4.5 9 -4 19 C-3.6 26 0 30.5 4.5 36.5 C5.5 32 8 29.5 11.5 28.5" fill="#B3BDC6" stroke="{INK}" stroke-width="1.6"/>
    <path d="M11.5 13.5 C5 10 0 13.5 0 19.5 C0 24 2.5 27.5 5.5 31 C7 28.5 9 27 11 26.5" fill="#D9C3C0"/>
    <g fill="none" stroke="{INK}" stroke-width="1.8"><path d="M19 35 l-2 5 l-1 4.5"/><path d="M28 35.5 l2.5 4 l4 2.5"/></g>
    <path d="M10 23C10 11 16 5 25 5c8 0 13 6 13 16 0 11-6 16-15 16-8 0-13-5-13-14Z" fill="{BODY}" stroke="{INK}" stroke-width="1.7"/>
    <path d="M15 13c5-4 13-4 18 0v12c-5 4-13 4-18 0Z" fill="{SCREEN}" stroke="{INK}" stroke-width="1.4"/>
    <circle cx="22.5" cy="18" r="1.4" fill="{INK}"/><circle cx="29.5" cy="18" r="1.4" fill="{INK}"/>
    <path d="M23.5 22c2 2 4 2 6 0" fill="none" stroke="{INK}" stroke-width="1.2"/>
    <g fill="none" stroke="{INK}" stroke-width="1.8"><path d="M36 16 Q43 11.5 49 13"/><path d="M37 25 Q43 24 49 22"/></g>
    <circle cx="49" cy="13" r="1.9" fill="{BODY}" stroke="{INK}" stroke-width="1.2"/><circle cx="49" cy="22" r="1.9" fill="{BODY}" stroke="{INK}" stroke-width="1.2"/>
  </g>'''
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{body}</svg>\n'


# --- dmg を開いたときの背景（600×400pt）。左の Pastephant から右の Applications へ、小人が案内する ---
def dmg_background():
    ears = f'''<path d="M13 10 C4 4 -4.5 9 -4 19 C-3.6 26 0 30.5 4.5 36.5 C5.5 32 8 29.5 11.5 28.5" fill="#B3BDC6" stroke="{INK}" stroke-width="1.6"/>
    <path d="M11.5 13.5 C5 10 0 13.5 0 19.5 C0 24 2.5 27.5 5.5 31 C7 28.5 9 27 11 26.5" fill="#D9C3C0" stroke="none"/>
    <path d="M35 10 C44 4 52.5 9 52 19 C51.6 26 48 30.5 43.5 36.5 C42.5 32 40 29.5 36.5 28.5" fill="#B3BDC6" stroke="{INK}" stroke-width="1.6"/>
    <path d="M36.5 13.5 C43 10 48 13.5 48 19.5 C48 24 45.5 27.5 42.5 31 C41 28.5 39 27 37 26.5" fill="#D9C3C0" stroke="none"/>'''
    arms = '<path d="M37 24 Q41 22 44.5 17"/><path d="M11.5 26 Q8.5 29 8 32.5"/>'
    guide = kobito(300 - 24 * 1.9, 268, s=1.9, arms=arms, legs="walk", extra_back=ears, face="open")
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400" viewBox="0 0 600 400">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F6F3EC"/><stop offset="1" stop-color="#E7E2D6"/></linearGradient></defs>
  <rect width="600" height="400" fill="url(#bg)"/>
  <path d="M0 0 H600 V56 H0 Z" fill="#8FA2B3" opacity=".22"/>
  <text x="300" y="36" text-anchor="middle" font-family="Hiragino Sans, Hiragino Kaku Gothic ProN, sans-serif" font-size="17" font-weight="600" fill="{INK}">Pastephant を Applications フォルダへドラッグしてください</text>
  <path d="M225 190 C265 160 335 160 375 190" fill="none" stroke="#728698" stroke-width="5" stroke-linecap="round" stroke-dasharray="2 12"/>
  <path d="M366 176 L380 193 L360 199" fill="none" stroke="#728698" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
  {guide}
  <text x="300" y="384" text-anchor="middle" font-family="Hiragino Sans, sans-serif" font-size="11" fill="#7A817D">kobito-tools</text>
</svg>
'''


if __name__ == "__main__":
    open(sys.argv[1], "w").write(pastephant())
    if len(sys.argv) > 2:
        open(sys.argv[2], "w").write(cling())
    if len(sys.argv) > 3:
        open(sys.argv[3], "w").write(dmg_background())
