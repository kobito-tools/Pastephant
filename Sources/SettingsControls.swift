import AppKit
import SwiftUI

// 設定の画面で使う部品。値は文字（#RRGGBB・bundle ID・タグの名前）で保存するが、画面では選んで決められるようにする。

/// タブの先頭に置く説明。
struct ExplainBox: View {
    let title: String
    let text: String
    var symbol = "info.circle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

extension Color {
    /// #RRGGBB にする（sRGB）。
    var hexString: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

/// 色を選ぶ（パレット・よく使う色・#RRGGBB の入力）。
struct HexColorField: View {
    @Binding var hex: String
    var swatches: [(String, String)] = [("#000000", "黒"), ("#FFFFFF", "白"), ("#3B4441", "墨"), ("#1F5FA8", "青"), ("#B3261E", "赤"), ("#2E7D32", "緑")]

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(get: { Color(hex: hex) }, set: { hex = $0.hexString }), supportsOpacity: false)
                .labelsHidden()
            ForEach(swatches, id: \.0) { color, name in
                Circle()
                    .fill(Color(hex: color))
                    .overlay(Circle().strokeBorder(hex.uppercased() == color ? Theme.accent : Color.secondary.opacity(0.35), lineWidth: hex.uppercased() == color ? 2.5 : 1))
                    .frame(width: 16, height: 16)
                    .help(name)
                    .onTapGesture { hex = color }
            }
            TextField("#RRGGBB", text: $hex).textFieldStyle(.roundedBorder).frame(width: 78).font(.system(size: 11, design: .monospaced))
        }
    }
}

/// 数式の描き方を、選んで決める。
struct LatexOptionsEditor: View {
    @Binding var options: LatexOptions

    private enum BackgroundChoice: String, CaseIterable { case clear = "透明", white = "白", black = "黒", custom = "色を選ぶ" }

    private var background: Binding<BackgroundChoice> {
        Binding(get: {
            switch options.background?.uppercased() {
            case nil: .clear
            case "#FFFFFF": .white
            case "#000000": .black
            default: .custom
            }
        }, set: { choice in
            switch choice {
            case .clear: options.background = nil
            case .white: options.background = "#FFFFFF"
            case .black: options.background = "#000000"
            case .custom: if options.background == nil || ["#FFFFFF", "#000000"].contains(options.background!.uppercased()) { options.background = "#F3F0E8" }
            }
        })
    }

    var body: some View {
        LabeledContent("文字色") { HexColorField(hex: $options.color) }
        LabeledContent("背景") {
            HStack {
                Picker("", selection: background) { ForEach(BackgroundChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                if background.wrappedValue == .custom {
                    ColorPicker("", selection: Binding(get: { Color(hex: options.background ?? "#FFFFFF") }, set: { options.background = $0.hexString }), supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
        LabeledContent("文字の大きさ") {
            HStack {
                Slider(value: $options.fontSize, in: 10...96, step: 2).frame(maxWidth: 220)
                Text("\(Int(options.fontSize))pt").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
        LabeledContent("周りの余白") {
            Stepper("\(Int(options.padding))pt", value: $options.padding, in: 0...40, step: 2).fixedSize()
        }
        LabeledContent("式の形") {
            Picker("", selection: $options.displayMode) {
                Text("ディスプレイ（独立した行の式）").tag(true)
                Text("文中（文章の中の式）").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }
}

/// 描き方の見本（同梱の KaTeX で実際に描く）。明るい文字色なら暗い地に置く。
struct LatexSample: View {
    let options: LatexOptions
    let macros: String
    var height: CGFloat = 64

    @MainActor private static let renderer = LatexRenderer()
    static let source = "\\int_0^1 f(x)\\,dx = \\frac{a+b}{2}"
    @State private var image: NSImage?
    @State private var error: String?

    private var darkTile: Bool {
        guard options.background == nil, let color = NSColor(hex: options.color).usingColorSpace(.sRGB) else { return false }
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent > 0.7
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(darkTile ? Color(hex: "#3B4441") : Color.white)
            if !darkTile { Checkerboard().clipShape(RoundedRectangle(cornerRadius: 8)) }
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(6)
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2).padding(6)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: height)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
        .task(id: LatexSource(source: macros, options: options)) {
            do {
                let rendered = try await Self.renderer.render(LatexSource(source: Self.source, options: options), macros: macros)
                image = NSImage(data: rendered.png)
                error = nil
            } catch { self.error = "\(error)" }
        }
    }
}

/// アプリを選ぶ（アプリケーションフォルダから）。bundle ID で保存し、アイコンと名前で表示する。
struct AppLabel: View {
    let bundleID: String

    var body: some View {
        HStack(spacing: 6) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                Text(bundleID).font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "app.dashed").frame(width: 18, height: 18).foregroundStyle(.secondary)
                Text(bundleID.isEmpty ? "（未選択）" : bundleID).foregroundStyle(bundleID.isEmpty ? .secondary : .primary)
            }
        }
    }

    /// アプリケーションフォルダからアプリを選んで、bundle ID を返す。
    @MainActor static func choose(multiple: Bool = false) -> [String] {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = multiple
        panel.message = "アプリを選んでください"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }
}

/// タグを1つ選ぶ（今あるタグから選ぶか、新しい名前を入力する）。
struct TagField: View {
    @Binding var tag: String
    let available: [String]

    var body: some View {
        HStack(spacing: 4) {
            Text("#").foregroundStyle(.secondary)
            TextField("タグ", text: $tag).textFieldStyle(.roundedBorder).frame(width: 120)
            Menu {
                if available.isEmpty { Text("まだタグがありません") }
                ForEach(available, id: \.self) { name in Button(name) { tag = name } }
            } label: { Image(systemName: "tag") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("今あるタグから選ぶ")
        }
    }
}

/// タグをいくつか選ぶ（丸い札で表示し、× で外す）。
struct TagChips: View {
    @Binding var tags: [String]
    let available: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tags.isEmpty {
                Text("まだ選んでいません").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text("#\(tag)").font(.system(size: 12, weight: .medium))
                            Button { tags.removeAll { $0 == tag } } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.borderless)
                        }
                        .foregroundStyle(Theme.color(for: tag))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.color(for: tag).opacity(0.15)))
                    }
                }
            }
            HStack {
                Menu("今あるタグから加える") {
                    let rest = available.filter { !tags.contains($0) }
                    if rest.isEmpty { Text("加えられるタグがありません") }
                    ForEach(rest, id: \.self) { name in Button(name) { tags.append(name) } }
                }
                .fixedSize()
                TextField("新しいタグの名前", text: $draft).textFieldStyle(.roundedBorder).frame(width: 150)
                Button("加える") {
                    let name = draft.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, !tags.contains(name) { tags.append(name) }
                    draft = ""
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
