import SwiftUI
import Network

@MainActor
final class FlightStore: ObservableObject {

    // MARK: - Published State

    @Published var flights: [Flight] = []
    @Published var aircraft: [Aircraft] = []
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var lastSyncDate: Date? = nil
    @Published var pendingCount: Int = 0

    // MARK: - Private

    private let local = LocalStore.shared
    private let remote = SupabaseProvider()
    private var monitor: NWPathMonitor?
    private var isOnline = false

    // MARK: - Init

    init() {
        flights = local.loadAll().sorted { $0.date > $1.date }
        aircraft = local.loadAircraft().sorted { $0.registration < $1.registration }
        migrateAircraftIfNeeded()
        pendingCount = local.loadPendingIDs().count
        startNetworkMonitor()
    }

    /// Normalizza aeromobili con dati vecchi (es. icaoCode="Airbus A320" → icao="A320", manufacturer="Airbus")
    private func migrateAircraftIfNeeded() {
        var changed = false
        for i in aircraft.indices {
            let raw = aircraft[i].icaoCode
            // Se icaoCode contiene spazi o più di 4 caratteri, è un tipo grezzo non parsato
            if raw.contains(" ") || raw.count > 4 {
                let parsed = Self.parseFlightType(raw)
                aircraft[i].icaoCode = parsed.icao
                if aircraft[i].manufacturer.isEmpty { aircraft[i].manufacturer = parsed.manufacturer }
                if aircraft[i].model.isEmpty { aircraft[i].model = parsed.model }
                if aircraft[i].variant.isEmpty { aircraft[i].variant = parsed.variant }
                changed = true
            }
        }
        if changed {
            local.saveAircraft(aircraft)
        }
    }

    // MARK: - Local Save (istantaneo, offline)

    func save(_ flight: Flight) async {
        var updated = flight
        updated.updatedAt = Date()

        if let index = flights.firstIndex(where: { $0.id == flight.id }) {
            flights[index] = updated
        } else {
            flights.append(updated)
            flights.sort { $0.date > $1.date }
        }

        local.saveAll(flights)
        local.markPending(updated.id)
        pendingCount = local.loadPendingIDs().count

        if isOnline { Task { await syncPending() } }
    }

    func delete(_ flight: Flight) async {
        flights.removeAll { $0.id == flight.id }
        local.saveAll(flights)

        if isOnline {
            do { try await remote.delete(id: flight.id) } catch {
                errorMessage = error.localizedDescription
            }
        }
        // Se offline, il volo è già rimosso dal locale.
        // Al prossimo sync Supabase non lo troverà come "pending" da pushare.
        local.markSynced(flight.id)
        pendingCount = local.loadPendingIDs().count
    }

    // MARK: - Fetch (pull da Supabase + merge con locale)

