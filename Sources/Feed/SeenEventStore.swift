import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor SeenEventStore: SeenEventStoring {
    static let shared = SeenEventStore()

    private let databaseURL: URL
    private let nostrDatabase: FlowNostrDB
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxEventCount = 40_000
    private let maxRetainedNostrDBEventCount: Int
    private var database: OpaquePointer?

    init(
        fileManager: FileManager = .default,
        nostrDatabase: FlowNostrDB = .shared,
        maxRetainedNostrDBEventCount: Int = 30_000
    ) {
        self.nostrDatabase = nostrDatabase
        self.maxRetainedNostrDBEventCount = max(1, min(maxRetainedNostrDBEventCount, maxEventCount))
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.databaseURL = root.appendingPathComponent("x21-seen-events.sqlite", isDirectory: false)
        self.database = Self.openDatabase(at: databaseURL)
        Self.createSchema(in: database)
    }

    deinit {
        if let database {
            sqlite3_close_v2(database)
        }
    }

    func store(events: [NostrEvent]) {
        guard !events.isEmpty else { return }

        guard database != nil else { return }

        persistEventsToMirror(events)
        pruneIfNeeded()

        let ingested = nostrDatabase.ingest(events: events)
        if !ingested || nostrDatabase.requiresRebuild() {
            rebuildNostrDatabaseFromMirror()
        }
    }

    private func persistEventsToMirror(_ events: [NostrEvent]) {
        withTransaction {
            guard let statement = prepareStatement(
                """
                INSERT OR REPLACE INTO seen_events (
                    id,
                    pubkey,
                    kind,
                    created_at,
                    seen_at,
                    event_json
                ) VALUES (?, ?, ?, ?, ?, ?);
                """
            ) else {
                return
            }
            defer { sqlite3_finalize(statement) }

            let seenAt = Date().timeIntervalSince1970
            for event in events {
                guard let encoded = try? encoder.encode(event),
                      let json = String(data: encoded, encoding: .utf8) else {
                    continue
                }

                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)

                bindText(event.id, to: statement, index: 1)
                bindText(event.pubkey, to: statement, index: 2)
                sqlite3_bind_int64(statement, 3, Int64(event.kind))
                sqlite3_bind_int64(statement, 4, Int64(event.createdAt))
                sqlite3_bind_double(statement, 5, seenAt)
                bindText(json, to: statement, index: 6)

                sqlite3_step(statement)
            }
        }
    }

    private func rebuildNostrDatabaseFromMirror() {
        let retainedEvents = recentEventsForNostrDB(limit: maxRetainedNostrDBEventCount)
        guard !retainedEvents.isEmpty else { return }
        _ = nostrDatabase.rebuild(retaining: retainedEvents)
    }

    func storeRecentFeed(key: String, events: [NostrEvent]) {
        store(events: events)
        guard database != nil else { return }

        withTransaction {
            guard let deleteStatement = prepareStatement(
                "DELETE FROM recent_feed_events WHERE feed_key = ?;"
            ) else {
                return
            }
            bindText(key, to: deleteStatement, index: 1)
            sqlite3_step(deleteStatement)
            sqlite3_finalize(deleteStatement)

            guard !events.isEmpty else { return }
            guard let insertStatement = prepareStatement(
                """
                INSERT OR REPLACE INTO recent_feed_events (
                    feed_key,
                    position,
                    event_id,
                    stored_at
                ) VALUES (?, ?, ?, ?);
                """
            ) else {
                return
            }
            defer { sqlite3_finalize(insertStatement) }

            let storedAt = Date().timeIntervalSince1970
            for (index, event) in events.enumerated() {
                sqlite3_reset(insertStatement)
                sqlite3_clear_bindings(insertStatement)

                bindText(key, to: insertStatement, index: 1)
                sqlite3_bind_int64(insertStatement, 2, Int64(index))
                bindText(event.id, to: insertStatement, index: 3)
                sqlite3_bind_double(insertStatement, 4, storedAt)

                sqlite3_step(insertStatement)
            }
        }

    }

    func recentFeed(key: String) -> [NostrEvent]? {
        guard let statement = prepareStatement(
            """
            SELECT event_id
            FROM recent_feed_events
            WHERE feed_key = ?
            ORDER BY position ASC;
            """
        ) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bindText(key, to: statement, index: 1)

        var orderedIDs: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let eventID = columnText(statement, column: 0) else { continue }
            orderedIDs.append(eventID)
        }

        guard !orderedIDs.isEmpty else { return nil }

        let eventsByID = events(ids: orderedIDs)
        let events = orderedIDs.compactMap { eventsByID[$0.lowercased()] }
        return events.isEmpty ? nil : events
    }

    func events(ids: [String]) -> [String: NostrEvent] {
        let normalizedIDs = Array(
            Set(
                ids
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        )
        guard !normalizedIDs.isEmpty else { return [:] }

        if let resolvedByNostrDB = nostrDatabase.events(ids: normalizedIDs) {
            let missingIDs = normalizedIDs.filter { resolvedByNostrDB[$0] == nil }
            guard !missingIDs.isEmpty else {
                return resolvedByNostrDB
            }

            var merged = resolvedByNostrDB
            let legacyResolved = legacyEvents(ids: missingIDs)
            for (eventID, event) in legacyResolved {
                merged[eventID] = event
            }
            return merged
        }

        return legacyEvents(ids: normalizedIDs)
    }

    private func legacyEvents(ids: [String]) -> [String: NostrEvent] {
        var decoded: [String: NostrEvent] = [:]
        for chunk in ids.chunked(into: 250) {
            guard let statement = prepareStatement(
                """
                SELECT id, event_json
                FROM seen_events
                WHERE id IN (\(sqlPlaceholders(count: chunk.count)));
                """
            ) else {
                continue
            }

            for (index, eventID) in chunk.enumerated() {
                bindText(eventID, to: statement, index: Int32(index + 1))
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let eventID = columnText(statement, column: 0),
                      let event = decodeEvent(from: statement, column: 1) else {
                    continue
                }
                decoded[eventID] = event
            }

            sqlite3_finalize(statement)
        }

        return decoded
    }

    private static func openDatabase(at databaseURL: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        if sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK {
            sqlite3_busy_timeout(database, 1_500)
            sqlite3_exec(database, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            sqlite3_exec(database, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        } else {
            if let database {
                sqlite3_close_v2(database)
            }
            database = nil
        }

        return database
    }

    private static func createSchema(in database: OpaquePointer?) {
        guard let database else { return }

        let statements = [
            """
            CREATE TABLE IF NOT EXISTS seen_events (
                id TEXT PRIMARY KEY,
                pubkey TEXT NOT NULL,
                kind INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                seen_at REAL NOT NULL,
                event_json TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS recent_feed_events (
                feed_key TEXT NOT NULL,
                position INTEGER NOT NULL,
                event_id TEXT NOT NULL,
                stored_at REAL NOT NULL,
                PRIMARY KEY (feed_key, position)
            );
            """,
            "CREATE INDEX IF NOT EXISTS seen_events_seen_at_idx ON seen_events(seen_at ASC);",
            "CREATE INDEX IF NOT EXISTS seen_events_created_at_idx ON seen_events(created_at DESC);",
            "CREATE INDEX IF NOT EXISTS recent_feed_events_feed_key_idx ON recent_feed_events(feed_key);"
        ]

        for statement in statements {
            sqlite3_exec(database, statement, nil, nil, nil)
        }
    }

    private func withTransaction(_ body: () -> Void) {
        guard let database else { return }
        sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
        body()
        sqlite3_exec(database, "COMMIT TRANSACTION;", nil, nil, nil)
    }

    private func prepareStatement(_ sql: String) -> OpaquePointer? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }
        return statement
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func decodeEvent(from statement: OpaquePointer?, column: Int32) -> NostrEvent? {
        guard let json = columnText(statement, column: column),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(NostrEvent.self, from: data)
    }

    private func columnText(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: raw)
    }

    private func pruneIfNeeded() {
        guard let database else { return }

        guard let countStatement = prepareStatement("SELECT COUNT(*) FROM seen_events;") else {
            return
        }
        defer { sqlite3_finalize(countStatement) }

        guard sqlite3_step(countStatement) == SQLITE_ROW else { return }
        let count = Int(sqlite3_column_int64(countStatement, 0))
        guard count > maxEventCount else { return }

        let overflow = count - maxEventCount
        let sql =
            """
            DELETE FROM seen_events
            WHERE id IN (
                SELECT id
                FROM seen_events
                WHERE id NOT IN (
                    SELECT DISTINCT event_id
                    FROM recent_feed_events
                )
                ORDER BY seen_at ASC
                LIMIT \(overflow)
            );
            """
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func recentEventsForNostrDB(limit: Int) -> [NostrEvent] {
        guard limit > 0 else { return [] }
        guard let statement = prepareStatement(
            """
            SELECT event_json
            FROM seen_events
            ORDER BY seen_at DESC, created_at DESC
            LIMIT ?;
            """
        ) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(limit))

        var events: [NostrEvent] = []
        events.reserveCapacity(limit)

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let event = decodeEvent(from: statement, column: 0) else { continue }
            events.append(event)
        }

        return events
    }

    private func sqlPlaceholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)

        var index = startIndex
        while index < endIndex {
            let nextIndex = Swift.min(index + size, endIndex)
            result.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }

        return result
    }
}
