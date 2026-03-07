import Foundation
import SQLite3

enum MessagesDBHealth {

    /// Location of the local Messages database.
    /// Note: reading this file requires Full Disk Access for most users.
    static func chatDBURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Messages")
            .appendingPathComponent("chat.db")
    }

    /// Simple gate check used by the onboarding screen.
    static func hasAccess() -> Bool {
        let url = chatDBURL()

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return false
        }

        sqlite3_close(db)
        return true
    }
}
