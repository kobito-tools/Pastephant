import AppKit
import SwiftUI

/// パネルの上部に出す作業の画面。
struct ModeView: View {
    @ObservedObject var model: PanelModel
    var focused: FocusState<PanelModel.Field?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.mode {
            case .actions: actionsList
            case .tags: tags
            case .edit: edit
            case .transform: transform
            case .merge: merge
            case .latex: latex
            case .snippet: snippet
            case .help: help
            case .list: EmptyView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func title(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 13, weight: .semibold))
    }

    // MARK: - 操作の一覧

    private var actionsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            title(model.targets.count > 1 ? "\(model.targets.count)件にできること" : "この項目にできること", "bolt")
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                            HStack(spacing: 10) {
                                Text(String(action.key).uppercased())
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .frame(width: 22, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                                Image(systemName: action.symbol).frame(width: 18).foregroundStyle(.secondary)
                                Text(action.label).font(.system(size: 13))
                                Spacer()
                                if let shortcut = action.shortcut {
                                    Text(shortcut).font(.system(size: 11)).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(index == model.actionIndex ? Theme.accent.opacity(0.25) : Color.clear))
                            .contentShape(Rectangle())
                            .id(action.id)
                            .onTapGesture { action.run() }
                        }
                    }
                }
                .onChange(of: model.actionIndex) { index in
                    if model.actions.indices.contains(index) { proxy.scrollTo(model.actions[index].id) }
                }
            }
        }
    }

    // MARK: - タグ（F-04）

    private var tags: some View {
        VStack(alignment: .leading, spacing: 8) {
            title(model.targets.count > 1 ? "タグ（\(model.targets.count)件に付ける）" : "タグ", "tag")
            if !model.targetTags.isEmpty {
                FlowTags(tags: model.targetTags) { model.removeTag($0) }
            }
            TextField("タグの名前", text: $model.tagInput)
                .textFieldStyle(.roundedBorder)
                .focused(focused, equals: .tag)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.tagSuggestions.enumerated()), id: \.element.id) { index, tag in
                        Text("#\(tag.name)")
                            .font(.system(size: 13))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(index == model.tagSuggestionIndex ? Theme.accent.opacity(0.25) : Color.clear))
                            .contentShape(Rectangle())
                            .onTapGesture { model.tagSuggestionIndex = index; model.commitTag() }
                    }
                    if model.tagSuggestions.isEmpty, !model.tagInput.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("⏎ で「\(model.tagInput.trimmingCharacters(in: .whitespaces))」を新しいタグとして作ります")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    // MARK: - 貼る前に編集（F-10）

    private var edit: some View {
        VStack(alignment: .leading, spacing: 8) {
            title("貼る前に編集", "pencil")
            TextEditor(text: $model.editText)
                .font(.system(size: 13))
                .focused(focused, equals: .edit)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
        }
    }

    // MARK: - 変換（F-07）

    private var transform: some View {
        VStack(alignment: .leading, spacing: 8) {
            title("変換してから貼る", "wand.and.stars")
            if !model.chain.isEmpty {
                Text("つなげた変換：" + model.chain.map(\.label).joined(separator: " → "))
                    .font(.system(size: 11)).foregroundStyle(Theme.accent).lineLimit(2)
            }
            HStack(alignment: .top, spacing: 8) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(model.transformEntries.enumerated()), id: \.element.id) { index, entry in
                                Text(entry.label)
                                    .font(.system(size: 12, weight: entry.isCombo ? .semibold : .regular))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(index == model.transformIndex ? Theme.accent.opacity(0.25) : Color.clear))
                                    .contentShape(Rectangle())
                                    .id(entry.id)
                                    .onTapGesture { model.transformIndex = index }
                                    .onTapGesture(count: 2) { model.transformIndex = index; model.commitTransform(copyOnly: false) }
                            }
                        }
                    }
                    .onChange(of: model.transformIndex) { index in
                        if model.transformEntries.indices.contains(index) { proxy.scrollTo(model.transformEntries[index].id) }
                    }
                }
                .frame(width: 170)
                ScrollView {
                    Text(model.transformPreview ?? "（この変換はかけられません）")
                        .font(.system(size: 12))
                        .foregroundStyle(model.transformPreview == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(6)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
        }
    }

    // MARK: - まとめる（F-11）

    private var merge: some View {
        VStack(alignment: .leading, spacing: 8) {
            title("\(model.multi.count)件を1つにまとめる", "square.stack.3d.up")
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(MergeSeparator.allCases) { separator in
                        Text(separator.label)
                            .font(.system(size: 12))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 5).fill(separator == model.mergeSeparator ? Theme.accent.opacity(0.25) : Color.clear))
                            .contentShape(Rectangle())
                            .onTapGesture { model.mergeSeparator = separator; if separator == .custom { model.requestFocus(.mergeCustom) } }
                    }
                    if model.mergeSeparator == .custom {
                        TextField("区切り（\\n で改行）", text: $model.mergeCustom)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .focused(focused, equals: .mergeCustom)
                    }
                }
                .frame(width: 150)
                ScrollView {
                    Text(model.mergePreview)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(6)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
        }
    }

    // MARK: - 数式（F-06）

    private static let swatches: [(String, String)] = [("#000000", "黒"), ("#FFFFFF", "白"), ("#3B4441", "墨"), ("#1F5FA8", "青"), ("#B3261E", "赤"), ("#2E7D32", "緑")]

    private var latex: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                title("数式画像", "function")
                Spacer()
                Menu("描き方") {
                    ForEach(model.settings().latexPresets) { preset in
                        Button(preset.name) { model.applyPreset(preset) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            TextEditor(text: $model.latexSource)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 64)
                .focused(focused, equals: .latex)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            HStack(spacing: 10) {
                Picker("", selection: $model.latexOptions.displayMode) {
                    Text("ディスプレイ").tag(true)
                    Text("文中").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Stepper("\(Int(model.latexOptions.fontSize))pt", value: $model.latexOptions.fontSize, in: 8...144, step: 2)
                    .font(.system(size: 12))
                    .fixedSize()
                Menu(model.latexOptions.background == nil ? "背景：透明" : "背景：\(model.latexOptions.background!)") {
                    Button("透明") { model.latexOptions.background = nil }
                    Button("白") { model.latexOptions.background = "#FFFFFF" }
                    Button("黒") { model.latexOptions.background = "#000000" }
                }
                .menuStyle(.borderlessButton)
                .font(.system(size: 12))
                .fixedSize()
            }
            HStack(spacing: 6) {
                Text("文字色").font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(Self.swatches, id: \.0) { color, name in
                    Circle()
                        .fill(Color(hex: color))
                        .overlay(Circle().strokeBorder(model.latexOptions.color.uppercased() == color ? Theme.accent : Color.primary.opacity(0.3), lineWidth: model.latexOptions.color.uppercased() == color ? 3 : 1))
                        .frame(width: 18, height: 18)
                        .help(name)
                        .onTapGesture { model.latexOptions.color = color }
                }
            }
            ZStack {
                Checkerboard().clipShape(RoundedRectangle(cornerRadius: 6))
                if let image = model.latexPreviewImage {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: min(image.size.width / LatexRenderer.rasterScale, 1000), maxHeight: image.size.height / LatexRenderer.rasterScale)
                        .padding(6)
                } else if model.latexSource.isEmpty {
                    Text("例：\\int_0^1 f(x)\\,dx").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = model.latexError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(3)
            }
        }
    }

    // MARK: - 定型文（F-09）

    private var snippet: some View {
        VStack(alignment: .leading, spacing: 8) {
            title(model.snippetEditingID == nil ? "新しい定型文" : "定型文を編集", "text.badge.star")
            TextField("名前（一覧に出ます。空なら本文の冒頭）", text: $model.snippetTitle)
                .textFieldStyle(.roundedBorder)
                .focused(focused, equals: .snippetTitle)
            TextEditor(text: $model.snippetBody)
                .font(.system(size: 13))
                .focused(focused, equals: .snippetBody)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            Text("差し込み：{date}・{date:yyyy年M月d日}・{time}・{clipboard}（今のクリップボード）・{cursor}（貼ったあとのカーソルの位置）")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: - キーの一覧

    private var help: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                title("キー操作", "keyboard")
                ForEach(Self.helpRows, id: \.1) { key, text in
                    HStack(alignment: .top) {
                        Text(key).font(.system(size: 12, design: .monospaced)).frame(width: 90, alignment: .leading)
                        Text(text).font(.system(size: 12))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let helpRows: [(String, String)] = [
        ("⏎", "いまの貼り方で貼る（⌘⏎ はコピーだけ）"), ("⇥ ⇧⇥", "貼り方を切り替える（貼られる内容がプレビューに出る）"),
        ("→ ⌘K", "この項目にできること（1文字で選ぶ。右クリックでも）"),
        ("↑↓", "選択を動かす（⇧ で複数選択。⌘クリック・⇧クリックも）"), ("⌘1〜9", "上から N 番目を貼る"),
        ("", "── 覚えると速いキー ──"),
        ("⇧⏎ ⌥⏎", "プレーンで貼る・改行を消して貼る"), ("⌃1〜9", "保存した変換の組み合わせで貼る"),
        ("⌘T ⌘E ⌘P", "タグ・編集してから貼る・ピン留め"), ("⌘L ⌘M ⌘N", "数式画像・まとめる・新しい定型文"),
        ("⌘S ⇧⌘N", "Tomelet に残す・PopNote! に送る"), ("⌥⌘↑↓", "ピンの並べ替え"), ("⌘Y ⌘⌫", "Quick Look・削除"),
        ("⌘, esc", "設定・戻る"), ("ドラッグ", "ほかのアプリへ取り出す"),
    ]
}

/// 付いているタグ（× で外す）。
private struct FlowTags: View {
    let tags: [Tag]
    let remove: (Tag) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag.name)").font(.system(size: 12))
                        Button { remove(tag) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.18)))
                }
            }
        }
    }
}

/// 透明な部分がわかるよう、画像の後ろに敷く市松模様。
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            for row in 0..<Int(ceil(size.height / cell)) {
                for column in 0..<Int(ceil(size.width / cell)) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(.gray.opacity(0.2)))
                }
            }
        }
    }
}

extension Color {
    /// #RRGGBB から作る。
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
