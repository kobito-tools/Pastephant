import AppKit
import ImageIO
import SwiftUI

/// パネルの上部に出す作業の画面。list のときはプレビュー。
enum PanelMode: Equatable {
    case list, actions, tags, edit, transform, merge, latex, snippet, help
}

/// パネルから本体（AppDelegate）に頼む操作。
enum PanelCommand {
    case paste([Int], Paster.Mode)
    case copyOnly(Int)
    case pasteText(String, copyOnly: Bool)
    case pasteLatex(LatexImage, copyOnly: Bool)
    case exportToTomelet([Int])
    case sendToPopNote([Int], append: Bool)
    case pushToStack([Int])
    case tagsChanged([Int])
    case openSettings
}

/// 変換メニューの1行（保存した組み合わせか、1つの変換）。
struct TransformEntry: Identifiable, Equatable {
    let id: String
    let label: String
    let steps: [TransformKind]
    let isCombo: Bool
}

/// 履歴パネルの状態。検索語が変わるたびに一覧を読み直す。
@MainActor
final class PanelModel: ObservableObject {
    enum Field: Hashable { case search, tag, edit, latex, snippetTitle, snippetBody, mergeCustom }

    @Published var mode: PanelMode = .list
    @Published var query = "" { didSet { if query != oldValue { reload(keepSelection: false) } } }
    @Published var sort: SortOrder = .lastUsed { didSet { if sort != oldValue { onSortChange(sort); reload() } } }
    @Published private(set) var pins: [ClipSummary] = []
    @Published private(set) var clips: [ClipSummary] = []
    @Published var selection: Int? { didSet { if selection != oldValue { updatePreview(); updateStyles() } } }
    /// 複数選択（選んだ順）。空なら selection の1件だけが対象。
    @Published var multi: [Int] = [] { didSet { if multi != oldValue, multi.count > 1 || oldValue.count > 1 { updateStyles() } } }
    /// カーソルを当てている行。当てている間はこちらをプレビューする。
    @Published var hovered: Int? { didSet { if hovered != oldValue { updatePreview() } } }
    @Published private(set) var preview: ClipDetail?
    @Published private(set) var previewImage: NSImage?
    @Published var focus: Field? = .search
    /// 変えると、focus の欄にフォーカスを移す。
    @Published private(set) var focusRequest = 0
    @Published var message: String?
    @Published var showPreview = true
    @Published var rowColorMode: RowColorMode = .app

    // 貼り方（⇥ で切り替え、⏎ でこの貼り方で貼る）
    @Published private(set) var styles: [PasteStyle] = []
    @Published var styleIndex = 0 { didSet { if styleIndex != oldValue { updateStyleResult() } } }
    /// いまの貼り方で貼られる文字（元の形のときは nil。プレビューに出す）。
    @Published private(set) var styleResult: String?
    /// 選んだ貼り方。ほかの項目に移っても、その項目に同じ貼り方があれば続けて使う。
    private var preferredStyleID = "original"

    // 操作の一覧（→・⌘K・右クリック）
    @Published private(set) var actions: [PanelAction] = []
    @Published var actionIndex = 0

    // タグ（F-04）
    @Published var tagInput = "" { didSet { updateTagSuggestions() } }
    @Published private(set) var tagSuggestions: [Tag] = []
    @Published var tagSuggestionIndex: Int?
    @Published private(set) var targetTags: [Tag] = []

    // 貼る前に編集（F-10）
    @Published var editText = ""

    // 変換（F-07）
    @Published private(set) var transformEntries: [TransformEntry] = []
    @Published var transformIndex = 0 { didSet { updateTransformPreview() } }
    @Published private(set) var chain: [TransformKind] = []
    @Published private(set) var transformPreview: String?

    // まとめる（F-11）
    @Published var mergeSeparator: MergeSeparator = .newline { didSet { updateMergePreview() } }
    @Published var mergeCustom = "" { didSet { updateMergePreview() } }
    @Published private(set) var mergePreview = ""

    // 数式（F-06）
    @Published var latexSource = "" { didSet { scheduleLatexRender() } }
    @Published var latexOptions = LatexOptions() { didSet { scheduleLatexRender(); onLatexOptionsChange(latexOptions) } }
    @Published private(set) var latexImage: LatexImage?
    @Published private(set) var latexPreviewImage: NSImage?
    @Published private(set) var latexError: String?
    @Published private(set) var latexRendering = false

    // 定型文（F-09）
    @Published var snippetTitle = ""
    @Published var snippetBody = ""
    @Published private(set) var snippetEditingID: Int?

