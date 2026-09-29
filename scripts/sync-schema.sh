#!/bin/zsh
# TomeletのDB更新（migrations/*.sql）を schema/tomelet/ へ写す。
# Tomelet への書き出し用のDB（.kobito-tools/Pastephant/database/pastephant.sqlite3）はこの内容で作るため、Tomeletと同じ形式になる。
# 使い方: scripts/sync-schema.sh <Tomeletのフォルダ>
set -euo pipefail
cd "${0:A:h}/.."
source_dir="${1:?Tomeletのフォルダを指定してください}/migrations"
[[ -d "$source_dir" ]] || { echo "migrationsが見つかりません: $source_dir" >&2; exit 1; }
rm -f schema/tomelet/*.sql
cp "$source_dir"/[0-9]*_*.sql schema/tomelet/
ls schema/tomelet
