import AppKit

// 取得 → 保存 → 書き戻しで、全ての項目・型・データが元のまま戻ることなどを、本物の NSPasteboard（名前付き）で確かめる。
// 実行は tests/run.sh から。第1引数に一時フォルダ、第2引数に schema/ を渡す。

setvbuf(stdout, nil, _IONBF, 0)
var failures = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    if (try? condition()) == true { print("ok - \(message)") } else { print("NG - \(message)"); failures += 1 }
}

let work = URL(fileURLWithPath: CommandLine.arguments[1])
let schema = URL(fileURLWithPath: CommandLine.arguments[2])
let katex = URL(fileURLWithPath: CommandLine.arguments[3])
let store = try ClipStore(directory: work.appendingPathComponent("store"), schemaDirectory: schema)

func makePNG(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func put(_ items: [[(String, Data)]], on pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    pasteboard.writeObjects(items.map { representations in
        let item = NSPasteboardItem()
        for (type, data) in representations { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
        return item
    })
}

func contents(of pasteboard: NSPasteboard) -> [[Representation]] {
    (pasteboard.pasteboardItems ?? []).map { item in
        item.types.compactMap { type in item.data(forType: type).map { Representation(type: type.rawValue, data: $0) } }.filter { $0.type != Capture.ownType }
    }
}

let source = NSPasteboard(name: NSPasteboard.Name("pastephant-test-source-\(UUID().uuidString)"))
let destination = NSPasteboard(name: NSPasteboard.Name("pastephant-test-destination-\(UUID().uuidString)"))
defer { source.releaseGlobally(); destination.releaseGlobally() }

MainActor.assumeIsolated {
    // 1. パワポの図形のような独自の型を含む、2つの項目のコピー
    let slides = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
    let png = makePNG(width: 800, height: 400)
    put([[("public.utf8-plain-text", Data("図形のテキスト".utf8)), ("com.microsoft.PowerPoint-14.0-Slides-Package", slides), ("public.png", png)],
         [("public.utf8-plain-text", Data("2つ目の項目".utf8))]], on: source)
    let original = contents(of: source)
    let capture = Capture.read(from: source, sourceBundleID: "com.microsoft.Powerpoint", sourceAppName: "Microsoft PowerPoint")!
    check(capture.kind == .office, "パワポの型を含むコピーは office")
    let saved = try! store.save(capture, maxItemBytes: 100 * 1024 * 1024)
    guard case .inserted(let id) = saved else { fatalError("新しく保存されない") }
    check(FileManager.default.fileExists(atPath: store.thumbnailURL(id).path), "画像を含むコピーのサムネを作る")
    let detail = try! store.detail(id)!
    check(detail.imageData == png && detail.text == "図形のテキスト\n2つ目の項目", "プレビューに画像と文字を渡す")
    check(detail.types == ["public.utf8-plain-text", "com.microsoft.PowerPoint-14.0-Slides-Package", "public.png"], "プレビューに型の一覧を渡す（重複なし・元の並び）")
    check(try! store.detail(id, maxImageBytes: 10)!.imageData == nil, "大きすぎる画像はプレビューで読まない")

    let paster = Paster(store: store, pasteboard: destination) { Settings() }
    check(paster.write(id, mode: .original), "元の形で書き戻せる")
    check(contents(of: destination) == original, "全ての項目・型・データが元のまま戻る（\(original.count)項目・\(original.flatMap { $0 }.count)型）")
    check(destination.pasteboardItems?.allSatisfy { $0.types.contains(NSPasteboard.PasteboardType(Capture.ownType)) } == true, "書き戻した物に自分の印が付く")

    check(paster.write(id, mode: .plainText), "プレーンテキストで書き戻せる")
    check(contents(of: destination).flatMap { $0 }.map(\.type) == ["public.utf8-plain-text"], "プレーンテキストは文字の型だけ（\(destination.types?.map(\.rawValue) ?? [])）")
    check(destination.string(forType: .string) == "図形のテキスト\n2つ目の項目", "プレーンテキストは全ての項目の文字をつなぐ")

    // 2. 同じ中身をもう一度コピー
    let again = try! store.save(Capture.read(from: source)!, maxItemBytes: 100 * 1024 * 1024)
    check(again == .bumped(id), "同じ中身は新しい項目を作らない")
    check(try! store.summary(id)?.copyCount == 2, "コピーした回数が増える")

    // 3. 改行を消して貼る
    put([[("public.utf8-plain-text", Data("これは日本語の\n文章です。\nThis is an inter-\nnational\ntest.".utf8))]], on: source)
    let lines = try! store.save(Capture.read(from: source)!, maxItemBytes: 100 * 1024 * 1024).id
    paster.write(lines, mode: .joinLines)
    check(destination.string(forType: .string) == "これは日本語の文章です。This is an international test.", "改行を消して書き戻す")

    // 4. 保存しない物
    put([[("public.utf8-plain-text", Data("password".utf8)), ("org.nspasteboard.ConcealedType", Data())]], on: source)
    var captured: [Capture] = []
    let watcher = PasteboardWatcher(pasteboard: source, excludedBundleIDs: { [] }) { captured.append($0) }
    watcher.check()
    check(captured.isEmpty, "パスワード管理アプリの印が付いた物は取らない")
    put([[("public.utf8-plain-text", Data("ふつうの文字".utf8))]], on: source)
    watcher.check()
    check(captured.count == 1 && captured[0].plainText == "ふつうの文字", "ふつうのコピーは取る")
    paster.write(lines, mode: .original)
    let ownWatcher = PasteboardWatcher(pasteboard: destination, excludedBundleIDs: { [] }) { captured.append($0) }
    put([[("public.utf8-plain-text", Data("x".utf8))]], on: destination)
    paster.write(lines, mode: .original)
    ownWatcher.check()
    check(captured.count == 1, "自分で書き戻した物は取らない")
    watcher.isPaused = true
    put([[("public.utf8-plain-text", Data("停止中".utf8))]], on: source)
    watcher.check()
    check(captured.count == 1, "一時停止中は取らない")

    // 5. 大きすぎる物
    put([[("public.utf8-plain-text", Data("大きい".utf8)), ("public.png", png)]], on: source)
    let big = try! store.save(Capture.read(from: source)!, maxItemBytes: 10).id
    check(try! store.summary(big)?.oversized == true && (try! store.representations(of: big)) == nil, "上限を超えた物は生データを保存しない")
    paster.write(big, mode: .original)
    check(destination.string(forType: .string) == "大きい", "生データの無い物は文字だけ書き戻す")
}

// 6. 検索
_ = try store.save(Capture(items: [[Representation(type: "public.utf8-plain-text", data: Data("クリップボードの履歴を検索する".utf8))]], plainText: "クリップボードの履歴を検索する"), maxItemBytes: 1 << 20)
check(try store.recent(query: "履歴を検索").count == 1, "3文字以上は全文検索で見つかる")
check(try store.recent(query: "履歴").count == 1, "2文字は部分一致で見つかる")
check(try store.recent(query: "クリップ 検索").count == 1, "空白で区切った語は全て含む物")
check(try store.recent(query: "見つからない語").isEmpty, "含まない語では見つからない")
check(try store.recent(query: "PowerPoint").count >= 1, "コピー元のアプリ名でも見つかる")

// 7. 整理
let blobCount = { (try? FileManager.default.subpathsOfDirectory(atPath: store.directory.appendingPathComponent("blobs").path).filter { $0.hasSuffix(".bin") }.count) ?? 0 }
let beforeBlobs = blobCount()
var settings = Settings()
let future = Date().addingTimeInterval(40 * 86_400)
let report = try store.cleanup(settings: settings, now: future)
check(report.removedClips == 1, "30日を過ぎた office の項目を消す（\(report.removedClips)件）")
check(try store.recent().allSatisfy { $0.kind != .office }, "消した項目は一覧から消える")
check(blobCount() < beforeBlobs, "使われなくなった生データを消す")
check(try store.recent().contains { $0.kind == .text }, "テキストは無期限")
settings.maxItems = 1
try store.cleanup(settings: settings)
check(try store.usage().count == 1, "件数の上限を超えた分を古い順に消す")

// 8. 改行を消す
let dictionary: (String) -> Bool = { ["international", "email"].contains($0) }
check(LineJoiner.join("inter-\nnational", isWord: dictionary) == "international", "辞書にある語はハイフンを消す")
check(LineJoiner.join("well-\nknown", isWord: dictionary) == "well-known", "辞書に無い語はハイフンを残す")
check(LineJoiner.join("first line\nsecond line") == "first line second line", "英語の行は半角スペースでつなぐ")
check(LineJoiner.join("日本語の\n文章") == "日本語の文章", "日本語の行はそのままつなぐ")
check(LineJoiner.join("英語 English\nwords") == "英語 English words", "英語で終わる行と英語で始まる行は空白を入れる")
check(LineJoiner.join("段落1の\n続き\n\n段落2") == "段落1の続き\n\n段落2", "空行（段落の区切り）は残す")
check(LineJoiner.join("段落1\n\n\n段落2", keepParagraphs: false) == "段落1段落2", "段落の区切りを残さない設定")
check(LineJoiner.join("a\r\nb") == "a b", "CRLF の改行も消す")
check(LineJoiner.isDictionaryWord("international") && !LineJoiner.isDictionaryWord("wellknown"), "macOS の辞書で語を判定できる")

// 9. 変換（F-07・F-11・F-12）と定型文の差し込み（F-09）
check(TextTransforms.apply(.toWesternPunctuation, "これは、例です。") == "これは，例です．", "句読点を「，．」に")
check(TextTransforms.apply(.toJapanesePunctuation, "これは，例です．") == "これは、例です。", "句読点を「、。」に")
check(TextTransforms.apply(.halfWidthAlphanumerics, "ＡＢＣ　１２３！カナ") == "ABC 123!カナ", "英数字・記号だけ半角に")
check(TextTransforms.apply(.fullWidthKatakana, "ｶﾞｷﾞABC") == "ガギABC", "半角カタカナだけ全角に")
check(TextTransforms.apply(.trimSpaces, "  a   b \n\n c  ") == "a b\n\nc", "余分な空白を消す")
check(TextTransforms.apply(.sentenceCase, "HELLO WORLD. NEW LINE") == "Hello world. New line", "文の先頭だけ大文字")
let tsv = "名前\t値\na_b\t50%"
check(TextTransforms.apply(.tableToLatex, tsv) == "\\begin{tabular}{ll}\n\\hline\n名前 & 値 \\\\\n\\hline\na\\_b & 50\\% \\\\\n\\hline\n\\end{tabular}", "表を LaTeX の tabular に（特殊文字を逃がす）")
check(TextTransforms.apply(.tableToMarkdown, tsv) == "| 名前 | 値 |\n| --- | --- |\n| a_b | 50% |", "表を Markdown に")
check(TextTransforms.apply(.tableToCSV, "a,b\tc\"d") == "\"a,b\",\"c\"\"d\"", "表を CSV に（引用符で囲む）")
check(TextTransforms.htmlTableRows("<table><tr><th>A</th><td>B &amp; C</td></tr><tr><td>1<br>2</td><td></td></tr></table>") == [["A", "B & C"], ["1 2", ""]], "HTML の表を読む")
check(TextTransforms.apply(.numbered, "x\n\ny") == "1. x\n\n2. y", "番号付きにする（空行は飛ばす）")
check(TextTransforms.apply([.joinLines, .toWesternPunctuation], to: TransformContext(text: "これは、\n例です。")) == "これは，例です．", "変換をつなげる")
check(TextTransforms.apply([.ocrText], to: TransformContext(text: nil, ocrText: "画像の文字")) == "画像の文字", "画像の文字をテキストで")
check(TextTransforms.apply([.tableToMarkdown], to: TransformContext(text: "A B", html: "<table><tr><td>A</td><td>B</td></tr></table>")) == "| A | B |\n| --- | --- |", "タブの無い表は HTML から読む")
let home = NSHomeDirectory()
check(TextTransforms.paths(["\(home)/Docs/a.pdf", "/tmp/b.txt"], .pathTilde, basePath: nil) == "~/Docs/a.pdf\n/tmp/b.txt", "パス（~ から）")
check(TextTransforms.paths(["/Base/Paper/a.pdf"], .pathRelative, basePath: "/Base") == "Paper/a.pdf", "パス（基準パスから）")
check(TextTransforms.paths(["/Base/a b.pdf"], .fileURL, basePath: nil) == "file:///Base/a%20b.pdf", "file:// の URL")
check(MergeSeparator.custom.separator(custom: "\\n---\\n") == "\n---\n", "任意の区切り（\\n で改行）")
let fixedDate = ISO8601DateFormatter().date(from: "2026-09-28T05:06:07Z")!
let expanded = SnippetExpander.expand("{date:yyyy}年 {clipboard}：{cursor}です", clipboard: "コピー", now: fixedDate)
check(expanded.text == "2026年 コピー：です" && expanded.cursorOffsetFromEnd == 2, "定型文の差し込み（{date:書式}・{clipboard}・{cursor}）")

// 10. 絞り込み・タグ・ピン・定型文（F-04・F-05・F-09）
let store2 = try ClipStore(directory: work.appendingPathComponent("store2"), schemaDirectory: schema)
func saveText(_ text: String, app: String, date: Date = Date()) throws -> Int {
    try store2.save(Capture(items: [[Representation(type: "public.utf8-plain-text", data: Data(text.utf8))]], sourceBundleID: "com.example.\(app)", sourceAppName: app, date: date, plainText: text), maxItemBytes: 1 << 20).id
}
let wordID = try saveText("会議の議事録", app: "Word", date: ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")!)
let safariID = try saveText("https://arxiv.org/abs/1234", app: "Safari")
let paper = try store2.findOrCreateTag("論文")
try store2.addTag(paper, to: [safariID])
check(try store2.findOrCreateTag("論文") == paper, "同じ名前のタグは作り直さない")
check(try store2.recent(query: "#論文").map(\.id) == [safariID], "#タグ で絞り込む")
check(try store2.recent(query: "論文").map(\.id) == [safariID], "タグの名前も検索の対象")
check(try store2.recent(query: "type:link").map(\.id) == [safariID] && (try store2.recent(query: "type:リンク").map(\.id)) == [safariID], "type: で種類を絞り込む")
check(try store2.recent(query: "app:word").map(\.id) == [wordID], "app: でコピー元を絞り込む")
check(try store2.recent(query: "before:2026-09-02").map(\.id) == [wordID] && (try store2.recent(query: "after:2026-09-02").map(\.id)) == [safariID], "after:・before: で日付を絞り込む")
check(try store2.recent(sort: .copied).first?.id == safariID, "並べ替え（コピーした順）")
check(try store2.recent().first { $0.id == safariID }?.tags == ["論文"], "一覧にタグの名前を入れる")
try store2.removeTag(paper.id, from: [safariID])
check(try store2.recent(query: "#論文").isEmpty, "タグを外す")
try store2.setPinned([wordID], true)
let snippetID = try store2.createSnippet(title: "署名", body: "よろしくお願いします。\n{date:yyyy}")
check(try store2.pinned().map(\.id) == [wordID, snippetID], "ピンと定型文は並び順どおり")
check(try store2.recent(excludePinned: true).map(\.id) == [safariID], "ピンは履歴の欄から外す")
check(try store2.recent(query: "is:pinned").count == 2 && (try store2.recent(query: "type:snippet").map(\.id)) == [snippetID], "is:pinned・type:snippet")
try store2.movePin(snippetID, by: -1)
check(try store2.pinned().map(\.id) == [snippetID, wordID], "ピンを並べ替える")
try store2.updateSnippet(snippetID, title: "署名2", body: "新しい本文")
check(try store2.text(of: snippetID) == "新しい本文" && (try store2.pinned().first?.title) == "署名2" && (try store2.recent(query: "新しい本文").map(\.id)) == [snippetID], "定型文を直す")
var keepAll = Settings()
keepAll.maxItems = 0
try store2.cleanup(settings: keepAll)
check(Set(try store2.pinned().map(\.id)) == [snippetID, wordID], "整理してもピンと定型文は消さない")
MainActor.assumeIsolated {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("pastephant-test-snippet-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    try! store2.updateSnippet(snippetID, title: "署名", body: "ab{cursor}cd")
    let resolved = Paster(store: store2, pasteboard: pasteboard) { Settings() }.items(for: snippetID, mode: .original)
    check(resolved.map { String(data: $0.items[0][0].data, encoding: .utf8) } == "abcd" && resolved?.cursorOffset == 2, "定型文を貼るときに差し込みを展開する")
}

// 11. 自動タグ（F-04）
var rules = Settings()
rules.autoTagRules = [AutoTagRule(kind: .app, pattern: "TeXShop", tag: "latex"), AutoTagRule(kind: .domain, pattern: "arxiv.org", tag: "論文")]
check(rules.autoTags(bundleID: "x", appName: "TeXShop", text: "a") == ["latex"], "アプリで自動タグ")
check(rules.autoTags(bundleID: "com.apple.Safari", appName: "Safari", text: "見て https://export.arxiv.org/abs/1") == ["論文"], "ドメインで自動タグ（サブドメインも）")
check(rules.autoTags(bundleID: nil, appName: nil, text: "https://example.com") == [], "当てはまらなければ付けない")

// 12. 文字認識（F-08）
func textImage(_ text: String) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 160, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 900, height: 160).fill()
    NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 30, y: 50))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let screenshotID = try store2.save(Capture(items: [[Representation(type: "public.png", data: textImage("Pastephant 画像の文字"))]], sourceAppName: "スクリーンショット"), maxItemBytes: 1 << 24).id
let pending = try store2.pendingOCR()
check(pending.map(\.id) == [screenshotID], "まだ文字を読んでいない画像を返す")
let recognized = OCR.recognize(pending[0].data) ?? ""
check(recognized.contains("Pastephant"), "画像の文字を読む（\(recognized.replacingOccurrences(of: "\n", with: " "))）")
try store2.setOCR(screenshotID, text: recognized)
check(try store2.pendingOCR().isEmpty && (try store2.recent(query: "Pastephant").map(\.id)) == [screenshotID], "読んだ文字で検索できる")

// 13. 数式（F-06）
let latex = LatexSource(source: "\\frac{a}{b}", options: LatexOptions())
check(LatexSource(embedded: latex.embedded) == latex && LatexSource(json: latex.json) == latex, "元の式を埋め込み・取り出せる")
check(LatexSource.looksLikeLatex("$x^2$") && LatexSource.looksLikeLatex("\\frac{1}{2}") && !LatexSource.looksLikeLatex("ふつうの文章"), "LaTeX らしい文字を見分ける")
check(LatexSource.stripDelimiters("\\[ x \\]") == "x" && LatexSource.stripDelimiters("$$y$$") == "y", "囲みを外す")
_ = NSApplication.shared
var rendered: Result<LatexImage, Error>?
Task { @MainActor in
    do { rendered = .success(try await LatexRenderer(resources: katex).render(latex, macros: "\\newcommand{\\Pset}{\\mathbb{P}}")) } catch { rendered = .failure(error) }
}
let deadline = Date().addingTimeInterval(30)
while rendered == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
switch rendered {
case .success(let image)?:
    check(image.size.width > 5 && image.size.height > 5, "数式を描く（\(Int(image.size.width))×\(Int(image.size.height))pt）")
    check(image.png.starts(with: [0x89, 0x50, 0x4E, 0x47]) && image.pdf.starts(with: Array("%PDF".utf8)), "PNG と PDF を作る")
    if let source = CGImageSourceCreateWithData(image.png as CFData, nil), let image2 = CGImageSourceCreateImageAtIndex(source, 0, nil),
       let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
        context.draw(image2, in: CGRect(x: 0, y: 0, width: image2.width, height: image2.height))
        check(context.data!.load(fromByteOffset: 3, as: UInt8.self) == 0, "背景が透明（左下の点）")
    }
    for (label, representations) in [("PNG だけ", [image.representations[1]]), ("PDF だけ", [image.representations[0]]), ("全部", image.representations)] {
        let capture = Capture(items: [representations])
        var read = capture
        read.latex = nil
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("pastephant-test-latex-\(UUID().uuidString)"))
        put([representations.map { ($0.type, $0.data) }], on: pasteboard)
        let captured = Capture.read(from: pasteboard)
        pasteboard.releaseGlobally()
        check(captured?.kind == .formula && captured?.latex == latex && captured?.plainText == latex.source, "\(label)のコピーから元の式を読む")
    }
