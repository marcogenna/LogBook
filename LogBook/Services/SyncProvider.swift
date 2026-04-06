import Foundation

// MARK: - SyncProvider
// Abstract protocol: swap backend by replacing only the provider,
// FlightStore and the entire app remain unchanged.

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
            return "Configure the Supabase URL and API Key in Settings."
        case .httpError(let code, let body):
            return "HTTP Error \(code): \(body)"
        case .decodingFailed(let err):
            return "Response decoding error: \(err.localizedDescription)"
        case .noData:
            return "No data received from server."
        }
    }
}
