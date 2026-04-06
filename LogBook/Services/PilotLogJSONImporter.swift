import Foundation

// MARK: - PilotLog JSON Importer
// Imports from PilotLog JSON backup (array of records with "table" + "meta").
// Same schema as the SQLite database, but in JSON cloud-export format.

enum PilotLogJSONError: LocalizedError {
    case invalidFormat
    case noFlights

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "The file is not a valid PilotLog backup."
        case .noFlights:     return "No flights found in JSON file."
        }
    }
}

final class PilotLogJSONImporter {

    // MARK: - Detection

    static func isPilotLogJSON(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first
        else { return false }
        return first["table"] != nil && first["meta"] != nil
    }

    // MARK: - Import

    static func importFlights(from url: URL) throws -> [Flight] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PilotLogJSONError.invalidFormat
        }

        // Group by table (case-insensitive)
        var byTable: [String: [Meta]] = [:]
        for record in records {
            guard let table = record["table"] as? String,
                  let meta  = record["meta"]  as? [String: Any]
            else { continue }
            let key = table.lowercased()
            byTable[key, default: []].append(meta)
        }

        // Lookup Aircraft: AircraftCode → meta
        var aircraft: [String: Meta] = [:]
        for meta in (byTable["aircraft"] ?? []) {
            if let code = meta["AircraftCode"] as? String { aircraft[code] = meta }
        }

        // Lookup Airfield: AFCode → AFICAO
        var airfield: [String: String] = [:]
        for meta in (byTable["airfield"] ?? []) {
            if let code  = meta["AFCode"]  as? String,
               let icao  = meta["AFICAO"]  as? String { airfield[code] = icao }
        }

        // Lookup Pilot: PilotCode → PilotName
        var pilot: [String: String] = [:]
        for meta in (byTable["pilot"] ?? []) {
            if let code = meta["PilotCode"]  as? String,
               let name = meta["PilotName"]  as? String { pilot[code] = name }
        }

        // Flights
        let flightMetas = (byTable["flight"] ?? [])
        if flightMetas.isEmpty { throw PilotLogJSONError.noFlights }

        var flights: [Flight] = []
        flights.reserveCapacity(flightMetas.count)

        for meta in flightMetas {
            guard let dateStr = meta["DateUTC"] as? String,
                  let date    = parseDate(dateStr)
            else { continue }

            // Tempi (minuti → ore)
            let total  = min2h(meta, "minTOTAL")
            let pic    = min2h(meta, "minPIC")
            let picus  = min2h(meta, "minPICUS")
            let cop    = min2h(meta, "minCOP")
            let dual   = min2h(meta, "minDUAL")
            let instr  = min2h(meta, "minINSTR")
            let night  = min2h(meta, "minNIGHT")
            let ifr    = min2h(meta, "minIFR")

            // Times: minutes from midnight UTC
            let depMins = intVal(meta, "DepTimeUTC")
            let arrMins = intVal(meta, "ArrTimeUTC")
            let depTime: Date? = depMins > 0 ? date.addingTimeInterval(Double(depMins) * 60) : nil
            let arrTime: Date? = arrMins > 0 ? date.addingTimeInterval(Double(arrMins) * 60) : nil

            // Rotta
            let depICAO = airfield[str(meta, "DepCode")] ?? ""
            let arrICAO = airfield[str(meta, "ArrCode")] ?? ""

            // Aeromobile
            let acCode  = str(meta, "AircraftCode")
            let acMeta  = aircraft[acCode]
            let make    = (acMeta?["Make"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let model   = (acMeta?["Model"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let acType  = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
            let acReg   = (acMeta?["Reference"] as? String ?? "").uppercased()

            // SE/ME/MP
            let modelUp = model.uppercased()
            let isSEP   = modelUp == "SEP" || modelUp.contains("TMG")
            let isMEP   = modelUp == "MEP" || modelUp == "MEP LAND"
            let isMP    = !isSEP && !isMEP

            // Pilot
            let picName = pilot[str(meta, "P1Code")] ?? ""

            let flight = Flight(
                id:                   UUID(),
                date:                 date,
                departurePlace:       depICAO.uppercased(),
                departureTime:        depTime,
                arrivalPlace:         arrICAO.uppercased(),
                arrivalTime:          arrTime,
                aircraftType:         acType,
                aircraftRegistration: acReg,
                seSinglePilotTime:    isSEP ? total : 0,
                meSinglePilotTime:    isMEP ? total : 0,
                multiPilotTime:       isMP  ? total : 0,
                totalFlightTime:      total,
                picName:              picName,
                dayLandings:          intVal(meta, "LdgDay"),
                nightLandings:        intVal(meta, "LdgNight"),
                nightTime:            night,
                ifrTime:              ifr,
                picTime:              pic + picus,
                coPilotTime:          cop,
                dualTime:             dual,
                instructorTime:       instr,
                fstdType:             "",
                fstdTime:             0,
                remarks:              str(meta, "Remarks"),
                updatedAt:            Date()
            )
            flights.append(flight)
        }

        if flights.isEmpty { throw PilotLogJSONError.noFlights }
        return flights
    }

    // MARK: - Helpers

    private typealias Meta = [String: Any]

    private static func str(_ m: Meta, _ key: String) -> String {
        (m[key] as? String) ?? ""
    }

    private static func intVal(_ m: Meta, _ key: String) -> Int {
        if let i = m[key] as? Int    { return i }
        if let d = m[key] as? Double { return Int(d) }
        return 0
    }

    private static func min2h(_ m: Meta, _ key: String) -> Double {
        Double(intVal(m, key)) / 60.0
    }

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
