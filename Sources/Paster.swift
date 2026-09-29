import AppKit
import ApplicationServices

/// 履歴の項目や変換した文字をクリップボードに書き戻し、⌘V を送って貼る（F-03）。
@MainActor
final class Paster {
    enum Mode { case original, plainText, joinLines }

    private let store: ClipStore
    private let pasteboard: NSPasteboard
    private let settings: () -> Settings
    /// 書き戻したことを監視側に伝え、履歴に二重に入れないようにする。
    var didWrite: () -> Void = {}

    init(store: ClipStore, pasteboard: NSPasteboard = .general, settings: @escaping () -> Settings) {
        self.store = store
        self.pasteboard = pasteboard
        self.settings = settings
    }

    // MARK: - 載せる物を決める

    /// 項目から、クリップボードに載せる物を作る。定型文は差し込みを展開する（{cursor} の位置も返す）。
    func items(for id: Int, mode: Mode) -> (items: [[Representation]], cursorOffset: Int?)? {
        let summary = try? store.summary(id)
        if summary?.isSnippet == true, let body = try? store.text(of: id) {
            let expanded = SnippetExpander.expand(body, clipboard: pasteboard.string(forType: .string))
            let text = mode == .joinLines ? LineJoiner.join(expanded.text, keepParagraphs: settings().keepParagraphBreaks) : expanded.text
            return (Self.textItems(text), mode == .joinLines ? nil : expanded.cursorOffsetFromEnd)
        }
        switch mode {
        case .original:
            if let stored = try? store.representations(of: id) { return (stored, nil) }
            // 大きすぎて生データを残さなかった物は、文字だけを載せる。
            if let text = try? store.text(of: id) { return (Self.textItems(text), nil) }
            return nil
        case .plainText, .joinLines:
            guard var text = try? store.text(of: id) else { return nil }
            if mode == .joinLines { text = LineJoiner.join(text, keepParagraphs: settings().keepParagraphBreaks) }
            return (Self.textItems(text), nil)
        }
    }

    static func textItems(_ text: String) -> [[Representation]] { [[Representation(type: Capture.plainTextType, data: Data(text.utf8))]] }

    // MARK: - 書き戻し

    /// 項目をクリップボードに載せる。載せられた物が無ければ false。
    @discardableResult
    func write(_ id: Int, mode: Mode, markUsed: Bool = true) -> Bool {
        guard let resolved = items(for: id, mode: mode) else { return false }
        write(resolved.items)
        if markUsed { try? store.markUsed(id) }
        return true
    }

    func markUsed(_ id: Int) { try? store.markUsed(id) }

    /// 全ての項目に自分の印を付けて載せる。
    func write(_ items: [[Representation]]) {
        pasteboard.clearContents()
        let pasteboardItems = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for representation in representations { item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type)) }
            item.setData(Data(), forType: NSPasteboard.PasteboardType(Capture.ownType))
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
        didWrite()
    }

    // MARK: - 貼り付け

    /// 履歴の項目を貼る。
    func paste(_ id: Int, mode: Mode, into application: NSRunningApplication?) {
        guard let resolved = items(for: id, mode: mode) else { NSSound.beep(); return }
        try? store.markUsed(id)
        deliver(resolved.items, into: application, cursorOffset: resolved.cursorOffset)
    }

    /// 変換した文字などを貼る。
    func paste(text: String, into application: NSRunningApplication?) {
        deliver(Self.textItems(text), into: application, cursorOffset: nil)
    }

    /// 書き戻してから、元のアプリへ ⌘V を送る。アクセシビリティの許可が無ければ書き戻すだけにする。
    func deliver(_ items: [[Representation]], into application: NSRunningApplication?, cursorOffset: Int?) {
        let previous = settings().restoreClipboardAfterPaste ? snapshot() : nil
        write(items)
        guard Self.isTrusted(prompt: true) else { return }
        if let application, application != NSWorkspace.shared.frontmostApplication { application.activate() }
        // パネルが閉じ、元のアプリにキーが届く状態になってから送る。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.sendCommandV()
            if let cursorOffset, cursorOffset > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { Self.sendLeftArrows(cursorOffset) }
            }
            guard let previous else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.write(previous) }
        }
    }

    /// 貼る前のクリップボードの中身。
    private func snapshot() -> [[Representation]]? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        let snapshot = items.map { item in item.types.compactMap { type in item.data(forType: type).map { Representation(type: type.rawValue, data: $0) } } }
            .map { $0.filter { $0.type != Capture.ownType } }.filter { !$0.isEmpty }
        return snapshot.isEmpty ? nil : snapshot
    }

    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// ⌘V を送る。9 は ANSI・JIS 配列の V のキー。
    static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// 定型文の {cursor} の位置へ戻す。
    static func sendLeftArrows(_ count: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<min(count, 2000) {
            for keyDown in [true, false] { CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: keyDown)?.post(tap: .cghidEventTap) }
        }
    }
}
