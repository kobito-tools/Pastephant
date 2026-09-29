# 開発について

Pastephant のビルド方法とソースコードの構成をまとめます。利用方法は [README](../README.md)、機能の要件は [REQUIREMENTS.md](REQUIREMENTS.md) を参照してください。

## ビルド

Xcode Command Line Tools（`xcode-select --install`）が必要です。

```bash
./build.sh                                 # フォルダ直下に Pastephant.app（ユニバーサルバイナリ）を作成
./scripts/package-release.sh               # Releases 用の dist/Pastephant_<版>.dmg と dist/Pastephant_<版>_universal.zip を作成
./tests/run.sh                             # 取得から書き戻し・検索・タグ・変換・文字認識・数式・Tomelet への書き出しまでのテスト
./scripts/make-icon.sh                     # アイコンを描き直す（make-icon.py → icon.svg → icon-1024.png・AppIcon.icns）
./scripts/sync-schema.sh <Tomeletのフォルダ> # Tomelet の DB 更新を schema/tomelet/ へ写す
./scripts/social-preview.sh                # シリーズの紹介画像（assets/icon/Pastephant-1280x640.png）を作り直す（Google Chrome と Tomelet のフォントを使う）
```

版番号は `build.sh` の `VERSION` で指定します。`Pastephant-Setup.command` は `build.sh` を呼び出すだけの、ソースから使う人向けの入口です。

`package-release.sh` の dmg は、アプリ・Applications へのリンク・背景（`assets/dmg/`。`scripts/make-icon.sh` で描き直せる）を置き、窓の並べ方を Finder に頼んでから圧縮します。初回は「Finder を操作する許可」を求められることがあります。許可しないと、背景なし（並べ方なし）の dmg になります。

`tests/run.sh` は名前付きの NSPasteboard と一時フォルダを使うので、実際のクリップボード・履歴・基準パスには触れません。数式のテストは同梱の KaTeX を画面外の WKWebView で動かします。

### 許可について

`build.sh` はアドホック署名なので、ビルドし直すたびに macOS からは別のアプリに見え、アクセシビリティと入力監視の許可が外れます。ビルドし直したら、「システム設定」→「プライバシーとセキュリティ」の各項目で Pastephant を一度削除（`−`）してから、もう一度許可してください。

## ソースコードの構成

| パス | 内容 |
|---|---|
| `Sources/PastephantApp.swift` | 起動、取得した物の流れ（保存 → 自動タグ → スタック → 文字認識 → 自動書き出し）、パネルからの操作、メニューバー、URL、ショートカット |
| `Sources/PasteboardWatcher.swift` | クリップボードの監視（0.3秒ごと）と、保存しない物の判定（F-01, F-02） |
| `Sources/ClipContent.swift` | 1回のコピーの中身（全ての項目・型・データ）、種類の判定、埋め込んだ数式の読み取り、プレビュー、サムネ |
| `Sources/ClipStore.swift` | 履歴のDBと `blobs/` の読み書き、削除、整理（F-01, F-15） |
| `Sources/ClipStore+Organize.swift` | 検索と絞り込み・並べ替え、タグ、ピン、定型文、文字認識の結果、書き出しの印（F-04, F-05, F-08, F-09） |
| `Sources/Paster.swift` | 書き戻しと ⌘V の送信、定型文の差し込み（F-03） |
| `Sources/PasteStack.swift` | ペーストスタックと「スタック N 件」の表示（F-14） |
| `Sources/OCR.swift` | Vision による文字認識（F-08） |
| `Sources/HotKey.swift` | どのアプリでも効くショートカット（Carbon の RegisterEventHotKey） |
| `Sources/Settings.swift` | このMacの設定（`settings.json`）と自動タグの規則 |
| `Sources/SettingsWindow.swift` | 設定の画面（F-19） |
| `Sources/SQLiteDatabase.swift` | macOS 標準の SQLite の薄いラッパーと、`schema/` の適用 |
| `Sources/Panel/` | パネル（フォーカスを奪わない NSPanel）、一覧、プレビュー、作業の画面（タグ・編集・変換・まとめる・数式・定型文）、キー操作、Quick Look、ドラッグ |
| `Sources/Transforms/` | 改行を消す処理、貼る前の変換・パス・まとめる区切り・定型文の差し込み（F-07, F-09, F-11, F-12） |
| `Sources/Latex/` | 数式の元の式と描き方、KaTeX での描画と PDF・PNG・TIFF の作成（F-06） |
| `Sources/Companions/` | 基準パス（`.kobito-tools/`）の扱いと使用中の印・共有タグ（PopNote! の `Dataset.swift`・`TagStore.swift` の写し）、Tomelet への書き出し、PopNote! への受け渡し（F-04, F-16, F-17） |
| `Resources/katex/` | 同梱の KaTeX（MIT）と描画ページ `render.html` |
| `schema/` | 履歴のDBの作成と更新（ファイル名順に、まだの物だけ適用） |
| `schema/tomelet/` | Tomelet の DB 更新の写し（Tomelet への書き出し用のDBを作る） |
| `tests/` | `run.sh` とハーネス（`harness/main.swift`） |

