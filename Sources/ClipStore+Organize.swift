import Foundation

/// 一覧の並べ替え（F-05）。
enum SortOrder: String, CaseIterable, Codable {
    case lastUsed, copied, useCount, kind, app

    var label: String {
        switch self {
        case .lastUsed: "最後に使った順"
        case .copied: "コピーした順"
        case .useCount: "使った回数順"
        case .kind: "種類ごと"
        case .app: "コピー元のアプリごと"
        }
    }

    var sql: String {
        switch self {
        case .lastUsed: "last_used_at DESC, id DESC"
        case .copied: "copied_at DESC, id DESC"
        case .useCount: "(copy_count + paste_count) DESC, last_used_at DESC"
        case .kind: "kind, last_used_at DESC"
        case .app: "source_app_name IS NULL, source_app_name COLLATE NOCASE, last_used_at DESC"
        }
    }
}

/// 検索欄の文字を、ふつうの語と絞り込み（#タグ、type:、app:、is:pinned、after:、before:）に分ける（F-05）。
struct ClipQuery: Equatable {
    var terms: [String] = []
    var tags: [String] = []
    var kinds: [ClipKind] = []
    var snippetsOnly = false
    var apps: [String] = []
    var pinnedOnly = false
    var after: Date?
    var before: Date?
    /// その日（このMacの日付）に Tomelet へ残した物（Tomelet の日ごとのメモから開くとき）。
    var exportedDay: Date?

    static let kindAliases: [String: ClipKind] = [
        "text": .text, "テキスト": .text, "rich": .richText, "richtext": .richText, "書式": .richText, "書式付き": .richText,
        "image": .image, "画像": .image, "file": .file, "ファイル": .file, "url": .url, "link": .url, "リンク": .url,
        "color": .color, "色": .color, "office": .office, "オブジェクト": .office, "formula": .formula, "数式": .formula,
    ]

    init(_ text: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        for token in text.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            let lower = token.lowercased()
            if token.hasPrefix("#"), token.count > 1 { tags.append(String(token.dropFirst())) }
            else if lower.hasPrefix("type:") || lower.hasPrefix("種類:") {
                let value = String(token.split(separator: ":", maxSplits: 1).last ?? "")
                if ["snippet", "定型文"].contains(value.lowercased()) { snippetsOnly = true }
                else if let kind = Self.kindAliases[value.lowercased()] ?? ClipKind(rawValue: value) { kinds.append(kind) }
                else { terms.append(token) }
            }
            else if lower.hasPrefix("app:"), token.count > 4 { apps.append(String(token.dropFirst(4))) }
            else if lower == "is:pinned" || lower == "is:pin" || token == "ピン" { pinnedOnly = true }
            else if lower.hasPrefix("after:"), let date = formatter.date(from: String(token.dropFirst(6))) { after = date }
            else if lower.hasPrefix("before:"), let date = formatter.date(from: String(token.dropFirst(7))) { before = date.addingTimeInterval(86_400) }
            else if lower.hasPrefix("exported:"), let date = formatter.date(from: String(token.dropFirst(9))) { exportedDay = date }
            else { terms.append(token) }
        }
    }

    var isEmpty: Bool { self == ClipQuery("") }
}

/// 共有タグ（Tomelet・PopNote! と同じ tags 表）の1件。
struct Tag: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
}

extension ClipStore {
    private static func likePattern(_ term: String) -> String {
        "%" + term.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
    }

    // MARK: - 一覧と検索（F-05）

