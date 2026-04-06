import SwiftUI

struct LogbookView: View {

    @EnvironmentObject private var store: FlightStore
    @State private var sortOrder = [KeyPathComparator(\Flight.date, order: .reverse)]
    @State private var selection: Set<Flight.ID> = []
    @State private var showAddFlight = false
    @State private var editingFlight: Flight?
    @State private var searchText = ""
    @State private var confirmDelete = false

    private var filtered: [Flight] {
        if searchText.isEmpty { return store.flights }
        return store.flights.filter { flight in
            flight.departurePlace.localizedCaseInsensitiveContains(searchText)
            || flight.arrivalPlace.localizedCaseInsensitiveContains(searchText)
            || flight.aircraftType.localizedCaseInsensitiveContains(searchText)
            || flight.aircraftRegistration.localizedCaseInsensitiveContains(searchText)
            || flight.picName.localizedCaseInsensitiveContains(searchText)
            || flight.remarks.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            colsRouteAircraft
            colsTime
            colsConditionsFunction
        }
        .onChange(of: sortOrder) { _, newOrder in
            store.flights.sort(using: newOrder)
        }
        .navigationTitle("Logbook")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await store.fetchFlights() }
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
                Button {
                    showAddFlight = true
                } label: {
                    Label("Aggiungi Volo", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem(placement: .destructiveAction) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Elimina", systemImage: "trash")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Cerca voli…")
        .onDeleteCommand { if !selection.isEmpty { confirmDelete = true } }
        .confirmationDialog(
            "Eliminare \(selection.count) volo/i?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) { deleteSelected() }
        }
        .sheet(isPresented: $showAddFlight) {
            FlightEditorView(flight: Flight()) { saved in
                Task { await store.save(saved) }
            }
        }
        .sheet(item: $editingFlight) { flight in
            FlightEditorView(flight: flight) { saved in
                Task { await store.save(saved) }
            }
        }
        .onTapGesture(count: 2) {
            if let id = selection.first,
               let flight = store.flights.first(where: { $0.id == id }) {
                editingFlight = flight
            }
        }
        .overlay {
            if store.flights.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "Nessun volo registrato",
                    systemImage: "airplane",
                    description: Text("Premi ⌘N per aggiungere il primo volo")
                )
            }
        }
    }

    // MARK: - Column Groups (spezzati per il type-checker)

    @TableColumnBuilder<Flight, KeyPathComparator<Flight>>
    private var colsRouteAircraft: some TableColumnContent<Flight, KeyPathComparator<Flight>> {
        TableColumn("Data", value: \Flight.date) { flight in
            Text(flight.date, style: .date)
                .font(.system(.body, design: .monospaced))
        }
        .width(min: 90, ideal: 100)

        TableColumn("Rotta") { flight in
            Text(flight.route)
                .font(.system(.body, design: .monospaced))
        }
        .width(min: 110, ideal: 130)

        TableColumn("Tipo", value: \Flight.aircraftType)
            .width(min: 60, ideal: 70)

        TableColumn("Marche", value: \Flight.aircraftRegistration)
            .width(min: 70, ideal: 80)

        TableColumn("Comandante", value: \Flight.picName)
            .width(min: 80, ideal: 100)

        TableColumn("Att. G") { flight in
            Text(flight.dayLandings > 0 ? "\(flight.dayLandings)" : "—")
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .width(min: 40, ideal: 45)

        TableColumn("Att. N") { flight in
            Text(flight.nightLandings > 0 ? "\(flight.nightLandings)" : "—")
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .width(min: 40, ideal: 45)
    }

    @TableColumnBuilder<Flight, KeyPathComparator<Flight>>
    private var colsTime: some TableColumnContent<Flight, KeyPathComparator<Flight>> {
        TableColumn("SP SE") { flight in
            TimeCell(hours: flight.seSinglePilotTime)
        }
        .width(min: 55, ideal: 60)

        TableColumn("SP ME") { flight in
            TimeCell(hours: flight.meSinglePilotTime)
        }
        .width(min: 55, ideal: 60)

        TableColumn("MP") { flight in
            TimeCell(hours: flight.multiPilotTime)
        }
        .width(min: 55, ideal: 60)

        TableColumn("Totale", value: \Flight.totalFlightTime) { flight in
            TimeCell(hours: flight.totalFlightTime, bold: true)
        }
        .width(min: 55, ideal: 65)
    }

    @TableColumnBuilder<Flight, KeyPathComparator<Flight>>
    private var colsConditionsFunction: some TableColumnContent<Flight, KeyPathComparator<Flight>> {
        TableColumn("Notte") { flight in
            TimeCell(hours: flight.nightTime)
        }
        .width(min: 55, ideal: 60)

        TableColumn("IFR") { flight in
            TimeCell(hours: flight.ifrTime)
        }
        .width(min: 55, ideal: 60)

        TableColumn("PIC") { flight in
            TimeCell(hours: flight.picTime)
        }
        .width(min: 55, ideal: 60)

        TableColumn("Co-P") { flight in
            TimeCell(hours: flight.coPilotTime)
        }
        .width(min: 55, ideal: 60)

        TableColumn("Duale") { flight in
            TimeCell(hours: flight.dualTime)
        }
        .width(min: 55, ideal: 60)

        TableColumn("Sim") { flight in
            TimeCell(hours: flight.fstdTime)
        }
        .width(min: 55, ideal: 60)

        TableColumn("Note", value: \Flight.remarks)
            .width(min: 100)
    }

    // MARK: - Actions

    private func deleteSelected() {
        let toDelete = store.flights.filter { selection.contains($0.id) }
        selection = []
        for flight in toDelete {
            Task { await store.delete(flight) }
        }
    }
}

// MARK: - Supporting Views

private struct TimeCell: View {
    let hours: Double
    var bold: Bool = false

    var body: some View {
        Text(hours > 0 ? hours.hoursMinutes : "—")
            .font(.system(.body, design: .monospaced).weight(bold ? .semibold : .regular))
            .foregroundStyle(hours > 0 ? .primary : .tertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
