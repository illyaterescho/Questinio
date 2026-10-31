import Foundation
import SQLite3
public struct ConversationRecord: Identifiable, Sendable {
    public let id: Int64
    public let session: String
    public let date: Date
    public let question: String
    public let answer: String
}
public actor StorageManager {
    private var db: OpaquePointer?
    public init(url: URL = LocalPaths.support.appendingPathComponent("history.sqlite")) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pointer: OpaquePointer?
        guard sqlite3_open(url.path, &pointer) == SQLITE_OK else { if let pointer { sqlite3_close(pointer) }; throw CopilotError.message("Cannot open history database") }
        db = pointer
        sqlite3_busy_timeout(pointer, 3000)
        let sql = "PRAGMA journal_mode=DELETE; CREATE TABLE IF NOT EXISTS turns (id INTEGER PRIMARY KEY, session TEXT NOT NULL, date REAL NOT NULL, question TEXT NOT NULL, answer TEXT NOT NULL);"
        guard sqlite3_exec(pointer, sql, nil, nil, nil) == SQLITE_OK else { sqlite3_close(pointer); db = nil; throw CopilotError.message("Cannot create history database") }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    deinit { sqlite3_close(db) }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw CopilotError.message("History SQL error") }
        return stmt
    }
    private func bind(_ value: String, _ column: Int32, _ stmt: OpaquePointer) {
        _ = value.withCString { sqlite3_bind_text(stmt, column, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
    public func save(session: UUID, question: String, answer: String) throws {
        let stmt = try statement("INSERT INTO turns(session,date,question,answer) VALUES(?,?,?,?)"); defer { sqlite3_finalize(stmt) }
        bind(session.uuidString, 1, stmt); sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970); bind(question, 3, stmt); bind(answer, 4, stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw CopilotError.message("Cannot save history") }
    }
    public func records() throws -> [ConversationRecord] {
        let stmt = try statement("SELECT id,session,date,question,answer FROM turns ORDER BY id DESC LIMIT 300"); defer { sqlite3_finalize(stmt) }
        var records: [ConversationRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            records.append(ConversationRecord(id: sqlite3_column_int64(stmt, 0), session: String(cString: sqlite3_column_text(stmt, 1)), date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)), question: String(cString: sqlite3_column_text(stmt, 3)), answer: String(cString: sqlite3_column_text(stmt, 4))))
        }
        return records
    }
    public func deleteAll() throws {
        guard sqlite3_exec(db, "PRAGMA secure_delete=ON; DELETE FROM turns; VACUUM;", nil, nil, nil) == SQLITE_OK else { throw CopilotError.message("Cannot delete history") }
    }
}
