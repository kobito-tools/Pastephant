import Foundation

/// 数式画像の描き方（F-06）。
struct LatexOptions: Codable, Equatable {
    /// 文字色（#RRGGBB）。
    var color = "#000000"
    /// 文字の大きさ（pt）。
    var fontSize = 24.0
    /// 背景色（#RRGGBB）。nil なら透明。
    var background: String? = nil
    /// ディスプレイ数式（true）か、文中の数式（false）か。
    var displayMode = true
    /// 周りの余白（pt）。
    var padding = 4.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LatexOptions()
        color = (try? c.decode(String.self, forKey: .color)) ?? d.color
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? d.fontSize
        background = try? c.decode(String.self, forKey: .background)
        displayMode = (try? c.decode(Bool.self, forKey: .displayMode)) ?? d.displayMode
        padding = (try? c.decode(Double.self, forKey: .padding)) ?? d.padding
    }
}

/// よく使う描き方に名前を付けたもの。
struct LatexPreset: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var options: LatexOptions

    static let defaults = [
        LatexPreset(id: "default", name: "標準（黒・透明）", options: LatexOptions()),
        LatexPreset(id: "dark-slide", name: "暗いスライド用（白文字）", options: { var options = LatexOptions(); options.color = "#FFFFFF"; return options }()),
        LatexPreset(id: "white-background", name: "白い背景", options: { var options = LatexOptions(); options.background = "#FFFFFF"; options.padding = 8; return options }()),
    ]
}

/// 数式の元の式と描き方。画像に埋め込み、履歴から開き直せるようにする。
struct LatexSource: Codable, Equatable {
    var source: String
    var options: LatexOptions

    /// PNG の説明や PDF のキーワードに入れるときの目印。
    static let marker = "pastephant-latex:"

    var json: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "{}" }

    init(source: String, options: LatexOptions) {
        self.source = source
        self.options = options
    }

    init?(json: String) {
        guard let data = json.data(using: .utf8), let value = try? JSONDecoder().decode(LatexSource.self, from: data) else { return nil }
        self = value
    }

    /// 画像に埋め込む文字列（目印 ＋ JSON を Base64 にしたもの）。
    var embedded: String { Self.marker + Data(json.utf8).base64EncodedString() }

    init?(embedded: String) {
        guard let range = embedded.range(of: Self.marker) else { return nil }
        let encoded = embedded[range.upperBound...].prefix { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(encoded)), let json = String(data: data, encoding: .utf8) else { return nil }
        self.init(json: json)
    }

    /// 文字が LaTeX の式に見えるか（$…$、\[…\]、\frac など）。
    static func looksLikeLatex(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 5000 else { return false }
        if (trimmed.hasPrefix("$") && trimmed.hasSuffix("$") && trimmed.count > 2) || (trimmed.hasPrefix("\\[") && trimmed.hasSuffix("\\]")) || (trimmed.hasPrefix("\\(") && trimmed.hasSuffix("\\)")) { return true }
        return trimmed.range(of: "\\\\(frac|sum|int|sqrt|alpha|beta|gamma|theta|lambda|mu|sigma|pi|begin|left|right|mathrm|mathbf|cdot|times|infty|partial|nabla|hat|bar|vec)\\b", options: .regularExpression) != nil
            || trimmed.range(of: "[_^]\\{", options: .regularExpression) != nil
    }

    /// $…$ などの囲みを外した式。
    static func stripDelimiters(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)"), ("$", "$")] where value.hasPrefix(open) && value.hasSuffix(close) && value.count >= open.count + close.count {
            value = String(value.dropFirst(open.count).dropLast(close.count))
            break
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
