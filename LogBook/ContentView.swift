import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case logbook = "Logbook"
    case aircraft = "Aeromobili"
    case statistics = "Statistiche"
    case settings = "Impostazioni"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .logbook: return "book.closed"
        case .aircraft: return "airplane.circle"
        case .statistics: return "chart.bar"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {

    @EnvironmentObject private var store: FlightStore
    @State private var selection: SidebarItem? = .logbook

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .listStyle(.sidebar)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "cloud")
                    .foregroundStyle(.secondary)
                Text("Supabase")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

        } detail: {
            switch selection ?? .logbook {
            case .logbook:
                LogbookView()
            case .aircraft:
                AircraftListView()
            case .statistics:
                StatisticsView()
            case .settings:
                SettingsView()
            }
        }
        .alert("Errore", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
