import Foundation

// MARK: - SyncProvider
// Protocollo astratto: cambia backend sostituendo solo il provider,
// FlightStore e tutta l'app restano invariati.

protocol SyncProvider: Actor {
    func fetchAll() async throws -> [Flight]
    func save(_ flight: Flight) async throws -> Flight     // insert o update
    func delete(id: UUID) async throws
    var isConfigured: Bool { get }
}

// MARK: - SyncError

enum SyncError: LocalizedError {
    case notConfigured
    case httpError(statusCode: Int, body: String)
    case decodingFailed(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Configura l'URL e la API Key di Supabase nelle Impostazioni."
        case .httpError(let code, let body):
            return "Errore HTTP \(code): \(body)"
        case .decodingFailed(let err):
            return "Errore decodifica risposta: \(err.localizedDescription)"
        case .noData:
            return "Nessun dato ricevuto dal server."
        }
    }
}
