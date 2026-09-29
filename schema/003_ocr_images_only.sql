-- 文字認識（F-08）は画像の項目だけ。002 より前からある画像以外の項目を「対象外」にする。
UPDATE clips SET ocr_state = 2 WHERE kind <> 'image' AND ocr_state = 0;
