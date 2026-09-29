import Foundation

/// Tomelet に残す（F-17）。その日の分を「09月28日のクリップ」という1つのメモにまとめ、
/// <基準パス>/.kobito-tools/Pastephant/database/pastephant.sqlite3（Tomelet の memos 表と同じ形）に保存する。
/// Tomelet は PopNote! のメモと同じように、このDBを読み取り専用で開いて表示する。
struct TomeletExporter {
    /// 書き出す1件。
    struct Item {
        let clipID: Int
        let copiedAt: Date
        let appName: String?
        let tags: [String]
        let text: String?
        let latex: String?
        let filePaths: [String]
        let ocrText: String?
        /// 添付する画像（PNG・JPEG など）と、その MIME タイプ。
        let image: (data: Data, mimeType: String)?
    }

    enum ExportError: Error, CustomStringConvertible {
        /// 基準パスに .kobito-tools/dataset.json がまだ無い（ID を決めて作る必要がある）。
        case datasetMissing
        case failed(String)

        var description: String {
            switch self {
            case .datasetMissing: "基準パスに共有フォルダ（.kobito-tools）がありません。"
            case .failed(let message): message
            }
        }
    }

    let schemaDirectory: URL

    static func title(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM月dd日のクリップ"
        return formatter.string(from: date)
    }

    /// 書き出して、メモのIDを返す。同じ日のメモがあれば末尾に追記する。
    @discardableResult
    func export(_ items: [Item], basePath: String, now: Date = Date()) throws -> String {
        guard !items.isEmpty else { throw ExportError.failed("書き出す項目がありません。") }
        guard try Dataset.read(basePath) != nil else { throw ExportError.datasetMissing }
        let lock = DatasetLock(basePath: basePath)
        try Dataset.ensureDirectories(basePath)
        try lock.acquire()
        defer { lock.release() }
        let database = try Dataset.openDatabase(basePath, schemaDirectory: schemaDirectory)
        // 共有タグを写してから、名前でタグのIDを引く。
        try? TagStore.sync(database, basePath: basePath)
        let timestamp = Dataset.timestamp(now)
        var html = "", text = "", uploadIds: [String] = [], tagIds: [String] = []
        for item in items {
            let (itemHTML, itemText, uploadId) = try render(item, database: database, basePath: basePath, now: now)
            html += itemHTML
            text += itemText
            if let uploadId { uploadIds.append(uploadId) }
            for name in item.tags {
                if let id = try database.first("SELECT id FROM tags WHERE name = ? AND deleted_at IS NULL", name)?["id"] as? String, !tagIds.contains(id) { tagIds.append(id) }
            }
        }
        let title = Self.title(for: now)
        // 和暦の設定のMacでも西暦で比べる。
        let day = { () -> String in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: now)
        }()
        return try database.transaction { () -> String in
            let id: String
            if let existing = try database.first("SELECT id, body_html, body_text FROM memos WHERE title = ? AND deleted_at IS NULL AND strftime('%Y-%m-%d', created_at, 'localtime') = ? ORDER BY created_at LIMIT 1", title, day),
               let existingId = existing["id"] as? String {
                id = existingId
                let separator = "<div>――――――――</div>"
                try database.run("UPDATE memos SET body_html = ?, body_text = ?, updated_at = ?, revision = revision + 1 WHERE id = ?",
                                 (existing["body_html"] as? String ?? "") + separator + html, (existing["body_text"] as? String ?? "") + "――――――――\n" + text, timestamp, id)
            } else {
                id = "memo-\(UUID().uuidString.lowercased())"
                try database.run("INSERT INTO memos(id, title, body_html, body_text, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)", id, title, html, text, timestamp, timestamp)
            }
            for tagId in tagIds { try database.run("INSERT OR IGNORE INTO memo_tags(memo_id, tag_id) VALUES (?, ?)", id, tagId) }
            for uploadId in uploadIds { try database.run("INSERT OR IGNORE INTO memo_uploads(memo_id, upload_id) VALUES (?, ?)", id, uploadId) }
            return id
        }
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 1件分の本文（HTML と文字）。見出しの行（時刻・アプリ・タグ）、中身、画像の順。
    private func render(_ item: Item, database: SQLiteDatabase, basePath: String, now: Date) throws -> (String, String, String?) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let heading = ([formatter.string(from: item.copiedAt), item.appName].compactMap { $0 } + (item.tags.isEmpty ? [] : [item.tags.map { "#\($0)" }.joined(separator: " ")])).joined(separator: "・")
        var html = "<div><b>\(Self.escape(heading))</b></div>", text = heading + "\n"
        var lines: [String] = []
        if let latex = item.latex { lines.append("数式：\(latex)") }
        else if let body = item.text, !body.isEmpty { lines += body.components(separatedBy: "\n") }
        for path in item.filePaths { lines.append("ファイル：\(path)") }
        if let ocr = item.ocrText, !ocr.isEmpty, item.text == nil { lines.append("（画像の文字）"); lines += ocr.components(separatedBy: "\n") }
        for line in lines {
            html += line.isEmpty ? "<div><br></div>" : "<div>\(Self.escape(line))</div>"
            text += line + "\n"
        }
        var uploadId: String?
        if let image = item.image {
            let ext = ["image/png": ".png", "image/jpeg": ".jpg", "image/gif": ".gif", "image/heic": ".heic"][image.mimeType] ?? ".png"
            let id = "upload-\(UUID().uuidString.lowercased())", storedName = UUID().uuidString.lowercased() + ext
            let destination = Dataset.uploadsDirectory(basePath).appendingPathComponent(storedName)
            guard FileManager.default.createFile(atPath: destination.path, contents: image.data, attributes: [.posixPermissions: 0o600]) else {
                throw ExportError.failed("画像を保存できませんでした。")
            }
            try database.run("INSERT INTO managed_uploads(id, stored_name, original_name, mime_type, size_bytes, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                             id, storedName, "クリップ\(ext)", image.mimeType, image.data.count, Dataset.timestamp(now))
            html += "<div><img src=\"/api/v1/uploads/\(id)/content\" alt=\"\"></div>"
            uploadId = id
        }
        return (html, text, uploadId)
    }
}
