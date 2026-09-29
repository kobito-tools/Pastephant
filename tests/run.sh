#!/bin/zsh
# 取得・保存・書き戻し・整理・改行の処理を、本物の NSPasteboard（名前付き）と一時フォルダで確かめる。
# 実際のクリップボードと履歴（~/Library/Application Support/Pastephant）には触れない。
set -euo pipefail
cd "${0:A:h}/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# PastephantApp.swift（@main）以外をハーネスと一緒にコンパイルする。
sources=(Sources/**/*.swift)
sources=(${sources:#Sources/PastephantApp.swift})
if ! xcrun swiftc -o "$work/harness" $sources tests/harness/main.swift \
  -framework Cocoa -framework SwiftUI -framework Carbon -framework WebKit -framework PDFKit -framework Vision -framework Quartz -framework ServiceManagement -lsqlite3 > "$work/build.log" 2>&1; then
  cat "$work/build.log"; exit 1
fi
"$work/harness" "$work" schema Resources/katex | tee "$work/harness.log"
grep -q "すべて成功" "$work/harness.log"

# DBの形と整合性
python3 - "$work/store/database/history.sqlite3" <<'PY'
import sqlite3, sys, os
db = sqlite3.connect(sys.argv[1])
applied = [row[0] for row in db.execute("SELECT version FROM schema_migrations ORDER BY version")]
bundled = sorted(name for name in os.listdir("schema") if name.endswith(".sql"))
assert applied == bundled, (applied, bundled)
assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
assert db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
print(f"ok - DBの更新 {len(applied)}件・整合性OK・WAL")
PY

# Tomelet への書き出し用のDB：Tomelet と同じ形・メモ・タグ・画像
python3 - "$work/harness.log" <<'PY'
import sqlite3, sys, os
values = dict(line.strip().split("=", 1) for line in open(sys.argv[1]) if line.startswith("EXPORT_"))
db = sqlite3.connect(values["EXPORT_DB"])
applied = [row[0] for row in db.execute("SELECT version FROM schema_migrations ORDER BY version")]
bundled = sorted(name for name in os.listdir("schema/tomelet") if name.endswith(".sql"))
assert applied == bundled, (applied, bundled)
assert db.execute("PRAGMA journal_mode").fetchone()[0] == "delete"
title, html, text = db.execute("SELECT title, body_html, body_text FROM memos WHERE id = ?", (values["EXPORT_MEMO"],)).fetchone()
assert title == values["EXPORT_TITLE"], title
assert "arxiv.org" in html and "&lt;b&gt;" in html and "2件目" in html and "<img src=\"/api/v1/uploads/upload-" in html, html
assert db.execute("SELECT count(*) FROM memos").fetchone()[0] == 1
tags = [row[0] for row in db.execute("SELECT t.name FROM memo_tags r JOIN tags t ON t.id = r.tag_id")]
assert tags == ["書き出し"], tags
stored = db.execute("SELECT u.stored_name FROM memo_uploads r JOIN managed_uploads u ON u.id = r.upload_id").fetchone()[0]
assert os.path.exists(os.path.join(os.path.dirname(os.path.dirname(values["EXPORT_DB"])), "uploads", stored))
print("ok - Tomelet への書き出し：Tomelet と同じ形・1日1メモ・タグ・画像")
PY
