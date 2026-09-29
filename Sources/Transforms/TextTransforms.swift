import Foundation

/// 貼る前の変換（F-07）とファイルのパス（F-12）。いくつかを続けてかけられる。
enum TransformKind: String, Codable, CaseIterable, Identifiable {
    case joinLines, toWesternPunctuation, toJapanesePunctuation, halfWidthAlphanumerics, fullWidthKatakana, trimSpaces
    case uppercase, lowercase, sentenceCase
    case tableToLatex, tableToMarkdown, tableToCSV
    case quote, bulletHyphen, bulletDot, numbered
    case ocrText
    case pathAbsolute, pathTilde, pathRelative, fileName, fileURL
    case latexImage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .joinLines: "改行を消す"
        case .toWesternPunctuation: "句読点を「，．」に"
        case .toJapanesePunctuation: "句読点を「、。」に"
        case .halfWidthAlphanumerics: "英数字・記号を半角に"
        case .fullWidthKatakana: "半角カタカナを全角に"
        case .trimSpaces: "余分な空白を消す"
        case .uppercase: "大文字に"
        case .lowercase: "小文字に"
        case .sentenceCase: "文の先頭だけ大文字に"
        case .tableToLatex: "表を LaTeX の tabular に"
        case .tableToMarkdown: "表を Markdown に"
        case .tableToCSV: "表を CSV に"
        case .quote: "引用（> ）にする"
        case .bulletHyphen: "箇条書き（- ）にする"
        case .bulletDot: "箇条書き（・）にする"
        case .numbered: "番号付き（1. ）にする"
        case .ocrText: "画像の文字をテキストで"
        case .pathAbsolute: "パス（絶対パス）"
        case .pathTilde: "パス（~ から）"
        case .pathRelative: "パス（基準パスから）"
        case .fileName: "ファイル名だけ"
        case .fileURL: "file:// の URL"
        case .latexImage: "数式画像にする"
        }
    }

    enum Input { case text, files, ocr, latex }

    var input: Input {
        switch self {
        case .ocrText: .ocr
        case .pathAbsolute, .pathTilde, .pathRelative, .fileName, .fileURL: .files
        case .latexImage: .latex
        default: .text
        }
    }

    /// 続けてかけられるか（文字を受けて文字を返すもの）。
    var chainable: Bool { input == .text }
}

/// 名前を付けて保存した変換の組み合わせ。パネルで ⌃1〜⌃9 に割り当てる。
struct TransformCombo: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var steps: [TransformKind]
}

/// 変換にかける材料。
struct TransformContext {
    var text: String?
    var html: String?
    var filePaths: [String] = []
    var ocrText: String?
    var basePath: String?
    var keepParagraphs = true
}

enum TextTransforms {
    /// 最初の変換の材料を選び、順にかける。かけられなければ nil。
    static func apply(_ steps: [TransformKind], to context: TransformContext) -> String? {
        guard let first = steps.first else { return context.text }
        var value: String
        switch first.input {
        case .files:
            guard !context.filePaths.isEmpty else { return nil }
            value = paths(context.filePaths, first, basePath: context.basePath)
        case .ocr:
            guard let ocr = context.ocrText, !ocr.isEmpty else { return nil }
            value = ocr
        case .latex:
            return nil
        case .text:
            guard let text = context.text else { return nil }
            value = text
            if first.rawValue.hasPrefix("table"), let html = context.html, !text.contains("\t"), let rows = htmlTableRows(html) {
                value = rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            }
            value = apply(first, value, context)
        }
        for step in steps.dropFirst() where step.chainable { value = apply(step, value, context) }
        return value
    }

