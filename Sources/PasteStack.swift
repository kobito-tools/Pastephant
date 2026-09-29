import AppKit
import CoreGraphics

/// ペーストスタック（F-14）。積んだ項目を、⌘V を押すたびに1つずつ順に貼る。
/// 次に貼る項目をいつもクリップボードに載せておき、⌘V が押されたら（イベントタップで見るだけ）次の項目に入れ替える。
@MainActor
final class PasteStack {
    private let paster: Paster
    private let reverse: () -> Bool
    private let hud = StackHUD()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var items: [Int] = []
    private(set) var isActive = false
    var onChange: () -> Void = {}

    init(paster: Paster, reverse: @escaping () -> Bool) {
        self.paster = paster
        self.reverse = reverse
    }

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        guard installTap() else { return }
        isActive = true
        items.removeAll()
        hud.show(count: 0)
        onChange()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        items.removeAll()
        removeTap()
        hud.hide()
        onChange()
    }

    /// 積む。スタックが止まっていれば始める。
    func push(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        if !isActive { start() }
        guard isActive else { return }
        items.append(contentsOf: ids)
        loadHead()
        hud.show(count: items.count)
    }

    /// 次に貼る項目。
    var head: Int? { reverse() ? items.last : items.first }

    private func loadHead() {
        guard let head else { return }
        paster.write(head, mode: .original, markUsed: false)
    }

    /// ⌘V が押された。貼られるのを少し待ってから次の項目に入れ替える。
    fileprivate func pasted() {
        guard isActive, let head else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isActive, self.head == head else { return }
            if let index = self.reverse() ? self.items.lastIndex(of: head) : self.items.firstIndex(of: head) { self.items.remove(at: index) }
            self.paster.markUsed(head)
            if self.items.isEmpty { self.stop() } else { self.loadHead(); self.hud.show(count: self.items.count) }
        }
    }

    fileprivate func reenableTap() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    // MARK: - ⌘V を見るイベントタップ

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let stack = Unmanaged<PasteStack>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { stack.reenableTap() }
            } else if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9,
                      event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == .maskCommand {
                DispatchQueue.main.async { stack.pasted() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
                                          callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            // キー入力を見る許可（入力監視）が無い。
            CGRequestListenEventAccess()
            let alert = NSAlert()
            alert.messageText = "ペーストスタックには「入力監視」の許可が必要です"
            alert.informativeText = "「システム設定」→「プライバシーとセキュリティ」→「入力監視」で Pastephant をオンにしてから、もう一度お試しください。⌘V が押されたことだけを見て、次の項目に入れ替えます。"
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }
}

/// 画面の上部に出す「スタック N 件」の小さな表示。
@MainActor
private final class StackHUD {
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")

    func show(count: Int) {
        let panel = self.panel ?? makePanel()
        label.stringValue = count == 0 ? "📚 スタック：コピーすると積みます（⌃⌘C で終了）" : "📚 スタック \(count) 件：⌘V で順に貼ります（⌃⌘C で終了）"
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 28, height: 30)
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.maxY - size.height - 10, width: size.width, height: size.height), display: true)
        }
        label.frame = NSRect(x: 14, y: (size.height - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 30), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let background = NSVisualEffectView(frame: panel.contentView!.bounds)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 15
        background.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(background)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        panel.contentView?.addSubview(label)
        self.panel = panel
        return panel
    }
}