    func fetchFlights() async {
        guard await remote.isConfigured else {
            errorMessage = SyncError.notConfigured.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let remote = try await remote.fetchAll()
            mergeRemote(remote)
            lastSyncDate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sync pending → Supabase

    func syncPending() async {
        let pendingIDs = local.loadPendingIDs()
        guard !pendingIDs.isEmpty else { return }
        guard await remote.isConfigured else { return }

        isSyncing = true
        defer { isSyncing = false }

        let toSync = flights.filter { pendingIDs.contains($0.id) }
        for flight in toSync {
            do {
                _ = try await remote.save(flight)
                local.markSynced(flight.id)
            } catch {
                // Lascia in pending, riproverà al prossimo sync
            }
        }

        pendingCount = local.loadPendingIDs().count
        if pendingCount == 0 { lastSyncDate = Date() }
    }

    // MARK: - Import (da SQLite o altra fonte)

    func importFlights(_ incoming: [Flight]) {
        var merged = Dictionary(uniqueKeysWithValues: flights.map { ($0.id, $0) })
        for flight in incoming {
            merged[flight.id] = flight
            local.markPending(flight.id)
        }
        flights = merged.values.sorted { $0.date > $1.date }
        local.saveAll(flights)
        pendingCount = local.loadPendingIDs().count
        if isOnline { Task { await syncPending() } }
    }

    // MARK: - Aircraft CRUD

    func saveAircraft(_ ac: Aircraft) {
        var updated = ac
        updated.updatedAt = Date()

        if let index = aircraft.firstIndex(where: { $0.id == ac.id }) {
            aircraft[index] = updated
        } else {
            aircraft.append(updated)
        }
        aircraft.sort { $0.registration < $1.registration }
        local.saveAircraft(aircraft)
    }

    func deleteAircraft(_ ac: Aircraft) {
        aircraft.removeAll { $0.id == ac.id }
        local.saveAircraft(aircraft)
    }

    /// Estrae aeromobili unici dai voli importati e li aggiunge alla lista.
    func autoPopulateAircraft() -> Int {
        var seen = Set(aircraft.map { $0.registration.uppercased() })
        var added = 0

        // Raggruppa i voli per marche
        var byReg: [String: [Flight]] = [:]
        for f in flights where !f.aircraftRegistration.isEmpty {
            byReg[f.aircraftRegistration.uppercased(), default: []].append(f)
        }

        for (reg, regFlights) in byReg {
            guard !seen.contains(reg) else { continue }
            seen.insert(reg)

            // Tipo più frequente per queste marche
            let typeCounts = Dictionary(grouping: regFlights, by: { $0.aircraftType })
            let bestType = typeCounts.max(by: { $0.value.count < $1.value.count })?.key ?? ""

            // Parsa il tipo grezzo: "Airbus A320", "A320", "B738", "Cessna 172", etc.
            let parsed = Self.parseFlightType(bestType)

            // Classifica SE/ME/MP basata sui tempi prevalenti dei voli
            let totalSE = regFlights.reduce(0.0) { $0 + $1.seSinglePilotTime }
            let totalME = regFlights.reduce(0.0) { $0 + $1.meSinglePilotTime }
            let totalMP = regFlights.reduce(0.0) { $0 + $1.multiPilotTime }
            let maxTime = max(totalSE, totalME, totalMP)

            let ac = Aircraft(
                registration: reg,
                icaoCode: parsed.icao,
                manufacturer: parsed.manufacturer,
                model: parsed.model,
                variant: parsed.variant,
                isSingleEngine: maxTime > 0 && totalSE == maxTime,
                isMultiEngine:  maxTime > 0 && totalME == maxTime,
                isMultiPilot:   maxTime > 0 && totalMP == maxTime
            )
            aircraft.append(ac)
            added += 1
        }

        aircraft.sort { $0.registration < $1.registration }
        local.saveAircraft(aircraft)
        return added
    }

    // MARK: - Parsing tipo aeromobile da voli importati

    private static let manufacturerMap: [(keyword: String, name: String)] = [
        ("AIRBUS", "Airbus"),
        ("BOEING", "Boeing"),
        ("CESSNA", "Cessna"),
        ("PIPER", "Piper"),
        ("BEECHCRAFT", "Beechcraft"),
        ("BEECH", "Beechcraft"),
        ("BOMBARDIER", "Bombardier"),
        ("EMBRAER", "Embraer"),
        ("ATR", "ATR"),
        ("DIAMOND", "Diamond"),
        ("PILATUS", "Pilatus"),
        ("DASSAULT", "Dassault"),
        ("GULFSTREAM", "Gulfstream"),
        ("FOKKER", "Fokker"),
        ("SAAB", "Saab"),
        ("DE HAVILLAND", "De Havilland"),
        ("MCDONNELL", "McDonnell Douglas"),
        ("TECNAM", "Tecnam"),
        ("CIRRUS", "Cirrus"),
        ("SOCATA", "Socata"),
        ("ROBIN", "Robin"),
    ]

    /// Mapping modelli comuni → codice ICAO
    private static let modelToICAO: [String: String] = [
        "A318": "A318", "A319": "A319", "A320": "A320", "A321": "A321",
        "A319NEO": "A19N", "A320NEO": "A20N", "A321NEO": "A21N",
        "A330": "A333", "A340": "A343", "A350": "A359", "A380": "A388",
        "717": "B712",
        "727": "B727", "737": "B738", "747": "B744", "757": "B752",
        "767": "B763", "777": "B772", "787": "B789",
        "B717": "B712",
        "B727": "B727", "B737": "B738", "B738": "B738", "B739": "B739",
        "B747": "B744", "B757": "B752", "B767": "B763",
        "B777": "B772", "B787": "B789",
        "737-800": "B738", "737-900": "B739", "737-700": "B737",
        "747-400": "B744", "747-8": "B748",
        "777-200": "B772", "777-300": "B773", "777-300ER": "B77W",
        "787-8": "B788", "787-9": "B789", "787-10": "B78X",
        "172": "C172", "C172": "C172", "182": "C182", "C182": "C182",
        "152": "C152", "C152": "C152", "150": "C150", "C150": "C150",
        "208": "C208", "C208": "C208",
        "ATR42": "AT43", "ATR72": "AT72", "ATR 42": "AT43", "ATR 72": "AT72",
        "DA40": "DA40", "DA42": "DA42", "DA62": "DA62",
        "PA28": "P28A", "PA34": "PA34", "PA44": "PA44", "PA46": "PA46",
        "PC12": "PC12", "PC24": "PC24",
        "CRJ": "CRJ2", "ERJ": "E145",
        "E170": "E170", "E175": "E175", "E190": "E190", "E195": "E195",
        "F50": "F50", "F70": "F70", "F100": "F100",
        "DASH 8": "DH8D", "Q400": "DH8D",
        "SAAB 340": "SF34", "SAAB 2000": "SB20",
        "SEP": "SEP", "MEP": "MEP", "TMG": "TMG",
    ]

    struct ParsedFlightType {
        var icao: String
        var manufacturer: String
        var model: String
        var variant: String
    }

    /// Parsa stringhe tipo dai voli: "Airbus A320", "A320", "B738", "Cessna 172 Skyhawk", etc.
    static func parseFlightType(_ raw: String) -> ParsedFlightType {
        let upper = raw.trimmingCharacters(in: .whitespaces).uppercased()
        var manufacturer = ""
        var rest = upper

        // 1. Estrai manufacturer se presente all'inizio
        for (keyword, name) in manufacturerMap {
            if upper.hasPrefix(keyword) {
                manufacturer = name
                rest = String(upper.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // 2. Separa modello e variant: "A320-271N" → model="A320", variant="271N"
        let normalized = rest.replacingOccurrences(of: "-", with: " ")
        let parts = normalized.split(separator: " ").map(String.init)

        let modelPart = parts.first ?? rest
        let variant: String
        if parts.count >= 2 {
            variant = parts.dropFirst().joined(separator: "")
        } else {
            variant = ""
        }

        // 3. Cerca codice ICAO dal modello
        //    Prima prova "A320" diretto, poi "A320-271N" completo
        let fullModel = variant.isEmpty ? modelPart : "\(modelPart)-\(variant)"
        let icao = modelToICAO[fullModel]
            ?? modelToICAO[modelPart]
            ?? modelPart  // fallback: usa il modello come codice ICAO

        return ParsedFlightType(
            icao: icao,
            manufacturer: manufacturer,
            model: modelPart,
            variant: variant
        )
    }

    /// Cerca un aeromobile per marche (case insensitive)
    func findAircraft(byRegistration reg: String) -> Aircraft? {
        aircraft.first { $0.registration.uppercased() == reg.uppercased() }
    }

    // MARK: - Statistics

    var totals: FlightTotals { FlightTotals(flights: flights) }

    func totals(forYear year: Int) -> FlightTotals {
        FlightTotals(flights: flights.filter {
            Calendar.current.component(.year, from: $0.date) == year
        })
    }

    var availableYears: [Int] {
        Set(flights.map { Calendar.current.component(.year, from: $0.date) })
            .sorted(by: >)
    }

    // MARK: - Private helpers

    private func mergeRemote(_ remoteFlights: [Flight]) {
        var merged = Dictionary(uniqueKeysWithValues: flights.map { ($0.id, $0) })
        for rf in remoteFlights {
            if let local = merged[rf.id] {
                // Vince chi ha updatedAt più recente
                if rf.updatedAt > local.updatedAt { merged[rf.id] = rf }
            } else {
                merged[rf.id] = rf
            }
        }
        flights = merged.values.sorted { $0.date > $1.date }
        local.saveAll(flights)
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                if wasOffline && self.isOnline {
                    await self.syncPending()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "net.monitor"))
    }
}

// MARK: - Aggregated Totals

struct FlightTotals {
    let flightCount: Int
    let totalFlightTime: Double
    let multiPilotTime: Double
    let seSinglePilotTime: Double
    let meSinglePilotTime: Double
    let nightTime: Double
    let ifrTime: Double
    let picTime: Double
    let coPilotTime: Double
    let dualTime: Double
    let instructorTime: Double
    let fstdTime: Double
    let dayLandings: Int
    let nightLandings: Int

    init(flights: [Flight]) {
        flightCount       = flights.count
        totalFlightTime   = flights.reduce(0) { $0 + $1.totalFlightTime }
        multiPilotTime    = flights.reduce(0) { $0 + $1.multiPilotTime }
        seSinglePilotTime = flights.reduce(0) { $0 + $1.seSinglePilotTime }
        meSinglePilotTime = flights.reduce(0) { $0 + $1.meSinglePilotTime }
        nightTime         = flights.reduce(0) { $0 + $1.nightTime }
        ifrTime           = flights.reduce(0) { $0 + $1.ifrTime }
        picTime           = flights.reduce(0) { $0 + $1.picTime }
        coPilotTime       = flights.reduce(0) { $0 + $1.coPilotTime }
        dualTime          = flights.reduce(0) { $0 + $1.dualTime }
        instructorTime    = flights.reduce(0) { $0 + $1.instructorTime }
        fstdTime          = flights.reduce(0) { $0 + $1.fstdTime }
        dayLandings       = flights.reduce(0) { $0 + $1.dayLandings }
        nightLandings     = flights.reduce(0) { $0 + $1.nightLandings }
    }
}
