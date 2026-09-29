import AppKit

/// PopNote! に送る（F-16）。中身を一時ファイル（JSON）に書き、popnote://import?file=… で PopNote! に渡す。
/// PopNote! は読み終えたらファイルを消し、新しいメモ（append なら開いているメモの末尾）に文字と画像を入れる。
enum PopNoteLink {
    struct Payload: Encodable {
        struct Image: Encodable {
            let name: String
            let mimeType: String
            let base64: String
        }
        let format = "pastephant-clip"
        let version = 1
        let append: Bool
        let text: String
        let images: [Image]
    }

    static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(toOpen: URL(string: "popnote://new")!) != nil }

    /// 送る。PopNote! が入っていなければ false。
    @discardableResult
    static func send(text: String, images: [(data: Data, mimeType: String)], append: Bool) throws -> Bool {
        guard isInstalled else { return false }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Pastephant-PopNote", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let ext = ["image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/heic": "heic"]
        let payload = Payload(append: append, text: text, images: images.enumerated().map { index, image in
            Payload.Image(name: "クリップ\(index + 1).\(ext[image.mimeType] ?? "png")", mimeType: image.mimeType, base64: image.data.base64EncodedString())
        })
        let file = directory.appendingPathComponent("\(UUID().uuidString).json")
        try JSONEncoder().encode(payload).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var components = URLComponents(string: "popnote://import")!
        components.queryItems = [URLQueryItem(name: "file", value: file.path)]
        return NSWorkspace.shared.open(components.url!)
    }
}
