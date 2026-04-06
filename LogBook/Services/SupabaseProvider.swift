import Foundation

// MARK: - SupabaseProvider
// Usa solo URLSession + PostgREST — nessun SDK esterno.
// Migrazione a self-hosted: cambia solo projectURL in Impostazioni.

actor SupabaseProvider: SyncProvider {

    private static let table = "flights"

    // Credenziali lette al momento della chiamata (mai cachate)
    private var projectURL: String { UserDefaults.standard.string(forKey: "supabaseURL") ?? "" }
    private var anonKey: String { Keychain.load(for: Keychain.supabaseAnonKey) ?? "" }

    var isConfigured: Bool {
        !projectURL.isEmpty && !anonKey.isEmpty
    }

    // MARK: - Fetch

    func fetchAll() async throws -> [Flight] {
        guard isConfigured else { throw SyncError.notConfigured }
        var components = URLComponents(string: "\(projectURL)/rest/v1/\(Self.table)")!
        components.queryItems = [URLQueryItem(name: "order", value: "date.desc")]

        var req = URLRequest(url: components.url!)
        addHeaders(to: &req)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        try checkHTTP(response, data)

        do {
            return try JSONDecoder.supabase.decode([Flight].self, from: data)
        } catch {
            throw SyncError.decodingFailed(error)
        }
    }

    // MARK: - Save (upsert)

    func save(_ flight: Flight) async throws -> Flight {
        guard isConfigured else { throw SyncError.notConfigured }
        let url = URL(string: "\(projectURL)/rest/v1/\(Self.table)")!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        addHeaders(to: &req)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Upsert: se l'id esiste già, aggiorna
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONEncoder.supabase.encode(flight)

        let (data, response) = try await URLSession.shared.data(for: req)
        try checkHTTP(response, data)

        // Supabase restituisce array anche per insert singolo
        do {
            let flights = try JSONDecoder.supabase.decode([Flight].self, from: data)
            return flights.first ?? flight
        } catch {
            // Alcuni setup restituiscono oggetto singolo
            if let single = try? JSONDecoder.supabase.decode(Flight.self, from: data) {
                return single
            }
            return flight
        }
    }

    // MARK: - Delete

    func delete(id: UUID) async throws {
        guard isConfigured else { throw SyncError.notConfigured }
        var components = URLComponents(string: "\(projectURL)/rest/v1/\(Self.table)")!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]

        var req = URLRequest(url: components.url!)
        req.httpMethod = "DELETE"
        addHeaders(to: &req)

        let (data, response) = try await URLSession.shared.data(for: req)
        try checkHTTP(response, data)
    }

    // MARK: - Helpers

    private func addHeaders(to req: inout URLRequest) {
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    }

    private func checkHTTP(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw SyncError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}