    let store: ClipStore
    let latexRenderer = LatexRenderer()
    private var thumbnails: [Int: NSImage] = [:]
    private var appIcons: [String: NSImage] = [:]
    private var lastMouseLocation: NSPoint?
    private var latexTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var allTagsCache: [Tag] = []
    private var cachedContext: (id: Int, context: TransformContext)?
    /// 複数選んだときに、つないだ文字（貼り方の結果に使う）。
    private var cachedMerged: [Int: String] = [:]
    /// 裏で読むときの番号。選択やカーソルが動くたびに増やし、読み終えたときに番号が変わっていれば捨てる。
    private var previewGeneration = 0, styleGeneration = 0, resultGeneration = 0
    private let latest = LatestRequests()
    /// 貼り方を入れ替える間は、結果を読み直さない（まとめて読むため）。
    private var applyingStyles = false
    /// styles・styleResult がどの項目（と複数選択）のものか。⏎ のときに、いまの選択と合っているかを確かめる。
    private var stylesTarget: [Int] = []
    private static let loader = DispatchQueue(label: "io.github.kobito-tools.pastephant.preview", qos: .userInitiated, attributes: .concurrent)
    /// 矢印キーを押し続けている間は読まない（最後に止まった項目だけ読む）。
    private static let settle: TimeInterval = 0.05

    var settings: () -> Settings = { Settings() }
    var onCommand: (PanelCommand) -> Void = { _ in }
    var onSortChange: (SortOrder) -> Void = { _ in }
    var onLatexOptionsChange: (LatexOptions) -> Void = { _ in }
    var onSaveCombo: (TransformCombo) -> Void = { _ in }
    var onQuickLook: () -> Void = {}

    init(store: ClipStore) { self.store = store }

    // MARK: - 一覧

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// ピンを出すのは、検索も絞り込みもしていないときだけ。
    var showsPins: Bool { !searching && !pins.isEmpty }

    /// キー操作で動く順の全ての行。
    var rows: [ClipSummary] { showsPins ? pins + clips : clips }

    func reload(keepSelection: Bool = true) {
        let previous = selection
        pins = (try? store.pinned()) ?? []
        clips = (try? store.recent(query: query, sort: sort, excludePinned: !searching)) ?? []
        let rows = rows
        if keepSelection, let previous, rows.contains(where: { $0.id == previous }) { selection = previous }
        else { selection = searching ? rows.first?.id : (clips.first ?? rows.first)?.id }
        multi = multi.filter { id in rows.contains { $0.id == id } }
        if let hovered, !rows.contains(where: { $0.id == hovered }) { self.hovered = nil }
        cachedContext = nil
        reloadPreview()
        updateStyles()
    }

    func prepareForShow(query initialQuery: String = "") {
        mode = .list
        preferredStyleID = "original"
        multi = []
        hovered = nil
        message = nil
        showPreview = settings().showPreview
        rowColorMode = settings().rowColorMode
        sort = settings().sortOrder
        query = initialQuery
        thumbnails.removeAll()
        reload(keepSelection: false)
        requestFocus(.search)
    }

    func requestFocus(_ field: Field?) {
        focus = field
        focusRequest += 1
    }

    var selectedIndex: Int? { selection.flatMap { id in rows.firstIndex { $0.id == id } } }

    /// 操作の対象（複数選択があればその順、無ければ選んでいる1件）。
    var targets: [Int] { multi.isEmpty ? (selection.map { [$0] } ?? []) : multi }

    func isHighlighted(_ id: Int) -> Bool { multi.isEmpty ? id == selection : multi.contains(id) }

    func moveSelection(_ delta: Int, extend: Bool = false) {
        let rows = rows
        guard !rows.isEmpty else { return }
        // キーで動かしたら、カーソルを当てた行より選択を優先する。
        hovered = nil
        let index = min(max((selectedIndex ?? -1) + delta, 0), rows.count - 1)
        let id = rows[index].id
        if extend {
            if multi.isEmpty, let selection { multi = [selection] }
            if multi.count >= 2, multi[multi.count - 2] == id { multi.removeLast() }  // 戻ったら外す
            else if !multi.contains(id) { multi.append(id) }
        } else {
            multi = []
        }
        selection = id
    }

    /// クリック。⌘ で1件ずつ足し引き、⇧ で範囲を選ぶ。
    func click(_ id: Int, modifiers: NSEvent.ModifierFlags) {
        let rows = rows
        if modifiers.contains(.command) {
            if multi.isEmpty, let selection, selection != id { multi = [selection] }
            if let index = multi.firstIndex(of: id) { multi.remove(at: index) } else { multi.append(id) }
        } else if modifiers.contains(.shift), let from = selectedIndex, let to = rows.firstIndex(where: { $0.id == id }) {
            multi = (from <= to ? Array(from...to) : Array((to...from).reversed())).map { rows[$0].id }
        } else {
            multi = []
        }
        selection = id
    }

