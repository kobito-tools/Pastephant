#!/bin/zsh
# GitHubのReleasesへ添付するzipを作る。dist/Pastephant_<版>_universal.zip
set -euo pipefail
cd "${0:A:h}/.."
./build.sh >/dev/null
version=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' build.sh)
mkdir -p dist
archive="dist/Pastephant_${version}_universal.zip"
rm -f "$archive"
# Finderの「圧縮」と同じ形式（拡張属性・署名を保ったまま）で固める。
ditto -c -k --keepParent "Pastephant.app" "$archive"
echo "$PWD/$archive"
