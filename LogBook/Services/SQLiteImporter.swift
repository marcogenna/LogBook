import Foundation
import SQLite3

// MARK: - SQLiteImporter
// Reads a .sqlite/.db file and maps found columns → [Flight].
// Supports LogTen Pro, Zulu Log, and generic schemas.

enum SQLiteImportError: LocalizedError {
    case cannotOpen(String)
    case noSuitableTable
    case noRows

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let p): return "Cannot open database: \(p)"
        case .noSuitableTable:  return "No table with flight data found."
        case .noRows:           return "The database contains no flights to import."
        }
    }
}

final class SQLiteImporter {

    // MARK: - Public

    /// Opens the file and returns the flights found.
    /// Auto-detects: PilotLog JSON, PilotLog SQLite, generic.
    static func importFlights(from url: URL) throws -> [Flight] {

        // PilotLog JSON export
        if url.pathExtension.lowercased() == "json" {
            return try PilotLogJSONImporter.importFlights(from: url)
        }

        // PilotLog SQLite (has the minTOTAL column)
        if PilotLogImporter.isPilotLog(at: url) {
            return try PilotLogImporter.importFlights(from: url)
        }

        // Generic importer for other formats
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else {
            throw SQLiteImportError.cannotOpen(url.lastPathComponent)
        }
        defer { sqlite3_close(db) }

        let tables = listTables(db: db)
        guard let table = pickFlightTable(from: tables) else {
            throw SQLiteImportError.noSuitableTable
        }

        let columns = listColumns(db: db, table: table)
        let map = buildColumnMap(columns)
        return try readFlights(db: db, table: table, map: map)
    }

    // MARK: - Table discovery

