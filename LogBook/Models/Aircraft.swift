import Foundation

// MARK: - Aircraft Model

struct Aircraft: Identifiable, Codable {
    var id: UUID
    var registration: String      // "SX-DVQ"
    var icaoCode: String          // "A320", "A20N", "B738"
    var manufacturer: String      // "Airbus"
    var model: String             // "A320"
    var variant: String           // "214", "271N" (identifica motorizzazione)
    var serialNumber: String      // MSN "7654"
    var engineType: String        // "CFM56-5B4", "PW1127G-JM"
    var engineCount: Int          // 2
    var mtow: String              // "77,000 kg"
    var firstFlight: String       // "2018-03-15" o "2018"
    var isSingleEngine: Bool      // SE single pilot
    var isMultiEngine: Bool       // ME single pilot
    var isMultiPilot: Bool        // MP
    var company: String           // "Aegean Airlines"
    var notes: String
    var updatedAt: Date

    // Campo legacy per compatibilità con voli importati
    var type: String {
        get {
            if !manufacturer.isEmpty && !model.isEmpty {
                return "\(manufacturer) \(model)"
            }
            return icaoCode
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case registration
        case icaoCode        = "icao_code"
        case manufacturer
        case model
        case variant
        case serialNumber    = "serial_number"
        case engineType      = "engine_type"
        case engineCount     = "engine_count"
        case mtow
        case firstFlight     = "first_flight"
        case isSingleEngine  = "is_single_engine"
        case isMultiEngine   = "is_multi_engine"
        case isMultiPilot    = "is_multi_pilot"
        case company
        case notes
        case updatedAt       = "updated_at"
    }

    init(
        id: UUID = UUID(),
        registration: String = "",
        icaoCode: String = "",
        manufacturer: String = "",
        model: String = "",
        variant: String = "",
        serialNumber: String = "",
        engineType: String = "",
        engineCount: Int = 0,
        mtow: String = "",
        firstFlight: String = "",
        isSingleEngine: Bool = false,
        isMultiEngine: Bool = false,
        isMultiPilot: Bool = false,
        company: String = "",
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.registration = registration
        self.icaoCode = icaoCode
        self.manufacturer = manufacturer
        self.model = model
        self.variant = variant
        self.serialNumber = serialNumber
        self.engineType = engineType
        self.engineCount = engineCount
        self.mtow = mtow
        self.firstFlight = firstFlight
        self.isSingleEngine = isSingleEngine
        self.isMultiEngine = isMultiEngine
        self.isMultiPilot = isMultiPilot
        self.company = company
        self.notes = notes
        self.updatedAt = updatedAt
    }

    // MARK: - Custom Decoder (per compatibilità con JSON vecchi senza i nuovi campi)

    // Chiave legacy per migrare JSON vecchi che avevano "type" come campo stored
    private enum LegacyCodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        registration    = try c.decodeIfPresent(String.self, forKey: .registration) ?? ""
        icaoCode        = try c.decodeIfPresent(String.self, forKey: .icaoCode) ?? ""
        manufacturer    = try c.decodeIfPresent(String.self, forKey: .manufacturer) ?? ""
        model           = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        variant         = try c.decodeIfPresent(String.self, forKey: .variant) ?? ""
        serialNumber    = try c.decodeIfPresent(String.self, forKey: .serialNumber) ?? ""
        engineType      = try c.decodeIfPresent(String.self, forKey: .engineType) ?? ""
        engineCount     = try c.decodeIfPresent(Int.self, forKey: .engineCount) ?? 0
        mtow            = try c.decodeIfPresent(String.self, forKey: .mtow) ?? ""
        firstFlight     = try c.decodeIfPresent(String.self, forKey: .firstFlight) ?? ""
        isSingleEngine  = try c.decodeIfPresent(Bool.self, forKey: .isSingleEngine) ?? false
        isMultiEngine   = try c.decodeIfPresent(Bool.self, forKey: .isMultiEngine) ?? false
        isMultiPilot    = try c.decodeIfPresent(Bool.self, forKey: .isMultiPilot) ?? false
        company         = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        notes           = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        updatedAt       = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        // Migrazione: se icaoCode è vuoto ma c'era il vecchio "type", usalo come icaoCode
        if icaoCode.isEmpty {
            let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self)
            if let oldType = try? legacy?.decodeIfPresent(String.self, forKey: .type), !oldType.isEmpty {
                icaoCode = oldType
            }
        }
    }
}

// MARK: - Classification label

extension Aircraft {
    var classificationLabel: String {
        if isSingleEngine { return "SE" }
        if isMultiEngine  { return "ME" }
        if isMultiPilot   { return "MP" }
        return "—"
    }

    /// Descrizione completa del tipo: "Airbus A320-271N" o fallback a icaoCode
    var fullTypeDescription: String {
        var parts: [String] = []
        if !manufacturer.isEmpty { parts.append(manufacturer) }
        if !model.isEmpty { parts.append(model) }
        let base = parts.isEmpty ? icaoCode : parts.joined(separator: " ")
        if !variant.isEmpty {
            return "\(base)-\(variant)"
        }
        return base
    }
}
