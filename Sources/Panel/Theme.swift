import AppKit
import SwiftUI

/// パネルの色（kobito-tools シリーズの小人と同じ墨色・紙の色、アイコンの青みがかった灰色）。明るい画面と暗い画面の両方を持つ。
enum Theme {
    private static func dynamic(_ light: String, _ dark: String, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(hex: hex, alpha: alpha)
        })
    }

    /// アクセント（アイコンの背景の色）。
    static let accent = dynamic("#5F7A90", "#9DB4C6")
    /// パネルの地（紙の色）。すりガラスの上に重ねる。
    static let paper = dynamic("#F3F0E8", "#262B2A", alpha: 0.94)
    /// カード。
    static let card = dynamic("#FFFFFF", "#333A39")
    static let cardBorder = dynamic("#E0DBCF", "#454D4B")
    /// プレビューの枠の中。
    static let well = dynamic("#FBFAF6", "#2D3332")
    static let wellBorder = dynamic("#D3CCBC", "#56605D")
    /// 文字（小人の墨色）。
    static let ink = dynamic("#3B4441", "#E6E3D9")
    static let subtle = dynamic("#7A817D", "#A3A9A5")
    /// キーの印の地。
    static let keycap = dynamic("#E8E3D7", "#3E4644")

    /// 色分けに使う色（PopNote! のタグの色と同じ並び）。
    static let palette = ["#477B70", "#C75543", "#9B7432", "#5C668F", "#7B587D", "#416B7C", "#8A6A4F", "#6D7A45"]

    /// PopNote! の tagColor と同じハッシュ（hash = hash * 31 + 文字のコード）で、同じ名前にはいつも同じ色を返す。
    static func paletteIndex(for key: String) -> Int {
        var hash: UInt32 = 0
        for scalar in key.unicodeScalars { hash = hash &* 31 &+ scalar.value }
        return Int(hash % UInt32(palette.count))
    }

    static func color(for key: String) -> Color { Color(nsColor: NSColor(hex: palette[paletteIndex(for: key)])) }
}

/// 一覧のカードの色分け（設定で選ぶ）。
enum RowColorMode: String, Codable, CaseIterable {
    case app, kind, tag, none

    var label: String {
        switch self {
        case .app: "コピー元のアプリごと"
        case .kind: "種類ごと"
        case .tag: "最初のタグごと"
        case .none: "色分けしない"
        }
    }

    /// 色を決める名前。nil なら色を付けない。
    func key(for clip: ClipSummary) -> String? {
        switch self {
        case .app: clip.isSnippet ? "定型文" : (clip.sourceBundleID ?? clip.sourceAppName)
        case .kind: clip.isSnippet ? "snippet" : clip.kind.rawValue
        case .tag: clip.tags.first
        case .none: nil
        }
    }

    func color(for clip: ClipSummary) -> Color? {
        guard let key = key(for: clip) else { return nil }
        if self == .kind {
            // 種類は数が決まっているので、重ならないよう順に色を割り当てる。
            let order = ClipKind.allCases.map(\.rawValue) + ["snippet"]
            return Color(nsColor: NSColor(hex: Theme.palette[(order.firstIndex(of: key) ?? 0) % Theme.palette.count]))
        }
        return Theme.color(for: key)
    }
}

extension NSColor {
    /// #RRGGBB から作る。
    convenience init(hex: String, alpha: CGFloat = 1) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
}