    func clip(at index: Int) -> ClipSummary? { rows.indices.contains(index) ? rows[index] : nil }

    func delete(_ ids: [Int]) {
        guard let first = ids.first else { return }
        let index = rows.firstIndex { $0.id == first } ?? 0
        try? store.delete(ids)
        for id in ids { thumbnails[id] = nil }
        multi = []
        reload(keepSelection: false)
        if let next = clip(at: min(index, rows.count - 1)) { selection = next.id }
    }

    func togglePin() {
        let ids = targets
        guard !ids.isEmpty else { return }
        let pin = !(rows.first { $0.id == ids[0] }?.pinned ?? false)
        try? store.setPinned(ids, pin)
        reload()
        show(pin ? "ピン留めしました（⌥⌘↑↓ で並べ替え）" : "ピン留めを外しました")
    }

    func movePin(_ delta: Int) {
        guard let id = selection, pins.contains(where: { $0.id == id }) else { NSSound.beep(); return }
        try? store.movePin(id, by: delta)
        reload()
    }

    func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    // MARK: - プレビュー

    var previewID: Int? { hovered ?? selection }

    /// カーソルが行に入った・出た。キー操作で一覧が流れて、止まったままのカーソルの下に行が来ただけのときは無視する。
    func hover(_ id: Int, inside: Bool) {
        let location = NSEvent.mouseLocation
        defer { lastMouseLocation = location }
        if inside {
            guard location != lastMouseLocation else { return }
            hovered = id
        } else if hovered == id {
            hovered = nil
        }
    }

    /// プレビューを裏で読む。選択はすぐに動かし、中身は少し遅れて出てもよい。
    private func updatePreview(force: Bool = false) {
        guard let id = previewID else {
            previewGeneration += 1
            latest.preview = previewGeneration
            preview = nil; previewImage = nil
            return
        }
        guard force || preview?.summary.id != id else { return }
        previewGeneration += 1
        let generation = previewGeneration, store = store, latest = latest
        latest.preview = generation
        Self.loader.asyncAfter(deadline: .now() + Self.settle) {
            guard latest.preview == generation else { return }  // もう別の項目に移った
            let detail = try? store.detail(id)
            guard latest.preview == generation else { return }
            let image = detail?.imageData.flatMap { Self.downsample($0, maxPixels: 1400) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                self.preview = detail
                self.previewImage = image
            }
        }
    }

    /// 一覧を読み直したあと、同じ項目でも中身（回数・タグなど）が変わっていることがあるので読み直す。
    private func reloadPreview() { updatePreview(force: true) }

    /// 画面に出す大きさに縮めて読む（大きな画像をそのまま開かない）。PDF はそのまま。
    nonisolated static func downsample(_ data: Data, maxPixels: Int) -> NSImage? {
        if data.starts(with: Array("%PDF".utf8)) { return NSImage(data: data) }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func thumbnail(for clip: ClipSummary) -> NSImage? {
        guard clip.hasThumbnail else { return nil }
        if let cached = thumbnails[clip.id] { return cached }
        let image = NSImage(contentsOf: store.thumbnailURL(clip.id))
        thumbnails[clip.id] = image
        return image
    }

    func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = appIcons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = icon
        return icon
    }

    /// ドラッグで取り出す（F-13）。保存してある全ての型を載せる。複数選んでいれば、文字をつないだ物を載せる。
    func itemProvider(for id: Int) -> NSItemProvider {
        let provider = NSItemProvider()
        let ids = multi.contains(id) && multi.count > 1 ? multi : [id]
        func registerText(_ text: String) {
            provider.registerDataRepresentation(forTypeIdentifier: Capture.plainTextType, visibility: .all) { completion in completion(Data(text.utf8), nil); return nil }
        }
        if ids.count > 1 {
            registerText(ids.compactMap { try? store.text(of: $0) }.joined(separator: "\n"))
            return provider
        }
        guard let items = try? store.representations(of: id), let first = items.first else {
            if let text = try? store.text(of: id) { registerText(text) }
            return provider
        }
        for representation in first where representation.type != Capture.ownType && !representation.type.hasPrefix("dyn.") {
            if representation.type == Capture.fileURLType, let string = String(data: representation.data, encoding: .utf8), let url = URL(string: string) {
                provider.registerFileRepresentation(forTypeIdentifier: "public.item", fileOptions: [], visibility: .all) { completion in completion(url, false, nil); return nil }
                provider.suggestedName = url.lastPathComponent
                continue
            }
            let data = representation.data
            provider.registerDataRepresentation(forTypeIdentifier: representation.type, visibility: .all) { completion in completion(data, nil); return nil }
        }
        return provider
    }

