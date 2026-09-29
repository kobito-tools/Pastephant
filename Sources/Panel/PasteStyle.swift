import Foundation

/// 貼り方。選んだ項目の中身に合う物だけを並べ、⇥ で切り替える。⏎ はいつも、いま選んでいる貼り方で貼る。
struct PasteStyle: Identifiable, Equatable {
    enum Action: Equatable {
        /// 元の形（Paster.Mode で貼る）。
        case mode(Paster.Mode)
        /// 変換してから貼る。
        case transform([TransformKind])
        /// 数式画像の画面を開く。
        case latexImage
        /// 変換を選ぶ画面を開く（つなげる・保存する）。
        case moreTransforms
    }

    let id: String
    let label: String
    let symbol: String
    let action: Action

    /// 選んだ項目に合う貼り方。最初はいつも「元の形」。
    static func styles(kind: ClipKind, context: TransformContext?, combos: [TransformCombo], multiple: Bool) -> [PasteStyle] {
        var styles = [PasteStyle(id: "original", label: originalLabel(kind), symbol: kind.symbolName, action: .mode(.original))]
        let text = context?.text
        if multiple {
            // 複数選んでいるときは、文字をつないで貼るものだけ。
            styles.append(PasteStyle(id: "plain", label: "プレーン", symbol: "textformat.size", action: .mode(.plainText)))
            styles.append(PasteStyle(id: "joinLines", label: "改行を消す", symbol: "arrow.right.to.line", action: .mode(.joinLines)))
            return styles
        }
        if let files = context?.filePaths, !files.isEmpty {
            styles.append(PasteStyle(id: "pathAbsolute", label: "パス", symbol: "folder", action: .transform([.pathAbsolute])))
            styles.append(PasteStyle(id: "pathTilde", label: "~ のパス", symbol: "house", action: .transform([.pathTilde])))
            if let base = context?.basePath, files.contains(where: { $0.hasPrefix(base.hasSuffix("/") ? base : base + "/") }) {
                styles.append(PasteStyle(id: "pathRelative", label: "基準パスから", symbol: "arrow.turn.down.right", action: .transform([.pathRelative])))
            }
            styles.append(PasteStyle(id: "fileName", label: "ファイル名", symbol: "doc.text", action: .transform([.fileName])))
            styles.append(PasteStyle(id: "fileURL", label: "file://", symbol: "link", action: .transform([.fileURL])))
            return styles + [more]
        }
        if let ocr = context?.ocrText, !ocr.isEmpty, text == nil {
            styles.append(PasteStyle(id: "ocrText", label: "画像の文字", symbol: "text.viewfinder", action: .transform([.ocrText])))
        }
        guard let text, !text.isEmpty else { return styles }
        if kind == .formula {
            styles.append(PasteStyle(id: "plain", label: "LaTeX の式", symbol: "chevron.left.forwardslash.chevron.right", action: .mode(.plainText)))
            return styles
        }
        if kind != .text { styles.append(PasteStyle(id: "plain", label: "プレーン", symbol: "textformat.size", action: .mode(.plainText))) }
        if text.contains("\n") { styles.append(PasteStyle(id: "joinLines", label: "改行を消す", symbol: "arrow.right.to.line", action: .mode(.joinLines))) }
        if isTable(text: text, html: context?.html) {
            styles.append(PasteStyle(id: "tableToLatex", label: "表 → LaTeX", symbol: "tablecells", action: .transform([.tableToLatex])))
            styles.append(PasteStyle(id: "tableToMarkdown", label: "表 → Markdown", symbol: "tablecells", action: .transform([.tableToMarkdown])))
            styles.append(PasteStyle(id: "tableToCSV", label: "表 → CSV", symbol: "tablecells", action: .transform([.tableToCSV])))
        }
        if text.contains("、") || text.contains("。") {
            styles.append(PasteStyle(id: "toWesternPunctuation", label: "「，．」に", symbol: "textformat.abc", action: .transform([.toWesternPunctuation])))
        } else if text.contains("，") || text.contains("．") {
            styles.append(PasteStyle(id: "toJapanesePunctuation", label: "「、。」に", symbol: "textformat.abc", action: .transform([.toJapanesePunctuation])))
        }
        if text.unicodeScalars.contains(where: { (0xFF01...0xFF5E).contains($0.value) }) {
            styles.append(PasteStyle(id: "halfWidthAlphanumerics", label: "半角英数に", symbol: "character", action: .transform([.halfWidthAlphanumerics])))
        }
        if LatexSource.looksLikeLatex(text) {
            styles.append(PasteStyle(id: "latexImage", label: "数式画像に", symbol: "function", action: .latexImage))
        }
        for combo in combos where combo.steps.allSatisfy({ $0.input == .text }) {
            styles.append(PasteStyle(id: "combo-\(combo.id)", label: "★ \(combo.name)", symbol: "star", action: .transform(combo.steps)))
        }
        return styles + [more]
    }

    static let more = PasteStyle(id: "more", label: "ほかの変換…", symbol: "ellipsis.circle", action: .moreTransforms)

    static func originalLabel(_ kind: ClipKind) -> String {
        switch kind {
        case .text: "そのまま"
        case .richText: "書式付き"
        case .image: "画像"
        case .file: "ファイル"
        case .url: "リンク"
        case .color: "色"
        case .office: "オブジェクト"
        case .formula: "数式画像"
        }
    }

    /// タブ区切りの行が2行以上ある（Excel などのコピー）か、HTML の表がある。
    static func isTable(text: String, html: String?) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        if lines.count >= 2, lines.filter({ $0.contains("\t") }).count >= 2 { return true }
        return html?.range(of: "<table", options: .caseInsensitive) != nil
    }
}

/// 項目にできること。→ か ⌘K で開く一覧に、1文字のキーと一緒に並べる。
struct PanelAction: Identifiable {
    let id: String
    /// 一覧を開いているときに押す1文字。
    let key: Character
    let label: String
    let symbol: String
    /// 一覧を開かずに使えるショートカット（覚えた人向けに、横に小さく出す）。
    let shortcut: String?
    let run: () -> Void
}
