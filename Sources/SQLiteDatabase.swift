import Foundation
import SQLite3

struct DatabaseError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// macOS標準のSQLiteを使う薄いラッパー（PopNote!の SQLiteDatabase.swift と同じ使い方）。
/// 履歴のDBはこのMacの中だけに置くのでWALで開く。基準パスに置くDBはシリーズと同じDELETEモードで開く。
final class SQLiteDatabase {
    enum Journal: String { case wal = "WAL", delete = "DELETE" }

    private var handle: OpaquePointer?

    init(path: String, journal: Journal = .wal) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(handle)
            throw DatabaseError(message: "データベースを開けませんでした: \(message)")
        }
        let synchronous = journal == .wal ? "NORMAL" : "FULL"
        try exec("PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000; PRAGMA journal_mode = \(journal.rawValue); PRAGMA synchronous = \(synchronous);")
    }

    deinit { sqlite3_close_v2(handle) }

    private var lastError: String { String(cString: sqlite3_errmsg(handle)) }

    var lastInsertRowID: Int { Int(sqlite3_last_insert_rowid(handle)) }

    func exec(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? lastError
            sqlite3_free(message)
            throw DatabaseError(message: text)
        }
    }

    private func prepare(_ sql: String, _ parameters: [Any?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DatabaseError(message: lastError) }
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case nil: sqlite3_bind_null(statement, index)
            case let value as Int: sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Int64: sqlite3_bind_int64(statement, index, value)
            case let value as Bool: sqlite3_bind_int64(statement, index, value ? 1 : 0)
            case let value as Double: sqlite3_bind_double(statement, index, value)
            case let value as String: sqlite3_bind_text(statement, index, value, -1, transientDestructor)
            default: sqlite3_bind_text(statement, index, String(describing: value!), -1, transientDestructor)
            }
        }
        return statement
    }

    /// 行を列名つきの辞書で返す。NULLの列は辞書に入れない。
    func query(_ sql: String, _ parameters: Any?...) throws -> [[String: Any]] { try rows(sql, parameters) }

    func first(_ sql: String, _ parameters: Any?...) throws -> [String: Any]? { try rows(sql, parameters).first }

    /// 条件の数が変わる検索など、引数を配列で渡したい場合に使う。
    func rows(_ sql: String, _ parameters: [Any?]) throws -> [[String: Any]] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: Any]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw DatabaseError(message: lastError) }
            var row: [String: Any] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, column)
                case SQLITE_NULL: break
                default: row[name] = String(cString: sqlite3_column_text(statement, column))
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// 変更した行数を返す。
    @discardableResult
    func run(_ sql: String, _ parameters: Any?...) throws -> Int {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError(message: lastError) }
        return Int(sqlite3_changes(handle))
    }

    /// 引数を配列で渡す版。
    @discardableResult
    func run(_ sql: String, values: [Any?]) throws -> Int {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError(message: lastError) }
        return Int(sqlite3_changes(handle))
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try exec("COMMIT")
            return value
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// schema/ のSQLをファイル名順に、まだ適用していないものだけ適用する。
    func migrate(schemaDirectory: URL) throws {
        try exec("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL) STRICT;")
        let applied = Set(try query("SELECT version FROM schema_migrations").compactMap { $0["version"] as? String })
        let files = try FileManager.default.contentsOfDirectory(atPath: schemaDirectory.path)
            .filter { $0.range(of: "^\\d+_[A-Za-z0-9_-]+\\.sql$", options: .regularExpression) != nil }.sorted()
        for file in files where !applied.contains(file) {
            let sql = try String(contentsOf: schemaDirectory.appendingPathComponent(file), encoding: .utf8)
            try transaction {
                try exec(sql)
                try run("INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)", file, ISO8601DateFormatter().string(from: Date()))
            }
        }
    }
}