## 保存の仕組み

```text
~/Library/Application Support/Pastephant/
├── database/history.sqlite3   項目・型の一覧・タグの写し・全文検索（WAL）
├── blobs/ab/<sha256>.bin      生データ（中身のハッシュ名。同じデータは1つだけ）
├── thumbs/<項目ID>.png        一覧用のサムネ
└── settings.json              このMacの設定
```

- 1回のコピーは、`NSPasteboardItem` ごと・型ごとに `clip_representations` の1行になります。貼るときは同じ並びで `NSPasteboardItem` を作り直すので、アプリ独自の型（パワポの図形など）も元のまま戻ります。
- 全ての項目・型・データから作るハッシュ（`clips.content_hash`）で重複を判定し、同じ物は回数を増やして先頭に移します。定型文は重複を判定しません。
- 自分が書き戻した物には `io.github.kobito-tools.pastephant.own` の型を付け、監視側で取らないようにしています。
- 取得（クリップボードを読む）はメインスレッド、保存・整理・タグの同期・書き出しは裏の1本のキュー、文字認識は別のキューです。`ClipStore` の公開メソッドは1つのロックの中で動きます。
- 検索は FTS5 の trigram（3文字以上）と、それより短い語の部分一致を組み合わせます。タグの名前も対象です。
- 数式画像には元の式と描き方（`LatexSource` の JSON）を、自分の型・PNG の説明・PDF のキーワードの3か所に入れます。どれか1つが残っていれば、ほかのアプリから戻ってきても数式として扱えます。

## シリーズとのつながり

基準パスは任意です。設定の「連携」で選ぶと、次の2つにだけ使います。仕様は Tomelet の `docs/BASE_PATH_FOR_COMPANIONS.md`（4章・5a章）にあります。

```text
<基準パス>/.kobito-tools/
├── dataset.json                    読むだけ（無ければ ID を尋ねて作る）
├── Tags/tags.json                  共有タグ。このMacの履歴DBの tags・tag_categories はその写し
└── Pastephant/                     Tomelet への書き出し（⌘S・自動で残すタグ）
    ├── lock.json                   書き出す間だけ置く使用中の印
    ├── database/pastephant.sqlite3 日ごとのクリップのメモ（Tomelet の memos 表と同じ形・DELETE モード）
    └── uploads/                    メモに添付した画像
```

- **共有タグ**：起動時、基準パスを変えたとき、タグを付け外ししたときに、PopNote! と同じ規則（`TagStore.swift`）で `tags.json` と統合します。
- **Tomelet**：`scripts/popnote-memos.js` の `mirrorCompanionMemos` が、PopNote! のメモと一緒に `pastephant.sqlite3` のメモを読み取り専用で写します。表示するかは `dataset.json` の `settings.showPastephantMemos`。Tomelet でメモを開くと `pastephant://open?query=exported:<日付>` で呼ばれます。
- **PopNote!**：選んだ項目を `$TMPDIR/Pastephant-PopNote/<UUID>.json`（`format: "pastephant-clip"`、文字と Base64 の画像）に書き、`popnote://import?file=<パス>` で渡します。PopNote! はこのフォルダのファイルだけを読み、読んだら消します。

Tomelet の DB 更新が増えたら `scripts/sync-schema.sh` で `schema/tomelet/` を更新し、`tests/run.sh` を実行してください。