case .failure(let error)?: check(false, "数式を描く（\(error)）")
case nil: check(false, "数式を描く（時間切れ）")
}
var broken: Result<LatexImage, Error>?
Task { @MainActor in
    do { broken = .success(try await LatexRenderer(resources: katex).render(LatexSource(source: "\\frac{a", options: LatexOptions()), macros: "")) } catch { broken = .failure(error) }
}
while broken == nil, Date() < deadline.addingTimeInterval(10) { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
if case .failure(let error)? = broken { check(error is LatexError, "書き方の誤りを知らせる（\(error)）") } else { check(false, "書き方の誤りを知らせる") }

// 14. 共有タグと Tomelet への書き出し（F-04・F-17）
let base = work.appendingPathComponent("base").path
try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
_ = try Dataset.create(base, datasetId: "テスト")
let exportTag = try store2.findOrCreateTag("書き出し")
try store2.addTag(exportTag, to: [wordID])
try store2.syncTags(basePath: base)
let tagsJSON = (try? JSONSerialization.jsonObject(with: Data(contentsOf: Dataset.tagsFile(base)))) as? [String: Any]
check((tagsJSON?["tags"] as? [[String: Any]])?.contains { $0["name"] as? String == "書き出し" } == true, "共有タグ（tags.json）に書き出す")
let exporter = TomeletExporter(schemaDirectory: schema.appendingPathComponent("tomelet"))
let exportTime = Date()
let memoID = try exporter.export([TomeletExporter.Item(clipID: safariID, copiedAt: exportTime, appName: "Safari", tags: ["書き出し"], text: "https://arxiv.org/abs/1234\n<b>", latex: nil, filePaths: [], ocrText: nil, image: (makePNG(width: 10, height: 10), "image/png"))], basePath: base, now: exportTime)
let again2 = try exporter.export([TomeletExporter.Item(clipID: wordID, copiedAt: exportTime, appName: "Word", tags: [], text: "2件目", latex: nil, filePaths: [], ocrText: nil, image: nil)], basePath: base, now: exportTime)
check(memoID == again2, "同じ日の書き出しは1つのメモに追記する")
try store2.markExported([wordID], at: exportTime)
let todayFormatter = DateFormatter()
todayFormatter.locale = Locale(identifier: "en_US_POSIX"); todayFormatter.calendar = Calendar(identifier: .gregorian); todayFormatter.dateFormat = "yyyy-MM-dd"
check(try store2.recent(query: "exported:\(todayFormatter.string(from: exportTime))").map(\.id) == [wordID] && (try store2.recent(query: "exported:2000-01-01")).isEmpty, "exported: でその日に残した物を絞り込む（Tomelet から開くとき）")
check(!FileManager.default.fileExists(atPath: Dataset.directory(base).appendingPathComponent("lock.json").path), "書き出し終えたら使用中の印を外す")
print("EXPORT_DB=\(Dataset.databasePath(base))")
print("EXPORT_MEMO=\(memoID)")
print("EXPORT_TITLE=\(TomeletExporter.title(for: exportTime))")

// 15. 貼り方（⇥）：項目の中身に合う物だけを並べる
func styleIDs(_ kind: ClipKind, _ context: TransformContext?, combos: [TransformCombo] = [], multiple: Bool = false) -> [String] {
    PasteStyle.styles(kind: kind, context: context, combos: combos, multiple: multiple).map(\.id)
}
check(styleIDs(.text, TransformContext(text: "ひとこと")) == ["original", "more"], "短い文字は「そのまま」と「ほかの変換」だけ")
check(styleIDs(.text, TransformContext(text: "これは、\n例です。")) == ["original", "joinLines", "toWesternPunctuation", "more"], "改行と句読点のある文章")
check(styleIDs(.richText, TransformContext(text: "名前\t値\na\t1")).starts(with: ["original", "plain", "joinLines", "tableToLatex", "tableToMarkdown", "tableToCSV"]), "表（タブ区切り）には表の変換を出す")
check(styleIDs(.file, TransformContext(filePaths: ["/Base/a.pdf"], basePath: "/Base")) == ["original", "pathAbsolute", "pathTilde", "pathRelative", "fileName", "fileURL", "more"], "ファイルにはパスの貼り方")
check(styleIDs(.image, TransformContext(ocrText: "文字")) == ["original", "ocrText"], "画像には画像の文字")
check(styleIDs(.formula, TransformContext(text: "\\frac{a}{b}")) == ["original", "plain"], "数式には LaTeX の式")
check(styleIDs(.text, TransformContext(text: "$x^2$")).contains("latexImage"), "LaTeX らしい文字には数式画像")
check(styleIDs(.text, TransformContext(text: "abc"), combos: [TransformCombo(name: "組", steps: [.uppercase])]).contains { $0.hasPrefix("combo-") }, "保存した組み合わせも並べる")
check(styleIDs(.text, TransformContext(text: "a"), multiple: true) == ["original", "plain", "joinLines"], "複数選んでいるときは文字をつなぐ貼り方だけ")

// 16. カードの色分け：PopNote! の tagColor と同じハッシュで、同じ名前にはいつも同じ色
check(Theme.paletteIndex(for: "com.apple.Safari") == 1, "PopNote! と同じハッシュで色を選ぶ")
check(Theme.paletteIndex(for: "論文") == Theme.paletteIndex(for: "論文") && (0..<Theme.palette.count).contains(Theme.paletteIndex(for: "🐘長い名前のアプリ")), "日本語・絵文字でも色が決まる")
let kindColors = Set(ClipKind.allCases.map { kind in ClipKind.allCases.firstIndex(of: kind)! % Theme.palette.count })
check(kindColors.count == ClipKind.allCases.count, "種類ごとの色は重ならない")

print(failures == 0 ? "すべて成功" : "\(failures) 件失敗")
exit(failures == 0 ? 0 : 1)