    // MARK: - 貼り方

    var currentStyle: PasteStyle? { styles.indices.contains(styleIndex) ? styles[styleIndex] : nil }

    /// 選んだ項目に合う貼り方と、いまの貼り方の結果を裏で作る。
    private func updateStyles() {
        styleGeneration += 1
        resultGeneration += 1
        let generation = styleGeneration
        latest.style = generation
        guard let id = selection, let clip = rows.first(where: { $0.id == id }) else {
            styles = []; styleIndex = 0; styleResult = nil
            return
        }
        let ids = multi.count > 1 ? multi : [], combos = settings().transformCombos, basePath = settings().basePath
        let keep = settings().keepParagraphBreaks, preferred = preferredStyleID, kind = clip.kind, store = store, latest = latest
        let cached = cachedContext?.id == id ? cachedContext?.context : nil
        Self.loader.asyncAfter(deadline: .now() + Self.settle) {
            guard latest.style == generation else { return }
            let context = cached ?? Self.makeContext(store, id: id, basePath: basePath, keepParagraphs: keep)
            guard latest.style == generation else { return }
            let styles = PasteStyle.styles(kind: kind, context: context, combos: combos, multiple: ids.count > 1)
            let index = styles.firstIndex { $0.id == preferred } ?? 0
            let merged = ids.isEmpty ? nil : ids.compactMap { try? store.text(of: $0) }.joined(separator: "\n")
            let result = Self.result(of: styles[index], context: context, merged: merged, keepParagraphs: keep)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.styleGeneration == generation else { return }
                self.cachedContext = (id, context)
                self.cachedMerged = merged.map { [generation: $0] } ?? [:]
                self.stylesTarget = ids.isEmpty ? [id] : ids
                self.applyingStyles = true
                self.styles = styles
                self.styleIndex = index
                self.applyingStyles = false
                self.styleResult = result
            }
        }
    }

    /// ⇥ で貼り方を変えたとき、その結果だけを裏で作り直す。
    private var resultPending = false

    private func updateStyleResult() {
        guard !applyingStyles else { return }
        resultPending = true
        resultGeneration += 1
        let generation = resultGeneration
        guard let style = currentStyle, let id = selection, let context = cachedContext?.id == id ? cachedContext?.context : nil else { styleResult = nil; resultPending = false; return }
        let merged = multi.count > 1 ? cachedMerged[styleGeneration] : nil, keep = settings().keepParagraphBreaks
        Self.loader.async {
            let result = Self.result(of: style, context: context, merged: merged, keepParagraphs: keep)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.resultGeneration == generation else { return }
                self.styleResult = result
                self.resultPending = false
            }
        }
    }

    nonisolated static func makeContext(_ store: ClipStore, id: Int, basePath: String?, keepParagraphs: Bool) -> TransformContext {
        let detail = try? store.detail(id, maxTextLength: ClipStore.maxStoredTextLength, maxImageBytes: 0)
        let html = (try? store.data(of: id, type: "public.html")).flatMap { $0 }.flatMap { String(data: $0, encoding: .utf8) }
        return TransformContext(text: detail?.text, html: html, filePaths: detail?.filePaths ?? [], ocrText: detail?.ocrText,
                                basePath: basePath, keepParagraphs: keepParagraphs)
    }

    /// 貼り方で貼られる文字（元の形のときは nil）。
    nonisolated static func result(of style: PasteStyle, context: TransformContext, merged: String?, keepParagraphs: Bool) -> String? {
        switch style.action {
        case .mode(.original), .latexImage, .moreTransforms: return nil
        case .mode(.plainText): return merged ?? context.text
        case .mode(.joinLines): return (merged ?? context.text).map { LineJoiner.join($0, keepParagraphs: keepParagraphs) }
        case .transform(let steps): return TextTransforms.apply(steps, to: context)
        }
    }

    private func mergedText(_ ids: [Int]) -> String { ids.compactMap { try? store.text(of: $0) }.joined(separator: "\n") }

    /// ⇥・⇧⇥：貼り方を切り替える（最後の次は最初に戻る）。
    func cycleStyle(_ delta: Int) {
        guard !styles.isEmpty else { NSSound.beep(); return }
        selectStyle((styleIndex + delta + styles.count) % styles.count)
    }

    func selectStyle(_ index: Int) {
        guard styles.indices.contains(index) else { return }
        styleIndex = index
        preferredStyleID = styles[index].id
    }

    /// 裏で読み終える前に ⏎ を押したときは、いまの項目の貼り方と結果をここで作ってそろえる。
    private func ensureStylesReady() {
        let ids = targets
        guard stylesTarget != ids, let id = selection, let clip = rows.first(where: { $0.id == id }) else { return }
        styleGeneration += 1
        latest.style = styleGeneration
        let context = transformContext ?? TransformContext()
        let newStyles = PasteStyle.styles(kind: clip.kind, context: context, combos: settings().transformCombos, multiple: ids.count > 1)
        let index = newStyles.firstIndex { $0.id == preferredStyleID } ?? 0
        applyingStyles = true
        styles = newStyles
        styleIndex = index
        applyingStyles = false
        styleResult = Self.result(of: newStyles[index], context: context, merged: ids.count > 1 ? mergedText(ids) : nil, keepParagraphs: settings().keepParagraphBreaks)
        stylesTarget = ids
    }

    /// ⏎：いまの貼り方で貼る。copyOnly なら、クリップボードに載せるだけ。
    func pasteSelected(copyOnly: Bool = false) {
        let ids = targets
        guard !ids.isEmpty else { NSSound.beep(); return }
        ensureStylesReady()
        if resultPending, let style = currentStyle, let context = cachedContext?.context {
            // ⇥ で変えた直後で、結果がまだ届いていない。
            styleResult = Self.result(of: style, context: context, merged: ids.count > 1 ? mergedText(ids) : nil, keepParagraphs: settings().keepParagraphBreaks)
            resultPending = false
        }
        switch currentStyle?.action ?? .mode(.original) {
        case .mode(.original):
            if copyOnly { ids.count == 1 ? onCommand(.copyOnly(ids[0])) : onCommand(.pasteText(mergedText(ids), copyOnly: true)) }
            else { onCommand(.paste(ids, .original)) }
        case .mode(let mode):
            if copyOnly, let styleResult { onCommand(.pasteText(styleResult, copyOnly: true)) } else { onCommand(.paste(ids, mode)) }
        case .transform:
            guard let styleResult else { NSSound.beep(); return }
            onCommand(.pasteText(styleResult, copyOnly: copyOnly))
        case .latexImage:
            beginLatex(text: transformContext?.text)
        case .moreTransforms:
            beginTransform()
        }
    }

    // MARK: - 操作の一覧

    /// → か ⌘K で開く。
    func beginActions() {
        guard !targets.isEmpty else { NSSound.beep(); return }
        actions = actionItems(for: targets)
        actionIndex = 0
        mode = .actions
        requestFocus(nil)
    }

    func moveAction(_ delta: Int) {
        guard !actions.isEmpty else { return }
        actionIndex = min(max(actionIndex + delta, 0), actions.count - 1)
    }

    /// 一覧を開いているときに1文字押した。
    func runAction(key: Character) -> Bool {
        guard let action = actions.first(where: { $0.key == key }) else { return false }
        action.run()
        return true
    }

    func runSelectedAction() {
        guard actions.indices.contains(actionIndex) else { return }
        actions[actionIndex].run()
    }

    /// 項目にできること。右クリックのメニューにも同じ物を出す（そのときは、その行を選んでから行う）。
    func actionItems(for ids: [Int]) -> [PanelAction] {
        guard let first = ids.first else { return [] }
        let clip = (pins + clips).first { $0.id == first }
        let single = ids.count == 1
        var items: [PanelAction] = []
        func add(_ id: String, _ key: Character, _ label: String, _ symbol: String, _ shortcut: String?, _ run: @escaping () -> Void) {
            items.append(PanelAction(id: id, key: key, label: label, symbol: symbol, shortcut: shortcut) { [weak self] in
                guard let self else { return }
                if self.targets != ids { self.multi = ids.count > 1 ? ids : []; self.selection = first }
                run()
            })
        }
        add("copy", "c", "コピーだけ（貼らない）", "doc.on.clipboard", "⌘⏎") { [unowned self] in pasteSelected(copyOnly: true) }
        add("tags", "t", "タグを付ける・外す", "tag", "⌘T") { [unowned self] in beginTags() }
        add("pin", "p", clip?.pinned == true ? "ピン留めを外す" : "ピン留めする", "pin", "⌘P") { [unowned self] in endMode(); togglePin() }
        if single { add("edit", "e", clip?.isSnippet == true ? "定型文を直す" : "編集してから貼る", "pencil", "⌘E") { [unowned self] in beginEdit() } }
        if ids.count >= 2 { add("merge", "m", "\(ids.count)件を1つにまとめる", "square.stack.3d.up", "⌘M") { [unowned self] in beginMerge() } }
        if single { add("transform", "r", "変換を選ぶ（つなげる・保存する）", "wand.and.stars", nil) { [unowned self] in beginTransform() } }
        if single { add("latex", "l", clip?.kind == .formula ? "数式を開き直す" : "数式画像を作る", "function", "⌘L") { [unowned self] in beginLatex() } }
        add("stack", "k", "ペーストスタックに積む", "square.stack", nil) { [unowned self] in onCommand(.pushToStack(ids)) }
        add("tomelet", "s", "Tomelet に残す", "calendar.badge.plus", "⌘S") { [unowned self] in endMode(); onCommand(.exportToTomelet(ids)) }
        add("popnote", "n", "PopNote! の新しいメモにする", "note.text", "⇧⌘N") { [unowned self] in onCommand(.sendToPopNote(ids, append: false)) }
        add("popnoteAppend", "a", "PopNote! の開いているメモに足す", "note.text.badge.plus", "⌥⇧⌘N") { [unowned self] in onCommand(.sendToPopNote(ids, append: true)) }
        if single { add("quicklook", "q", "Quick Look", "eye", "⌘Y") { [unowned self] in endMode(); onQuickLook() } }
        add("snippet", "f", "新しい定型文", "text.badge.star", "⌘N") { [unowned self] in beginSnippet() }
        add("delete", "d", ids.count > 1 ? "\(ids.count)件を履歴から削除" : "履歴から削除", "trash", "⌘⌫") { [unowned self] in endMode(); delete(ids) }
        add("help", "?", "キーの一覧", "keyboard", "⌘/") { [unowned self] in mode = .help; requestFocus(nil) }
        return items
    }

    // MARK: - タグ（F-04）

    func beginTags() {
        guard !targets.isEmpty else { NSSound.beep(); return }
        allTagsCache = (try? store.allTags()) ?? []
        refreshTargetTags()
        tagInput = ""
        tagSuggestionIndex = nil
        updateTagSuggestions()
        mode = .tags
        requestFocus(.tag)
    }

    private func refreshTargetTags() {
        // 選んだ全ての項目に付いているタグ。
        let sets = targets.map { Set((try? store.tags(of: $0)) ?? []) }
        targetTags = (sets.dropFirst().reduce(sets.first ?? []) { $0.intersection($1) }).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func updateTagSuggestions() {
        let input = tagInput.trimmingCharacters(in: .whitespaces)
        let current = Set(targetTags.map(\.id))
        tagSuggestions = Array(allTagsCache.filter { !current.contains($0.id) && (input.isEmpty || $0.name.localizedCaseInsensitiveContains(input)) }.prefix(8))
        if let index = tagSuggestionIndex, index >= tagSuggestions.count { tagSuggestionIndex = tagSuggestions.isEmpty ? nil : tagSuggestions.count - 1 }
    }

    func moveTagSuggestion(_ delta: Int) {
        guard !tagSuggestions.isEmpty else { return }
        let next = (tagSuggestionIndex ?? -1) + delta
        tagSuggestionIndex = next < 0 ? nil : min(next, tagSuggestions.count - 1)
    }

    /// 候補を選んでいればそれを、選んでいなければ入力した名前のタグ（無ければ作る）を付ける。
    func commitTag() {
        let tag: Tag?
        if let index = tagSuggestionIndex, tagSuggestions.indices.contains(index) { tag = tagSuggestions[index] }
        else if !tagInput.trimmingCharacters(in: .whitespaces).isEmpty { tag = try? store.findOrCreateTag(tagInput) }
        else { tag = nil }
        guard let tag else { NSSound.beep(); return }
        try? store.addTag(tag, to: targets)
        if !allTagsCache.contains(tag) { allTagsCache.append(tag) }
        tagInput = ""
        tagSuggestionIndex = nil
        refreshTargetTags()
        updateTagSuggestions()
        onCommand(.tagsChanged(targets))
    }

    func removeTag(_ tag: Tag) {
        try? store.removeTag(tag.id, from: targets)
        refreshTargetTags()
        updateTagSuggestions()
        onCommand(.tagsChanged(targets))
    }

    func removeLastTag() { if let last = targetTags.last { removeTag(last) } }

    // MARK: - 貼る前に編集（F-10）

    func beginEdit() {
        guard let id = selection else { NSSound.beep(); return }
        if rows.first(where: { $0.id == id })?.isSnippet == true { beginSnippet(editing: id); return }
        guard let text = try? store.text(of: id) else { show("文字の無い項目は編集できません"); return }
        editText = text
        mode = .edit
        requestFocus(.edit)
    }

    /// 編集した物を新しい項目として保存し、貼る（copyOnly なら載せるだけ）。
    func commitEdit(copyOnly: Bool) {
        guard !editText.isEmpty else { NSSound.beep(); return }
        _ = try? store.saveText(editText, sourceName: "Pastephant（編集）")
        onCommand(.pasteText(editText, copyOnly: copyOnly))
    }

    // MARK: - 変換（F-07）

    private var transformContext: TransformContext? {
        guard let id = selection else { return nil }
        if let cachedContext, cachedContext.id == id { return cachedContext.context }
        let context = Self.makeContext(store, id: id, basePath: settings().basePath, keepParagraphs: settings().keepParagraphBreaks)
        cachedContext = (id, context)
        return context
    }

    func beginTransform() {
        guard let context = transformContext else { NSSound.beep(); return }
        var entries = settings().transformCombos.map { TransformEntry(id: "combo-\($0.id)", label: "★ \($0.name)", steps: $0.steps, isCombo: true) }
        for kind in TransformKind.allCases {
            let available: Bool
            switch kind.input {
            case .text, .latex: available = context.text != nil
            case .files: available = !context.filePaths.isEmpty
            case .ocr: available = context.ocrText?.isEmpty == false
            }
            if available { entries.append(TransformEntry(id: kind.rawValue, label: kind.label, steps: [kind], isCombo: false)) }
        }
        guard !entries.isEmpty else { show("この項目にかけられる変換がありません"); return }
        transformEntries = entries
        chain = []
        mode = .transform
        transformIndex = 0
        updateTransformPreview()
        requestFocus(nil)
    }

    func moveTransform(_ delta: Int) {
        guard !transformEntries.isEmpty else { return }
        transformIndex = min(max(transformIndex + delta, 0), transformEntries.count - 1)
    }

    /// つなげた変換 ＋ いま選んでいる変換。
    private var currentSteps: [TransformKind] {
        guard transformEntries.indices.contains(transformIndex) else { return chain }
        let steps = transformEntries[transformIndex].steps
        if chain.count >= steps.count, Array(chain.suffix(steps.count)) == steps { return chain }
        return chain + steps
    }

    private func updateTransformPreview() {
        guard mode == .transform, let context = transformContext else { transformPreview = nil; return }
        transformPreview = currentSteps.last == .latexImage ? "（⏎ で数式画像の画面を開きます）" : TextTransforms.apply(currentSteps, to: context)
    }

    /// Space：いま選んでいる変換をつなげる・外す。つなげられるのは、文字から文字への変換（最初の1つはファイルや画像の文字でもよい）。
    func toggleChain() {
        guard transformEntries.indices.contains(transformIndex) else { return }
        let steps = transformEntries[transformIndex].steps
        if chain.count >= steps.count, Array(chain.suffix(steps.count)) == steps {
            chain.removeLast(steps.count)
        } else {
            let startsChain = chain.isEmpty && steps.first.map { $0.input == .files || $0.input == .ocr } == true && steps.dropFirst().allSatisfy(\.chainable)
            guard startsChain || steps.allSatisfy(\.chainable) else { NSSound.beep(); return }
            chain += steps
        }
        updateTransformPreview()
    }

    func commitTransform(copyOnly: Bool) {
        if currentSteps.last == .latexImage {
            beginLatex(text: transformContext?.text)
            return
        }
        guard let result = transformPreview, let context = transformContext, TextTransforms.apply(currentSteps, to: context) != nil else { NSSound.beep(); return }
        onCommand(.pasteText(result, copyOnly: copyOnly))
    }

    /// ⌘S：つなげた変換を保存する（名前は変換の名前をつないだ物。設定で変えられる）。
    func saveCombo() {
        let steps = currentSteps.filter { $0 != .latexImage }
        guard !steps.isEmpty else { NSSound.beep(); return }
        onSaveCombo(TransformCombo(name: steps.map(\.label).joined(separator: " → "), steps: steps))
        show("組み合わせを保存しました（一覧で ⌃\(settings().transformCombos.count) を押すと使えます）")
    }

    func applyCombo(_ number: Int) {
        let combos = settings().transformCombos
        guard combos.indices.contains(number - 1), let context = transformContext, let result = TextTransforms.apply(combos[number - 1].steps, to: context) else { NSSound.beep(); return }
        onCommand(.pasteText(result, copyOnly: false))
    }

    // MARK: - まとめる（F-11）

    func beginMerge() {
        guard multi.count >= 2 else { show("⇧↑↓ か ⌘クリックで2件以上選んでから ⌘M を押してください"); return }
        mode = .merge
        updateMergePreview()
        requestFocus(mergeSeparator == .custom ? .mergeCustom : nil)
    }

    func moveMergeSeparator(_ delta: Int) {
        let all = MergeSeparator.allCases
        guard let index = all.firstIndex(of: mergeSeparator) else { return }
        mergeSeparator = all[min(max(index + delta, 0), all.count - 1)]
        requestFocus(mergeSeparator == .custom ? .mergeCustom : nil)
    }

    private func updateMergePreview() {
        guard mode == .merge else { return }
        mergePreview = multi.compactMap { try? store.text(of: $0) }.joined(separator: mergeSeparator.separator(custom: mergeCustom))
    }

    /// 貼る。saveAsNew なら新しい項目として保存し、クリップボードに載せるだけにする。
    func commitMerge(saveAsNew: Bool) {
        guard !mergePreview.isEmpty else { NSSound.beep(); return }
        if saveAsNew { _ = try? store.saveText(mergePreview, sourceName: "Pastephant（まとめ）") }
        onCommand(.pasteText(mergePreview, copyOnly: saveAsNew))
    }

    // MARK: - 数式（F-06）

    /// 数式の画面を開く。数式の項目なら元の式を、LaTeX らしい文字ならその文字を入れる。
    func beginLatex(text: String? = nil, fromSelection: Bool = true) {
        mode = .latex
        latexOptions = settings().latexOptions
        if let text {
            latexSource = LatexSource.stripDelimiters(text)
        } else if fromSelection, let id = selection, let latex = try? store.latex(of: id) {
            latexSource = latex.source
            latexOptions = latex.options
        } else if fromSelection, let id = selection, let text = try? store.text(of: id), LatexSource.looksLikeLatex(text) {
            latexSource = LatexSource.stripDelimiters(text)
        } else {
            latexSource = ""
        }
        scheduleLatexRender()
        requestFocus(.latex)
    }

    func applyPreset(_ preset: LatexPreset) {
        var options = preset.options
        options.displayMode = latexOptions.displayMode
        latexOptions = options
    }

    private func scheduleLatexRender() {
        guard mode == .latex else { return }
        latexTask?.cancel()
        let latex = LatexSource(source: latexSource, options: latexOptions), macros = settings().latexMacros
        guard !latexSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            latexImage = nil; latexPreviewImage = nil; latexError = nil
            return
        }
        latexTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, !Task.isCancelled else { return }
            self.latexRendering = true
            defer { self.latexRendering = false }
            do {
                let image = try await self.latexRenderer.render(latex, macros: macros)
                guard !Task.isCancelled else { return }
                self.latexImage = image
                self.latexPreviewImage = NSImage(data: image.png)
                self.latexError = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.latexError = "\(error)"
            }
        }
    }

    func commitLatex(copyOnly: Bool) {
        let latex = LatexSource(source: latexSource, options: latexOptions)
        Task { @MainActor in
            if let image = latexImage, image.latex == latex { onCommand(.pasteLatex(image, copyOnly: copyOnly)); return }
            // 打ち終えてすぐ ⏎ を押したときは、ここで描く。
            do { onCommand(.pasteLatex(try await latexRenderer.render(latex, macros: settings().latexMacros), copyOnly: copyOnly)) }
            catch { latexError = "\(error)"; NSSound.beep() }
        }
    }

    // MARK: - 定型文（F-09）

    func beginSnippet(editing id: Int? = nil) {
        snippetEditingID = id
        if let id, let summary = rows.first(where: { $0.id == id }) {
            snippetTitle = summary.title ?? ""
            snippetBody = (try? store.text(of: id)) ?? ""
        } else {
            snippetTitle = ""
            snippetBody = ""
        }
        mode = .snippet
        requestFocus(.snippetTitle)
    }

    func commitSnippet() {
        guard !snippetBody.isEmpty else { NSSound.beep(); return }
        let editing = snippetEditingID
        var saved: Int?
        if let editing { try? store.updateSnippet(editing, title: snippetTitle, body: snippetBody); saved = editing }
        else { saved = try? store.createSnippet(title: snippetTitle, body: snippetBody) }
        endMode()
        if let saved { selection = saved }
        show(editing == nil ? "定型文を作りました（ピンの欄にあります）" : "定型文を保存しました")
    }

    // MARK: - 画面の切り替え

    func toggleHelp() {
        if mode == .help { endMode() } else { mode = .help; requestFocus(nil) }
    }

    func endMode() {
        mode = .list
        latexTask?.cancel()
        reload()
        requestFocus(.search)
    }
}

/// 裏で読むときに、いま欲しい番号を読むための入れ物（裏のキューからも読むので、ロックで守る）。
final class LatestRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var values = (preview: 0, style: 0)

    var preview: Int {
        get { lock.lock(); defer { lock.unlock() }; return values.preview }
        set { lock.lock(); values.preview = newValue; lock.unlock() }
    }

    var style: Int {
        get { lock.lock(); defer { lock.unlock() }; return values.style }
        set { lock.lock(); values.style = newValue; lock.unlock() }
    }
}
