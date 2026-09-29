import Foundation

/// 一覧に出す1行分の情報。
struct ClipSummary: Identifiable, Equatable {
    let id: Int
    let kind: ClipKind
    let preview: String
    let sourceBundleID: String?
    let sourceAppName: String?
    let copiedAt: Date
    let lastUsedAt: Date
    let copyCount: Int
    let pasteCount: Int
    let hasThumbnail: Bool
    let oversized: Bool
    let pinned: Bool
    let title: String?
    let isSnippet: Bool
    /// 付いているタグの名前（一覧を読むときにまとめて入れる）。
    var tags: [String] = []

    /// 一覧に出す見出し。定型文とピンは名前、ほかは中身の冒頭。
    var displayText: String {
        if let title, !title.isEmpty { return title }
        return preview.isEmpty ? kind.label : preview
    }

    init(row: [String: Any]) {
        id = row["id"] as? Int ?? 0
        kind = ClipKind(rawValue: row["kind"] as? String ?? "") ?? .text
        preview = row["preview"] as? String ?? ""
        sourceBundleID = row["source_bundle_id"] as? String
        sourceAppName = row["source_app_name"] as? String
        copiedAt = Date(timeIntervalSince1970: row["copied_at"] as? Double ?? 0)
        lastUsedAt = Date(timeIntervalSince1970: row["last_used_at"] as? Double ?? 0)
        copyCount = row["copy_count"] as? Int ?? 1
        pasteCount = row["paste_count"] as? Int ?? 0
        hasThumbnail = row["has_thumbnail"] as? Int == 1
        oversized = row["oversized"] as? Int == 1
        pinned = row["pinned"] as? Int == 1
        title = row["title"] as? String
        isSnippet = row["is_snippet"] as? Int == 1
    }
}

/// プレビューに出す中身（選んだ・カーソルを当てた1件分）。
struct ClipDetail {
    let summary: ClipSummary
    let text: String?
    let imageData: Data?
    let filePaths: [String]
    let types: [String]
    let totalBytes: Int
    let createdAt: Date
    let ocrText: String?
    let latex: LatexSource?
}

/// このMacの履歴（~/Library/Application Support/Pastephant/）の読み書きと整理（F-01, F-15）。
///
///   database/history.sqlite3   項目・型の一覧・タグの写し・全文検索
///   blobs/ab/<sha256>.bin      生データ（中身のハッシュ名。同じデータは1つだけ）
///   thumbs/<項目ID>.png        一覧用のサムネ
///
/// 取得は裏のキュー、一覧はメインスレッドから呼ぶため、公開メソッドはすべて1つのロックの中で動かす。
final class ClipStore: @unchecked Sendable {
    let directory: URL
    let database: SQLiteDatabase
    private let lock = NSRecursiveLock()
    let columns = "id, kind, preview, source_bundle_id, source_app_name, copied_at, last_used_at, copy_count, paste_count, has_thumbnail, oversized, pinned, title, is_snippet"
    /// 貼り付けと検索に使う文字の上限。これを超える部分は生データにだけ残る。
    static let maxStoredTextLength = 1_000_000

    enum SaveResult: Equatable {
        case inserted(Int)
        case bumped(Int)
        var id: Int { switch self { case .inserted(let id), .bumped(let id): id } }
    }

