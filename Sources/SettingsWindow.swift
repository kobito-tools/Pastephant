import AppKit
import Carbon
import ServiceManagement
import SwiftUI

/// 設定の画面（F-19）。変更はすぐに settings.json に保存し、本体に反映する。
@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: Settings { didSet { if settings != oldValue { onChange(settings) } } }
    @Published var usage: (count: Int, bytes: Int) = (0, 0)
    @Published var datasetID: String?
    /// 今あるタグの名前（選んで決めるときに使う）。
    @Published var availableTags: [String] = []
    var loadTags: () -> [String] = { [] }
    var onChange: (Settings) -> Void = { _ in }
    var onCleanup: () -> Void = {}
    var onChooseBasePath: () -> Void = {}
    /// 設定の画面を閉じた。
    var onClose: () -> Void = {}
    var refreshUsage: () -> (count: Int, bytes: Int) = { (0, 0) }

    init(settings: Settings) { self.settings = settings }

    /// Tomelet がこのMacで開いている基準パス（~/Library/Application Support/TickTockTome/config/setting.json。古い版は DailyLog/）。
    static var tomeletBasePath: String? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for name in ["TickTockTome", "DailyLog"] {
            let url = support.appendingPathComponent(name).appendingPathComponent("config/setting.json")
            if let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let path = object["basePath"] as? String, FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) { self.model = model }

    var isVisible: Bool { window?.isVisible == true }

    func windowWillClose(_ notification: Notification) { model.onClose() }

    func show() {
        model.usage = model.refreshUsage()
        model.availableTags = model.loadTags()
        model.datasetID = model.settings.basePath.flatMap { try? Dataset.read($0)?.datasetId }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Pastephant の設定"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            general.tabItem { Label("一般", systemImage: "gearshape") }
            capture.tabItem { Label("取得とタグ", systemImage: "tray.and.arrow.down") }
            storage.tabItem { Label("保存", systemImage: "externaldrive") }
            transforms.tabItem { Label("変換", systemImage: "wand.and.stars") }
            latex.tabItem { Label("数式", systemImage: "function") }
            companions.tabItem { Label("連携", systemImage: "link") }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 540)
    }

    // MARK: - 一般

    private var general: some View {
        Form {
            Section {
                PermissionRow(title: "アクセシビリティ", detail: "選んだ項目を、元のアプリに貼り付けるのに使います（⌘V を送ります）。無いときは、クリップボードに戻すだけになります。",
                              granted: { Paster.isTrusted(prompt: false) }) {
                    _ = Paster.isTrusted(prompt: true)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                PermissionRow(title: "入力監視", detail: "ペーストスタックで、⌘V が押されたことだけを見て次の項目に入れ替えるのに使います。スタックを使わなければいりません。",
                              granted: { CGPreflightListenEventAccess() }) {
                    CGRequestListenEventAccess()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
            } header: {
                Text("許可")
            } footer: {
                Text("ビルドし直したあとは許可が外れることがあります。その場合は、システム設定の一覧で Pastephant を一度削除（−）してから、もう一度オンにしてください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("ショートカット") {
                HotKeyRecorder(title: "履歴を開く", value: $model.settings.openPanelHotKey)
                HotKeyRecorder(title: "ペーストスタックを始める・終える", value: $model.settings.stackHotKey)
            }
            Section("パネル") {
                Picker("出てくる側", selection: $model.settings.panelEdge) {
                    Text("右端").tag(Settings.Edge.right)
                    Text("左端").tag(Settings.Edge.left)
                }
                Picker("出すディスプレイ", selection: $model.settings.panelScreen) {
                    Text("マウスのある画面").tag(Settings.PanelScreen.mouse)
                    Text("メインの画面").tag(Settings.PanelScreen.main)
                }
                HStack {
                    Text("幅")
                    Slider(value: $model.settings.panelWidth, in: 320...640, step: 10)
                    Text("\(Int(model.settings.panelWidth))").monospacedDigit().frame(width: 40)
                }
                Toggle("上部にプレビューを表示", isOn: $model.settings.showPreview)
                Picker("カードの色分け", selection: $model.settings.rowColorMode) {
                    ForEach(RowColorMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("縁にしがみつく小人を表示", isOn: $model.settings.showKobito)
                Text("ここを変えている間は、画面の端にパネルを出して、そのまま見た目を確かめられます（設定を閉じると隠れます）。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("並べ替え", selection: $model.settings.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("貼り付け") {
                Toggle("貼ったあと、クリップボードを貼る前の中身に戻す", isOn: $model.settings.restoreClipboardAfterPaste)
                Toggle("改行を消すとき、段落の区切り（空行）を残す", isOn: $model.settings.keepParagraphBreaks)
            }
            Section {
                LoginItemToggle()
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 取得とタグ

    private var capture: some View {
        Form {
            Section {
                ExplainBox(title: "どのコピーを取っておくか", text: "Pastephant は ⌘C でコピーした物を、自動で履歴に取っておきます。ここでは、取っておかないアプリと、コピーしたときに自動で付けるタグを決めます。")
            }
            Section {
                ForEach(model.settings.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Button { model.settings.excludedBundleIDs.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button("アプリを選んで加える…") {
                    for id in AppLabel.choose(multiple: true) where !model.settings.excludedBundleIDs.contains(id) { model.settings.excludedBundleIDs.append(id) }
                }
            } header: {
                Text("取っておかないアプリ")
            } footer: {
                Text("ここにあるアプリでコピーした物は、履歴に入れません。パスワード管理アプリなどが付ける「保存しないで」の印（org.nspasteboard.ConcealedType など）の付いたコピーは、ここに無くても入れません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach($model.settings.autoTagRules) { $rule in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Picker("", selection: $rule.kind) {
                                Text("このアプリでコピーしたら").tag(AutoTagRule.Kind.app)
                                Text("このサイトのリンクなら").tag(AutoTagRule.Kind.domain)
                            }
                            .labelsHidden().fixedSize()
                            Spacer()
                            Button { model.settings.autoTagRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        HStack {
                            if rule.kind == .app {
                                AppLabel(bundleID: rule.pattern)
                                Button("アプリを選ぶ…") { if let id = AppLabel.choose().first { rule.pattern = id } }
                            } else {
                                TextField("arxiv.org など", text: $rule.pattern).textFieldStyle(.roundedBorder).frame(width: 180)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TagField(tag: $rule.tag, available: model.availableTags)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button("規則を加える") { model.settings.autoTagRules.append(AutoTagRule(kind: .app, pattern: "", tag: "")) }
            } header: {
                Text("自動でタグを付ける")
            } footer: {
                Text("例：TeXShop でコピーしたら #latex、arxiv.org のリンクなら #論文。「このサイトのリンクなら」は、ブラウザからコピーした文字に含まれるリンクで見分けます（サブドメインも含みます）。タグは今あるタグから選ぶか、新しい名前を入力します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 保存

    private func retention(_ kind: ClipKind) -> Binding<Int> {
        Binding(get: { model.settings.retentionDays[kind.rawValue] ?? 0 },
                set: { model.settings.retentionDays[kind.rawValue] = $0 > 0 ? $0 : nil })
    }

    private var storage: some View {
        Form {
            Section {
                ExplainBox(title: "履歴をいつまで取っておくか", text: "古い履歴は自動で消して、Mac の容量を使いすぎないようにします。ピン留めした項目と定型文は、ここの設定にかかわらず消しません。")
            }
            Section("消える期限（最後に使ってからの日数。0 は無期限）") {
                ForEach(ClipKind.allCases, id: \.self) { kind in
                    Stepper(value: retention(kind), in: 0...3650, step: kind == .text ? 30 : 7) {
                        Text("\(kind.label)：\(retention(kind).wrappedValue == 0 ? "無期限" : "\(retention(kind).wrappedValue)日")")
                    }
                }
                Toggle("タグの付いた項目も期限で消す", isOn: $model.settings.expireTagged)
                Text("ピン留めした項目と定型文は消しません。").font(.caption).foregroundStyle(.secondary)
            }
            Section("上限") {
                Stepper("件数：\(model.settings.maxItems)件", value: $model.settings.maxItems, in: 100...500_000, step: 1000)
                Stepper("生データの合計：\(model.settings.maxTotalBytes / 1_073_741_824)GB", value: Binding(get: { model.settings.maxTotalBytes / 1_073_741_824 }, set: { model.settings.maxTotalBytes = max(1, $0) * 1_073_741_824 }), in: 1...200)
                Stepper("1件の大きさ：\(model.settings.maxItemBytes / 1_048_576)MB（超えた物は文字だけ保存）", value: Binding(get: { model.settings.maxItemBytes / 1_048_576 }, set: { model.settings.maxItemBytes = max(1, $0) * 1_048_576 }), in: 1...2000, step: 10)
            }
            Section("いまの履歴") {
                HStack {
                    Text("\(model.usage.count)件・\(ByteCountFormatter.string(fromByteCount: Int64(model.usage.bytes), countStyle: .file))")
                    Spacer()
                    Button("今すぐ整理") { model.onCleanup() }
                    Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([ClipStore.defaultDirectory]) }
                }
                Text("履歴はこのMacの ~/Library/Application Support/Pastephant/ にだけ保存します。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 変換

    private var transforms: some View {
        Form {
            Section {
                ExplainBox(title: "変換の組み合わせ", text: "パネルの「ほかの変換…」（→ の R でも）で、space を押して変換をつなげ（例：改行を消す → 句読点を「，．」に）、⌘S で保存した物がここに並びます。保存した組み合わせは、貼り方の帯に ★ で並び、一覧で ⌃1〜⌃9 を押しても使えます。名前と並び順はここで変えられます。")
            }
            Section("保存した組み合わせ（一覧で ⌃1〜⌃9）") {
                if model.settings.transformCombos.isEmpty {
                    Text("変換の画面（⇥）で space を押して変換をつなげ、⌘S で保存します。").foregroundStyle(.secondary)
                }
                ForEach(Array(model.settings.transformCombos.enumerated()), id: \.element.id) { index, combo in
                    HStack {
                        Text(index < 9 ? "⌃\(index + 1)" : "").monospacedDigit().frame(width: 28)
                        TextField("名前", text: Binding(get: { combo.name }, set: { model.settings.transformCombos[index].name = $0 }))
                        Text(combo.steps.map(\.label).joined(separator: " → ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Button { if index > 0 { model.settings.transformCombos.swapAt(index, index - 1) } } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless)
                        Button { model.settings.transformCombos.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 数式

    private var latex: some View {
        Form {
            Section {
                ExplainBox(title: "数式画像", text: "パネルで ⌘L（→ の L でも）を押すと、LaTeX の式を書いて、そのまま画像にして貼れます。PowerPoint や Keynote には拡大しても粗くならない形で貼られます。ここでは、その画像の見た目を決めます。")
            }
            Section {
                LatexSample(options: model.settings.latexOptions, macros: model.settings.latexMacros, height: 72)
                LatexOptionsEditor(options: $model.settings.latexOptions)
            } header: {
                Text("いつもの描き方")
            } footer: {
                Text("数式の画面を開いたときに、最初に使う描き方です。数式の画面で描き方を変えると、ここにも残ります。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("プリセットは、よく使う描き方（文字色・背景・大きさ・余白）に名前を付けて取っておくものです。数式の画面の右上にある「描き方」メニューに、ここで付けた名前で並び、選ぶと一度にその描き方へ切り替わります。たとえば、暗いスライドに貼るときは「暗いスライド用（白文字）」を選びます。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(model.settings.latexPresets.enumerated()), id: \.element.id) { index, _ in
                    LatexPresetRow(preset: Binding(get: { model.settings.latexPresets[index] }, set: { model.settings.latexPresets[index] = $0 }),
                                   macros: model.settings.latexMacros,
                                   remove: { model.settings.latexPresets.remove(at: index) })
                }
                Button("いつもの描き方を、新しいプリセットとして加える") {
                    model.settings.latexPresets.append(LatexPreset(name: "わたしの描き方 \(model.settings.latexPresets.count + 1)", options: model.settings.latexOptions))
                }
            } header: {
                Text("プリセット（名前を付けた描き方）")
            }
            Section {
                TextEditor(text: $model.settings.latexMacros)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 80)
                // KaTeX は \R を先に持っているので、例では別の名前にする。
                Button("例を入れる") { model.settings.latexMacros += (model.settings.latexMacros.isEmpty ? "" : "\n") + #"\newcommand{\Rset}{\mathbb{R}}"# + "\n" + #"\newcommand{\diff}{\mathrm{d}}"# }
            } header: {
                Text("自分で決めた命令（マクロ）")
            } footer: {
                Text("よく使う長い書き方に短い名前を付けておけます。ここに書いた \\newcommand は、全ての式の前に付けて描きます。例：\\newcommand{\\diff}{\\mathrm{d}} と書くと、式の中で \\diff x と書けます。同梱の KaTeX で描くので、KaTeX が対応している命令だけ使えます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 連携

    private var companions: some View {
        Form {
            Section {
                ExplainBox(title: "連携でできること", text: "Pastephant は単独で使えます。同じシリーズ（kobito-tools）のアプリも使っているなら、次のことができるようになります。\n・タグを Tomelet・PopNote! と共有する\n・⌘S で残したクリップを、Tomelet のカレンダーに日ごとのメモとして並べる\n・⇧⌘N で選んだクリップを PopNote! のメモにする\n・OpenSesame! から1キーで Pastephant を開く")
                VStack(alignment: .leading, spacing: 4) {
                    Text("はじめかた").font(.system(size: 12, weight: .semibold))
                    Text("1. 下の「基準パス」で、Tomelet・PopNote! と同じフォルダを選びます（Tomelet の基準パスが見つかれば「これを使う」ボタンが出ます）。\n2. 必要なら「自動で残すタグ」を選びます。\n3. PopNote! と OpenSesame! は、入っていればそのまま使えます（設定はいりません）。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                HStack(alignment: .top) {
                    Image(systemName: model.settings.basePath == nil ? "folder.badge.questionmark" : "folder.fill.badge.person.crop")
                        .font(.system(size: 20)).foregroundStyle(model.settings.basePath == nil ? Color.secondary : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.settings.basePath == nil ? "まだ選んでいません（連携しない）" : (model.datasetID.map { "「\($0)」を使っています" } ?? "選んでいます"))
                            .font(.system(size: 13, weight: .semibold))
                        if let path = model.settings.basePath { Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled) }
                    }
                    Spacer()
                    Button(model.settings.basePath == nil ? "フォルダを選ぶ…" : "変える…") { model.onChooseBasePath() }
                    if model.settings.basePath != nil { Button("やめる") { model.settings.basePath = nil; model.datasetID = nil } }
                }
                if let candidate = SettingsModel.tomeletBasePath, candidate != model.settings.basePath {
                    HStack {
                        Image(systemName: "lightbulb").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tomelet が使っているフォルダが見つかりました").font(.system(size: 12, weight: .medium))
                            Text(candidate).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("これを使う") { model.settings.basePath = candidate; model.datasetID = try? Dataset.read(candidate)?.datasetId }
                    }
                }
            } header: {
                Text("基準パス（シリーズで共有するフォルダ）")
            } footer: {
                Text("基準パスは、kobito-tools のアプリが一緒に使うフォルダです（例：Google ドライブのマイドライブ）。中に .kobito-tools という隠しフォルダを作り、タグの共有や Tomelet への受け渡しに使います。Pastephant の履歴そのものはこのMacにだけ保存し、基準パスには置きません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TagChips(tags: $model.settings.autoExportTags, available: model.availableTags)
            } header: {
                Text("自動で Tomelet に残すタグ")
            } footer: {
                Text("ここで選んだタグをクリップに付けると、⌘S を押さなくても、その日の「○月○日のクリップ」のメモに自動で加わります。例：#論文 を選んでおくと、論文のリンクにタグを付けるだけで Tomelet の日々の記録に残ります。基準パスを選んでいるときだけ働きます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(SeriesApp.all) { app in SeriesAppRow(app: app) }
                HStack(spacing: 10) {
                    SeriesIcon(name: "kobito-tools").frame(width: 32, height: 32)
                    Text("kobito-tools は、同じ小人が毎日の作業を少しずつ手伝う、macOS 向けの小さなアプリのシリーズです。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Link("GitHub", destination: URL(string: "https://github.com/kobito-tools")!).font(.system(size: 12))
                }
            } header: {
                Text("シリーズのアプリ")
            }
            Section {
                Toggle("新しくコピーした物から順に貼る", isOn: $model.settings.reverseStack)
            } header: {
                Text("ペーストスタック")
            } footer: {
                Text("ペーストスタック（⌃⌘C）は、続けてコピーした物を ⌘V を押すたびに1つずつ順に貼る機能です。ふつうはコピーした順に貼ります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// シリーズのアプリの紹介。
struct SeriesApp: Identifiable {
    let id: String
    let name: String
    let bundleID: String
    let tagline: String
    let english: String
    /// Pastephant と一緒に使うと何ができるか。
    let together: String
    let url: URL

    static let all = [
        SeriesApp(id: "tomelet", name: "Tomelet", bundleID: "local.ticktocktome.desktop",
                  tagline: "日記・時間割・Todo・関連ファイルを一括管理", english: "Journal, timetable, todos and files in one place.",
                  together: "⌘S で残したクリップが、その日の「09月28日のクリップ」というメモになって、Tomelet のカレンダーや検索に並びます。タグも共有します。",
                  url: URL(string: "https://github.com/kobito-tools/Tomelet")!),
        SeriesApp(id: "popnote", name: "PopNote!", bundleID: "io.github.kobito-tools.popnote",
                  tagline: "押したらポンッと出てくる、クイックメモ。", english: "A memo that pops up when you need it.",
                  together: "⇧⌘N で選んだクリップ（文字と画像）を新しいメモに、⌥⇧⌘N で開いているメモに足せます。タグも共有します。",
                  url: URL(string: "https://github.com/kobito-tools/PopNote")!),
        SeriesApp(id: "opensesame", name: "OpenSesame!", bundleID: "io.github.kobito-tools.opensesame",
                  tagline: "アプリ・フォルダ・画面分割のショートカットランチャー", english: "A shortcut launcher for apps, folders and window layouts.",
                  together: "pastephant://open・pastephant://latex・pastephant://stack/toggle などを登録すると、1キーで履歴や数式の画面を開けます。",
                  url: URL(string: "https://github.com/kobito-tools/OpenSesame")!),
    ]

    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
}

private struct SeriesIcon: View {
    let name: String

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "series"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app").resizable().aspectRatio(contentMode: .fit).foregroundStyle(.secondary)
        }
    }
}

private struct SeriesAppRow: View {
    let app: SeriesApp

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SeriesIcon(name: app.id).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(app.name).font(.system(size: 14, weight: .semibold))
                    Text(app.isInstalled ? "インストール済み" : "未インストール")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(app.isInstalled ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15)))
                        .foregroundStyle(app.isInstalled ? Color.green : Color.secondary)
                }
                Text(app.tagline).font(.system(size: 12))
                Text(app.english).font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Pastephant と一緒に：\(app.together)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Link(destination: app.url) { Label("GitHub", systemImage: "arrow.up.right.square") }
                .font(.system(size: 12))
        }
        .padding(.vertical, 4)
    }
}

/// 許可の状態（1秒ごとに見直す。システム設定で許可すると、すぐに表示が変わる）。
private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: () -> Bool
    let open: () -> Void
    @State private var isGranted = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(isGranted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title)：\(isGranted ? "許可されています" : "許可されていません")").font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !isGranted { Button("許可する…", action: open) }
        }
        .onAppear { isGranted = granted() }
        .onReceive(timer) { _ in isGranted = granted() }
    }
}

/// 数式の描き方のプリセット1件。見本と名前を出し、「変える」で描き方を開く。
private struct LatexPresetRow: View {
    @Binding var preset: LatexPreset
    let macros: String
    let remove: () -> Void
    @State private var expanded = false

    private var summary: String {
        let background = preset.options.background.map { $0.uppercased() == "#FFFFFF" ? "白い背景" : $0.uppercased() == "#000000" ? "黒い背景" : "背景 \($0)" } ?? "透明"
        return "文字 \(preset.options.color)・\(background)・\(Int(preset.options.fontSize))pt"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                LatexSample(options: preset.options, macros: macros, height: 52).frame(width: 170)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("メニューに出る名前", text: $preset.name).textFieldStyle(.roundedBorder)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Button(expanded ? "閉じる" : "変える") { withAnimation { expanded.toggle() } }
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless).help("このプリセットを消す")
            }
            if expanded {
                LatexOptionsEditor(options: $preset.options).padding(.leading, 8)
            }
        }
        .padding(.vertical, 4)
    }
}

/// ログイン時に起動するか。
private struct LoginItemToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Toggle("ログイン時に起動", isOn: Binding(get: { enabled }, set: { value in
            do {
                if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                error = nil
            } catch { self.error = "\(error.localizedDescription)（アプリケーションフォルダに入れてからお試しください）" }
            enabled = SMAppService.mainApp.status == .enabled
        }))
        if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
}

/// 文字列の一覧（追加・削除）。
private struct StringListEditor: View {
    @Binding var items: [String]
    let placeholder: String
    let choose: () -> [String]
    @State private var draft = ""

    var body: some View {
        ForEach(items, id: \.self) { item in
            HStack {
                Text(item)
                Spacer()
                Button { items.removeAll { $0 == item } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
            }
        }
        HStack {
            TextField(placeholder, text: $draft)
            Button("加える") { add([draft]); draft = "" }.disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("アプリを選ぶ…") { add(choose()) }
        }
    }

    private func add(_ values: [String]) {
        for value in values.map({ $0.trimmingCharacters(in: .whitespaces) }) where !value.isEmpty && !items.contains(value) { items.append(value) }
    }
}

/// ショートカットを押して登録する。
private struct HotKeyRecorder: View {
    let title: String
    @Binding var value: HotKeySetting
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(recording ? "キーを押してください…" : value.display) { recording ? stop() : start() }
                .frame(minWidth: 140)
        }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }  // esc でやめる
            let flags = event.modifierFlags
            var modifiers = 0
            if flags.contains(.command) { modifiers |= HotKeySetting.command }
            if flags.contains(.shift) { modifiers |= HotKeySetting.shift }
            if flags.contains(.option) { modifiers |= HotKeySetting.option }
            if flags.contains(.control) { modifiers |= HotKeySetting.control }
            // ⌘・⌃・⌥ のどれかを含むものだけ（文字の入力とぶつからないように）。
            guard modifiers & (HotKeySetting.command | HotKeySetting.control | HotKeySetting.option) != 0 else { NSSound.beep(); return nil }
            value = HotKeySetting(keyCode: Int(event.keyCode), modifiers: modifiers)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
