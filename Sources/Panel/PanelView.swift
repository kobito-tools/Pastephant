import AppKit
import SwiftUI

/// 画面の端から出てくるパネル（3.1）。上から、検索、プレビューの枠（作業中はその画面）と貼り方、履歴のカード、操作の案内。
/// キー操作は PanelController が受け取る。
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var focused: PanelModel.Field?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                header
                if model.mode != .list {
                    Card(title: nil) { ModeView(model: model, focused: $focused) }
                        .frame(height: max(240, geometry.size.height * 0.5))
                } else if model.showPreview, model.preview != nil {
                    Card(title: "プレビュー") {
                        VStack(spacing: 0) {
                            PreviewView(model: model).frame(maxHeight: .infinity)
                            if model.styles.count > 1 {
                                Rectangle().fill(Theme.wellBorder).frame(height: 1)
                                StyleStrip(model: model)
                            }
                        }
                    }
                    .frame(height: max(190, geometry.size.height * 0.38))
                } else if model.styles.count > 1 {
                    Card(title: nil) { StyleStrip(model: model) }.fixedSize(horizontal: false, vertical: true)
                }
                list
                if let message = model.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                FooterHints(model: model)
            }
            .padding(10)
            .animation(.easeOut(duration: 0.15), value: model.message)
        }
        .foregroundStyle(Theme.ink)
        .background(ZStack { PanelBackground(); Theme.paper })
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.wellBorder.opacity(0.8), lineWidth: 1))
        .onChange(of: model.focusRequest) { _ in focused = model.focus }
        .onAppear { focused = model.focus }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.subtle)
                TextField("検索（#タグ type:画像 app:Word …）", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused, equals: .search)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.subtle) }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(focused == .search ? Theme.accent : Theme.cardBorder, lineWidth: focused == .search ? 1.5 : 1))
            Menu {
                Picker("並べ替え", selection: $model.sort) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("並べ替え：\(model.sort.label)")
            Button { model.onCommand(.openSettings) } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("設定（⌘,）")
        }
        .foregroundStyle(Theme.subtle)
    }

    private var list: some View {
        let indexByID = Dictionary(uniqueKeysWithValues: model.rows.enumerated().map { ($1.id, $0) })
        return Group {
            if model.rows.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: model.query.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 28)).foregroundStyle(Theme.subtle)
                    Text(model.query.isEmpty ? "まだ履歴がありません。\nコピーするとここに並びます。" : "見つかりませんでした")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.subtle)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if model.showsPins {
                                SectionLabel(text: "ピン・定型文", symbol: "pin.fill", count: model.pins.count)
                                ForEach(model.pins) { clip in row(clip, index: indexByID[clip.id] ?? 0) }
                                SectionLabel(text: "履歴", symbol: "clock.fill", count: model.clips.count).padding(.top, 4)
                            } else {
                                SectionLabel(text: model.query.isEmpty ? "履歴" : "見つかった履歴", symbol: "clock.fill", count: model.clips.count)
                            }
                            ForEach(model.clips) { clip in row(clip, index: indexByID[clip.id] ?? 0) }
                        }
                        .padding(.horizontal, 2)
                        .padding(.bottom, 4)
                    }
                    .onChange(of: model.selection) { id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }

    private func row(_ clip: ClipSummary, index: Int) -> some View {
        ClipCard(model: model, clip: clip, index: index, selected: model.isHighlighted(clip.id), primary: clip.id == model.selection,
                 tint: model.rowColorMode.color(for: clip))
            .id(clip.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.selection = clip.id; model.pasteSelected() }
            .onTapGesture { model.click(clip.id, modifiers: NSEvent.modifierFlags) }
            .onHover { inside in model.hover(clip.id, inside: inside) }
            .onDrag { model.itemProvider(for: clip.id) }
            .contextMenu {
                ForEach(model.actionItems(for: model.multi.contains(clip.id) ? model.multi : [clip.id])) { action in
                    Button { action.run() } label: { Label(action.label, systemImage: action.symbol) }
                }
            }
    }
}

/// 見出しの付いた枠。プレビューと作業の画面に使い、一覧との境目をはっきりさせる。
private struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.subtle)
                    .padding(.horizontal, 12).padding(.top, 7)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.well))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.wellBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct SectionLabel: View {
    let text: String
    let symbol: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(.system(size: 11, weight: .semibold))
            Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(Theme.keycap))
            Spacer()
        }
        .foregroundStyle(Theme.subtle)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

