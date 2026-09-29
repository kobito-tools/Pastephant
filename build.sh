#!/bin/zsh
# Pastephant.appをこのフォルダ直下に作る。Xcode Command Line Tools（swiftc）が必要。
set -euo pipefail
cd "${0:A:h}"

APP_NAME="Pastephant"
VERSION="0.1.0"
BUILD_DIR=".build"
STAGE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$STAGE/Contents"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$BUILD_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
# 履歴のDBの作成と更新に使う。
cp -R schema "$CONTENTS/Resources/schema"
# 数式画像を描く KaTeX（MIT）と、その描画ページ。
cp -R Resources/. "$CONTENTS/Resources/"
[[ -f assets/icon/AppIcon.icns ]] && cp assets/icon/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>ja</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>io.github.kobito-tools.pastephant</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>io.github.kobito-tools.pastephant</string>
  <key>CFBundleURLSchemes</key><array><string>pastephant</string></array>
</dict></array>
</dict></plist>
PLIST

# Apple Silicon・Intelの両方で動くユニバーサルバイナリにする。
for arch in arm64 x86_64; do
  xcrun swiftc -sdk "$SDK" -target "$arch-apple-macosx13.0" -parse-as-library -O \
    Sources/**/*.swift -framework Cocoa -framework SwiftUI -framework Carbon -framework ServiceManagement -framework WebKit -framework PDFKit -framework Vision -lsqlite3 \
    -o "$BUILD_DIR/$APP_NAME-$arch"
done
lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" -output "$CONTENTS/MacOS/$APP_NAME"
codesign --force --sign - --timestamp=none "$STAGE"

rm -rf "$APP_NAME.app"
mv "$STAGE" "$APP_NAME.app"
rm -rf "$BUILD_DIR"

# pastephant:// をすぐ使えるように Launch Services へ登録する。
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$PWD/$APP_NAME.app"
echo "$PWD/$APP_NAME.app"