    /// 検索と絞り込みをした一覧。空白で区切った語は全てを含むもの（3文字以上は全文検索、それより短い語は部分一致。タグの名前も対象）。
    func recent(query: String = "", sort: SortOrder = .lastUsed, limit: Int = 300, excludePinned: Bool = false) throws -> [ClipSummary] {
        let parsed = ClipQuery(query)
        var conditions: [String] = [], parameters: [Any?] = []
        let tagMatch = "EXISTS (SELECT 1 FROM clip_tags ct JOIN tags t ON t.id = ct.tag_id WHERE ct.clip_id = clips.id AND t.name LIKE ? ESCAPE '\\')"
        for term in parsed.terms {
            let pattern = Self.likePattern(term)
            if term.count >= 3 {
                conditions.append("(id IN (SELECT rowid FROM clip_search WHERE clip_search MATCH ?) OR title LIKE ? ESCAPE '\\' OR \(tagMatch))")
                parameters += ["\"\(term.replacingOccurrences(of: "\"", with: "\"\""))\"", pattern, pattern]
            } else {
                conditions.append("(text LIKE ? ESCAPE '\\' OR preview LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\' OR file_names LIKE ? ESCAPE '\\' OR source_app_name LIKE ? ESCAPE '\\' OR ocr_text LIKE ? ESCAPE '\\' OR \(tagMatch))")
                parameters += Array(repeating: pattern, count: 7)
            }
        }
        for tag in parsed.tags {
            conditions.append("EXISTS (SELECT 1 FROM clip_tags ct JOIN tags t ON t.id = ct.tag_id WHERE ct.clip_id = clips.id AND t.name = ? COLLATE NOCASE)")
            parameters.append(tag)
        }
        if !parsed.kinds.isEmpty {
            conditions.append("kind IN (\(parsed.kinds.map { _ in "?" }.joined(separator: ", ")))")
            parameters += parsed.kinds.map(\.rawValue)
        }
        if parsed.snippetsOnly { conditions.append("is_snippet = 1") }
        for app in parsed.apps {
            conditions.append("(source_app_name LIKE ? ESCAPE '\\' OR source_bundle_id LIKE ? ESCAPE '\\')")
            parameters += [Self.likePattern(app), Self.likePattern(app)]
        }
        if parsed.pinnedOnly { conditions.append("pinned = 1") }
        if excludePinned { conditions.append("pinned = 0") }
        if let after = parsed.after { conditions.append("copied_at >= ?"); parameters.append(after.timeIntervalSince1970) }
        if let before = parsed.before { conditions.append("copied_at < ?"); parameters.append(before.timeIntervalSince1970) }
        if let day = parsed.exportedDay {
            conditions.append("exported_at >= ? AND exported_at < ?")
            parameters += [day.timeIntervalSince1970, Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: day)!.timeIntervalSince1970]
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        parameters.append(limit)
        return try locked {
            try withTags(database.rows("SELECT \(columns) FROM clips \(whereClause) ORDER BY \(sort.sql) LIMIT ?", parameters).map(ClipSummary.init))
        }
    }

    /// ピン留めした項目と定型文（並び順どおり）。
    func pinned() throws -> [ClipSummary] {
        try locked { try withTags(database.query("SELECT \(columns) FROM clips WHERE pinned = 1 ORDER BY pin_order, id").map(ClipSummary.init)) }
    }

    private func withTags(_ summaries: [ClipSummary]) throws -> [ClipSummary] {
        let names = try tagNames(for: summaries.map(\.id))
        return summaries.map { summary in
            var summary = summary
            summary.tags = names[summary.id] ?? []
            return summary
        }
    }

    func tagNames(for ids: [Int]) throws -> [Int: [String]] {
        guard !ids.isEmpty else { return [:] }
        var result: [Int: [String]] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let rows = try database.rows("SELECT ct.clip_id AS clipId, t.name FROM clip_tags ct JOIN tags t ON t.id = ct.tag_id WHERE ct.clip_id IN (\(chunk.map { _ in "?" }.joined(separator: ", "))) AND t.deleted_at IS NULL ORDER BY t.name", chunk)
            for row in rows { if let id = row["clipId"] as? Int, let name = row["name"] as? String { result[id, default: []].append(name) } }
        }
        return result
    }

    // MARK: - タグ（F-04）

    /// 使えるタグ（アーカイブ・削除していないもの）。
    func allTags() throws -> [Tag] {
        try locked {
            try database.query("SELECT id, name FROM tags WHERE archived_at IS NULL AND deleted_at IS NULL ORDER BY name COLLATE NOCASE").compactMap { row in
                guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
                return Tag(id: id, name: name)
            }
        }
    }

    func tags(of id: Int) throws -> [Tag] {
        try locked {
            try database.query("SELECT t.id, t.name FROM clip_tags ct JOIN tags t ON t.id = ct.tag_id WHERE ct.clip_id = ? AND t.deleted_at IS NULL ORDER BY t.name", id).compactMap { row in
                guard let tagID = row["id"] as? String, let name = row["name"] as? String else { return nil }
                return Tag(id: tagID, name: name)
            }
        }
    }

    /// 名前の同じタグがあればそれを、無ければ「その他」の分類に新しく作る（PopNote! の findOrCreateTag と同じ）。アーカイブ済みなら戻す。
    func findOrCreateTag(_ name: String) throws -> Tag {
        let value = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !value.isEmpty else { throw DatabaseError(message: "タグの名前を入力してください。") }
        return try locked {
            if let row = try database.first("SELECT id, name, archived_at FROM tags WHERE name = ? AND deleted_at IS NULL", value), let id = row["id"] as? String {
                if row["archived_at"] != nil { try database.run("UPDATE tags SET archived_at = NULL, revision = revision + 1 WHERE id = ?", id) }
                return Tag(id: id, name: value)
            }
            if try database.first("SELECT 1 AS found FROM tag_categories WHERE id = 'other'") == nil {
                try database.run("INSERT INTO tag_categories(id, name, description, display_order) VALUES ('other', 'その他', 'ほかの分類に当てはまらないもの', 8)")
            }
            let id = "tag-\(UUID().uuidString.lowercased())"
            let order = try database.first("SELECT coalesce(max(display_order), 0) + 1 AS next FROM tags WHERE category_id = 'other'")?["next"] as? Int ?? 1
            try database.run("INSERT INTO tags(id, category_id, name, description, display_order) VALUES (?, 'other', ?, '', ?)", id, value, order)
            return Tag(id: id, name: value)
        }
    }

    func addTag(_ tag: Tag, to ids: [Int], source: String = "manual") throws {
        try locked {
            try database.transaction {
                for id in ids { try database.run("INSERT OR IGNORE INTO clip_tags(clip_id, tag_id, source) VALUES (?, ?, ?)", id, tag.id, source) }
            }
        }
    }

    func removeTag(_ tagID: String, from ids: [Int]) throws {
        try locked {
            try database.transaction {
                for id in ids { try database.run("DELETE FROM clip_tags WHERE clip_id = ? AND tag_id = ?", id, tagID) }
            }
        }
    }

    /// 共有タグ（<基準パス>/.kobito-tools/Tags/tags.json）と、この履歴のDBの写しを統合する。
    func syncTags(basePath: String) throws {
        try locked { try TagStore.sync(database, basePath: basePath) }
    }

    // MARK: - ピン留め（F-09）

    func setPinned(_ ids: [Int], _ pinned: Bool) throws {
        try locked {
            try database.transaction {
                for id in ids {
                    if pinned {
                        let next = try database.first("SELECT coalesce(max(pin_order), 0) + 1 AS next FROM clips WHERE pinned = 1")?["next"] as? Int ?? 1
                        try database.run("UPDATE clips SET pinned = 1, pin_order = ? WHERE id = ? AND pinned = 0", next, id)
                    } else {
                        try database.run("UPDATE clips SET pinned = 0, pin_order = NULL WHERE id = ? AND is_snippet = 0", id)
                    }
                }
            }
        }
    }

    /// ピンの並びで、前（-1）か後ろ（+1）の項目と入れ替える。
    func movePin(_ id: Int, by delta: Int) throws {
        try locked {
            var ids = try database.query("SELECT id FROM clips WHERE pinned = 1 ORDER BY pin_order, id").compactMap { $0["id"] as? Int }
            guard let index = ids.firstIndex(of: id), ids.indices.contains(index + delta) else { return }
            ids.swapAt(index, index + delta)
            try database.transaction {
                for (order, id) in ids.enumerated() { try database.run("UPDATE clips SET pin_order = ? WHERE id = ?", order + 1, id) }
            }
        }
    }

    // MARK: - 定型文（F-09）

    /// 定型文を作る。中身はふつうのテキストの項目として保存し、ピンの欄に並べる。
    @discardableResult
    func createSnippet(title: String, body: String) throws -> Int {
        let capture = Capture(items: [[Representation(type: Capture.plainTextType, data: Data(body.utf8))]], sourceBundleID: Bundle.main.bundleIdentifier, sourceAppName: "定型文", plainText: body)
        return try locked {
            // 同じ中身の履歴があっても、定型文は別の項目にする。
            let id = try saveNew(capture, contentHash: "snippet-\(UUID().uuidString.lowercased())")
            let next = try database.first("SELECT coalesce(max(pin_order), 0) + 1 AS next FROM clips WHERE pinned = 1")?["next"] as? Int ?? 1
            try database.run("UPDATE clips SET is_snippet = 1, pinned = 1, pin_order = ?, title = ? WHERE id = ?", next, title.isEmpty ? nil : title, id)
            return id
        }
    }

    func updateSnippet(_ id: Int, title: String, body: String) throws {
        try locked {
            let blobHash = Capture.sha256(Data(body.utf8))
            try writeBlob(Data(body.utf8), hash: blobHash)
            try database.transaction {
                try database.run("UPDATE clips SET title = ?, text = ?, preview = ?, total_bytes = ? WHERE id = ? AND is_snippet = 1", title.isEmpty ? nil : title, body, Capture.shorten(body), body.utf8.count, id)
                try database.run("DELETE FROM clip_representations WHERE clip_id = ?", id)
                try database.run("INSERT INTO clip_representations(clip_id, item_index, position, type, blob_hash, size) VALUES (?, 0, 0, ?, ?, ?)", id, Capture.plainTextType, blobHash, body.utf8.count)
                try database.run("UPDATE clip_search SET text = ? WHERE rowid = ?", body, id)
            }
        }
    }

    func setTitle(_ id: Int, _ title: String?) throws {
        try locked { _ = try database.run("UPDATE clips SET title = ? WHERE id = ?", title?.isEmpty == false ? title : nil, id) }
    }

    /// 編集したテキストやまとめたテキストを、新しい項目として保存する（F-10, F-11）。
    @discardableResult
    func saveText(_ text: String, sourceName: String) throws -> Int {
        let capture = Capture(items: [[Representation(type: Capture.plainTextType, data: Data(text.utf8))]], sourceBundleID: Bundle.main.bundleIdentifier, sourceAppName: sourceName, plainText: text)
        return try save(capture, maxItemBytes: .max).id
    }

    // MARK: - 文字認識（F-08）

    /// まだ文字を読んでいない画像（新しい順）。
    func pendingOCR(limit: Int = 20) throws -> [(id: Int, data: Data)] {
        try locked {
            try database.query("SELECT c.id, r.blob_hash, r.type FROM clips c JOIN clip_representations r ON r.clip_id = c.id WHERE c.ocr_state = 0 AND c.kind = 'image' ORDER BY c.id DESC").reduce(into: [(id: Int, data: Data)]()) { result, row in
                guard result.count < limit, let id = row["id"] as? Int, !result.contains(where: { $0.id == id }),
                      let type = row["type"] as? String, Capture.imageTypes.contains(type), type != "com.adobe.pdf",
                      let hash = row["blob_hash"] as? String, let data = try? Data(contentsOf: blobURL(hash)) else { return }
                result.append((id, data))
            }
        }
    }

    func setOCR(_ id: Int, text: String?) throws {
        try locked {
            let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            try database.transaction {
                try database.run("UPDATE clips SET ocr_text = ?, ocr_state = ? WHERE id = ?", value?.isEmpty == false ? value : nil, value?.isEmpty == false ? 1 : 2, id)
                try database.run("UPDATE clip_search SET ocr = ? WHERE rowid = ?", value ?? "", id)
            }
        }
    }

    /// 1つの型の生データだけを読む（HTML の表など。全ての生データは読まない）。
    func data(of id: Int, type: String) throws -> Data? {
        guard let hash = try locked({ try database.first("SELECT blob_hash FROM clip_representations WHERE clip_id = ? AND type = ? ORDER BY item_index, position LIMIT 1", id, type)?["blob_hash"] as? String }) else { return nil }
        return try? Data(contentsOf: blobURL(hash))
    }

    func ocrText(of id: Int) throws -> String? {
        try locked { try database.first("SELECT ocr_text FROM clips WHERE id = ?", id)?["ocr_text"] as? String }
    }

    func latex(of id: Int) throws -> LatexSource? {
        try locked { (try database.first("SELECT latex FROM clips WHERE id = ?", id)?["latex"] as? String).flatMap(LatexSource.init(json:)) }
    }

    // MARK: - Tomelet への書き出し（F-17）

    func markExported(_ ids: [Int], at date: Date = Date()) throws {
        try locked {
            try database.transaction { for id in ids { try database.run("UPDATE clips SET exported_at = ? WHERE id = ?", date.timeIntervalSince1970, id) } }
        }
    }

    func exportedAt(_ id: Int) throws -> Date? {
        try locked { (try database.first("SELECT exported_at FROM clips WHERE id = ?", id)?["exported_at"] as? Double).map(Date.init(timeIntervalSince1970:)) }
    }
}
