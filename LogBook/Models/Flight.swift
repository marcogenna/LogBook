import Foundation

// MARK: - Flight Model (EASA ATPL Logbook format)

struct Flight: Identifiable, Codable {
    var id: UUID
    var date: Date
    var departurePlace: String
    var departureTime: Date?
    var arrivalPlace: String
    var arrivalTime: Date?
    var aircraftType: String
    var aircraftRegistration: String
    var seSinglePilotTime: Double
    var meSinglePilotTime: Double
    var multiPilotTime: Double
    var totalFlightTime: Double
    var picName: String
    var dayLandings: Int
    var nightLandings: Int
    var nightTime: Double
    var ifrTime: Double
    var picTime: Double
    var coPilotTime: Double
    var dualTime: Double
    var instructorTime: Double
    var fstdType: String
    var fstdTime: Double
    var remarks: String
    var updatedAt: Date

    // MARK: - CodingKeys (snake_case for Supabase/PostgREST)

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case departurePlace       = "departure_place"
        case departureTime        = "departure_time"
        case arrivalPlace         = "arrival_place"
        case arrivalTime          = "arrival_time"
        case aircraftType         = "aircraft_type"
        case aircraftRegistration = "aircraft_registration"
        case seSinglePilotTime    = "se_single_pilot_time"
        case meSinglePilotTime    = "me_single_pilot_time"
        case multiPilotTime       = "multi_pilot_time"
        case totalFlightTime      = "total_flight_time"
        case picName              = "pic_name"
        case dayLandings          = "day_landings"
        case nightLandings        = "night_landings"
        case nightTime            = "night_time"
        case ifrTime              = "ifr_time"
        case picTime              = "pic_time"
        case coPilotTime          = "co_pilot_time"
        case dualTime             = "dual_time"
        case instructorTime       = "instructor_time"
        case fstdType             = "fstd_type"
        case fstdTime             = "fstd_time"
        case remarks
        case updatedAt            = "updated_at"
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        departurePlace: String = "",
        departureTime: Date? = nil,
        arrivalPlace: String = "",
        arrivalTime: Date? = nil,
        aircraftType: String = "",
        aircraftRegistration: String = "",
        seSinglePilotTime: Double = 0,
        meSinglePilotTime: Double = 0,
        multiPilotTime: Double = 0,
        totalFlightTime: Double = 0,
        picName: String = "",
        dayLandings: Int = 0,
        nightLandings: Int = 0,
        nightTime: Double = 0,
        ifrTime: Double = 0,
        picTime: Double = 0,
        coPilotTime: Double = 0,
        dualTime: Double = 0,
        instructorTime: Double = 0,
        fstdType: String = "",
        fstdTime: Double = 0,
        remarks: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.departurePlace = departurePlace
        self.departureTime = departureTime
        self.arrivalPlace = arrivalPlace
        self.arrivalTime = arrivalTime
        self.aircraftType = aircraftType
        self.aircraftRegistration = aircraftRegistration
        self.seSinglePilotTime = seSinglePilotTime
        self.meSinglePilotTime = meSinglePilotTime
        self.multiPilotTime = multiPilotTime
        self.totalFlightTime = totalFlightTime
        self.picName = picName
        self.dayLandings = dayLandings
        self.nightLandings = nightLandings
        self.nightTime = nightTime
        self.ifrTime = ifrTime
        self.picTime = picTime
        self.coPilotTime = coPilotTime
        self.dualTime = dualTime
        self.instructorTime = instructorTime
        self.fstdType = fstdType
        self.fstdTime = fstdTime
        self.remarks = remarks
        self.updatedAt = updatedAt
    }
}

// MARK: - Helpers

extension Double {
    var hoursMinutes: String {
        let totalMinutes = Int(self * 60)
        return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}

extension Flight {
    var route: String {
        guard !departurePlace.isEmpty || !arrivalPlace.isEmpty else { return "—" }
        return "\(departurePlace) → \(arrivalPlace)"
    }
}

// MARK: - JSON Coders for Supabase

extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            // timestamptz: "2024-03-15T10:30:00+00:00"
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: string) { return date }

            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: string) { return date }

            // date only: "2024-03-15"
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "UTC")
            if let date = df.date(from: string) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            try container.encode(iso.string(from: date))
        }
        return encoder
    }
}
