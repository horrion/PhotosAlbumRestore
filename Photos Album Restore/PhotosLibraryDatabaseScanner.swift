//
//  PhotosLibraryDatabaseScanner.swift
//  Photos Album Restore
//
//  Reads album membership from a .photoslibrary package via Photos.sqlite
//  without opening it in Photos.app / PhotoKit.
//

import Foundation
import SQLite3

actor PhotosLibraryDatabaseScanner {

    enum ScannerError: LocalizedError {
        case libraryNotFound(URL)
        case databaseNotFound(URL)
        case openFailed(String)
        case schemaDiscoveryFailed(String)
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .libraryNotFound(let url):
                return "Photos-Mediathek nicht gefunden: \(url.path)"
            case .databaseNotFound(let url):
                return "Photos.sqlite nicht gefunden in: \(url.path)"
            case .openFailed(let message):
                return "Konnte Photos.sqlite nicht öffnen: \(message)"
            case .schemaDiscoveryFailed(let message):
                return "Unbekanntes Photos-Datenbankschema: \(message)"
            case .queryFailed(let message):
                return "Abfrage der Backup-Mediathek fehlgeschlagen: \(message)"
            }
        }
    }

    private struct AlbumAssetJoinSchema {
        let tableName: String
        let albumColumn: String
        let assetColumn: String
        let sortColumn: String
    }

    private struct AlbumRow {
        let pk: Int64
        let uuid: String
        let title: String
    }

    private struct MembershipRow {
        let albumPK: Int64
        let assetUUID: String
        let kind: Int
        let creationTimestamp: Double?
        let modificationTimestamp: Double?
        let width: Int
        let height: Int
        let duration: Double?
        let originalFilename: String?
    }

    func createAlbumManifest(
        libraryURL: URL,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> AlbumManifest {
        let databaseURL = try resolveDatabaseURL(libraryURL: libraryURL)

        progressHandler(0.02, "Öffne Backup-Datenbank…")

        let connection = try openReadOnlyConnection(databaseURL: databaseURL)
        defer { connection.close() }

        progressHandler(0.05, "Ermittle Schema…")

        let joinSchema = try discoverAlbumAssetJoinSchema(connection: connection)
        let hasAdditionalAttributes = connection.columnExists(
            table: "ZASSET",
            column: "ZADDITIONALATTRIBUTES"
        )

        progressHandler(0.1, "Lese Alben…")

        let albums = try fetchAlbums(connection: connection)
        guard !albums.isEmpty else {
            return AlbumManifest(generatedAt: Date(), albums: [])
        }

        var assetsByAlbumPK: [Int64: [AlbumManifestAsset]] = [:]
        for album in albums {
            assetsByAlbumPK[album.pk] = []
        }

        progressHandler(0.15, "Lese Album-Inhalte…")

        let membershipRows = try fetchAlbumMembership(
            connection: connection,
            joinSchema: joinSchema,
            hasAdditionalAttributes: hasAdditionalAttributes
        )

        let totalRows = max(membershipRows.count, 1)
        for (index, row) in membershipRows.enumerated() {
            guard assetsByAlbumPK[row.albumPK] != nil else { continue }

            let asset = AlbumManifestAsset(
                localIdentifier: "\(row.assetUUID)/L0/001",
                mediaType: mediaTypeString(kind: row.kind),
                originalFilename: row.originalFilename,
                creationDate: cocoaDate(row.creationTimestamp),
                modificationDate: cocoaDate(row.modificationTimestamp),
                pixelWidth: row.width,
                pixelHeight: row.height,
                duration: row.kind == 1 ? row.duration : nil
            )

            assetsByAlbumPK[row.albumPK, default: []].append(asset)

            if index % 250 == 0 || index + 1 == membershipRows.count {
                let progress = 0.15 + (0.8 * Double(index + 1) / Double(totalRows))
                progressHandler(
                    progress,
                    "Scanne Backup-Asset \(index + 1) von \(membershipRows.count)"
                )
            }
        }

        progressHandler(0.97, "Baue Manifest…")

        let manifestAlbums = albums.map { album in
            AlbumManifestAlbum(
                name: album.title,
                collectionLocalIdentifier: "\(album.uuid)/L0/040",
                assets: assetsByAlbumPK[album.pk] ?? []
            )
        }

        return AlbumManifest(
            generatedAt: Date(),
            albums: manifestAlbums
        )
    }

    // MARK: - Database location

    private func resolveDatabaseURL(libraryURL: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: libraryURL.path, isDirectory: &isDirectory) else {
            throw ScannerError.libraryNotFound(libraryURL)
        }

        let databaseDirectory = libraryURL.appendingPathComponent("database", isDirectory: true)
        let candidates = [
            databaseDirectory.appendingPathComponent("Photos.sqlite"),
            databaseDirectory.appendingPathComponent("photos.sqlite")
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        throw ScannerError.databaseNotFound(libraryURL)
    }

    private func openReadOnlyConnection(databaseURL: URL) throws -> SQLiteConnection {
        do {
            return try SQLiteConnection(path: databaseURL.path)
        } catch {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PhotosAlbumRestore-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

            let copyURL = temporaryDirectory.appendingPathComponent("Photos.sqlite")
            try FileManager.default.copyItem(at: databaseURL, to: copyURL)

            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
                if FileManager.default.fileExists(atPath: sidecar.path) {
                    let destination = URL(fileURLWithPath: copyURL.path + suffix)
                    try? FileManager.default.copyItem(at: sidecar, to: destination)
                }
            }

            do {
                return try SQLiteConnection(path: copyURL.path)
            } catch {
                throw ScannerError.openFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Schema discovery

    private func discoverAlbumAssetJoinSchema(connection: SQLiteConnection) throws -> AlbumAssetJoinSchema {
        let tableNames = try connection.stringList(
            sql: "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z_%ASSETS'"
        )

        guard let tableName = tableNames.first(where: {
            $0.range(of: #"^Z_\d+ASSETS$"#, options: .regularExpression) != nil
        }) else {
            throw ScannerError.schemaDiscoveryFailed(
                "Keine Album-Asset-Zuordnungstabelle gefunden (\(tableNames.joined(separator: ", ")))."
            )
        }

        let columns = try connection.tableInfo(tableName: tableName)

        guard let albumColumn = columns.first(where: {
            $0.range(of: #"^Z_\d+ALBUMS$"#, options: .regularExpression) != nil
        }) else {
            throw ScannerError.schemaDiscoveryFailed("Keine ALBUMS-Spalte in \(tableName).")
        }

        guard let assetColumn = columns.first(where: {
            $0.range(of: #"^Z_\d+ASSETS$"#, options: .regularExpression) != nil
        }) else {
            throw ScannerError.schemaDiscoveryFailed("Keine ASSETS-Spalte in \(tableName).")
        }

        guard let sortColumn = columns.first(where: {
            $0.range(of: #"^Z_FOK_\d+ASSETS$"#, options: .regularExpression) != nil
        }) else {
            throw ScannerError.schemaDiscoveryFailed("Keine Sortier-Spalte in \(tableName).")
        }

        return AlbumAssetJoinSchema(
            tableName: tableName,
            albumColumn: albumColumn,
            assetColumn: assetColumn,
            sortColumn: sortColumn
        )
    }

    // MARK: - Queries

    private func fetchAlbums(connection: SQLiteConnection) throws -> [AlbumRow] {
        let sql = """
        SELECT Z_PK, ZUUID, ZTITLE
        FROM ZGENERICALBUM
        WHERE ZKIND = 2
          AND COALESCE(ZTRASHEDSTATE, 0) = 0
          AND ZPARENTFOLDER IS NOT NULL
          AND ZTITLE IS NOT NULL
        ORDER BY ZTITLE COLLATE NOCASE
        """

        return try connection.query(sql: sql) { statement in
            let pk = sqlite3_column_int64(statement, 0)
            guard let uuid = Self.textColumn(statement, 1),
                  let title = Self.textColumn(statement, 2) else {
                return nil
            }
            return AlbumRow(pk: pk, uuid: uuid, title: title)
        }
    }

    private func fetchAlbumMembership(
        connection: SQLiteConnection,
        joinSchema: AlbumAssetJoinSchema,
        hasAdditionalAttributes: Bool
    ) throws -> [MembershipRow] {
        let filenameJoin: String
        let filenameSelect: String

        if hasAdditionalAttributes {
            filenameJoin = "LEFT JOIN ZADDITIONALASSETATTRIBUTES ZAA ON ZA.ZADDITIONALATTRIBUTES = ZAA.Z_PK"
            filenameSelect = "ZAA.ZORIGINALFILENAME"
        } else if connection.columnExists(table: "ZADDITIONALASSETATTRIBUTES", column: "ZASSET") {
            filenameJoin = "LEFT JOIN ZADDITIONALASSETATTRIBUTES ZAA ON ZAA.ZASSET = ZA.Z_PK"
            filenameSelect = "ZAA.ZORIGINALFILENAME"
        } else {
            filenameJoin = ""
            filenameSelect = "NULL"
        }

        let assetTable = connection.tableExists("ZASSET") ? "ZASSET" : "ZGENERICASSET"

        let sql = """
        SELECT
            ZAL.\(joinSchema.albumColumn) AS album_pk,
            ZA.ZUUID AS asset_uuid,
            ZA.ZKIND AS asset_kind,
            ZA.ZDATECREATED AS created_at,
            ZA.ZMODIFICATIONDATE AS modified_at,
            COALESCE(ZA.ZWIDTH, 0) AS width,
            COALESCE(ZA.ZHEIGHT, 0) AS height,
            ZA.ZDURATION AS duration,
            \(filenameSelect) AS original_filename
        FROM \(joinSchema.tableName) ZAL
        JOIN \(assetTable) ZA ON ZA.Z_PK = ZAL.\(joinSchema.assetColumn)
        \(filenameJoin)
        WHERE COALESCE(ZA.ZTRASHEDSTATE, 0) = 0
        ORDER BY ZAL.\(joinSchema.albumColumn), ZAL.\(joinSchema.sortColumn)
        """

        return try connection.query(sql: sql) { statement in
            guard let assetUUID = Self.textColumn(statement, 1) else { return nil }

            return MembershipRow(
                albumPK: sqlite3_column_int64(statement, 0),
                assetUUID: assetUUID,
                kind: Int(sqlite3_column_int(statement, 2)),
                creationTimestamp: Self.optionalDoubleColumn(statement, 3),
                modificationTimestamp: Self.optionalDoubleColumn(statement, 4),
                width: Int(sqlite3_column_int(statement, 5)),
                height: Int(sqlite3_column_int(statement, 6)),
                duration: Self.optionalDoubleColumn(statement, 7),
                originalFilename: Self.textColumn(statement, 8)
            )
        }
    }

    // MARK: - Helpers

    private func mediaTypeString(kind: Int) -> String {
        switch kind {
        case 0:
            return "image"
        case 1:
            return "video"
        default:
            return "unknown"
        }
    }

    private func cocoaDate(_ timestamp: Double?) -> Date? {
        guard let timestamp else { return nil }
        return Date(timeIntervalSinceReferenceDate: timestamp)
    }

    private static func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private static func optionalDoubleColumn(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }

    // MARK: - SQLite wrapper

    private final class SQLiteConnection {
        private var db: OpaquePointer?
        private static let sqliteTransient = unsafeBitCast(
            -1,
            to: sqlite3_destructor_type.self
        )

        init(path: String) throws {
            let status = sqlite3_open_v2(
                path,
                &db,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            )

            guard status == SQLITE_OK, db != nil else {
                let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
                if let db {
                    sqlite3_close(db)
                }
                throw ScannerError.openFailed(message)
            }

            sqlite3_exec(db, "PRAGMA query_only = ON;", nil, nil, nil)
        }

        func close() {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
        }

        deinit {
            close()
        }

        func tableExists(_ name: String) -> Bool {
            (try? stringList(
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
                parameters: [name]
            ).first) != nil
        }

        func columnExists(table: String, column: String) -> Bool {
            (try? tableInfo(tableName: table).contains(column)) ?? false
        }

        func tableInfo(tableName: String) throws -> [String] {
            let escaped = tableName.replacingOccurrences(of: "\"", with: "\"\"")
            return try query(sql: "PRAGMA table_info(\"\(escaped)\")") { statement in
                textColumn(statement, 1)
            }
        }

        func stringList(sql: String, parameters: [String] = []) throws -> [String] {
            try query(sql: sql, parameters: parameters) { statement in
                textColumn(statement, 0)
            }
        }

        func query<T>(
            sql: String,
            parameters: [String] = [],
            map: (OpaquePointer?) -> T?
        ) throws -> [T] {
            guard let db else {
                throw ScannerError.queryFailed("Datenbank ist geschlossen.")
            }

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw ScannerError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }

            for (index, value) in parameters.enumerated() {
                let status = sqlite3_bind_text(
                    statement,
                    Int32(index + 1),
                    value,
                    -1,
                    Self.sqliteTransient
                )
                guard status == SQLITE_OK else {
                    throw ScannerError.queryFailed(String(cString: sqlite3_errmsg(db)))
                }
            }

            var rows: [T] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_ROW {
                    if let value = map(statement) {
                        rows.append(value)
                    }
                } else if step == SQLITE_DONE {
                    break
                } else {
                    throw ScannerError.queryFailed(String(cString: sqlite3_errmsg(db)))
                }
            }

            return rows
        }

        private func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
            PhotosLibraryDatabaseScanner.textColumn(statement, index)
        }
    }
}
