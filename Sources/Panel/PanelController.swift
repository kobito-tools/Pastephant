import AppKit
import Quartz
import SwiftUI

/// フォーカスを奪わないパネル。ペースト先のアプリはアクティブなまま、キー入力だけを受け取る。
final class KeyPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var quickLook: QuickLookSource?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { quickLook != nil }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = quickLook; panel.delegate = quickLook }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
}

/// Quick Look に渡す一時ファイル。
final class QuickLookSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    let urls: [URL]
    init(urls: [URL]) { self.urls = urls }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls[index] as NSURL }
}

/// 履歴パネルの表示とキー操作（3.1・3.2）。
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    private let panel: KeyPanel
    private let settings: () -> Settings
    private var targetApplication: NSRunningApplication?
    private var clickMonitor: Any?
    /// 本体に頼む操作。パネルは必要に応じて先に閉じてから渡す。
    var onCommand: (PanelCommand, NSRunningApplication?) -> Void = { _, _ in }

    private(set) var isVisible = false
    /// 設定の画面でパネルの大きさなどを変えている間は、キーを取らずに出したままにする。
    private(set) var isSettingsPreview = false
    private let kobito = KobitoWindow()

    init(store: ClipStore, settings: @escaping () -> Settings) {
        self.settings = settings
        model = PanelModel(store: store)
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PanelView(model: model))
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        model.settings = settings
        model.onCommand = { [weak self] command in self?.perform(command) }
        model.onQuickLook = { [weak self] in self?.quickLook() }
    }

    func toggle() { isVisible ? hide() : show() }

    /// 開く。query を渡すと、その検索で開く（pastephant://open?tag=… など）。mode を渡すと、その画面で開く。
    func show(query: String = "", mode: PanelMode = .list) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if !isVisible || isSettingsPreview { targetApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost }
        model.prepareForShow(query: query)
        if mode == .latex { model.beginLatex(fromSelection: false) } else if mode == .snippet { model.beginSnippet() }
        if isVisible {
            // 設定の見本として出していた物を、ふつうのパネルにする。
            isSettingsPreview = false
            panel.makeKey()
            if clickMonitor == nil { installClickMonitor() }
            return
        }
        present()
        panel.makeKey()
        installClickMonitor()
    }

    /// 端から滑り込ませる（小人も一緒に）。
    private func present() {
        let (shown, hidden) = frames()
        panel.setFrame(hidden, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isVisible = true
        if settings().showKobito, KobitoWindow.image != nil {
            kobito.attach(to: hidden, edge: settings().panelEdge)
            kobito.alphaValue = 0
            panel.addChildWindow(kobito, ordered: .above)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(shown, display: true)
            panel.animator().alphaValue = 1
            kobito.animator().alphaValue = 1
        }
    }

    /// 設定の画面で大きさ・出る側・プレビューなどを変えたとき。キーを取らずに出し（出ていれば）すぐに作り直す。
    func showForSettings() {
        model.showPreview = settings().showPreview
        model.rowColorMode = settings().rowColorMode
        if !isVisible {
            isSettingsPreview = true
            model.prepareForShow()
            present()
            return
        }
        panel.setFrame(frames().shown, display: true)
        relayoutKobito()
    }

    /// 設定の画面を閉じたら、見本として出していたパネルを閉じる。
    func endSettingsPreview() {
        guard isSettingsPreview else { return }
        isSettingsPreview = false
        hide()
    }

    private func relayoutKobito() {
        if settings().showKobito, KobitoWindow.image != nil {
            if kobito.parent == nil { panel.addChildWindow(kobito, ordered: .above); kobito.alphaValue = 1 }
            kobito.attach(to: panel.frame, edge: settings().panelEdge)
        } else if kobito.parent != nil {
            panel.removeChildWindow(kobito)
            kobito.orderOut(nil)
        }
    }

    private func installClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide(animated: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        isSettingsPreview = false
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { QLPreviewPanel.shared().orderOut(nil) }
        let removeKobito = { [kobito, panel] in
            if kobito.parent != nil { panel.removeChildWindow(kobito) }
            kobito.orderOut(nil)
        }
        guard animated else { removeKobito(); panel.orderOut(nil); return }
        let hidden = frames().hidden
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().setFrame(hidden, display: true)
            panel.animator().alphaValue = 0
            kobito.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isVisible else { return }
                removeKobito()
                self.panel.orderOut(nil)
            }
        })
    }

    /// 取得した直後などに、開いていれば一覧を読み直す（作業中の画面はそのまま）。
    func refreshIfVisible() { if isVisible, model.mode == .list { model.reload() } }

    func windowDidResignKey(_ notification: Notification) {
        // 設定の見本として出しているときと、Quick Look を開いたときは閉じない。
        if isSettingsPreview { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { return }
        hide()
    }

    // MARK: - 位置

    /// 表示する位置と、その外側（スライドの始まり）の位置。
    private func frames() -> (shown: NSRect, hidden: NSRect) {
        let settings = settings()
        let mouse = NSEvent.mouseLocation
        let screen = (settings.panelScreen == .mouse ? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } : nil) ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame, margin: CGFloat = 8
        let width = min(CGFloat(settings.panelWidth), area.width - margin * 2)
        let x = settings.panelEdge == .right ? area.maxX - width - margin : area.minX + margin
        let shown = NSRect(x: x, y: area.minY + margin, width: width, height: area.height - margin * 2)
        let offset: CGFloat = settings.panelEdge == .right ? 40 : -40
        return (shown, shown.offsetBy(dx: offset, dy: 0))
    }

    // MARK: - 本体への操作

    private func perform(_ command: PanelCommand) {
        let target = targetApplication
        switch command {
        case .paste, .copyOnly, .pasteText, .pasteLatex, .sendToPopNote, .openSettings, .pushToStack:
            hide(animated: false)
        case .exportToTomelet, .tagsChanged:
            break
        }
        onCommand(command, target)
    }

    // MARK: - キー操作

    private func handleKey(_ event: NSEvent) -> Bool {
        // 日本語入力の変換中は、⏎ や矢印を入力欄へ渡す。
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.keyCode, character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isReturn = key == 36 || key == 76
        if key == 53 {  // esc
            if model.mode != .list { model.endMode() } else if !model.query.isEmpty { model.query = "" } else { hide() }
            return true
        }
        if flags == [.command], character == "," { perform(.openSettings); return true }
        switch model.mode {
        case .list: return handleListKey(event, flags: flags, key: key, character: character, isReturn: isReturn)
        case .actions:
            if key == 125 { model.moveAction(1) }
            else if key == 126 { model.moveAction(-1) }
            else if isReturn || key == 124 { model.runSelectedAction() }
            else if key == 123 { model.endMode() }  // ← で戻る
            else if flags.subtracting(.shift).isEmpty, let typed = event.characters?.lowercased().first, model.runAction(key: typed) { }
            else if flags.contains(.command) { return false }
            else { NSSound.beep() }
            return true
        case .tags:
            if key == 125 { model.moveTagSuggestion(1); return true }
            if key == 126 { model.moveTagSuggestion(-1); return true }
            if isReturn { model.commitTag(); return true }
            if key == 51, flags.isEmpty, model.tagInput.isEmpty { model.removeLastTag(); return true }
            return false
        case .edit:
            if isReturn, flags == [.command] { model.commitEdit(copyOnly: false); return true }
            if isReturn, flags == [.command, .shift] { model.commitEdit(copyOnly: true); return true }
            return false
        case .transform:
            if key == 125 { model.moveTransform(1) }
            else if key == 126 { model.moveTransform(-1) }
            else if isReturn { model.commitTransform(copyOnly: flags == [.command]) }
            else if key == 49 { model.toggleChain() }
            else if flags == [.command], character == "s" { model.saveCombo() }
            else if flags.contains(.command) { return false }
            return true
        case .merge:
            let typingCustom = model.mergeSeparator == .custom && model.focus == .mergeCustom
            if key == 125 { model.moveMergeSeparator(1); return true }
            if key == 126 { model.moveMergeSeparator(-1); return true }
            if isReturn { model.commitMerge(saveAsNew: flags == [.command]); return true }
            return !typingCustom && !flags.contains(.command)
        case .latex:
            if isReturn, flags.isEmpty { model.commitLatex(copyOnly: false); return true }
            if isReturn, flags == [.command] { model.commitLatex(copyOnly: true); return true }
            return false
        case .snippet:
            if isReturn, flags == [.command] || (flags == [.command] && character == "s") { model.commitSnippet(); return true }
            if flags == [.command], character == "s" { model.commitSnippet(); return true }
            return false
        case .help:
            model.endMode()
            return true
        }
    }

    private func handleListKey(_ event: NSEvent, flags: NSEvent.ModifierFlags, key: UInt16, character: String, isReturn: Bool) -> Bool {
        switch (key, flags) {
        case (125, []), (45, [.control]): model.moveSelection(1)
        case (126, []), (35, [.control]): model.moveSelection(-1)
        case (125, [.shift]): model.moveSelection(1, extend: true)
        case (126, [.shift]): model.moveSelection(-1, extend: true)
        case (125, [.command, .option]): model.movePin(1)
        case (126, [.command, .option]): model.movePin(-1)
        case (48, []): model.cycleStyle(1)  // ⇥ 貼り方
        case (48, [.shift]): model.cycleStyle(-1)
        case (124, []) where searchCaretAtEnd: model.beginActions()  // → できること
        case (51, [.command]): model.delete(model.targets)  // ⌘⌫
        case _ where isReturn:
            let ids = model.targets
            guard !ids.isEmpty else { NSSound.beep(); return true }
            if flags == [.command] { model.pasteSelected(copyOnly: true) }
            else if flags == [.shift] { perform(.paste(ids, .plainText)) }
            else if flags == [.option] { perform(.paste(ids, .joinLines)) }
            else { model.pasteSelected() }
        case (49, []) where model.query.isEmpty && model.focus == .search:  // 検索が空のときの space は Quick Look
            quickLook()
        default:
            if flags == [.command] {
                switch character {
                case "t": model.beginTags()
                case "e": model.beginEdit()
                case "n": model.beginSnippet()
                case "p": model.togglePin()
                case "l": model.beginLatex()
                case "m": model.beginMerge()
                case "k": model.beginActions()
                case "s": perform(.exportToTomelet(model.targets))
                case "y": quickLook()
                case "/": model.toggleHelp()
                default:
                    if let number = Int(character), (1...9).contains(number) {
                        if let clip = model.clip(at: number - 1) { perform(.paste([clip.id], .original)) } else { NSSound.beep() }
                    } else { return false }
                }
                return true
            }
            if flags == [.command, .shift], character == "n" { perform(.sendToPopNote(model.targets, append: false)); return true }
            if flags == [.command, .shift, .option], character == "n" { perform(.sendToPopNote(model.targets, append: true)); return true }
            if flags == [.control], let number = Int(character), (1...9).contains(number) { model.applyCombo(number); return true }
            return false
        }
        return true
    }

    /// 検索欄が空か、文字の最後にカーソルがある（→ で文字の中を動かすときは、できることの一覧を開かない）。
    private var searchCaretAtEnd: Bool {
        guard let editor = panel.firstResponder as? NSTextView else { return true }
        let range = editor.selectedRange()
        return range.length == 0 && range.location >= (editor.string as NSString).length
    }

    // MARK: - Quick Look

    /// 選んだ項目を一時ファイルに書き出して Quick Look で開く。
    private func quickLook() {
        guard let id = model.selection, let detail = try? model.store.detail(id, maxTextLength: ClipStore.maxStoredTextLength) else { NSSound.beep(); return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Pastephant-QuickLook", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = detail.filePaths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty, let items = try? model.store.representations(of: id), let first = items.first {
            let candidates: [(String, String)] = [("com.adobe.pdf", "pdf"), ("public.png", "png"), ("public.tiff", "tiff"), ("public.jpeg", "jpg"), ("public.rtf", "rtf"), ("public.html", "html")]
            if let (type, ext) = candidates.first(where: { candidate in first.contains { $0.type == candidate.0 } }), let data = first.first(where: { $0.type == type })?.data {
                let url = directory.appendingPathComponent("クリップ.\(ext)")
                if (try? data.write(to: url)) != nil { urls = [url] }
            }
        }
        if urls.isEmpty, let text = detail.text {
            let url = directory.appendingPathComponent("クリップ.txt")
            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil { urls = [url] }
        }
        guard !urls.isEmpty else { NSSound.beep(); return }
        panel.quickLook = QuickLookSource(urls: urls)
        let preview = QLPreviewPanel.shared()!
        if preview.isVisible { preview.reloadData() } else { preview.makeKeyAndOrderFront(nil) }
    }
}