    struct CleanupReport { var removedClips = 0; var removedBlobs = 0 }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pastephant", isDirectory: true)
    }

    init(directory: URL, schemaDirectory: URL) throws {
        self.directory = directory
        for name in ["database", "blobs", "thumbs"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        database = try SQLiteDatabase(path: directory.appendingPathComponent("database/history.sqlite3").path, journal: .wal)
        try database.migrate(schemaDirectory: schemaDirectory)
    }

    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func blobURL(_ hash: String) -> URL { directory.appendingPathComponent("blobs/\(hash.prefix(2))/\(hash).bin") }

    func thumbnailURL(_ id: Int) -> URL { directory.appendingPathComponent("thumbs/\(id).png") }

    // MARK: - 保存

    /// 同じ中身が既にあれば先頭へ移して回数を増やし、無ければ新しく保存する。
    @discardableResult
    func save(_ capture: Capture, maxItemBytes: Int) throws -> SaveResult {
        let hash = capture.contentHash
        let now = capture.date.timeIntervalSince1970
        return try locked {
            if let existing = try database.first("SELECT id FROM clips WHERE content_hash = ?", hash), let id = existing["id"] as? Int {
                try database.run("""
                    UPDATE clips SET copied_at = ?, last_used_at = ?, copy_count = copy_count + 1,
                      source_bundle_id = COALESCE(?, source_bundle_id), source_app_name = COALESCE(?, source_app_name) WHERE id = ?
                    """, now, now, capture.sourceBundleID, capture.sourceAppName, id)
                return .bumped(id)
            }
            return .inserted(try saveNew(capture, contentHash: hash, maxItemBytes: maxItemBytes))
        }
    }

    /// 重複を確かめずに新しい項目として保存する。
    func saveNew(_ capture: Capture, contentHash hash: String, maxItemBytes: Int = .max) throws -> Int {
        let now = capture.date.timeIntervalSince1970
        return try locked {
            let oversized = capture.totalBytes > maxItemBytes
            var blobs: [(item: Int, position: Int, type: String, hash: String, size: Int)] = []
            if !oversized {
                for (itemIndex, item) in capture.items.enumerated() {
                    for (position, representation) in item.enumerated() {
                        let blobHash = Capture.sha256(representation.data)
                        try writeBlob(representation.data, hash: blobHash)
                        blobs.append((itemIndex, position, representation.type, blobHash, representation.data.count))
                    }
                }
            }
            let text = capture.plainText.map { $0.count > Self.maxStoredTextLength ? String($0.prefix(Self.maxStoredTextLength)) : $0 }
            let fileNames = capture.fileNames
            let latex = capture.latex
            let id = try database.transaction { () -> Int in
                try database.run("""
                    INSERT INTO clips(kind, content_hash, text, preview, file_names, source_bundle_id, source_app_name,
                      created_at, copied_at, last_used_at, total_bytes, oversized, latex, ocr_state)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, capture.kind.rawValue, hash, text, capture.preview, fileNames, capture.sourceBundleID, capture.sourceAppName,
                    now, now, now, capture.totalBytes, oversized, latex?.json, capture.kind == .image && !oversized ? 0 : 2)
                let id = database.lastInsertRowID
                for blob in blobs {
                    try database.run("INSERT INTO clip_representations(clip_id, item_index, position, type, blob_hash, size) VALUES (?, ?, ?, ?, ?, ?)",
                                     id, blob.item, blob.position, blob.type, blob.hash, blob.size)
                }
                try database.run("INSERT INTO clip_search(rowid, text, ocr, latex, file_names, app_name) VALUES (?, ?, '', ?, ?, ?)",
                                 id, latex == nil ? text ?? "" : "", latex?.source ?? "", fileNames ?? "", capture.sourceAppName ?? "")
                return id
            }
            if let thumbnail = capture.makeThumbnail() {
                try? thumbnail.write(to: thumbnailURL(id), options: .atomic)
                try database.run("UPDATE clips SET has_thumbnail = 1 WHERE id = ?", id)
            }
            return id
        }
    }

    /// 一時ファイルに書いてから名前を変えて置く。同じ中身が既にあれば書かない。
    func writeBlob(_ data: Data, hash: String) throws {
        let url = blobURL(hash)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - 読み取り

    func summary(_ id: Int) throws -> ClipSummary? {
        try locked {
            guard var summary = try database.first("SELECT \(columns) FROM clips WHERE id = ?", id).map(ClipSummary.init) else { return nil }
            summary.tags = try tagNames(for: [id])[id] ?? []
            return summary
        }
    }

    /// プレビュー用。文字は先頭の maxTextLength 文字まで、画像は maxImageBytes までの物だけ読む。
    func detail(_ id: Int, maxTextLength: Int = 20_000, maxImageBytes: Int = 30 * 1024 * 1024) throws -> ClipDetail? {
        try locked {
            guard let row = try database.first("SELECT \(columns), substr(text, 1, ?) AS text, total_bytes, created_at, ocr_text, latex FROM clips WHERE id = ?", maxTextLength, id) else { return nil }
            let representations = try database.query("SELECT type, blob_hash, size FROM clip_representations WHERE clip_id = ? ORDER BY item_index, position", id)
            var types: [String] = []
            for type in representations.compactMap({ $0["type"] as? String }) where !types.contains(type) { types.append(type) }
            let image = Capture.imageTypes.lazy.compactMap { type in representations.first { $0["type"] as? String == type } }.first
            let imageData = image.flatMap { image -> Data? in
                guard let hash = image["blob_hash"] as? String, (image["size"] as? Int ?? 0) <= maxImageBytes else { return nil }
                return try? Data(contentsOf: blobURL(hash))
            }
            let filePaths = representations.filter { $0["type"] as? String == Capture.fileURLType }.compactMap { row -> String? in
                guard let hash = row["blob_hash"] as? String, let data = try? Data(contentsOf: blobURL(hash)), let string = String(data: data, encoding: .utf8) else { return nil }
                return URL(string: string)?.path
            }
            var summary = ClipSummary(row: row)
            summary.tags = try tagNames(for: [id])[id] ?? []
            return ClipDetail(summary: summary, text: row["text"] as? String, imageData: imageData, filePaths: filePaths, types: types,
                              totalBytes: row["total_bytes"] as? Int ?? 0, createdAt: Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0),
                              ocrText: row["ocr_text"] as? String, latex: (row["latex"] as? String).flatMap(LatexSource.init(json:)))
        }
    }

    func text(of id: Int) throws -> String? {
        try locked { try database.first("SELECT text FROM clips WHERE id = ?", id)?["text"] as? String }
    }

    /// 保存した生データを、元の項目・型の並びのまま返す。生データが欠けていれば nil。
    func representations(of id: Int) throws -> [[Representation]]? {
        let rows = try locked { try database.query("SELECT item_index, type, blob_hash FROM clip_representations WHERE clip_id = ? ORDER BY item_index, position", id) }
        guard !rows.isEmpty else { return nil }
        var items: [[Representation]] = []
        for row in rows {
            let index = row["item_index"] as? Int ?? 0
            guard let type = row["type"] as? String, let hash = row["blob_hash"] as? String,
                  let data = try? Data(contentsOf: blobURL(hash)) else { return nil }
            while items.count <= index { items.append([]) }
            items[index].append(Representation(type: type, data: data))
        }
        return items.filter { !$0.isEmpty }
    }

    func markUsed(_ id: Int, at date: Date = Date()) throws {
        try locked { _ = try database.run("UPDATE clips SET last_used_at = ?, paste_count = paste_count + 1 WHERE id = ?", date.timeIntervalSince1970, id) }
    }

    // MARK: - 削除と整理（F-15）

    /// 項目を消し、ほかから使われなくなった生データとサムネもすぐに消す。
    func delete(_ ids: [Int]) throws {
        guard !ids.isEmpty else { return }
        try locked {
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let hashes = Set(try database.rows("SELECT DISTINCT blob_hash FROM clip_representations WHERE clip_id IN (\(placeholders))", ids).compactMap { $0["blob_hash"] as? String })
            try database.transaction {
                _ = try database.rows("DELETE FROM clip_search WHERE rowid IN (\(placeholders))", ids)
                _ = try database.rows("DELETE FROM clips WHERE id IN (\(placeholders))", ids)
            }
            for id in ids { try? FileManager.default.removeItem(at: thumbnailURL(id)) }
            for hash in hashes {
                if try database.first("SELECT 1 AS used FROM clip_representations WHERE blob_hash = ? LIMIT 1", hash) == nil {
                    try? FileManager.default.removeItem(at: blobURL(hash))
                }
            }
        }
    }

    /// 種類ごとの期限、件数の上限、容量の上限の順に、古いものから消す。ピン留めと（設定によって）タグの付いたものは消さない。
    @discardableResult
    func cleanup(settings: Settings, now: Date = Date()) throws -> CleanupReport {
        try locked {
            var report = CleanupReport()
            let deletable = "pinned = 0 AND is_snippet = 0" + (settings.expireTagged ? "" : " AND id NOT IN (SELECT clip_id FROM clip_tags)")
            func remove(_ rows: [[String: Any]]) throws -> Int {
                let ids = rows.compactMap { $0["id"] as? Int }
                try delete(ids)
                return ids.count
            }
            for (kind, days) in settings.retentionDays where days > 0 {
                let limit = now.timeIntervalSince1970 - Double(days) * 86_400
                report.removedClips += try remove(database.query("SELECT id FROM clips WHERE kind = ? AND last_used_at < ? AND \(deletable)", kind, limit))
            }
            let count = try database.first("SELECT COUNT(*) AS n FROM clips")?["n"] as? Int ?? 0
            if count > settings.maxItems {
                report.removedClips += try remove(database.query("SELECT id FROM clips WHERE \(deletable) ORDER BY last_used_at ASC LIMIT ?", count - settings.maxItems))
            }
            while try usage().bytes > settings.maxTotalBytes {
                let removed = try remove(database.query("SELECT id FROM clips WHERE \(deletable) AND total_bytes > 0 AND oversized = 0 ORDER BY last_used_at ASC LIMIT 50"))
                report.removedClips += removed
                if removed == 0 { break }
            }
            report.removedBlobs = try collectGarbage()
            return report
        }
    }

    /// どの項目からも使われていない生データと、項目の無いサムネを消す。
    private func collectGarbage() throws -> Int {
        let manager = FileManager.default
        let used = Set(try database.query("SELECT DISTINCT blob_hash FROM clip_representations").compactMap { $0["blob_hash"] as? String })
        var removed = 0
        let blobs = directory.appendingPathComponent("blobs")
        for folder in (try? manager.contentsOfDirectory(atPath: blobs.path)) ?? [] {
            let folderURL = blobs.appendingPathComponent(folder)
            for file in (try? manager.contentsOfDirectory(atPath: folderURL.path)) ?? [] where file.hasSuffix(".bin") && !used.contains(String(file.dropLast(4))) {
                if (try? manager.removeItem(at: folderURL.appendingPathComponent(file))) != nil { removed += 1 }
            }
        }
        let ids = Set(try database.query("SELECT id FROM clips WHERE has_thumbnail = 1").compactMap { $0["id"] as? Int })
        let thumbs = directory.appendingPathComponent("thumbs")
        for file in (try? manager.contentsOfDirectory(atPath: thumbs.path)) ?? [] {
            guard let id = Int((file as NSString).deletingPathExtension), !ids.contains(id) else { continue }
            try? manager.removeItem(at: thumbs.appendingPathComponent(file))
        }
        return removed
    }

    /// 項目の数と、生データの合計（同じ中身は1つ分として数える）。
    func usage() throws -> (count: Int, bytes: Int) {
        try locked {
            let count = try database.first("SELECT COUNT(*) AS n FROM clips")?["n"] as? Int ?? 0
            let bytes = try database.first("SELECT COALESCE(SUM(size), 0) AS n FROM (SELECT MAX(size) AS size FROM clip_representations GROUP BY blob_hash)")?["n"] as? Int ?? 0
            return (count, bytes)
        }
    }
}