/// 一覧の1件。左の色の帯（色分け）、サムネかアイコン、見出し、コピー元と時刻、タグ。
private struct ClipCard: View {
    let model: PanelModel
    let clip: ClipSummary
    let index: Int
    let selected: Bool
    let primary: Bool
    let tint: Color?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .short
        return formatter
    }()

    private var color: Color { tint ?? Theme.subtle }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leading
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.14)))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if clip.pinned && !clip.isSnippet { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(color) }
                    Text(clip.displayText)
                        .font(.system(size: 13, weight: clip.title == nil ? .regular : .semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 5) {
                    if let icon = model.appIcon(for: clip.sourceBundleID), !clip.isSnippet {
                        Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                    }
                    Text(caption).lineLimit(1)
                    ForEach(clip.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.color(for: tag))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.color(for: tag).opacity(0.13)))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.subtle)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.subtle.opacity(0.8))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.keycap.opacity(0.7)))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .padding(.vertical, 8)
        .background(alignment: .leading) {
            // 色分けの帯。
            Rectangle().fill(tint ?? Color.clear).frame(width: 4)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Theme.accent.opacity(primary ? 0.16 : 0.09) : Color.clear))
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Theme.accent : Theme.cardBorder, lineWidth: selected && primary ? 2 : 1))
        .shadow(color: .black.opacity(selected ? 0.1 : 0.05), radius: selected ? 4 : 1.5, y: 1)
    }

    @ViewBuilder private var leading: some View {
        if let thumbnail = model.thumbnail(for: clip) {
            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: clip.isSnippet ? "text.badge.star" : clip.kind.symbolName).font(.system(size: 17)).foregroundStyle(color)
        }
    }

    private var caption: String {
        if clip.isSnippet { return "定型文" + (clip.title == nil ? "" : "・" + clip.preview) }
        var parts = [clip.sourceAppName, Self.relativeFormatter.localizedString(for: clip.lastUsedAt, relativeTo: Date())].compactMap { $0 }
        if clip.copyCount > 1 { parts.append("×\(clip.copyCount)") }
        if clip.oversized { parts.append("文字だけ保存") }
        return parts.joined(separator: " · ")
    }
}

/// 貼り方の帯。選んだ項目に合う貼り方だけを並べる。⇥ で切り替え、クリックでも選べる。
private struct StyleStrip: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("貼り方").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.subtle)
                    ForEach(Array(model.styles.enumerated()), id: \.element.id) { index, style in
                        let selected = index == model.styleIndex
                        Label(style.label, systemImage: style.symbol)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(selected ? Theme.accent : Theme.card))
                            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.cardBorder))
                            .foregroundStyle(selected ? Color.white : Theme.ink)
                            .contentShape(Capsule())
                            .id(style.id)
                            .onTapGesture(count: 2) { model.selectStyle(index); model.pasteSelected() }
                            .onTapGesture { model.selectStyle(index) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .onChange(of: model.styleIndex) { index in
                if model.styles.indices.contains(index) { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(model.styles[index].id, anchor: .center) } }
            }
        }
    }
}

/// いまの画面で使えるキーの案内。一覧では3つだけにし、ほかは → の一覧で見つけられるようにする。
private struct FooterHints: View {
    @ObservedObject var model: PanelModel

    private var items: [(String, String)] {
        switch model.mode {
        case .list:
            let style = model.currentStyle.map { $0.id == "more" ? "変換を選ぶ" : "「\($0.label)」で貼る" } ?? "貼る"
            return [("⏎", style), ("⇥", "貼り方"), ("→", "できること"), ("⌘/", "キー")]
        case .actions: return [("英字", "そのキーの操作"), ("⏎", "選んだ操作"), ("esc", "戻る")]
        case .tags: return [("⏎", "付ける（無ければ作る）"), ("↑↓", "候補"), ("⌫", "最後のタグを外す"), ("esc", "戻る")]
        case .edit: return [("⌘⏎", "貼る"), ("⇧⌘⏎", "コピーだけ"), ("esc", "戻る")]
        case .transform: return [("⏎", "貼る"), ("space", "つなげる"), ("⌘S", "組み合わせを保存"), ("esc", "戻る")]
        case .merge: return [("⏎", "まとめて貼る"), ("⌘⏎", "新しい項目として保存"), ("↑↓", "区切り"), ("esc", "戻る")]
        case .latex: return [("⏎", "画像にして貼る"), ("⇧⏎", "改行"), ("⌘⏎", "コピーだけ"), ("esc", "戻る")]
        case .snippet: return [("⌘⏎", "保存"), ("⇥", "次の欄"), ("esc", "戻る")]
        case .help: return [("どのキーでも", "戻る")]
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.0) { key, text in
                HStack(spacing: 4) {
                    Text(key)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.keycap))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.cardBorder))
                    Text(text).font(.system(size: 11)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.subtle)
        .padding(.horizontal, 4)
    }
}

struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
