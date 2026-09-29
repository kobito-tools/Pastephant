-- このMacの履歴（~/Library/Application Support/Pastephant/database/history.sqlite3）。
-- 生データは blobs/ に中身のハッシュ名で置き、ここには型と名前だけを記録する。

CREATE TABLE clips (
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('text', 'richText', 'image', 'file', 'url', 'color', 'office', 'formula')),
  content_hash TEXT NOT NULL UNIQUE,          -- 全ての項目・型・データから作るハッシュ（重複の判定）
  text TEXT,                                  -- 貼り付けと検索に使うプレーンテキスト（無ければNULL）
  preview TEXT NOT NULL DEFAULT '',           -- 一覧に出す短い文字
  file_names TEXT,                            -- ファイルの項目の名前（改行区切り）
  source_bundle_id TEXT,
  source_app_name TEXT,
  created_at REAL NOT NULL,                   -- 初めてコピーした日時（UNIX秒）
  copied_at REAL NOT NULL,                    -- 最後にコピーした日時
  last_used_at REAL NOT NULL,                 -- 最後にコピーまたは貼り付けた日時（一覧の並び順）
  copy_count INTEGER NOT NULL DEFAULT 1 CHECK (copy_count >= 1),
  paste_count INTEGER NOT NULL DEFAULT 0 CHECK (paste_count >= 0),
  total_bytes INTEGER NOT NULL DEFAULT 0,
  oversized INTEGER NOT NULL DEFAULT 0 CHECK (oversized IN (0, 1)),   -- 大きすぎて生データを保存しなかった
  has_thumbnail INTEGER NOT NULL DEFAULT 0 CHECK (has_thumbnail IN (0, 1)),
  pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
  pin_order INTEGER,
  exported_at REAL                            -- Tomelet に書き出した日時（F-17）
);
CREATE INDEX clips_last_used_idx ON clips(last_used_at DESC);
CREATE INDEX clips_kind_used_idx ON clips(kind, last_used_at);

-- 1回のコピーに含まれる NSPasteboardItem ごと・型ごとの生データ。並びは元のアプリが載せた順。
CREATE TABLE clip_representations (
  clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
  item_index INTEGER NOT NULL,
  position INTEGER NOT NULL,
  type TEXT NOT NULL,
  blob_hash TEXT NOT NULL,
  size INTEGER NOT NULL,
  PRIMARY KEY (clip_id, item_index, position)
);
CREATE INDEX clip_representations_blob_idx ON clip_representations(blob_hash);

-- 共有タグ（.kobito-tools/Tags/tags.json）の写し。Tomelet・PopNote! と同じ形。
CREATE TABLE tag_categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  display_order INTEGER NOT NULL DEFAULT 1 CHECK (display_order >= 1),
  deleted_at TEXT,
  revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1)
);
CREATE TABLE tags (
  id TEXT PRIMARY KEY,
  category_id TEXT REFERENCES tag_categories(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  display_order INTEGER NOT NULL DEFAULT 1 CHECK (display_order >= 1),
  deleted_at TEXT,
  revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
  archived_at TEXT
);
CREATE TABLE clip_tags (
  clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'auto')),
  PRIMARY KEY (clip_id, tag_id)
);
CREATE INDEX clip_tags_tag_idx ON clip_tags(tag_id, clip_id);

-- 全文検索。日本語でも部分一致できるよう trigram を使う。rowid は clips.id。
CREATE VIRTUAL TABLE clip_search USING fts5(text, ocr, latex, file_names, app_name, tokenize = 'trigram');
