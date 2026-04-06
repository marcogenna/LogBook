import Foundation
import SQLite3

// MARK: - PilotLog Importer
// Imports from PilotLog (backup .db) with JOIN on Aircraft, Airfield, Pilot.
// All times are in MINUTES in PilotLog database → automatic conversion to hours.

enum PilotLogImportError: LocalizedError {
    case cannotOpen(String)
    case queryFailed
    case noFlights

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let f): return "Cannot open: \(f)"
        case .queryFailed:       return "Query failed on PilotLog database."
        case .noFlights:         return "No flights found in database."
        }
    }
}

final class PilotLogImporter {

    /// Detects whether the file is a PilotLog database (has the Flight table with minTOTAL column).
    static func isPilotLog(at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return false }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT minTOTAL FROM Flight LIMIT 1;"
        let ok = sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK
        sqlite3_finalize(stmt)
        return ok
    }

    static func importFlights(from url: URL) throws -> [Flight] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else {
            throw PilotLogImportError.cannotOpen(url.lastPathComponent)
        }
        defer { sqlite3_close(db) }
        return try readFlights(db: db)
    }

    // MARK: - Query

    private static let joinSQL = """
        SELECT
            f.FlightCode,
            f.DateUTC,
            dep.AFICAO          AS DepICAO,
            arr.AFICAO          AS ArrICAO,
            f.DepTimeUTC,
            f.ArrTimeUTC,
            TRIM(
                COALESCE(ac.Make,'') || ' ' || COALESCE(ac.Model,'')
            )                   AS AcType,
            ac.Reference        AS AcReg,
            f.minTOTAL,
            f.minPIC,
            f.minPICUS,
            f.minCOP,
            f.minDUAL,
            f.minINSTR,
            f.minNIGHT,
            f.minIFR,
            f.LdgDay,
            f.LdgNight,
            p1.PilotName        AS PICName,
            f.Remarks,
            ac.EngGroup,
            ac.Model
        FROM Flight f
        LEFT JOIN Airfield dep ON dep.AFCode = f.DepCode
        LEFT JOIN Airfield arr ON arr.AFCode = f.ArrCode
        LEFT JOIN Aircraft ac  ON ac.AircraftCode = f.AircraftCode
        LEFT JOIN Pilot p1     ON p1.PilotCode = f.P1Code
        ORDER BY f.DateUTC ASC;
        """

    private static func readFlights(db: OpaquePointer) throws -> [Flight] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, joinSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw PilotLogImportError.queryFailed
        }
        defer { sqlite3_finalize(stmt) }

        // Mappa nome colonna → indice
        let count = Int(sqlite3_column_count(stmt))
        var idx: [String: Int32] = [:]
        for i in 0..<count {
            idx[String(cString: sqlite3_column_name(stmt, Int32(i)))] = Int32(i)
        }

        func str(_ col: String) -> String {
            guard let i = idx[col] else { return "" }
            return sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        func int(_ col: String) -> Int {
            guard let i = idx[col] else { return 0 }
            return Int(sqlite3_column_int(stmt, i))
        }
        func min2h(_ col: String) -> Double {
            Double(int(col)) / 60.0
        }

        var flights: [Flight] = []

        while sqlite3_step(stmt) == SQLITE_ROW {

            // Data
            let dateStr = str("DateUTC")
            guard let date = parseDate(dateStr) else { continue }

            // Times: minutes from midnight UTC → Date
            let depMins = int("DepTimeUTC")
            let arrMins = int("ArrTimeUTC")
            let depTime: Date? = depMins > 0 ? date.addingTimeInterval(Double(depMins) * 60) : nil
            let arrTime: Date? = arrMins > 0 ? date.addingTimeInterval(Double(arrMins) * 60) : nil

            // Tempi (minuti → ore)
            let total   = min2h("minTOTAL")
            let pic     = min2h("minPIC")
            let picus   = min2h("minPICUS")   // PIC Under Supervision → conta come PIC
            let cop     = min2h("minCOP")
            let dual    = min2h("minDUAL")
            let instr   = min2h("minINSTR")
            let night   = min2h("minNIGHT")
            let ifr     = min2h("minIFR")

            // Tipo aereo e classificazione SE/ME/MP
            let model    = str("Model").uppercased()
            let acType   = str("AcType").trimmingCharacters(in: .whitespaces)
            let isSEP    = model.contains("SEP") || model.contains("TMG")
            let isMEP    = model.contains("MEP")
            let isMP     = !isSEP && !isMEP   // everything else (commercial jets = multi pilot)

            let seSP  = isSEP ? total : 0.0
            let meSP  = isMEP ? total : 0.0
            let mp    = isMP  ? total : 0.0

            let flight = Flight(
                id:                   UUID(),
                date:                 date,
                departurePlace:       str("DepICAO").uppercased(),
                departureTime:        depTime,
                arrivalPlace:         str("ArrICAO").uppercased(),
                arrivalTime:          arrTime,
                aircraftType:         acType,
                aircraftRegistration: str("AcReg").uppercased(),
                seSinglePilotTime:    seSP,
                meSinglePilotTime:    meSP,
                multiPilotTime:       mp,
                totalFlightTime:      total,
                picName:              str("PICName"),
                dayLandings:          int("LdgDay"),
                nightLandings:        int("LdgNight"),
                nightTime:            night,
                ifrTime:              ifr,
                picTime:              pic + picus,
                coPilotTime:          cop,
                dualTime:             dual,
                instructorTime:       instr,
                fstdType:             "",
                fstdTime:             0,
                remarks:              str("Remarks"),
                updatedAt:            Date()
            )

            flights.append(flight)
        }

        if flights.isEmpty { throw PilotLogImportError.noFlights }
        return flights
    }

    // MARK: - Date parsing

    private static func parseDate(_ str: String) -> Date? {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            df.dateFormat = fmt
            if let d = df.date(from: str) { return d }
        }
        return nil
    }
}
