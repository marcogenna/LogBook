import SwiftUI

struct AircraftListView: View {

    @EnvironmentObject private var store: FlightStore

    @State private var selection: Aircraft.ID?
    @State private var editingAircraft: Aircraft?
    @State private var searchText = ""
    @State private var showPopulateAlert = false
    @State private var populatedCount = 0

    var body: some View {
        VStack(spacing: 0) {
            if store.aircraft.isEmpty {
                emptyState
            } else {
                aircraftTable
            }
        }
        .navigationTitle("Aeromobili")
        .searchable(text: $searchText, prompt: "Cerca per marche o tipo…")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    populatedCount = store.autoPopulateAircraft()
                    showPopulateAlert = true
                } label: {
                    Label("Popola da voli", systemImage: "wand.and.stars")
                }
                .help("Estrai aeromobili dai voli importati")

                Button {
                    editingAircraft = Aircraft()
                } label: {
                    Label("Aggiungi", systemImage: "plus")
                }

                Button {
                    if let id = selection,
                       let ac = store.aircraft.first(where: { $0.id == id }) {
                        store.deleteAircraft(ac)
                        selection = nil
                    }
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
                .disabled(selection == nil)
            }
        }
        .sheet(item: $editingAircraft) { ac in
            AircraftEditorView(aircraft: ac) { saved in
                store.saveAircraft(saved)
            }
        }
        .alert("Aeromobili estratti", isPresented: $showPopulateAlert) {
            Button("OK") {}
        } message: {
            Text("\(populatedCount) nuovi aeromobili aggiunti dai voli esistenti.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Nessun aeromobile")
                    .font(.title2.bold())
                Text("Aggiungi manualmente o estrai\ndai voli già importati.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button("Popola da voli") {
                    populatedCount = store.autoPopulateAircraft()
                    showPopulateAlert = true
                }
                .buttonStyle(.borderedProminent)

                Button("Aggiungi manualmente") {
                    editingAircraft = Aircraft()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Table

    private var filteredAircraft: [Aircraft] {
        if searchText.isEmpty { return store.aircraft }
        let q = searchText.lowercased()
        return store.aircraft.filter {
            $0.registration.lowercased().contains(q) ||
            $0.type.lowercased().contains(q) ||
            $0.manufacturer.lowercased().contains(q) ||
            $0.model.lowercased().contains(q) ||
            $0.company.lowercased().contains(q)
        }
    }

    private var aircraftTable: some View {
        Table(filteredAircraft, selection: $selection) {
            TableColumn("Marche", value: \.registration)
                .width(min: 80, ideal: 100)
            TableColumn("ICAO", value: \.icaoCode)
                .width(min: 50, ideal: 60)
            TableColumn("Costruttore", value: \.manufacturer)
                .width(min: 80, ideal: 120)
            TableColumn("Modello", value: \.model)
                .width(min: 60, ideal: 80)
            TableColumn("Variante", value: \.variant)
                .width(min: 50, ideal: 70)
            TableColumn("Classe") { ac in
                Text(ac.classificationLabel)
                    .foregroundStyle(classColor(ac))
            }
            .width(min: 40, ideal: 50)
            TableColumn("Motore", value: \.engineType)
                .width(min: 80, ideal: 120)
            TableColumn("Compagnia", value: \.company)
                .width(min: 100, ideal: 140)
        }
        .contextMenu(forSelectionType: Aircraft.ID.self) { ids in
            if let id = ids.first,
               let ac = store.aircraft.first(where: { $0.id == id }) {
                Button("Modifica") {
                    editingAircraft = ac
                }
                Divider()
                Button("Elimina", role: .destructive) {
                    store.deleteAircraft(ac)
                    if selection == id { selection = nil }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first,
               let ac = store.aircraft.first(where: { $0.id == id }) {
                editingAircraft = ac
            }
        }
    }

    private func classColor(_ ac: Aircraft) -> Color {
        if ac.isSingleEngine { return .green }
        if ac.isMultiEngine  { return .orange }
        if ac.isMultiPilot   { return .blue }
        return .secondary
    }
}

