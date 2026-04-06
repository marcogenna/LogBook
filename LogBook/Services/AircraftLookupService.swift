import Foundation

// MARK: - AircraftLookupService
// Looks up aircraft data from free sources + local ICAO database.

actor AircraftLookupService {

    static let shared = AircraftLookupService()

    // MARK: - ICAO Type Database (local, from bundle)

    private var icaoTypes: [ICAOType] = []

    struct ICAOType: Codable {
        let icao: String
        let manufacturer: String
        let model: String
        let engineCount: Int
        let engineType: String
        let wtc: String       // Wake Turbulence Category: L, M, H, J
        let mtow: String
    }

    func loadICAODatabase() {
        guard icaoTypes.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "icao_types", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let types = try? JSONDecoder().decode([ICAOType].self, from: data)
        else { return }
        icaoTypes = types
    }

    /// Look up ICAO type in local database (offline, instant)
    func lookupByICAOCode(_ code: String) -> ICAOType? {
        loadICAODatabase()
        let q = code.trimmingCharacters(in: .whitespaces).uppercased()
        return icaoTypes.first { $0.icao == q }
    }

    /// Search all types containing the query (for autocomplete)
    func searchICAOTypes(_ query: String) -> [ICAOType] {
        loadICAODatabase()
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard q.count >= 2 else { return [] }
        return icaoTypes.filter {
            $0.icao.contains(q) ||
            $0.manufacturer.uppercased().contains(q) ||
            $0.model.uppercased().contains(q)
        }
    }

    // MARK: - Online Lookup (adsbdb.com — free, no auth)

    /// Structured info ready to populate the Aircraft model
    struct AircraftInfo {
        let registration: String
        let icaoCode: String
        let manufacturer: String
        let model: String
        let variant: String
        let fullType: String      // "A320-271N" original from API
        let engineType: String
        let engineCount: Int
        let mtow: String
        let company: String
        let isSingleEngine: Bool
        let isMultiEngine: Bool
        let isMultiPilot: Bool
    }

    /// Look up aircraft by registration — combines online API + local ICAO database
    func fullLookup(registration: String) async -> AircraftInfo? {
        let reg = registration.trimmingCharacters(in: .whitespaces).uppercased()
        guard !reg.isEmpty else { return nil }

        // 1. Call adsbdb.com API
        let urlString = "https://api.adsbdb.com/v0/aircraft/\(reg)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LogBook-ATPL/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else { return nil }

        // 2. Parse JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseObj = json["response"] as? [String: Any],
              let ac = responseObj["aircraft"] as? [String: Any]
        else { return nil }

        let typeField    = ac["type"] as? String ?? ""              // "A320-271N" o "A320 232"
        let icaoType     = ac["icao_type"] as? String ?? ""         // "A320"
        let manufacturer = ac["manufacturer"] as? String ?? ""      // "Airbus"
        let regResult    = ac["registration"] as? String ?? reg     // "SX-NEF"
        let owner        = ac["registered_owner"] as? String ?? ""  // "Aegean Airlines"

        // 3. Parsing type → model + variant
        //    "A320-271N" → model="A320", variant="271N"
        //    "A320 232"  → model="A320", variant="232"
        //    "B737-8AS"  → model="B737", variant="8AS"
        let (model, variant) = parseTypeField(typeField, icaoFallback: icaoType)

        // 4. Correct ICAO code — adsbdb often returns the generic code
        //    "A320" even for neo (which should be "A20N"), etc.
        let correctedICAO = correctICAOCode(apiCode: icaoType, variant: variant, model: model)

        // 5. Enrich with local ICAO database (use corrected code)
        let icaoInfo = lookupByICAOCode(correctedICAO)
            ?? lookupByICAOCode(icaoType) // fallback to API code if corrected one not in DB

        let mfr = manufacturer.isEmpty ? (icaoInfo?.manufacturer ?? "") : manufacturer

        let engineCount = icaoInfo?.engineCount ?? 0
        let wtc = icaoInfo?.wtc ?? ""

        return AircraftInfo(
            registration: regResult,
            icaoCode: correctedICAO,
            manufacturer: mfr,
            model: model,
            variant: variant,
            fullType: typeField,
            engineType: icaoInfo?.engineType ?? "",
            engineCount: engineCount,
            mtow: icaoInfo?.mtow ?? "",
            company: owner,
            isSingleEngine: engineCount == 1,
            isMultiEngine: engineCount == 2 && wtc == "L",
            isMultiPilot: engineCount >= 2 && wtc != "L"
        )
    }

    // MARK: - Private

    /// Parse "A320-271N" → ("A320", "271N"), "A320 232" → ("A320", "232")
    private func parseTypeField(_ typeField: String, icaoFallback: String) -> (model: String, variant: String) {
        guard !typeField.isEmpty else {
            return (icaoFallback, "")
        }

        // Normalize separators: "A320-271N" → "A320 271N", "A320 232" stays the same
        let normalized = typeField.replacingOccurrences(of: "-", with: " ")
        let parts = normalized.split(separator: " ").map(String.init)

        guard parts.count >= 1 else {
            return (icaoFallback, "")
        }

        let model = parts[0]
        let variant = parts.count >= 2 ? parts.dropFirst().joined(separator: "") : ""

        return (model, variant)
    }

    /// Corrects the ICAO code when the API returns the generic code.
    /// Uses the variant to distinguish CEO vs NEO and other sub-families.
    private func correctICAOCode(apiCode: String, variant: String, model: String) -> String {
        let v = variant.uppercased()
        let isNeo = v.hasSuffix("N")  // 271N, 251N, 232N → neo

        switch apiCode.uppercased() {
        // Airbus A320 family: CEO vs NEO
        case "A318":
            return "A318"
        case "A319":
            return isNeo ? "A19N" : "A319"
        case "A320":
            return isNeo ? "A20N" : "A320"
        case "A321":
            return isNeo ? "A21N" : "A321"

        // Airbus A330: CEO vs NEO
        case "A330":
            if isNeo || v.hasPrefix("9") { return "A339" }  // -900neo
            if v.hasPrefix("8") { return "A338" }           // -800neo
            if v.hasPrefix("3") { return "A333" }           // -300
            if v.hasPrefix("2") { return "A332" }           // -200
            return apiCode

        // Boeing 737: classico vs MAX
        case "B737":
            if v.hasPrefix("MAX") || v.hasPrefix("7M") { return "B37M" }
            if v.hasPrefix("8M") || v.contains("MAX8") { return "B38M" }
            if v.hasPrefix("9M") || v.contains("MAX9") { return "B39M" }
            // NG variants
            if v.hasPrefix("7") { return "B737" }
            if v.hasPrefix("8") { return "B738" }
            if v.hasPrefix("9") { return "B739" }
            if v.hasPrefix("6") { return "B736" }
            if v.hasPrefix("5") { return "B735" }
            if v.hasPrefix("4") { return "B734" }
            if v.hasPrefix("3") { return "B733" }
            if v.hasPrefix("2") { return "B732" }
            return apiCode

        // Boeing 747
        case "B747":
            if v.hasPrefix("8") { return "B748" }
            if v.hasPrefix("4") { return "B744" }
            return apiCode

        // Boeing 767
        case "B767":
            if v.hasPrefix("4") { return "B764" }
            if v.hasPrefix("3") { return "B763" }
            if v.hasPrefix("2") { return "B762" }
            return apiCode

        // Boeing 777
        case "B777":
            if v.contains("LR") { return "B77L" }
            if v.contains("ER") || v.hasPrefix("3") { return "B77W" }
            if v.hasPrefix("9") { return "B779" }
            if v.hasPrefix("8") { return "B778" }
            if v.hasPrefix("2") { return "B772" }
            return apiCode

        // Boeing 787
        case "B787":
            if v.hasPrefix("10") { return "B78X" }
            if v.hasPrefix("9") { return "B789" }
            if v.hasPrefix("8") { return "B788" }
            return apiCode

        // ATR
        case "ATR":
            if model.contains("72") { return "AT72" }
            if model.contains("42") { return "AT43" }
            return apiCode

        default:
            return apiCode
        }
    }
}