    static func apply(_ kind: TransformKind, _ text: String, _ context: TransformContext = TransformContext()) -> String {
        switch kind {
        case .joinLines: return LineJoiner.join(text, keepParagraphs: context.keepParagraphs)
        case .toWesternPunctuation: return text.replacingOccurrences(of: "、", with: "，").replacingOccurrences(of: "。", with: "．")
        case .toJapanesePunctuation: return text.replacingOccurrences(of: "，", with: "、").replacingOccurrences(of: "．", with: "。")
        case .halfWidthAlphanumerics: return halfWidthAlphanumerics(text)
        case .fullWidthKatakana: return fullWidthKatakana(text)
        case .trimSpaces: return trimSpaces(text)
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .sentenceCase: return sentenceCase(text)
        case .tableToLatex: return latexTable(tableRows(text))
        case .tableToMarkdown: return markdownTable(tableRows(text))
        case .tableToCSV: return csv(tableRows(text))
        case .quote: return prefixLines(text) { _ in "> " }
        case .bulletHyphen: return prefixLines(text) { _ in "- " }
        case .bulletDot: return prefixLines(text) { _ in "・" }
        case .numbered: return prefixLines(text) { "\($0 + 1). " }
        case .ocrText, .pathAbsolute, .pathTilde, .pathRelative, .fileName, .fileURL, .latexImage: return text
        }
    }

    // MARK: - 文字

    /// 全角の英数字・記号（！〜～）と全角スペースを半角に。カタカナはそのまま。
    static func halfWidthAlphanumerics(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar -> Unicode.Scalar in
            switch scalar.value {
            case 0xFF01...0xFF5E: return Unicode.Scalar(scalar.value - 0xFEE0)!
            case 0x3000: return " "
            default: return scalar
            }
        }))
    }

    /// 半角カタカナ（濁点の結合を含む）だけを全角に。英数字はそのまま。
    static func fullWidthKatakana(_ text: String) -> String {
        var result = "", run = ""
        func flush() {
            guard !run.isEmpty else { return }
            result += run.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? run
            run = ""
        }
        for character in text {
            if character.unicodeScalars.allSatisfy({ (0xFF61...0xFF9F).contains($0.value) }) { run.append(character) } else { flush(); result.append(character) }
        }
        flush()
        return result
    }

    /// 行頭・行末の空白と、続いた空白を1つにする。空行は残す。
    static func trimSpaces(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{3000}" }).joined(separator: " ")
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 文の先頭（文字列の最初と「. ! ?」の後）だけを大文字にし、ほかは小文字にする。
    static func sentenceCase(_ text: String) -> String {
        var result = "", capitalizeNext = true
        for character in text.lowercased() {
            if capitalizeNext, character.isLetter { result += character.uppercased(); capitalizeNext = false; continue }
            result.append(character)
            if ".!?。！？".contains(character) || character == "\n" { capitalizeNext = true }
        }
        return result
    }

    private static func prefixLines(_ text: String, _ prefix: (Int) -> String) -> String {
        var index = 0
        return text.components(separatedBy: "\n").map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            defer { index += 1 }
            return prefix(index) + line
        }.joined(separator: "\n")
    }

    // MARK: - 表

    /// タブ区切り（Excel・Numbers のコピー）を行と列に分ける。
    static func tableRows(_ text: String) -> [[String]] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        let rows = lines.filter { !$0.isEmpty }.map { line in line.contains("\t") ? line.components(separatedBy: "\t") : [line] }
        let width = rows.map(\.count).max() ?? 0
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    /// HTML の <table> から行と列を取り出す（タブ区切りの無いコピー向け）。
    static func htmlTableRows(_ html: String) -> [[String]]? {
        guard html.range(of: "<table", options: .caseInsensitive) != nil else { return nil }
        func text(_ fragment: String) -> String {
            let stripped = fragment.replacingOccurrences(of: "<br[^>]*>", with: " ", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let decoded = stripped.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let rowPattern = try! NSRegularExpression(pattern: "<tr[^>]*>(.*?)</tr>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let cellPattern = try! NSRegularExpression(pattern: "<t[dh][^>]*>(.*?)</t[dh]>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let source = html as NSString
        let rows = rowPattern.matches(in: html, range: NSRange(location: 0, length: source.length)).map { row -> [String] in
            let inner = source.substring(with: row.range(at: 1)) as NSString
            return cellPattern.matches(in: inner as String, range: NSRange(location: 0, length: inner.length)).map { text(inner.substring(with: $0.range(at: 1))) }
        }.filter { !$0.isEmpty }
        return rows.isEmpty ? nil : rows
    }

    static func latexEscape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "\\": result += "\\textbackslash{}"
            case "&", "%", "$", "#", "_", "{", "}": result += "\\\(character)"
            case "~": result += "\\textasciitilde{}"
            case "^": result += "\\textasciicircum{}"
            default: result.append(character)
            }
        }
        return result
    }

    /// 1行目を見出しとして罫線で区切る。
    static func latexTable(_ rows: [[String]]) -> String {
        guard let first = rows.first else { return "" }
        var lines = ["\\begin{tabular}{\(String(repeating: "l", count: first.count))}", "\\hline"]
        for (index, row) in rows.enumerated() {
            lines.append(row.map(latexEscape).joined(separator: " & ") + " \\\\")
            if index == 0 { lines.append("\\hline") }
        }
        lines += ["\\hline", "\\end{tabular}"]
        return lines.joined(separator: "\n")
    }

    static func markdownTable(_ rows: [[String]]) -> String {
        guard let first = rows.first else { return "" }
        let escape = { (cell: String) in cell.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
        var lines = ["| " + first.map(escape).joined(separator: " | ") + " |", "|" + Array(repeating: " --- |", count: first.count).joined()]
        lines += rows.dropFirst().map { "| " + $0.map(escape).joined(separator: " | ") + " |" }
        return lines.joined(separator: "\n")
    }

    static func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { cell in
                cell.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : cell
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    // MARK: - ファイルのパス（F-12）

    static func paths(_ paths: [String], _ kind: TransformKind, basePath: String?) -> String {
        let home = NSHomeDirectory()
        return paths.map { path -> String in
            switch kind {
            case .pathTilde: return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
            case .pathRelative:
                guard let basePath, !basePath.isEmpty else { return path }
                let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
                return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
            case .fileName: return (path as NSString).lastPathComponent
            case .fileURL: return URL(fileURLWithPath: path).absoluteString
            default: return path
            }
        }.joined(separator: "\n")
    }
}

/// 複数の項目を1つにまとめるときの区切り（F-11）。
enum MergeSeparator: String, CaseIterable, Identifiable {
    case newline, blankLine, comma, japaneseComma, tab, space, none, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newline: "改行"
        case .blankLine: "空行"
        case .comma: "カンマ（, ）"
        case .japaneseComma: "読点（、）"
        case .tab: "タブ"
        case .space: "空白"
        case .none: "区切りなし"
        case .custom: "任意の文字列"
        }
    }

    func separator(custom: String) -> String {
        switch self {
        case .newline: "\n"
        case .blankLine: "\n\n"
        case .comma: ", "
        case .japaneseComma: "、"
        case .tab: "\t"
        case .space: " "
        case .none: ""
        case .custom: custom.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
        }
    }
}

