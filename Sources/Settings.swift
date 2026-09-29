import Foundation

/// ショートカット（Carbon のキーコードと修飾キー）。
struct HotKeySetting: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int

    // Carbon の cmdKey・shiftKey・optionKey・controlKey と同じ値。
    static let command = 256, shift = 512, option = 2048, control = 4096

    static let openPanel = HotKeySetting(keyCode: 9, modifiers: command | option)    // ⌥⌘V
    static let toggleStack = HotKeySetting(keyCode: 8, modifiers: command | control) // ⌃⌘C

    var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "?")
    }

    static let keyNames: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        49: "Space", 36: "↩", 48: "⇥", 50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

/// コピー元のアプリやリンクのドメインで、自動でタグを付ける規則（F-04）。
struct AutoTagRule: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case app, domain }
    var id = UUID().uuidString
    var kind: Kind
    /// app ならアプリの bundle ID か名前、domain ならドメイン（example.com なら sub.example.com も含む）。
    var pattern: String
    var tag: String
}

/// このMacの設定（~/Library/Application Support/Pastephant/settings.json）。
/// 項目が足りない古いファイルでも読めるよう、無い項目は初期値にする。
struct Settings: Codable, Equatable {
    enum Edge: String, Codable { case right, left }
    enum PanelScreen: String, Codable { case mouse, main }

    var panelEdge: Edge = .right
    var panelWidth: Double = 400
    var panelScreen: PanelScreen = .mouse
    /// 選んだ・カーソルを当てた項目の中身を、パネルの上部に出すか。
    var showPreview = true
    /// 一覧のカードの色分け。
    var rowColorMode: RowColorMode = .app
    /// パネルの縁にしがみつく小人を出すか。
    var showKobito = true
    var openPanelHotKey = HotKeySetting.openPanel
    var stackHotKey = HotKeySetting.toggleStack
    var sortOrder: SortOrder = .lastUsed
    /// 貼ったあと、貼る前のクリップボードに戻すか（F-03）。
    var restoreClipboardAfterPaste = false
    /// 改行を消すとき、空行（段落の区切り）を残すか（F-07）。
    var keepParagraphBreaks = true
    /// 取得しないアプリ（F-02）。
    var excludedBundleIDs: [String] = Settings.defaultExcludedBundleIDs
    var autoTagRules: [AutoTagRule] = []
    /// 種類ごとの保存日数。無い種類は無期限（F-15）。
    var retentionDays: [String: Int] = ["image": 30, "office": 30, "file": 90]
    var maxItems = 50_000
    var maxTotalBytes = 5 * 1024 * 1024 * 1024
    var maxItemBytes = 100 * 1024 * 1024
    /// タグの付いた項目も期限で消すか。
    var expireTagged = false
    var transformCombos: [TransformCombo] = []
    var latexPresets: [LatexPreset] = LatexPreset.defaults
    /// 最後に使った数式の描き方。
    var latexOptions = LatexOptions()
    /// 全ての式の前に付ける \newcommand など。
    var latexMacros = ""
    /// ペーストスタックを積んだ逆の順（新しい物から）に貼るか（F-14）。
    var reverseStack = false
    /// 共有タグと Tomelet への書き出しに使う基準パス（任意）。
    var basePath: String?
    /// このタグが付いたら、Tomelet へ自動で書き出す（F-17）。
    var autoExportTags: [String] = []

    static let defaultExcludedBundleIDs = [
        "com.apple.keychainaccess", "com.apple.Passwords",
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "com.dashlane.Dashlane", "in.sinew.Enpass-Desktop",
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var s = Settings()
        func read<T: Decodable>(_ key: CodingKeys, _ target: inout T) { if let value = try? c.decode(T.self, forKey: key) { target = value } }
        read(.panelEdge, &s.panelEdge); read(.panelWidth, &s.panelWidth); read(.panelScreen, &s.panelScreen); read(.showPreview, &s.showPreview); read(.rowColorMode, &s.rowColorMode); read(.showKobito, &s.showKobito)
        read(.openPanelHotKey, &s.openPanelHotKey); read(.stackHotKey, &s.stackHotKey); read(.sortOrder, &s.sortOrder)
        read(.restoreClipboardAfterPaste, &s.restoreClipboardAfterPaste); read(.keepParagraphBreaks, &s.keepParagraphBreaks)
        read(.excludedBundleIDs, &s.excludedBundleIDs); read(.autoTagRules, &s.autoTagRules)
        read(.retentionDays, &s.retentionDays); read(.maxItems, &s.maxItems); read(.maxTotalBytes, &s.maxTotalBytes); read(.maxItemBytes, &s.maxItemBytes)
        read(.expireTagged, &s.expireTagged); read(.transformCombos, &s.transformCombos)
        read(.latexPresets, &s.latexPresets); read(.latexOptions, &s.latexOptions); read(.latexMacros, &s.latexMacros)
        read(.reverseStack, &s.reverseStack); read(.autoExportTags, &s.autoExportTags)
        s.basePath = try? c.decode(String.self, forKey: .basePath)
        self = s
    }

    static func load(from url: URL) -> Settings {
        guard let data = try? Data(contentsOf: url), let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }

    func save(to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// コピー元のアプリとテキストから、自動で付けるタグの名前。
    func autoTags(bundleID: String?, appName: String?, text: String?) -> [String] {
        var tags: [String] = []
        let hosts = text.map(Self.hosts(in:)) ?? []
        for rule in autoTagRules where !rule.tag.isEmpty && !rule.pattern.isEmpty && !tags.contains(rule.tag) {
            let pattern = rule.pattern.lowercased()
            switch rule.kind {
            case .app:
                if bundleID?.lowercased() == pattern || appName?.lowercased() == pattern { tags.append(rule.tag) }
            case .domain:
                if hosts.contains(where: { $0 == pattern || $0.hasSuffix("." + pattern) }) { tags.append(rule.tag) }
            }
        }
        return tags
    }

    /// テキストに含まれる URL のホスト名（小文字）。
    static func hosts(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let sample = String(text.prefix(20_000))
        return detector.matches(in: sample, range: NSRange(sample.startIndex..., in: sample)).compactMap { $0.url?.host?.lowercased() }
    }
}
