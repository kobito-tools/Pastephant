import AppKit

/// 改行を消す（F-03・F-07）。PDFなどからコピーした文章を1つの段落に戻す。
///
/// - 日本語どうし（どちらかの端が日本語）の行はそのままつなぐ。英語どうしの行は半角スペースでつなぐ。
/// - 行末のハイフネーションを直す。つないだ語が辞書にあればハイフンを消し（inter-/national → international）、
///   無ければハイフンを残してつなぐ（well-/known → well-known）。
/// - keepParagraphs が true なら、空行（段落の区切り）は1つの空行として残す。
enum LineJoiner {
    static func join(_ text: String, keepParagraphs: Bool = true, isWord: (String) -> Bool = LineJoiner.isDictionaryWord) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var paragraphs: [[String]] = [[]]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !(paragraphs.last?.isEmpty ?? true) { paragraphs.append([]) }
            } else {
                paragraphs[paragraphs.count - 1].append(trimmed)
            }
        }
        let joined = paragraphs.filter { !$0.isEmpty }.map { joinLines($0, isWord: isWord) }
        // 段落の区切りも消すときは、段落どうしも行と同じ規則でつなぐ。
        return keepParagraphs ? joined.joined(separator: "\n\n") : joinLines(joined, isWord: isWord)
    }

    private static func joinLines(_ lines: [String], isWord: (String) -> Bool) -> String {
        var result = ""
        for line in lines {
            guard !result.isEmpty else { result = line; continue }
            result = append(line, to: result, isWord: isWord)
        }
        return result
    }

    private static func append(_ line: String, to result: String, isWord: (String) -> Bool) -> String {
        guard let last = result.last, let first = line.first else { return result + line }
        // 英字の後の行末ハイフンで、次の行が小文字から始まるとき。
        if last == "-", result.count >= 2, result.dropLast().last?.isLetter == true, first.isLowercase {
            let before = String(result.dropLast().reversed().prefix { $0.isLetter }.reversed())
            let after = String(line.prefix { $0.isLetter })
            if isWord(before + after) { return String(result.dropLast()) + line }
            return result + line
        }
        if isCJK(last) || isCJK(first) { return result + line }
        return result + " " + line
    }

    /// 日本語・中国語の文字と、全角の記号。
    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x303F, 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x2FA1F: true
            default: false
            }
        }
    }

    static func isDictionaryWord(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }
}
