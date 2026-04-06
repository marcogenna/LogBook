import Foundation

// MARK: - LocalStore
// Persists flights in a JSON file in Application Support.
// Works always, even without network.

final class LocalStore {

    static let shared = LocalStore()

    private let fileURL: URL
    private let pendingURL: URL  // IDs of flights not yet synced
    private let aircraftURL: URL

    private init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("com.logbook.atpl", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: support, withIntermediateDirectories: true
        )

        fileURL     = support.appendingPathComponent("flights.json")
        pendingURL  = support.appendingPathComponent("pending_sync.json")
        aircraftURL = support.appendingPathComponent("aircraft.json")
    }

    // MARK: - Flights

    func loadAll() -> [Flight] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.supabase.decode([Flight].self, from: data)) ?? []
    }

    func saveAll(_ flights: [Flight]) {
        guard let data = try? JSONEncoder.supabase.encode(flights) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Pending Sync

    /// IDs of flights modified locally but not yet confirmed by Supabase
    func loadPendingIDs() -> Set<UUID> {
        guard let data = try? Data(contentsOf: pendingURL),
              let ids = try? JSONDecoder().decode([UUID].self, from: data)
        else { return [] }
        return Set(ids)
    }

    func savePendingIDs(_ ids: Set<UUID>) {
        guard let data = try? JSONEncoder().encode(Array(ids)) else { return }
        try? data.write(to: pendingURL, options: .atomic)
    }

    func markPending(_ id: UUID) {
        var ids = loadPendingIDs()
        ids.insert(id)
        savePendingIDs(ids)
    }

    func markSynced(_ id: UUID) {
        var ids = loadPendingIDs()
        ids.remove(id)
        savePendingIDs(ids)
    }

    func clearPending() {
        savePendingIDs([])
    }

    // MARK: - Aircraft

    func loadAircraft() -> [Aircraft] {
        guard let data = try? Data(contentsOf: aircraftURL) else { return [] }
        return (try? JSONDecoder.supabase.decode([Aircraft].self, from: data)) ?? []
    }

    func saveAircraft(_ list: [Aircraft]) {
        guard let data = try? JSONEncoder.supabase.encode(list) else { return }
        try? data.write(to: aircraftURL, options: .atomic)
    }
}
