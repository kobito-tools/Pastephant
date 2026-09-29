import AppKit

/// クリップボードを0.3秒ごとに見て、変わったら中身を読んで渡す（F-01, F-02）。
/// 読むのはメインスレッド、保存は受け取った側が裏のキューで行う。
@MainActor
final class PasteboardWatcher {
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let excludedBundleIDs: () -> [String]
    private let onCapture: (Capture) -> Void
    /// 一時停止中は取得しない。期限付きの一時停止は pausedUntil で表す。
    var isPaused = false
    var pausedUntil: Date?

    init(pasteboard: NSPasteboard = .general, excludedBundleIDs: @escaping () -> [String], onCapture: @escaping (Capture) -> Void) {
        self.pasteboard = pasteboard
        self.excludedBundleIDs = excludedBundleIDs
        self.onCapture = onCapture
        // 起動した時点でクリップボードにある物は、起動前のコピーなので取らない。
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() { timer?.invalidate(); timer = nil }

    var effectivelyPaused: Bool {
        if let until = pausedUntil {
            if until > Date() { return true }
            pausedUntil = nil
        }
        return isPaused
    }

    /// 自分で書いた直後に呼び、その変化を取らないようにする。
    func skipCurrentChange() { lastChangeCount = pasteboard.changeCount }

    func check() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard !effectivelyPaused else { return }
        // 型だけを先に見て、保存しない物は中身を読まない（パスワードなどを読み込まないため）。
        let types = Set((pasteboard.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) })
        guard !types.isEmpty, !types.contains(Capture.ownType), types.isDisjoint(with: Capture.privacyMarkers) else { return }
        let application = NSWorkspace.shared.frontmostApplication
        if let bundleID = application?.bundleIdentifier, excludedBundleIDs().contains(bundleID) { return }
        guard let capture = Capture.read(from: pasteboard, sourceBundleID: application?.bundleIdentifier, sourceAppName: application?.localizedName) else { return }
        onCapture(capture)
    }
}
