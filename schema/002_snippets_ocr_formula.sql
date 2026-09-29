-- 定型文（F-09）、画像の文字認識（F-08）、数式の元の式（F-06）。

-- 定型文とピンの名前。定型文も1つの項目として clips に入れ、ピンの欄に並べる。
ALTER TABLE clips ADD COLUMN title TEXT;
ALTER TABLE clips ADD COLUMN is_snippet INTEGER NOT NULL DEFAULT 0 CHECK (is_snippet IN (0, 1));
-- 画像から読み取った文字。ocr_state は 0 まだ・1 済み・2 読み取れる文字なし／対象外。
ALTER TABLE clips ADD COLUMN ocr_text TEXT;
ALTER TABLE clips ADD COLUMN ocr_state INTEGER NOT NULL DEFAULT 0 CHECK (ocr_state IN (0, 1, 2));
-- 数式の元の式と描き方（JSON。io.github.kobito-tools.pastephant.latex と同じ中身）。
ALTER TABLE clips ADD COLUMN latex TEXT;

CREATE INDEX clips_pinned_idx ON clips(pinned, pin_order);
CREATE INDEX clips_ocr_idx ON clips(ocr_state, kind);
