import Foundation
import SQLite3

struct SQLiteError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// A minimal wrapper over the system SQLite, for reading other apps' databases.
final class SQLiteDatabase {
    private let handle: OpaquePointer

    /// Opens read-write so SQLite can replay a WAL file; only use on files you own.
    init(_ url: URL, create: Bool = false) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "error \(status)"
            sqlite3_close(handle)
            throw SQLiteError(message: "\(url.lastPathComponent): \(message)")
        }
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError }
    }

    func query(_ sql: String, row: (Row) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError
        }
        defer { sqlite3_finalize(statement) }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try row(Row(statement: statement))
            case SQLITE_DONE: return
            default: throw lastError
            }
        }
    }

    private var lastError: SQLiteError {
        SQLiteError(message: String(cString: sqlite3_errmsg(handle)))
    }

    struct Row {
        fileprivate let statement: OpaquePointer

        func int(_ column: Int32) -> Int64 {
            sqlite3_column_int64(statement, column)
        }

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
    }
}