    private static func listTables(db: OpaquePointer) -> [String] {
        var tables: [String] = []
        let sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    tables.append(String(cString: cStr))
                }
            }
        }
        sqlite3_finalize(stmt)
        return tables
    }

    /// Picks the most likely table for flight data.
    private static func pickFlightTable(from tables: [String]) -> String? {
        let preferred = ["flights", "flight", "logbook", "log", "entries",
                         "ZFLIGHT", "ZLOGBOOKENTRY"]
        for name in preferred {
            if tables.contains(where: { $0.lowercased() == name.lowercased() }) {
                return tables.first { $0.lowercased() == name.lowercased() }!
            }
        }
        // Fallback: first available table
        return tables.first
    }

    // MARK: - Column discovery

    private static func listColumns(db: OpaquePointer, table: String) -> [String] {
        var cols: [String] = []
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\"\(table)\");"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 1) {   // column 1 = name
                    cols.append(String(cString: cStr))
                }
            }
        }
        sqlite3_finalize(stmt)
        return cols
    }

    // MARK: - Column mapping

    /// Maps found column names → semantic Flight keys.
    private struct ColMap {
        var id, date, depPlace, depTime, arrPlace, arrTime: String?
        var acType, acReg, seSP, meSP, mp, total, picName: String?
        var dayLdg, nightLdg, night, ifr: String?
        var pic, cop, dual, instr, fstdType, fstdTime, remarks: String?
    }

    private static func buildColumnMap(_ cols: [String]) -> ColMap {
        func find(_ candidates: [String]) -> String? {
            for c in candidates {
                if let match = cols.first(where: { $0.lowercased() == c.lowercased() }) {
                    return match
                }
            }
            return nil
        }

        var m = ColMap()
        m.id        = find(["id","uuid","flight_id","ZFLIGHT"])
        m.date      = find(["date","flight_date","log_date","ZDATE","ZDEPARTURETIME"])
        m.depPlace  = find(["departure_place","departure","dep","from_icao","adep","ADEP",
                            "ZDEPARTUREAIRPORTIDENTIFIER","departure_airport","from"])
        m.depTime   = find(["departure_time","dep_time","off_time","ZDEPARTURETIMEOFFSET"])
        m.arrPlace  = find(["arrival_place","arrival","arr","to_icao","ades","ADES",
                            "ZARRIVALAIRPORTIDENTIFIER","arrival_airport","to"])
        m.arrTime   = find(["arrival_time","arr_time","on_time","ZARRIVALTIMEOFFSET"])
        m.acType    = find(["aircraft_type","type","ac_type","ZAIRCRAFTTYPE","aircraft"])
        m.acReg     = find(["aircraft_registration","registration","reg","tail",
                            "ZAIRCRAFTREGISTRATION","tail_number"])
        m.seSP      = find(["se_single_pilot_time","se_sp","single_engine","ZSINGLEENGINETIME"])
        m.meSP      = find(["me_single_pilot_time","me_sp","multi_engine","ZMULTIENGINE"])
        m.mp        = find(["multi_pilot_time","multi_pilot","mp","ZMULTIPILOTTIME"])
        m.total     = find(["total_flight_time","total","flight_time","duration",
                            "ZTOTALFLIGHTTIME","total_time","block_time"])
        m.picName   = find(["pic_name","pic_name","captain","commander","ZPICNAME","pilot_name"])
        m.dayLdg    = find(["day_landings","day_ldg","landings_day","ZDAYLANDINGS","ldg_day","ldg"])
        m.nightLdg  = find(["night_landings","night_ldg","landings_night","ZNIGHTLANDINGS"])
        m.night     = find(["night_time","night","ZNIGHTTIME"])
        m.ifr       = find(["ifr_time","ifr","instrument","ZIFRTIME","instrument_time"])
        m.pic       = find(["pic_time","pic","ZPICTIME","p1_time"])
        m.cop       = find(["co_pilot_time","copilot","sic","ZCOPILOTTIME","p2_time"])
        m.dual      = find(["dual_time","dual","ZDUALTIME"])
        m.instr     = find(["instructor_time","instructor","instr","ZINSTRUCTORTIME"])
        m.fstdType  = find(["fstd_type","sim_type","simulator_type","ZFSTDTYPE"])
        m.fstdTime  = find(["fstd_time","sim_time","simulator_time","ZFSTDTIME"])
        m.remarks   = find(["remarks","notes","comment","ZREMARKS","notes"])
        return m
    }

    // MARK: - Read rows

    private static func readFlights(db: OpaquePointer,
                                    table: String,
                                    map: ColMap) throws -> [Flight] {
        let sql = "SELECT * FROM \"\(table)\";"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteImportError.noSuitableTable
        }
        defer { sqlite3_finalize(stmt) }

        // Read column names in the order returned by the query
        let colCount = Int(sqlite3_column_count(stmt))
        var colNames: [String] = []
        for i in 0..<colCount {
            colNames.append(String(cString: sqlite3_column_name(stmt, Int32(i))))
        }

        var flights: [Flight] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            func str(_ key: String?) -> String {
                guard let k = key, let idx = colNames.firstIndex(of: k) else { return "" }
                return sqlite3_column_text(stmt, Int32(idx)).map { String(cString: $0) } ?? ""
            }
            func dbl(_ key: String?) -> Double {
                guard let k = key, let idx = colNames.firstIndex(of: k) else { return 0 }
                return sqlite3_column_double(stmt, Int32(idx))
            }
            func int(_ key: String?) -> Int {
                guard let k = key, let idx = colNames.firstIndex(of: k) else { return 0 }
                return Int(sqlite3_column_int(stmt, Int32(idx)))
            }

            let dateStr = str(map.date)
            let date = parseDate(dateStr) ?? Date()

            var f = Flight(
                id:                   UUID(),
                date:                 date,
                departurePlace:       str(map.depPlace).uppercased(),
                departureTime:        parseDate(str(map.depTime)),
                arrivalPlace:         str(map.arrPlace).uppercased(),
                arrivalTime:          parseDate(str(map.arrTime)),
                aircraftType:         str(map.acType).uppercased(),
                aircraftRegistration: str(map.acReg).uppercased(),
                seSinglePilotTime:    dbl(map.seSP),
                meSinglePilotTime:    dbl(map.meSP),
                multiPilotTime:       dbl(map.mp),
                totalFlightTime:      dbl(map.total),
                picName:              str(map.picName),
                dayLandings:          int(map.dayLdg),
                nightLandings:        int(map.nightLdg),
                nightTime:            dbl(map.night),
                ifrTime:              dbl(map.ifr),
                picTime:              dbl(map.pic),
                coPilotTime:          dbl(map.cop),
                dualTime:             dbl(map.dual),
                instructorTime:       dbl(map.instr),
                fstdType:             str(map.fstdType),
                fstdTime:             dbl(map.fstdTime),
                remarks:              str(map.remarks),
                updatedAt:            Date()
            )

            // Normalize times: if they look like minutes (e.g. 90 min instead of 1.5h)
            f = normalizeTime(f)

            flights.append(f)
        }

        if flights.isEmpty { throw SQLiteImportError.noRows }
        return flights
    }

    // MARK: - Date parsing

    private static func parseDate(_ str: String) -> Date? {
        guard !str.isEmpty else { return nil }

        // ISO 8601
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: str) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: str) { return d }

        // Date only
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd-MM-yyyy"] {
            df.dateFormat = fmt
            if let d = df.date(from: str) { return d }
        }

        // Unix timestamp
        if let ts = Double(str) { return Date(timeIntervalSince1970: ts) }

        return nil
    }

    // MARK: - Time normalization

    /// Some logbooks store times in minutes. If total > 24 it's probably in minutes.
    private static func normalizeTime(_ f: Flight) -> Flight {
        guard f.totalFlightTime > 24 else { return f }
        var n = f
        let toH: (Double) -> Double = { $0 / 60.0 }
        n.totalFlightTime   = toH(f.totalFlightTime)
        n.seSinglePilotTime = toH(f.seSinglePilotTime)
        n.meSinglePilotTime = toH(f.meSinglePilotTime)
        n.multiPilotTime    = toH(f.multiPilotTime)
        n.nightTime         = toH(f.nightTime)
        n.ifrTime           = toH(f.ifrTime)
        n.picTime           = toH(f.picTime)
        n.coPilotTime       = toH(f.coPilotTime)
        n.dualTime          = toH(f.dualTime)
        n.instructorTime    = toH(f.instructorTime)
        n.fstdTime          = toH(f.fstdTime)
        return n
    }
}