/// 定型文の差し込み（F-09）：{date}・{date:書式}・{time}・{clipboard}・{cursor}。
enum SnippetExpander {
    struct Result: Equatable {
        let text: String
        /// {cursor} の位置から末尾までの文字数。貼ったあと、この数だけ ← を送る。
        let cursorOffsetFromEnd: Int?
    }

    static func expand(_ template: String, clipboard: String?, now: Date = Date()) -> Result {
        let pattern = try! NSRegularExpression(pattern: "\\{(date|time|clipboard|cursor)(?::([^}]*))?\\}")
        let source = template as NSString
        var output = "", location = 0, cursor: Int?
        for match in pattern.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: location, length: match.range.location - location))
            location = match.range.location + match.range.length
            let name = source.substring(with: match.range(at: 1))
            let argument = match.range(at: 2).location == NSNotFound ? nil : source.substring(with: match.range(at: 2))
            switch name {
            case "date", "time":
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ja_JP")
                formatter.dateFormat = argument ?? (name == "date" ? "yyyy/MM/dd" : "HH:mm")
                output += formatter.string(from: now)
            case "clipboard": output += clipboard ?? ""
            default: if cursor == nil { cursor = output.count }
            }
        }
        output += source.substring(from: location)
        return Result(text: output, cursorOffsetFromEnd: cursor.map { output.count - $0 })
    }
}
